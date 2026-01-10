# ~/.zprofile
# Login shell initialization (once per login session).

# XDG_RUNTIME_DIR fallback for openrc/no-elogind setups
if [[ -z "${XDG_RUNTIME_DIR}" ]]; then
  export XDG_RUNTIME_DIR="/tmp/${UID}-runtime-dir"
  if [[ ! -d "${XDG_RUNTIME_DIR}" ]]; then
    mkdir -p -- "${XDG_RUNTIME_DIR}" && chmod 0700 -- "${XDG_RUNTIME_DIR}"
  fi
fi

# SSH_AUTH_SOCKの場所を取得
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  gpg-connect-agent /bye >/dev/null 2>&1
  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi

# RemoteForward用にextra_sockの場所を取得
export GPG_AGENT_EXTRA_SOCK="$(gpgconf --list-dirs agent-extra-socket)"


# Wayland / IM (river 前提ならセッション単位で export してよい)
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export XMODIFIERS=@im=fcitx

# Ensure gpg-agent is running (ssh-support is enabled in gpg-agent.conf)
if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --launch gpg-agent >/dev/null 2>&1
fi

