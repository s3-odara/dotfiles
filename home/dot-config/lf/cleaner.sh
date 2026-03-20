#!/bin/sh

set -eu

PATH=/usr/bin:/bin
export PATH

prev_file=${1:-}
next_file=${6:-}

if [ -z "$prev_file" ] || [ "$prev_file" = "$next_file" ]; then
    exit 0
fi

# Clear the terminal so sixel previews from the previous selection do not linger.
# lf redraws the interface immediately after this script returns.
if command -v tput >/dev/null 2>&1; then
    tput clear
else
    printf '\033[H\033[2J'
fi
