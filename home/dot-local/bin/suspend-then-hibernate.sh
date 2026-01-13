#!/bin/bash
set -euo pipefail

# ---- 設定値 ----
HIBERNATE_AFTER_SEC="${HIBERNATE_AFTER_SEC:-14400}"  # 例: 4時間
BAT_CAP_FILE="${BAT_CAP_FILE:-/sys/class/power_supply/BAT0/capacity}"
BAT_FORCE_HIBERNATE_PCT="${BAT_FORCE_HIBERNATE_PCT:-10}"
ELAPSED_TOLERANCE_SEC="${ELAPSED_TOLERANCE_SEC:-45}" # RTC/時刻差の吸収

LOGTAG="suspend-then-hibernate"

log() { logger -t "$LOGTAG" -- "$*"; }

get_bat_pct() {
  if [[ -r "$BAT_CAP_FILE" ]]; then
    tr -d ' \n' < "$BAT_CAP_FILE" | sed 's/[^0-9]//g'
  else
    echo ""
  fi
}

force_hibernate_now() {
  log "Force hibernate now (reason: $1)"
  sync
  # hibernate
  echo disk > /sys/power/state
  exit 0
}

disable_wakealarm_best_effort() {
  # rtcwake が消してくれるケースもありますが、念のため両方試す
  if command -v rtcwake >/dev/null 2>&1; then
    rtcwake -m disable >/dev/null 2>&1 || true
  fi
  for rtc in /sys/class/rtc/rtc*; do
    [[ -w "$rtc/wakealarm" ]] || continue
    echo 0 > "$rtc/wakealarm" 2>/dev/null || true
  done
}

main() {
  # 事前バッテリー判定
  bat="$(get_bat_pct)"
  if [[ -n "$bat" ]] && (( bat <= BAT_FORCE_HIBERNATE_PCT )); then
    force_hibernate_now "battery ${bat}% <= ${BAT_FORCE_HIBERNATE_PCT}% (pre-suspend)"
  fi

  start_epoch="$(date +%s)"
  log "Suspend requested: rtcwake mem for ${HIBERNATE_AFTER_SEC}s (start=${start_epoch})"

  # ここで「RTCアラームセット + サスペンド」を実行し、復帰後に戻ってくる
  rtcwake -m mem -s "$HIBERNATE_AFTER_SEC"

  end_epoch="$(date +%s)"
  elapsed="$(( end_epoch - start_epoch ))"
  log "Resumed: end=${end_epoch}, elapsed=${elapsed}s"

  # 起床理由がユーザー操作でもRTCでも、残っているアラームは消しておく
  disable_wakealarm_best_effort

  # 復帰後処理（必要ならここで）
  if [[ -x /usr/local/bin/cpu-scaling.sh ]]; then
    /usr/local/bin/cpu-scaling.sh || true
    log "cpu-scaling.sh executed"
  fi

  # 「指定時間以上眠っていた」場合のみ hibernate
  # ユーザーが途中で起こした場合は elapsed が短いので何もしない
  if (( elapsed + ELAPSED_TOLERANCE_SEC >= HIBERNATE_AFTER_SEC )); then
    force_hibernate_now "elapsed ${elapsed}s >= ${HIBERNATE_AFTER_SEC}s"
  fi

  log "Wake was earlier than threshold; skip hibernate (elapsed=${elapsed}s)"
  exit 0
}

main "$@"

