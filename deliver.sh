#!/bin/bash
# Puts one task tree's work into main, in the only order it lands: merge
# --no-ff, build the main checkout, delete the tree and its branch. One
# delivery at a time — the lock in .git is shared by every worktree — and the
# main checkout has to be empty when it starts.
#
#   ./deliver.sh <slug>        branch feat/<slug>, tree ../Aura-<slug>
#
# The main checkout never holds a task of its own (AGENTS.md「并行交付」), so
# this is the only writer main has, and it runs alone:
#
#   lock held by someone else        → refused, naming who and since when
#   main checkout has any change      → refused, listing them: that is a task
#                                       that belongs in a tree, not something
#                                       this script may stash or merge past
#   tree has uncommitted changes      → refused
#   branch has nothing new            → refused
#   branch would conflict with main   → refused; merge main into the tree
#                                       there, resolve, build, test, come back
#   build fails                       → merge taken back (reset to ORIG_HEAD),
#                                       tree kept so the work is still there
#   tree has new work while delivering→ worktree remove refuses, and so does
#                                       this script: never --force over work
set -euo pipefail
cd "$(dirname "$0")"

usage() { echo "usage: ./deliver.sh <slug>" >&2; exit 1; }
refuse() { echo "交付停下：$*" >&2; exit 1; }

[ $# -eq 1 ] || usage
slug=$1
branch="feat/$slug"
tree="../Aura-$slug"
git_dir="$(git rev-parse --absolute-git-dir)"
lock="$git_dir/deliver.lock"

# Only the main checkout merges; a linked worktree has its own branch to tend.
main_tree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ "$(git rev-parse --show-toplevel)" = "$main_tree" ] \
  || refuse "要在主仓检出里跑（$(pwd) 是一棵树，不是主仓）"

if ! mkdir "$lock" 2>/dev/null; then
  refuse "另一个交付正拿着锁：$(cat "$lock/who" 2>/dev/null || echo '（没写是谁）')；确认它没在跑再 rm -rf $lock"
fi
trap 'rm -rf "$lock"' EXIT
echo "$$ $(date '+%F %T') $slug" > "$lock/who"

git show-ref --verify --quiet "refs/heads/$branch" || refuse "没有分支 $branch"
[ -d "$tree" ] || refuse "没有树 $tree（先 git worktree add ../Aura-$slug -b $branch）"

dirty="$(git status --porcelain)"
[ -z "$dirty" ] || {
  printf '%s\n' "$dirty" >&2
  refuse "主仓检出不干净。这些改动属于某个还没进树的活，由它的会话挪进树；本脚本不替它 stash、也不越过它合并"
}

tree_dirty="$(git -C "$tree" status --porcelain)"
[ -z "$tree_dirty" ] || { printf '%s\n' "$tree_dirty" >&2; refuse "树 $tree 里有未提交的改动"; }

ahead="$(git rev-list --count "main..$branch")"
[ "$ahead" -gt 0 ] || refuse "$branch 相对 main 没有提交，没有可交付的"

# A conflict is settled in the tree, where the person who wrote it can see it.
if ! git merge-tree --write-tree main "$branch" >/dev/null 2>&1; then
  refuse "$branch 与 main 会冲突：先在树里 git -C $tree merge main，冲突、构建、测试都过了再回来"
fi

git merge --no-ff "$branch" -m "合并 $branch：$(git log -1 --format=%s "$branch")"

if ! ./build.sh; then
  git reset --hard ORIG_HEAD
  refuse "构建失败，合并已撤回（main 回到 $(git log -1 --format=%h)）；树与分支留着，改完再来"
fi

app="build/Aura.app/Contents/MacOS/Aura"
[ -x "$app" ] || refuse "构建说成功了但 $app 不在；树与分支留着，先查 build.sh"

git worktree remove "$tree"
git branch -d "$branch"
trap - EXIT
rm -rf "$lock"

echo "交付完成：$(git log -1 --format='%h %s')"
echo "  产物：$app（$(date -r "$app" '+%F %T')），对应当前 main 的代码"
echo "  worktree：$(git worktree list | wc -l | tr -d ' ') 个（主仓 + aura-pages）"
echo "  未合并的任务分支：$(git branch --no-merged main | grep -vc gh-pages || true) 个"
echo "  stash：$(git stash list | wc -l | tr -d ' ') 项"
