#!/bin/bash
# Puts one task tree's work into main, in the only order it lands: merge
# --no-ff, build the main checkout, delete the tree and its branch. One
# delivery at a time — the lock in .git is shared by every worktree — and the
# main checkout has to be empty when it starts.
#
#   ./deliver.sh <slug>                  branch feat/<slug>, its tree; waits for
#                                        another delivery to finish (up to 300s)
#   ./deliver.sh <slug> --wait 600       wait longer; --no-wait refuses instead
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

usage() { echo "usage: ./deliver.sh <slug> [--wait SECONDS | --no-wait]" >&2; exit 1; }
refuse() { echo "交付停下：$*" >&2; exit 1; }

wait_seconds=300
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --wait) wait_seconds="${2:-300}"; shift 2 ;;
    --wait=*) wait_seconds="${1#--wait=}"; shift ;;
    --no-wait) wait_seconds=0; shift ;;
    -*) usage ;;
    *) args+=("$1"); shift ;;
  esac
done
[ ${#args[@]} -eq 1 ] || usage
slug="${args[0]}"
branch="feat/$slug"
tree="../Aura-$slug"
git_dir="$(git rev-parse --absolute-git-dir)"
lock="$git_dir/deliver.lock"

# Only the main checkout merges; a linked worktree has its own branch to tend.
main_tree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ "$(git rev-parse --show-toplevel)" = "$main_tree" ] \
  || refuse "要在主仓检出里跑（$(pwd) 是一棵树，不是主仓）"

# A delivery takes a merge (seconds) and, when the app changed, a build
# (a minute or two). Rather than hand the wait back to whoever called this —
# as a `sleep` loop that keeps asking — wait here, saying who holds it. A
# lock whose process is gone is taken over: a killed delivery must not stop
# every other one, and the pid is what tells the two apart.
waited=0
while :; do
  if mkdir "$lock" 2>/dev/null; then
    trap 'rm -rf "$lock"' EXIT
    echo "$$ $(date '+%F %T') $slug" > "$lock/who"
    break
  fi
  holder="$(cat "$lock/who" 2>/dev/null || true)"
  held_pid="${holder%% *}"
  if [ -n "$held_pid" ] && ! kill -0 "$held_pid" 2>/dev/null; then
    echo "锁被「${holder:-（没写是谁）}」拿着，但那个进程已经不在了：接管"
    rm -rf "$lock"
    continue
  fi
  [ "$waited" -lt "$wait_seconds" ] ||     refuse "另一个交付拿锁超过了 ${wait_seconds}s：${holder:-（没写是谁）}；再来一次 ./deliver.sh $slug --wait 600"
  [ $((waited % 10)) -ne 0 ] || echo "等锁：${holder:-（没写是谁）}（已等 ${waited}s，上限 ${wait_seconds}s）"
  sleep 2
  waited=$((waited + 2))
done

git show-ref --verify --quiet "refs/heads/$branch" || refuse "没有分支 $branch"
# The tree is the one with this branch checked out, whatever it was named.
found="$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
  $1 == "worktree" { where = $2 }
  $1 == "branch" && $2 == b { print where }')"
[ -z "$found" ] || tree="$found"
[ -d "$tree" ] || refuse "没有树 $tree（先 git worktree add ../Aura-$slug -b $branch）"

# What the merge brings, so a main checkout busy with someone else's task can
# still take it when the two touch different files — waiting for a clean main
# is how branches pile up and start conflicting.
coming="$(git diff --name-only "main...$branch")"
dirty="$(git status --porcelain)"
dirty_paths="$(printf '%s\n' "$dirty" | sed 's/^...//')"
clash="$(comm -12 <(printf '%s\n' "$coming" | sort) <(printf '%s\n' "$dirty_paths" | sort) | grep . || true)"
[ -z "$clash" ] || { printf '%s\n' "$clash" >&2; refuse "主仓里这些文件正被别人改着，与本次合并重叠：等那份活提交或进树再来"; }

tree_dirty="$(git -C "$tree" status --porcelain)"
[ -z "$tree_dirty" ] || { printf '%s\n' "$tree_dirty" >&2; refuse "树 $tree 里有未提交的改动"; }

ahead="$(git rev-list --count "main..$branch")"
[ "$ahead" -gt 0 ] || refuse "$branch 相对 main 没有提交，没有可交付的"

# A conflict is settled in the tree, where the person who wrote it can see it.
if ! git merge-tree --write-tree main "$branch" >/dev/null 2>&1; then
  refuse "$branch 与 main 会冲突：先在树里 git -C $tree merge main，冲突、构建、测试都过了再回来"
fi

git merge --no-ff "$branch" -m "合并 $branch：$(git log -1 --format=%s "$branch")"

# The app is rebuilt only when this merge could have changed it, and only on a
# clean checkout: main busy with someone else's task would put that task into
# the product, which is how a build came to wipe another session's work.
app_paths='^(Sources/|Resources/|Engine/|Package\.swift$|VERSION$)'
if ! printf '%s\n' "$coming" | grep -qE "$app_paths"; then
  echo "只改了文档与脚本（$(printf '%s\n' "$coming" | tr '\n' ' ')），产物不受影响，不重建"
elif [ -n "$dirty" ]; then
  echo "主仓还有别人的活（$(printf '%s\n' "$dirty" | wc -l | tr -d ' ') 项），这次不构建：产物会把那份活编进去。需要新产物，等主仓干净后 ./build.sh"
else
  if ! ./build.sh; then
    git reset --hard ORIG_HEAD
    refuse "构建失败，合并已撤回（main 回到 $(git log -1 --format=%h)）；树与分支留着，改完再来"
  fi
fi

app="build/Aura.app/Contents/MacOS/Aura"

git worktree remove "$tree"
git branch -d "$branch"
trap - EXIT
rm -rf "$lock"

echo "交付完成：$(git log -1 --format='%h %s')"
echo "  产物：$app（$(date -r "$app" '+%F %T' 2>/dev/null || echo 没有)）"
echo "  worktree：$(git worktree list | wc -l | tr -d ' ') 个（主仓 + aura-pages）"
echo "  未合并的任务分支：$(git branch --no-merged main | grep -vc gh-pages || true) 个"
echo "  stash：$(git stash list | wc -l | tr -d ' ') 项"
