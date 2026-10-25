#!/bin/bash
# Puts one task tree's work into main, in the only order it lands: merge
# --no-ff, build the main checkout, delete the tree and its branch. One
# delivery at a time — the lock in .git is shared by every worktree — and the
# main checkout has to be empty when it starts.
#
#   ./deliver.sh <slug>        branch feat/<slug>, tree ../Aura-<slug>
#
# Refused, naming the reason, when: another delivery holds the lock, the main
# checkout has uncommitted work, the tree has uncommitted work or nothing to
# deliver, or the branch would conflict with main. A conflict is resolved in
# the tree (`git -C ../Aura-<slug> merge main`), never here. A build that
# fails takes the merge back (reset --hard to ORIG_HEAD) and leaves the tree
# alone, so what was working is still working.
#
# Why the lock exists: two merges into main at once are two writers on one
# index, and the loser fails halfway through with index.lock in its face. The
# lock makes the second one wait its turn instead — see AGENTS.md
# 「并行交付」.
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
  refuse "另一个交付正拿着锁：$(cat "$lock/who" 2>/dev/null || echo '（没写是谁）')"
fi
trap 'rm -rf "$lock"' EXIT
echo "$$ $(date '+%F %T') $slug" > "$lock/who"

git show-ref --verify --quiet "refs/heads/$branch" || refuse "没有分支 $branch"
[ -d "$tree" ] || refuse "没有树 $tree（先 git worktree add ../Aura-$slug -b $branch）"

dirty="$(git status --porcelain)"
[ -z "$dirty" ] || { printf '%s\n' "$dirty" >&2; refuse "主仓检出不干净，合并会被 git 拒；让那份活的负责会话先提交或收起"; }

tree_dirty="$(git -C "$tree" status --porcelain)"
[ -z "$tree_dirty" ] || { printf '%s\n' "$tree_dirty" >&2; refuse "树 $tree 里有未提交的改动"; }

ahead="$(git rev-list --count "main..$branch")"
[ "$ahead" -gt 0 ] || refuse "$branch 相对 main 没有提交，没有可交付的"

# A conflict is settled in the tree, where the person who wrote it can see it.
if ! git merge-tree --write-tree main "$branch" >/dev/null 2>&1; then
  refuse "$branch 与 main 会冲突：先在树里 git -C $tree merge main，把冲突、构建、测试都过一遍再来"
fi

git merge --no-ff "$branch" -m "合并 $branch：$(git log -1 --format=%s "$branch")"

if ! ./build.sh; then
  git reset --hard ORIG_HEAD
  refuse "构建失败，合并已撤回（main 回到 $(git log -1 --format=%h)）；树和分支留着"
fi

git worktree remove "$tree"
git branch -d "$branch"
trap - EXIT
rm -rf "$lock"

echo "交付完成：$(git log -1 --format='%h %s')"
echo "  worktree: $(git worktree list | wc -l | tr -d ' ') 个（主仓 + aura-pages）"
echo "  尚未合并的任务分支：$(git branch --no-merged main | grep -v gh-pages | wc -l | tr -d ' ') 个"
echo "  产物：build/Aura.app（$(date '+%F %T')）"
