#!/bin/bash
# Which tests to run, and in what order. The ladder, cheapest first — measured
# on this Mac (warm .build, an afternoon in October 2026):
#
#   ./test.sh changed      只看这次改过的文件对应的套件      约 2-10 秒
#   ./test.sh <套件名>     一个套件                         约 2 秒
#   ./test.sh              逻辑腿：其余全部 400 例           约 21 秒
#   ./test.sh heavy        只有那 10 个重套件               约 214 秒
#   ./test.sh all          全量 492 例（一轮只跑一次）      约 243 秒
#   ./test.sh --list       这套是怎么分的
#
# 顺序是有原因的：红了要修的是那个套件，不是把全量再跑一遍。有一轮会话在同一份
# 代码上跑了四次全量、还有两次带 grep 的全量只为找到错误输出，光这一项四十分钟里
# 花了十一分钟。`changed` 就是让这条梯子的第一格不用自己想。
#
# 那十个为什么单列：它们慢在等什么，不在断言什么 —— ApplePasswords 与
# ApplePairing 是真 SRP-3072 模幂（Debug 档 85s+21s，release 档 2s），
# PinDrag/SidebarPress/TabCapture/TabShortcutHint/ScreenPermission 驱动真 AppKit
# 事件，DownloadLifecycle 与 HostPipe 等 WebKit 与一条真管道，ShieldTests 编译
# 规则表。全量 243 秒里 88% 是它们。
#
# Debug 是这套测试的基准档：release 能把这 243 秒压到 122 秒，但那边有 2 例红，
# 不是可以随便换的捷径。
set -uo pipefail
cd "$(dirname "$0")"
./guard.sh

heavy=(ApplePasswordsTests ApplePairingTests PinDragTests SidebarPressTests
       DownloadLifecycleTests TabCaptureTests HostPipeTests TabShortcutHintTests
       ShieldTests ScreenPermissionTests)
fresh_stamp=".build/aura-tests-fresh"    # 测试二进制是按哪些文件构建的
green_stamp=".build/aura-all-green"      # 最近一次全量绿的时候

# `swift test` 每次都要重查一遍构建，热的时候也要十秒 —— 逻辑腿的三分之一。
# 这棵树上次构建测试之后没有 .swift 变新，就让它跳过那一步。
built_and_fresh() {
  [ -f "$fresh_stamp" ] || return 1
  local newer
  newer="$(find Sources Tests Package.swift -newer "$fresh_stamp" \
             \( -name '*.swift' -o -name 'Package.swift' \) 2>/dev/null | head -1)" || return 1
  [ -z "$newer" ]
}

# 上一次全量绿了之后没有人动过代码：同一份代码上再跑一遍，问的是同一个问题。
all_green_and_unchanged() {
  [ -f "$green_stamp" ] || return 1
  local newer
  newer="$(find Sources Tests Package.swift -newer "$green_stamp" \
             \( -name '*.swift' -o -name 'Package.swift' \) 2>/dev/null | head -1)" || return 1
  [ -z "$newer" ]
}

# 这次改过的东西对应哪些套件：Sources/Aura/X.swift → X 这个名字的套件，
# 测试文件自己的改动同理。挑不出来就是空 —— 调用方退回逻辑腿。
changed_suites() {
  local files name
  files="$(
    git diff --name-only "main...HEAD" 2>/dev/null
    git diff --name-only 2>/dev/null
    git diff --name-only --cached 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  )"
  printf '%s\n' "$files" | sed -e 's#.*/##' -e 's#\.swift$##' | sort -u | while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in *Tests) ;; *) name="${name}Tests" ;; esac
    if [ -f "Tests/AuraTests/$name.swift" ]; then echo "$name"; fi
  done | sort -u
}

run() {
  local -a skip_flags=() args=() elapsed start rc
  for arg in "$@"; do
    case "$arg" in --skip-build|--again) ;; *) args+=("$arg") ;; esac
  done
  start=$(date +%s)
  if built_and_fresh; then skip_flags=(--skip-build); fi
  swift test ${skip_flags[@]+"${skip_flags[@]}"} ${args[@]+"${args[@]}"}
  rc=$?
  if [ $rc -eq 0 ] && [ ${#skip_flags[@]} -eq 0 ]; then
    mkdir -p .build && touch "$fresh_stamp"
  fi
  elapsed=$(( $(date +%s) - start ))
  if [ $rc -eq 0 ]; then
    echo "· 用掉 ${elapsed}s$([ ${#skip_flags[@]} -gt 0 ] && echo '（跳过了构建检查）')"
  else
    echo "· 用掉 ${elapsed}s，红了：先修这个套件，别把全量再跑一遍" >&2
  fi
  return $rc
}

list() {
  echo "重套件（逻辑腿跳过它们，heavy 只跑它们）："
  printf '  %s\n' "${heavy[@]}"
  echo
  echo "梯子：changed → <套件> → 逻辑腿 → all；全量一轮只跑一次，红了修那个套件。"
}

case "${1:-}" in
  --list) list; exit 0 ;;
  -h|--help|help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  changed)
    shift
    picked="$(changed_suites | tr '\n' ' ')"
    if [ -z "${picked// /}" ]; then
      echo "· 这次没有改到有同名套件的源文件：走逻辑腿"
      args=()
      for suite in "${heavy[@]}"; do args+=(--skip "$suite"); done
      run "${args[@]}" "$@" || exit $?
      exit 0
    fi
    echo "· 这次改到：$picked"
    pattern="$(printf '%s|' $picked)"
    run --filter "${pattern%|}" "$@" ;;
  all)
    shift
    again=0
    for arg in "$@"; do [ "$arg" = "--again" ] && again=1; done
    if [ $again -eq 0 ] && all_green_and_unchanged; then
      echo "· 全量上一次已经绿了，之后 Sources/Tests 没变过：这一遍问的是同一个问题，跳过"
      echo "  （真要再跑一次：./test.sh all --again）"
      exit 0
    fi
    run "$@" || exit $?
    mkdir -p .build && touch "$green_stamp" ;;
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
