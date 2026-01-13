#!/usr/bin/env bash
set -euo pipefail

INTERNAL=${INTERNAL:-eDP-1}
EXTERNAL=${EXTERNAL:-HDMI-A-1}

# river の keybind から起動される前提（環境変数は river セッション側のものを使う）
: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set (run from your river session)}"
: "${WAYLAND_DISPLAY:?WAYLAND_DISPLAY is not set (run from your river session)}"

# 接続状態（card番号固定を避ける）
status_path="$(echo /sys/class/drm/*-"$EXTERNAL"/status | head -n1)"
[[ -e "$status_path" ]] || exit 0
status="$(<"$status_path")"

state_file="${XDG_RUNTIME_DIR}/river-display-mode"
lock_file="${XDG_RUNTIME_DIR}/river-display-mode.lock"

# 連打対策（util-linux の flock）
exec 9>"$lock_file"
flock 9

if [[ "$status" != "connected" ]]; then
  # 抜かれているなら外部OFF＆状態リセット
  wlr-randr --output "$EXTERNAL" --off
  rm -f "$state_file"
  exit 0
fi

# 初回（state_file無し）は extend から開始
current="none"
[[ -f "$state_file" ]] && current="$(<"$state_file")"

if [[ "$current" == "extend" ]]; then
  # 疑似ミラー：同一座標に重ねる（内部が 0,0 前提）
  wlr-randr --output "$EXTERNAL" --on --pos 0,0
  echo "mirror" > "$state_file"
else
  # 拡張（右に追加）
  wlr-randr --output "$EXTERNAL" --on --right-of "$INTERNAL"
  echo "extend" > "$state_file"
fi

