# ~/.zshenv
# NOTE: This file is sourced for *every* zsh invocation (interactive/non-interactive).
# Keep it minimal. Avoid running external commands here.

# XDG base dirs (safe defaults)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Common tools
export EDITOR="${EDITOR:-vim}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--iMR --mouse}"

# incus
export INCUS_SOCKET=/var/lib/incus/unix.socket.user
export INCUS_PROJECT=user-1000

# pass(1) / password-store
export PASSWORD_STORE_CHARACTER_SET='[:alnum:]!'
export PASSWORD_STORE_GENERATED_LENGTH=22
export PASSWORD_STORE_CLIP_TIME=10

# GnuPG / SSH agent socket (no gpgconf here)
export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"

