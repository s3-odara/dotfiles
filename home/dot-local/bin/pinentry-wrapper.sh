#!/usr/bin/env zsh

PINENTRY_WOFI="/home/user/.local/bin/pinentry-wofi"
PINENTRY_CURSES="/usr/bin/pinentry-curses"

if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  exec "$PINENTRY_WOFI" "$@"
fi

exec "$PINENTRY_CURSES" "$@"
