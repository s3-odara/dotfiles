#!/bin/sh
set -eu
umask 077

THRESHOLD="${THRESHOLD:-7}"     # %
INTERVAL="${INTERVAL:-60}"     # 秒
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"

# 同時起動排他（flock 用）
LOCKFILE="$RUNDIR/lowbat-hibernate.flock"

# 閾値以下で一度だけ発火（回復したら解除）
ONESHOT="$RUNDIR/lowbat-hibernate.oneshot"

get_capacity_min() {
  min=101

  set -- /sys/class/power_supply/BAT*/capacity
  [ -e "$1" ] || { echo 101; return; }

  for c in "$@"; do
    [ -r "$c" ] || continue
    v=$(cat "$c" 2>/dev/null || echo "")
    case $v in
      (''|*[!0-9]*) v=101 ;;
    esac
    [ "$v" -lt "$min" ] && min="$v"
  done

  echo "$min"
}

is_discharging() {
  set -- /sys/class/power_supply/BAT*/status
  [ -e "$1" ] || return 1

  for s in "$@"; do
    [ -r "$s" ] || continue
    st=$(cat "$s" 2>/dev/null || echo "")
    [ "$st" = "Discharging" ] && return 0
  done
  return 1
}

run_action() {
  if [ -x "$HOME/.local/bin/lock-and-suspend" ]; then
    "$HOME/.local/bin/lock-and-suspend" || true
  else
    return 1
  fi
}

# ロックファイルを FD 9 で開きっぱなしにする
#（ファイル自体の作成権限は umask 077 に従う）
exec 9>"$LOCKFILE"

while :; do
  # ロックが取れた周回だけ処理する（取れなければ別プロセスが実行中）
  if flock -n 9; then
    # 以降、この周回の処理が終わるまで排他される

    if is_discharging; then
      cap="$(get_capacity_min)"
      if [ "$cap" -le "$THRESHOLD" ]; then
        if [ ! -e "$ONESHOT" ]; then
          if run_action; then
            : > "$ONESHOT"
          fi
        fi
      else
        rm -f "$ONESHOT"
      fi
    else
      rm -f "$ONESHOT"
    fi

    # 周回の処理終了。ロック解放（明示的に）
    flock -u 9 || true
  fi

  sleep "$INTERVAL"
done

