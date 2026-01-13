#!/bin/sh
set -eu

waylock -ignore-empty-password -fork-on-lock

doas /usr/local/bin/suspend-then-hibernate.sh

