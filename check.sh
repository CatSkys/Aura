#!/bin/bash
# The quick leg: everything a build can catch, and nothing that needs a
# browser or the test suite.
#
#   ./check.sh        compile with an eye on warnings, check the translation
#                     table's syntax, and count what it still misses
#
# It is not a test. A change to behaviour wants one suite, not the whole run:
# swift test --filter <suite> for the file's own tests, and the full run only
# when the change spans several modules or a contract. AGENTS.md
# 「完成的定义」says which is which, and names what counts as behaviour.
set -euo pipefail
cd "$(dirname "$0")"
start=$(date +%s)
log="$(mktemp "${TMPDIR:-/tmp}/aura-check.XXXXXX")"
trap 'rm -f "$log"' EXIT

echo "· swift build"
if ! swift build >"$log" 2>&1; then
  tail -30 "$log" >&2
  echo "编译失败" >&2
  exit 1
fi
warnings=$(grep -c "warning:" "$log" || true)
echo "  编译通过；本轮 $warnings 条警告（冷树会带上全部既有警告，热编译只看改到的那个文件）"
[ "$warnings" -eq 0 ] || grep "warning:" "$log" | head -5

echo "· plutil -lint 译文表"
plutil -lint Resources/*/Localizable.strings

echo "· 译文缺口（只报数，不判红）"
./Tools/i18n.py missing | head -1

echo "快速腿通过：$(( $(date +%s) - start ))s"
