#!/usr/bin/env bash
# udevから呼ばれるのでwayland環境変数を設定
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY=$(ls "${XDG_RUNTIME_DIR}" | grep '^wayland-' | head -n1)

INTERNAL=eDP-1
EXTERNAL=HDMI-A-1

# 接続状態をチェック
status=$(</sys/class/drm/card0-${EXTERNAL}/status)

if [ "$status" = "connected" ]; then
    wlr-randr \
        --output eDP-1    --mode 1920x1080 \
        --output HDMI-A-1 --mode 1920x1080 --right-of eDP-1
else
    wlr-randr \
        --output "$INTERNAL" --mode 1920x1080 \
        --output "$EXTERNAL" --off
fi

