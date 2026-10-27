#!/bin/bash
# The main checkout is for merges, not for work. Compiled there with someone's
# uncommitted changes, build/Aura.app holds those changes while the artifact
# stamp says it is HEAD — the delivery that then hands people a DMG hands them
# work nobody committed. And a probe run there judges a tree nobody kept.
#
#   ./guard.sh      exit 0 in a worktree, or in a clean main checkout; exit 1,
#                   listing them, when the main checkout holds app changes
#
# Called by ./build.sh and ./check.sh before they compile anything. AGENTS.md
# §并行任务 is the rule it enforces, and §并行交付 is who may merge.
set -euo pipefail
cd "$(dirname "$0")"

main_tree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
here="$(git rev-parse --show-toplevel)"
[ "$here" = "$main_tree" ] || exit 0

app_paths='^(Sources/|Resources/|Engine/|Package\.swift$|VERSION$)'
held="$(git status --porcelain | sed 's/^...//' | grep -E "$app_paths" || true)"
[ -n "$held" ] || exit 0

{
  echo "主仓检出里有未提交的 app 改动，这里不编译："
  printf '  %s\n' "$held"
  cat <<'MSG'

  主仓只收合并（AGENTS.md「并行任务」）：活开一棵树做，编译也在树里跑。
      ./tree.sh <session>                    # ../Aura-<session>，.build 留热
      cd ../Aura-<session> && ./check.sh
  收尾：回到主仓 ./deliver.sh <slug>，它自己会构建。
MSG
} >&2
exit 1
