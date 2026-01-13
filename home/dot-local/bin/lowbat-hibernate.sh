#!/bin/sh
set -eu

THRESHOLD="${THRESHOLD:-7}"   # %
INTERVAL="${INTERVAL:-181}"    # 秒
LOCK="${XDG_RUNTIME_DIR:-/tmp}/lowbat-hibernate.lock"

get_capacity_min() {
  min=101
  for c in /sys/class/power_supply/BAT*/capacity; do
    [ -r "$c" ] || continue
    v="$(cat "$c" 2>/dev/null || echo 101)"
    [ "$v" -lt "$min" ] && min="$v"
  done
  echo "$min"
}

is_discharging() {
  for s in /sys/class/power_supply/BAT*/status; do
    [ -r "$s" ] || continue
    [ "$(cat "$s" 2>/dev/null || true)" = "Discharging" ] && return 0
  done
  return 1
}

while :; do
  if is_discharging; then
    cap="$(get_capacity_min)"
    if [ "$cap" -le "$THRESHOLD" ]; then
      if [ ! -e "$LOCK" ]; then
        : > "$LOCK"
        /usr/local/bin/call-hibernate || true
      fi
    else
      rm -f "$LOCK"
    fi
  else
    rm -f "$LOCK"
  fi
  sleep "$INTERVAL"
done

