#!/bin/bash
# One tree per session, one branch per task. A tree keeps its .build, so the
# second task in the same session compiles in seconds instead of from nothing;
# a fresh tree per task throws that away every time (44s for a build, a minute
# more for the tests').
#
#   ./tree.sh <session>              ../Aura-<session>, on branch feat/<session>
#   ./tree.sh <session> <task>       the same tree, on a new branch feat/<task>
#
# A tree with uncommitted work in it will not change branches — commit or set
# it aside first; that is git's own rule, and the right one.
set -euo pipefail
cd "$(dirname "$0")"

name="${1:-}"; task="${2:-$1}"
[ -n "$name" ] || { echo "usage: ./tree.sh <session> [task]" >&2; exit 1; }
tree="../Aura-$name"
branch="feat/$task"

if [ ! -d "$tree" ]; then
  git worktree add -q "$tree" -b "$branch"
  echo "树 $tree 建好了，在 $branch"
  exit 0
fi

here="$(git -C "$tree" rev-parse --abbrev-ref HEAD)"
if [ "$here" = "$branch" ]; then
  echo "树 $tree 已在 $branch"
elif git show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$tree" checkout -q "$branch"
  echo "树 $tree 换到已有的 $branch"
else
  git -C "$tree" checkout -q -b "$branch"
  echo "树 $tree 换到新分支 $branch"
fi
