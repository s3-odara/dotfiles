#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
  lock)   val=2 ;;  # internal-only
  unlock) val=1 ;;  # allow-all (default)
  *) echo "Usage: $0 {lock|unlock}" >&2; exit 2 ;;
esac

for host in /sys/bus/usb/devices/usb*; do
  if [[ -w "$host/authorized_default" ]]; then
    printf '%s' "$val" > "$host/authorized_default"
  fi
done

