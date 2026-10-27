#!/bin/bash
# Which tests to run, and what each way of running them costs. Measured on this
# Mac (warm .build, one afternoon in October 2026):
#
#   ./test.sh                逻辑腿：除下面那 10 个套件以外的全部
#                            400 例 / 约 21 秒         ← 改代码时的默认这条
#   ./test.sh <套件名>       一个套件                    2 秒
#   ./test.sh heavy          只有那 10 个重套件          约 214 秒
#   ./test.sh all            全量                        492 例 / 约 243 秒
#   ./test.sh --list         这套是怎么分的
#
# The ten left out are left out for what they wait on, not for what they assert:
# ApplePasswords/ApplePairing run real SRP-3072 modular exponentiation (85 s +
# 21 s in Debug, 2 s in a release build), PinDrag/SidebarPress/TabCapture/
# TabShortcutHint/ScreenPermission drive real AppKit events, DownloadLifecycle
# and HostPipe wait on WebKit and on a helper pipe, and ShieldTests compiles the
# rule tables. `swift test` runs them all in Debug, where that arithmetic is
# fifty times its release cost — the whole suite's 243 s is 88% these ten.
#
# So: the logic tier is for the loop, and `./test.sh heavy` (or `all`) is what a
# change to one of those areas, or a delivery, wants. Debug is the config the
# rest of the suite is written against: a release build halves the total but two
# examples fail there, so it is not a drop-in shortcut.

set -uo pipefail
cd "$(dirname "$0")"
./guard.sh

heavy=(ApplePasswordsTests ApplePairingTests PinDragTests SidebarPressTests
       DownloadLifecycleTests TabCaptureTests HostPipeTests TabShortcutHintTests
       ShieldTests ScreenPermissionTests)
stamp=".build/aura-tests-fresh"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

list() {
  echo "重套件（逻辑腿跳过它们，heavy 只跑它们）："
  printf '  %s\n' "${heavy[@]}"
  echo
  echo "  逻辑腿 = 全量减去它们；剩下的套件都是纯逻辑，毫秒到几秒。"
}

# `swift test` re-checks the build before running, which costs about ten seconds
# even when there is nothing to do — a third of the logic tier's whole budget.
# The stamp says when this tree last built its tests, `--skip-build` is passed
# only when no source or test file is newer. Anything unexpected (no stamp, a
# find that fails, a touched Package.swift) falls back to the plain run.
built_and_fresh() {
  [ -f "$stamp" ] || return 1
  local newer
  newer="$(find Sources Tests Package.swift -newer "$stamp" \
             \( -name '*.swift' -o -name 'Package.swift' \) 2>/dev/null | head -1)" || return 1
  [ -z "$newer" ]
}

run() {
  local -a skip_flags=() elapsed start
  start=$(date +%s)
  if built_and_fresh; then
    skip_flags=(--skip-build)
  fi
  swift test ${skip_flags[@]+"${skip_flags[@]}"} "$@"
  local rc=$?
  if [ $rc -eq 0 ] && [ ${#skip_flags[@]} -eq 0 ]; then
    mkdir -p .build && touch "$stamp"
  fi
  elapsed=$(( $(date +%s) - start ))
  if [ $rc -eq 0 ]; then
    echo "· 用掉 ${elapsed}s$([ ${#skip_flags[@]} -gt 0 ] && echo '（跳过了构建检查）')"
  else
    echo "· 用掉 ${elapsed}s，红了：上面的输出是唯一的账" >&2
  fi
  return $rc
}

case "${1:-}" in
  --list) list; exit 0 ;;
  -h|--help|help) usage; exit 0 ;;
  all) shift; run "$@" ;;
  heavy)
    shift
    pattern="$(printf '%s|' "${heavy[@]}")"
    run --filter "${pattern%|}" "$@" ;;
  "")
    args=()
    for suite in "${heavy[@]}"; do args+=(--skip "$suite"); done
    run "${args[@]}" || exit $?
    echo "· 这 10 个重套件没跑：./test.sh heavy（约 214s）；交付前跑 ./test.sh all" ;;
  *)
    run --filter "$@" ;;
esac
