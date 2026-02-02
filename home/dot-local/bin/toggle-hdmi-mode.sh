#!/usr/bin/env bash
set -euo pipefail

# 使い分けたい場合は、実行時に WL_PRESENT_PIPE_NAME を指定
# 例: WL_PRESENT_PIPE_NAME=present1 wl-present-toggle
NAME="${WL_PRESENT_PIPE_NAME:-wl-present}"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$STATE_DIR/wl-present-toggle.${NAME}.pids"
ARGSFILE="$STATE_DIR/wl-present-toggle.${NAME}.args"

# wl-mirror の --title に付与する識別子（この文字列でプロセスを特定して kill します）
TITLE="wl-present:${NAME}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# cmdline から PID を引く（pgrep があれば pgrep、なければ ps+awk）
pids_by_cmdline() {
  local pattern="$1"
  if have_cmd pgrep; then
    pgrep -f -- "$pattern" 2>/dev/null || true
  else
    ps -eo pid=,args= | awk -v pat="$pattern" '$0 ~ pat {print $1}' || true
  fi
}

is_running() {
  # PIDFILE が生きていればそれを優先
  if [[ -f "$PIDFILE" ]]; then
    while IFS= read -r pid; do
      [[ -n "${pid:-}" ]] || continue
      if kill -0 "$pid" 2>/dev/null; then
        return 0
      fi
    done < "$PIDFILE"
  fi

  # フォールバック: wl-mirror の title で生存確認
  local mpids
  mpids="$(pids_by_cmdline "wl-mirror.*--title(=|[[:space:]])${TITLE}")"
  [[ -n "$mpids" ]]
}

stop_mirror() {
  # wl-mirror を title で狙い撃ち
  local mpids
  mpids="$(pids_by_cmdline "wl-mirror.*--title(=|[[:space:]])${TITLE}")"
  if [[ -n "$mpids" ]]; then
    # shellcheck disable=SC2086
    kill $mpids 2>/dev/null || true
    sleep 0.2
    # shellcheck disable=SC2086
    kill -9 $mpids 2>/dev/null || true
  fi

  # wl-present（PIDFILE があればそれも止める）
  if [[ -f "$PIDFILE" ]]; then
    local pids
    pids="$(tr '\n' ' ' < "$PIDFILE" | xargs -r echo || true)"
    if [[ -n "${pids:-}" ]]; then
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 0.2
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    fi
  fi

  rm -f "$PIDFILE"
}

start_mirror() {
  local -a args=()

  # 引数があれば「次回以降も同じ設定で ON できるように」保存
  # （引数なしで ON したい場合は、wl-present が slurp 等で対話的に尋ねる挙動になります）
  if (($#)); then
    printf '%s\n' "$@" > "$ARGSFILE"
  fi
  if [[ -f "$ARGSFILE" ]]; then
    mapfile -t args < "$ARGSFILE"
  fi

  # ユーザが --title を渡していない場合のみ、識別用 title を付与（トグル OFF の安定性が上がります）
  local has_title=0
  for a in "${args[@]}"; do
    if [[ "$a" == "--title" || "$a" == --title=* ]]; then
      has_title=1
      break
    fi
  done
  if [[ $has_title -eq 0 ]]; then
    args+=(--title "$TITLE")
  fi

  # wl-present をバックグラウンド起動して PID を保存
  WL_PRESENT_PIPE_NAME="$NAME" wl-present -n "$NAME" mirror "${args[@]}" &
  local wlp_pid=$!
  printf '%s\n' "$wlp_pid" > "$PIDFILE"

  # 可能なら子プロセス（wl-mirror）も PIDFILE に追記（停止を速く・確実に）
  sleep 0.2
  if have_cmd pgrep; then
    local child
    child="$(pgrep -P "$wlp_pid" -x wl-mirror 2>/dev/null || true)"
    if [[ -n "$child" ]]; then
      printf '%s\n' "$child" >> "$PIDFILE"
    fi
  fi

  disown "$wlp_pid" 2>/dev/null || true
}

main() {
  if is_running; then
    stop_mirror
  else
    start_mirror "$@"
  fi
}

main "$@"

