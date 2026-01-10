export XMODIFIERS=@im=fcitx
export MOZ_ENABLE_WAYLAND='1 firefox'
export QT_QPA_PLATFORM=WAYLAND
export EDITOR=vim

unset SSH_AGENT_PID
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi


export PASSWORD_STORE_CHARACTER_SET=[:alnum:]!
export PASSWORD_STORE_GENERATED_LENGTH=22
export PASSWORD_STORE_CLIP_TIME=10

export PAGER=less
export LESS='-iMR --mouse'

