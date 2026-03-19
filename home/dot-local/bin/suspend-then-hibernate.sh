#!/bin/bash
set -euo pipefail

# ---- 設定値 ----
HIBERNATE_AFTER_SEC="${HIBERNATE_AFTER_SEC:-14400}"  # 例: 4時間
BAT_CAP_FILE="${BAT_CAP_FILE:-/sys/class/power_supply/BAT0/capacity}"
BAT_FORCE_HIBERNATE_PCT="${BAT_FORCE_HIBERNATE_PCT:-8}"
ELAPSED_TOLERANCE_SEC="${ELAPSED_TOLERANCE_SEC:-45}" # RTC/時刻差の吸収

LOCKFILE="${LOCKFILE:-/run/suspend-then-hibernate.lock}"

LOGTAG="suspend-then-hibernate"

log() {
  logger -t "$LOGTAG" -- "$*" || true
}

require_root() {
  if (( EUID != 0 )); then
    log "ERROR: must be run as root"
    exit 1
  fi
}

require_cmds() {
  command -v rtcwake >/dev/null 2>&1 || { log "ERROR: rtcwake not found"; exit 1; }
  [[ -w /sys/power/state ]] || { log "ERROR: /sys/power/state not writable"; exit 1; }
}

get_bat_pct() {
  if [[ -r "$BAT_CAP_FILE" ]]; then
    local v
    v="$(tr -d ' \n' < "$BAT_CAP_FILE" | sed 's/[^0-9]//g')"
    [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo ""
  else
    echo ""
  fi
}

disable_wakealarm_best_effort() {
  # rtcwake が消してくれるケースもあるが、念のため両方試す
  if command -v rtcwake >/dev/null 2>&1; then
    rtcwake -m disable >/dev/null 2>&1 || true
  fi
  for rtc in /sys/class/rtc/rtc*; do
    [[ -w "$rtc/wakealarm" ]] || continue
    echo 0 > "$rtc/wakealarm" 2>/dev/null || true
  done
}

acquire_lock() {
  exec 9>"$LOCKFILE"
  if ! flock -n 9; then
    log "Another instance is running; exit"
    exit 0
  fi
}

stop_incus_before_hibernate() {
  if ! command -v incus >/dev/null 2>&1; then
    log "incus is not installed; skip stop before hibernate"
    return 0
  fi

  local -a instances
  mapfile -t instances < <(incus list --format csv -c ns 2>/dev/null | awk -F, '$2 == "RUNNING" { print $1 }')

  if (( ${#instances[@]} == 0 )); then
    log "No running incus instances; skip stop before hibernate"
    return 0
  fi

  log "Stopping incus instances before hibernate: ${instances[*]}"
  if ! incus stop "${instances[@]}" --timeout 30; then
    log "Clean incus stop timed out or failed; forcing stop"
    if ! incus stop "${instances[@]}" --force; then
      log "Failed to force stop one or more incus instances; continue to hibernate"
    fi
  fi
}

force_hibernate_now() {
  log "Force hibernate now (reason: $1)"
  stop_incus_before_hibernate
  sync || true

  if ! ( echo disk > /sys/power/state ); then
    log "ERROR: failed to write 'disk' to /sys/power/state"
    exit 1
  fi

  log "WARN: returned from hibernate request unexpectedly"
  exit 0
}

main() {
  require_root
  require_cmds
  acquire_lock

  # 異常終了時にもアラームを消しに行く
  trap 'disable_wakealarm_best_effort' EXIT INT TERM

  bat="$(get_bat_pct)"
  if [[ -n "$bat" ]] && (( bat <= BAT_FORCE_HIBERNATE_PCT )); then
    force_hibernate_now "battery ${bat}% <= ${BAT_FORCE_HIBERNATE_PCT}% (pre-suspend)"
  fi

  start_epoch="$(date +%s)"
  log "Suspend requested: rtcwake mem for ${HIBERNATE_AFTER_SEC}s (start=${start_epoch})"

  bt_connected_before=()
  if command -v bluetoothctl >/dev/null 2>&1; then
    mapfile -t bt_connected_before < <(bluetoothctl devices Connected | awk '{print $2}')
  fi

  for mac in "${bt_connected_before[@]}"; do
    [[ -n "$mac" ]] || continue
    bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
  done
  log "BT disconnect requested (macs=${bt_connected_before[*]:-none})"

  rtcwake -m mem -s "$HIBERNATE_AFTER_SEC"

  end_epoch="$(date +%s)"
  elapsed="$(( end_epoch - start_epoch ))"
  log "Resumed: end=${end_epoch}, elapsed=${elapsed}s"

  disable_wakealarm_best_effort

  for mac in "${bt_connected_before[@]}"; do
    [[ -n "$mac" ]] || continue
    bluetoothctl connect "$mac" >/dev/null 2>&1 || true
  done
  log "BT connect requested (macs=${bt_connected_before[*]:-none})"

  if [[ -x /usr/local/bin/cpu-scaling.sh ]]; then
    /usr/local/bin/cpu-scaling.sh || true
    log "cpu-scaling.sh executed"
  fi

  if (( elapsed + ELAPSED_TOLERANCE_SEC >= HIBERNATE_AFTER_SEC )); then
    force_hibernate_now "elapsed ${elapsed}s >= ${HIBERNATE_AFTER_SEC}s"
  fi

  log "Wake was earlier than threshold; skip hibernate (elapsed=${elapsed}s)"
  exit 0
}

main "$@"
