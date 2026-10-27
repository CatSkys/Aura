#!/bin/bash
# Points git at .git-hooks, so the checks that keep the main checkout for
# merges are actually on: a direct commit there is refused (pre-commit), and so
# is a merge that isn't ./deliver.sh's (pre-merge-commit). Git reads
# core.hooksPath from the shared config, so one run covers every worktree
# beside this one.
#
#   ./hooks.sh          what the setting is now
#   ./hooks.sh on       turn it on: commits in this checkout are then refused
#   ./hooks.sh off      turn it off again
#
# What they refuse, and the way past them, is in .git-hooks/pre-commit,
# .git-hooks/pre-merge-commit and AGENTS.md §并行任务.
set -euo pipefail

cd "$(dirname "$0")"

state() {
  local now
  now="$(git config --get core.hooksPath || true)"
  if [ "$now" = ".git-hooks" ]; then
    echo "hooks on: 主仓检出上的 git commit、不是 deliver.sh 的 git merge 都会被拒；worktree 里照常（$(pwd)）"
  else
    echo "hooks off: 主仓检出上可以任意直接提交（core.hooksPath=${now:-未设置}）"
  fi
}

case "${1:-}" in
  "")     state ;;
  on)     git config core.hooksPath .git-hooks; state ;;
  off)    git config --unset core.hooksPath 2>/dev/null || true; state ;;
  *)      echo "usage: ./hooks.sh [on|off]" >&2; exit 1 ;;
esac
