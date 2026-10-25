#!/bin/bash
# Delivery: one at a time, waiting its turn instead of being retried, and
# building the app only when the merge could have changed it.
#
#   ./deliver.sh <slug> [--wait SECONDS]   merge feat/<slug>, build if the app
#                                          changed, remove tree and branch
#   ./deliver.sh --ready [--wait SECONDS]  the same for every branch that can be
#                                          merged cleanly — one window, one
#                                          build, one cleanup
#   ./deliver.sh --status                  who holds the lock, what is pending,
#                                          whether build/ covers HEAD
#
# What it refuses, and why, is in AGENTS.md「并行交付」. In short: the main
# checkout never holds a task of its own; a branch that conflicts is settled in
# its tree; a lock whose process is gone is taken over; and a failed build takes
# back this delivery's merges and leaves the trees alone.
#
# The build is the expensive part — a release build here is whole-module, a
# hundred seconds or more whatever changed — so it happens only when the commit
# the app in build/ was built from is behind HEAD on a file the app is made of.
# That commit is kept in .git/artifact.
set -euo pipefail
cd "$(dirname "$0")"

app_paths='^(Sources/|Resources/|Engine/|Package\.swift$|VERSION$)'
git_dir="$(git rev-parse --absolute-git-dir)"
lock="$git_dir/deliver.lock"
stamp="$git_dir/artifact"
main_tree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"

usage() {
  echo "usage: ./deliver.sh <slug> [--wait SECONDS] | --ready [--wait SECONDS] | --status" >&2
  exit 1
}
refuse() { echo "交付停下：$*" >&2; exit 1; }

mode=single; slug=""; wait_seconds=300
while [ $# -gt 0 ]; do
  case "$1" in
    --status) mode=status; shift ;;
    --ready) mode=ready; shift ;;
    --wait) wait_seconds="${2:-300}"; shift 2 ;;
    --wait=*) wait_seconds="${1#--wait=}"; shift ;;
    --no-wait) wait_seconds=0; shift ;;
    -*) usage ;;
    *) [ -z "$slug" ] || usage; slug="$1"; shift ;;
  esac
done

# Did anything the app is built of change since that commit?
touch_apps() {
  local from="${1:-}" files
  [ -n "$from" ] || return 0
  git rev-parse --verify --quiet "$from^{commit}" >/dev/null 2>&1 || return 0
  git merge-base --is-ancestor "$from" HEAD 2>/dev/null || return 0
  files="$(git diff --name-only "$from" HEAD)"
  [ -n "$files" ] && printf '%s\n' "$files" | grep -qE "$app_paths"
}

since_stamp() { cat "$stamp" 2>/dev/null || true; }

tree_of() {
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    $1 == "worktree" { where = $2 }
    $1 == "branch" && $2 == b { print where }'
}

pending_branches() {
  git for-each-ref --sort=committerdate --format='%(refname:short)' refs/heads/feat/
}

holder_line() {
  [ -d "$lock" ] || return 1
  cat "$lock/who" 2>/dev/null || true
  return 0
}

status() {
  local holder pid dirty since branch tree state n=0
  if holder="$(holder_line)"; then
    pid="${holder%% *}"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "锁：pid $pid 正在交付（${holder#* }）"
    else
      echo "锁：${holder:-（没写是谁）}，但那个进程已不在——下次交付会接管"
    fi
  else
    echo "锁：无"
  fi

  dirty="$(git status --porcelain)"
  if [ -z "$dirty" ]; then echo "主仓：干净"
  else echo "主仓：$(printf '%s\n' "$dirty" | wc -l | tr -d ' ') 项未提交（合并会被这些挡住）"; fi

  since="$(since_stamp)"
  if [ -z "$since" ]; then
    echo "产物：没有构建记录（.git/artifact 空）"
  elif touch_apps "$since"; then
    echo "产物：build/ 由 $(git rev-parse --short "$since" 2>/dev/null || echo "$since") 构建，此后 app 相关的文件变过——已过期"
  else
    echo "产物：build/ 由 $(git rev-parse --short "$since" 2>/dev/null || echo "$since") 构建，覆盖当前 HEAD"
  fi

  echo "待交付："
  for branch in $(pending_branches); do
    n=$((n + 1))
    tree="$(tree_of "$branch")"
    if [ -n "$tree" ] && [ -n "$(git -C "$tree" status --porcelain)" ]; then
      state="树里有未提交的改动"
    elif ! git merge-tree --write-tree main "$branch" >/dev/null 2>&1; then
      state="与 main 冲突（先在树里 merge main）"
    elif [ -z "$tree" ]; then
      state="可合（没有树，合完不留树）"
    else
      state="可合"
    fi
    printf '  %-30s %-24s %s\n' "$branch" "${tree:-—}" "$state"
  done
  [ "$n" -gt 0 ] || echo "  （没有 feat/ 分支）"
}

if [ "$mode" = status ]; then
  status
  exit 0
fi

# Every merge here is the main checkout's, and only one runs at a time.
[ "$(git rev-parse --show-toplevel)" = "$main_tree" ] \
  || refuse "要在主仓检出里跑（$(pwd) 是一棵树，不是主仓）"

# Waiting happens here, saying who holds it, rather than being handed back as
# a `sleep` loop. A lock whose process is gone is taken over: a killed
# delivery must not stop every other one.
waited=0
while :; do
  if mkdir "$lock" 2>/dev/null; then
    trap 'rm -rf "$lock"' EXIT
    echo "$$ $(date '+%F %T') ${slug:-ready}" > "$lock/who"
    break
  fi
  holder="$(holder_line)"
  held_pid="${holder%% *}"
  if [ -n "$held_pid" ] && ! kill -0 "$held_pid" 2>/dev/null; then
    echo "锁被「${holder:-（没写是谁）}」拿着，但那个进程已经不在了：接管"
    rm -rf "$lock"
    continue
  fi
  [ "$waited" -lt "$wait_seconds" ] || \
    refuse "另一个交付拿锁超过了 ${wait_seconds}s：${holder:-（没写是谁）}；再来一次加 --wait 600"
  [ $((waited % 10)) -ne 0 ] || echo "等锁：${holder:-（没写是谁）}（已等 ${waited}s，上限 ${wait_seconds}s）"
  sleep 2
  waited=$((waited + 2))
done

dirty="$(git status --porcelain)"
dirty_paths="$(printf '%s\n' "$dirty" | sed 's/^...//' | sort)"
before="$(git rev-parse HEAD)"

branches=(); reasons=()
if [ "$mode" = ready ]; then
  for branch in $(pending_branches); do
    tree="$(tree_of "$branch")"
    if [ "$(git rev-list --count "main..$branch")" -eq 0 ]; then
      reasons+=("$branch：没有新提交"); continue
    fi
    if [ -n "$tree" ] && [ -n "$(git -C "$tree" status --porcelain)" ]; then
      reasons+=("$branch：树里有未提交的改动"); continue
    fi
    branches+=("$branch")
  done
else
  branch="feat/$slug"
  git show-ref --verify --quiet "refs/heads/$branch" || refuse "没有分支 $branch"
  tree="$(tree_of "$branch")"
  [ -n "$tree" ] || refuse "没有树 ../Aura-$slug（先 git worktree add ../Aura-$slug -b $branch）"
  tree_dirty="$(git -C "$tree" status --porcelain)"
  [ -z "$tree_dirty" ] || { printf '%s\n' "$tree_dirty" >&2; refuse "树 $tree 里有未提交的改动"; }
  [ "$(git rev-list --count "main..$branch")" -gt 0 ] || refuse "$branch 相对 main 没有提交，没有可交付的"
  branches=("$branch")
fi
[ ${#branches[@]} -gt 0 ] || { for r in "${reasons[@]}"; do echo "跳过 $r" >&2; done; refuse "没有可交付的分支"; }

merged=()
for branch in "${branches[@]}"; do
  coming="$(git diff --name-only "main...$branch")"
  clash="$(comm -12 <(printf '%s\n' "$coming" | sort) <(printf '%s\n' "$dirty_paths") | grep . || true)"
  if [ -n "$clash" ]; then
    printf '%s\n' "$clash" >&2
    if [ "$mode" = ready ]; then reasons+=("$branch：与主仓里未提交的改动重叠"); continue; fi
    refuse "主仓里这些文件正被别人改着，与本次合并重叠：等那份活提交或进树再来"
  fi
  if ! git merge-tree --write-tree main "$branch" >/dev/null 2>&1; then
    if [ "$mode" = ready ]; then reasons+=("$branch：与 main 冲突，先在树里 merge main"); continue; fi
    refuse "$branch 与 main 会冲突：先在树里 git -C $tree merge main，冲突、构建、测试都过了再回来"
  fi
  git merge --no-ff "$branch" -m "合并 $branch：$(git log -1 --format=%s "$branch")"
  merged+=("$branch")
done
[ ${#merged[@]} -gt 0 ] || { for r in "${reasons[@]}"; do echo "跳过 $r" >&2; done; refuse "没有合进去的分支"; }

# One build for this delivery, and only when it can show something new.
since="$(since_stamp)"
if ! touch_apps "$since"; then
  echo "不重建：自 $(git rev-parse --short "${since:-HEAD}" 2>/dev/null || echo —) 起 app 相关的文件没变，build/ 已覆盖 HEAD"
elif [ -n "$dirty" ]; then
  echo "不重建：主仓还有别人的活（$(printf '%s\n' "$dirty" | wc -l | tr -d ' ') 项），产物会把那份活编进去；主仓干净后跑 ./build.sh"
else
  if ! ./build.sh; then
    git reset --hard "$before"
    refuse "构建失败，这批合并已撤回（main 回到 $(git rev-parse --short HEAD)）；树与分支都留着"
  fi
  git rev-parse HEAD > "$stamp"
fi

for branch in "${merged[@]}"; do
  tree="$(tree_of "$branch")"
  if [ -n "$tree" ]; then
    git worktree remove "$tree" || { echo "树 $tree 没能删（里面可能又长出新东西），留着" >&2; continue; }
  fi
  git branch -d "$branch" >/dev/null || { echo "分支 $branch 没能删（可能没合全），留着" >&2; continue; }
done
trap - EXIT
rm -rf "$lock"

echo "交付完成：$(git log --oneline -1)"
for r in "${reasons[@]}"; do echo "  跳过 $r"; done
echo "  产物：build/ $(date -r build/Aura.app/Contents/MacOS/Aura '+%F %T' 2>/dev/null || echo 没有)，构建自 $(git rev-parse --short "$(since_stamp)" 2>/dev/null || echo —)"
echo "  worktree：$(git worktree list | wc -l | tr -d ' ') 个；未合并的任务分支：$(git branch --no-merged main | grep -vc gh-pages || true) 个；stash：$(git stash list | wc -l | tr -d ' ') 项"
