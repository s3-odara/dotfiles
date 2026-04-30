#!/bin/bash
set -euo pipefail

# ---- 設定値 ----
HIBERNATE_AFTER_SEC="${HIBERNATE_AFTER_SEC:-14400}"  # 例: 4時間
BAT_CAP_FILE="${BAT_CAP_FILE:-/sys/class/power_supply/BAT0/capacity}"
BAT_FORCE_HIBERNATE_PCT="${BAT_FORCE_HIBERNATE_PCT:-8}"
LOCKFILE="${LOCKFILE:-/run/suspend-then-hibernate.lock}"

LOGTAG="suspend-then-hibernate"

bt_cleanup_needed=0

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
  command -v flock   >/dev/null 2>&1 || { log "ERROR: flock not found"; exit 1; }
  grep -qw disk /sys/power/state || { log "ERROR: disk not supported"; exit 1; }
  grep -qw mem /sys/power/state || { log "ERROR: mem not supported"; exit 1; }
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

cleanup() {
  poweron_bt_best_effort
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

  log "Requesting incus stop --all before hibernate (project=user-1000)"
  if incus stop --all --project user-1000 --timeout 30 >/dev/null 2>&1; then
    log "incus stop --all completed"
    return 0
  fi

  log "incus stop --all timed out or failed; trying --force"
  if incus stop --all --project user-1000 --force >/dev/null 2>&1; then
    log "incus stop --all --force completed"
  else
    log "Failed to stop incus instances; continue to hibernate"
  fi

  return 0
}

poweroff_bt_best_effort() {
  bt_cleanup_needed=0

  if ! command -v bluetoothctl >/dev/null 2>&1; then
    log "bluetoothctl not found; skip BT power off"
    return 0
  fi

  local powered
  powered="$(
    bluetoothctl show 2>/dev/null \
      | awk -F': ' '/Powered:/ {print $2; exit}'
  )"

  if [[ "$powered" != "yes" ]]; then
    log "BT already off; skip BT power off"
    return 0
  fi

  if bluetoothctl power off >/dev/null 2>&1; then
    bt_cleanup_needed=1
    log "BT power off requested"
  else
    log "Failed to power off BT; continue"
  fi
}

poweron_bt_best_effort() {
  (( bt_cleanup_needed )) || return 0
  bt_cleanup_needed=0

  if ! command -v bluetoothctl >/dev/null 2>&1; then
    log "bluetoothctl not found; skip BT power on"
    return 0
  fi

  if bluetoothctl power on >/dev/null 2>&1; then
    log "BT power on requested"
  else
    log "Failed to power on BT"
  fi
}

force_hibernate_now() {
  log "Force hibernate now (reason: $1)"
  poweroff_bt_best_effort
  stop_incus_before_hibernate
  sync || true

  if ! echo disk > /sys/power/state; then
    log "ERROR: failed to write 'disk' to /sys/power/state"
    exit 1
  fi

  log "Returned after hibernate resume; exit"
  exit 0
}

main() {
  local bat start_epoch end_epoch elapsed

  require_root
  require_cmds
  acquire_lock

  trap cleanup EXIT
  trap 'exit 130' INT TERM

  bat="$(get_bat_pct)"
  if [[ -n "$bat" ]] && (( bat <= BAT_FORCE_HIBERNATE_PCT )); then
    force_hibernate_now "battery ${bat}% <= ${BAT_FORCE_HIBERNATE_PCT}% (pre-suspend)"
  fi

  start_epoch="$(date +%s)"
  log "Suspend requested: rtcwake mem for ${HIBERNATE_AFTER_SEC}s (start=${start_epoch})"

  rtcwake -m mem -s "$HIBERNATE_AFTER_SEC"

  end_epoch="$(date +%s)"
  elapsed="$(( end_epoch - start_epoch ))"
  log "Resumed: end=${end_epoch}, elapsed=${elapsed}s"

  if (( elapsed >= HIBERNATE_AFTER_SEC )); then
    force_hibernate_now "elapsed ${elapsed}s >= ${HIBERNATE_AFTER_SEC}s"
  fi

  poweron_bt_best_effort

  if [[ -x /usr/local/bin/cpu-scaling.sh ]]; then
    /usr/local/bin/cpu-scaling.sh || true
    log "cpu-scaling.sh executed"
  fi

  log "Wake was earlier than threshold; skip hibernate (elapsed=${elapsed}s)"
  exit 0
}

main "$@"
