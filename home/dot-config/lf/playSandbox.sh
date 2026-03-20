#!/bin/sh

set -eu

PATH=/usr/bin:/bin
export PATH

if [ "$#" -lt 1 ]; then
    printf 'playSandbox.sh: expected at least 1 arg\n' >&2
    exit 1
fi

target=$1
shift

home_dir=${HOME:-/home/user}
lf_config_dir="$home_dir/.config/lf"
lf_config_parent=$(dirname -- "$lf_config_dir")
guard_bin="$lf_config_dir/player-guard"
guard_bin_real=$(readlink -f -- "$guard_bin")
safe_path=/usr/bin:/bin
target_dir=$(dirname -- "$target")
target_name=$(basename -- "$target")
runtime_dir=${XDG_RUNTIME_DIR:-}
wayland_display=${WAYLAND_DISPLAY:-}
pulse_server=${PULSE_SERVER:-}
pipewire_runtime_dir=${PIPEWIRE_RUNTIME_DIR:-}
player_choice=${LF_PLAYER:-auto}
player_extra_args=${LF_PLAYER_ARGS:-}
player_extra_rw_paths=/dev/shm
runtime_uid=

if ! parent_dir=$(cd -- "$target_dir" 2>/dev/null && pwd -P); then
    printf 'playSandbox.sh: cannot resolve target parent: %s\n' "$target_dir" >&2
    exit 1
fi

resolved_target="$parent_dir/$target_name"

resolve_runtime_dir() {
    path=$1

    if [ -z "$path" ] || [ "${path#/}" = "$path" ]; then
        return 1
    fi

    if ! resolved=$(cd -- "$path" 2>/dev/null && pwd -P); then
        return 1
    fi

    if [ "$resolved" = "/" ]; then
        return 1
    fi

    if ! owner_uid=$(stat -Lc '%u' -- "$resolved" 2>/dev/null); then
        return 1
    fi

    if [ "$owner_uid" != "$runtime_uid" ]; then
        return 1
    fi

    printf '%s\n' "$resolved"
    return 0
}

resolve_pipewire_runtime_dir() {
    path=$1

    if [ -z "$path" ]; then
        return 1
    fi

    case "$path" in
        /*)
            resolve_runtime_dir "$path"
            return $?
            ;;
    esac

    if [ -z "$runtime_dir" ]; then
        return 1
    fi

    case "$path" in
        */*|.|..)
            return 1
            ;;
    esac

    resolve_runtime_dir "$runtime_dir/$path"
}

select_player() {
    case "$player_choice" in
        mpv)
            if command -v mpv >/dev/null 2>&1; then
                printf 'mpv\n'
                return 0
            fi
            ;;
        ffplay)
            if command -v ffplay >/dev/null 2>&1; then
                printf 'ffplay\n'
                return 0
            fi
            ;;
        auto)
            if command -v mpv >/dev/null 2>&1; then
                printf 'mpv\n'
                return 0
            fi
            if command -v ffplay >/dev/null 2>&1; then
                printf 'ffplay\n'
                return 0
            fi
            ;;
    esac

    return 1
}

if ! player=$(select_player); then
    printf 'playSandbox.sh: mpv or ffplay not found in PATH\n' >&2
    exit 1
fi

runtime_uid=$(id -u)

player_bin=$(command -v -- "$player")
player_bin_real=$(readlink -f -- "$player_bin")
player_bin_dir=$(dirname -- "$player_bin_real")
guard_bin_dir=$(dirname -- "$guard_bin_real")
player_extra_ro_paths=$player_bin_dir
if [ "$guard_bin_dir" != "$player_bin_dir" ]; then
    player_extra_ro_paths=$player_extra_ro_paths:$guard_bin_dir
fi

set -- \
    bwrap \
    --unshare-all \
    --new-session \
    --die-with-parent \
    --clearenv \
    --setenv HOME "$home_dir" \
    --setenv PATH "$safe_path" \
    --setenv PLAYER_EXTRA_RO_PATHS "$player_extra_ro_paths" \
    --setenv TMPDIR /var/tmp \
    --setenv XDG_CONFIG_HOME /tmp/.config \
    --setenv XDG_CACHE_HOME /tmp/.cache \
    --setenv XDG_DATA_HOME /tmp/.local/share \
    --dev /dev \
    --tmpfs /home \
    --tmpfs /root \
    --tmpfs /tmp \
    --tmpfs /var/tmp \
    --tmpfs /proc \
    --tmpfs /sys \
    --tmpfs /dev/shm \
    --dir "$home_dir" \
    --dir "$lf_config_parent" \
    --dir "$parent_dir"

bind_paths=$(PLAYER_EXTRA_RO_PATHS=$player_extra_ro_paths "$guard_bin" --print-bwrap-ro-paths "$parent_dir" "$lf_config_dir")
old_ifs=$IFS
IFS='
'
for bind_path in $bind_paths; do
    set -- "$@" --dir "$bind_path" --ro-bind "$bind_path" "$bind_path"
done
IFS=$old_ifs

if [ -n "$runtime_dir" ] && runtime_dir=$(resolve_runtime_dir "$runtime_dir"); then
    set -- "$@" --dir "$runtime_dir" --bind "$runtime_dir" "$runtime_dir"
    set -- "$@" --setenv XDG_RUNTIME_DIR "$runtime_dir"
    player_extra_rw_paths=$player_extra_rw_paths:$runtime_dir
fi

if [ -n "$wayland_display" ]; then
    set -- "$@" --setenv WAYLAND_DISPLAY "$wayland_display"
fi

if [ -n "$pulse_server" ]; then
    set -- "$@" --setenv PULSE_SERVER "$pulse_server"
fi

if [ -n "$pipewire_runtime_dir" ]; then
    if pipewire_runtime_dir=$(resolve_pipewire_runtime_dir "$pipewire_runtime_dir"); then
        set -- "$@" --setenv PIPEWIRE_RUNTIME_DIR "$pipewire_runtime_dir"
        player_extra_rw_paths=$player_extra_rw_paths:$pipewire_runtime_dir
    fi
fi

set -- "$@" \
    --setenv PLAYER_EXTRA_RW_PATHS "$player_extra_rw_paths" \
    "$guard_bin_real" \
    "$parent_dir" \
    "$lf_config_dir" \
    "$player"

if [ "$player" = "mpv" ]; then
    set -- "$@" --force-window=yes
else
    set -- "$@" -autoexit
fi

if [ -n "$player_extra_args" ]; then
    # shellcheck disable=SC2086
    set -- "$@" $player_extra_args
fi

set -- "$@" "$resolved_target"

exec "$@"
