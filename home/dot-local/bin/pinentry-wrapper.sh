#!/bin/bash

REAL_PINENTRY="/usr/bin/pinentry-wayprompt"

systemd-run --user --on-active=900 --unit=reset-gpg-pin.timer /usr/bin/gpgconf --kill gpg-agent

exec "$REAL_PINENTRY" "$@"
