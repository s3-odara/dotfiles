#!/bin/bash
# shellcheck disable=SC2034 # SANDBOX_* globals are consumed by sandbox-backend.sh.

set -eu

# Player launcher policy summary:
# - resolves the target and selected player before sandboxing;
# - validates runtime sockets;
# - constructs a bwrap namespace with minimal /dev nodes and guard-derived
#   read-only binds;
# - passes player-specific RO/RW/Unix-socket environment variables;
# - runs backend resource limits without a preview timeout;
# - delegates final filesystem/seccomp enforcement to player-guard.

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
sandbox_backend_lib="$lf_config_dir/sandbox-backend.sh"
# shellcheck source=/dev/null
. "$sandbox_backend_lib"
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
pipewire_remote=${PIPEWIRE_REMOTE:-pipewire-0}
player_choice=${LF_PLAYER:-auto}
player_extra_args=${LF_PLAYER_ARGS:-}
player_cgroup_mode=${LF_PLAYER_CGROUP:-auto}
cgroup_root=${LF_PLAYER_CGROUP_ROOT:-/sys/fs/cgroup}
player_cpu_quota=${LF_PLAYER_CPU_QUOTA:-300%}
player_memory_high=${LF_PLAYER_MEMORY_HIGH:-2G}
player_memory_max=${LF_PLAYER_MEMORY_MAX:-3G}
player_tasks_max=${LF_PLAYER_TASKS_MAX:-256}
player_extra_rw_paths=/dev/shm
player_extra_unix_socket_paths=
runtime_uid=
if ! parent_dir_logical=$(cd -- "$target_dir" 2>/dev/null && pwd -L) ||
   ! parent_dir=$(cd -- "$target_dir" 2>/dev/null && pwd -P); then
    printf 'playSandbox.sh: cannot resolve target parent: %s\n' "$target_dir" >&2
    exit 1
fi
if [ "$parent_dir_logical" != "$parent_dir" ]; then
    printf 'playSandbox.sh: target parent path contains symlinks: %s\n' "$target_dir" >&2
    exit 1
fi

resolved_target="$parent_dir/$target_name"
if [ -L "$resolved_target" ]; then
    printf 'playSandbox.sh: symlink targets are not supported in sandbox mode: %s\n' "$resolved_target" >&2
    exit 1
elif [ -d "$resolved_target" ]; then
    if ! target_ro_path=$(cd -- "$resolved_target" 2>/dev/null && pwd -P); then
        printf 'playSandbox.sh: cannot resolve target directory: %s\n' "$resolved_target" >&2
        exit 1
    fi
    resolved_target=$target_ro_path
elif [ -f "$resolved_target" ]; then
    target_ro_path=$resolved_target
elif [ -e "$resolved_target" ]; then
    printf 'playSandbox.sh: unsupported target type in sandbox mode: %s\n' "$resolved_target" >&2
    exit 1
else
    target_ro_path=/__lf_sandbox_no_target__
fi

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

resolve_runtime_path() {
    path=$1
    base_dir=$2

    if [ -z "$path" ] || [ -z "$base_dir" ]; then
        return 1
    fi

    case "$path" in
        /*)
            candidate=$path
            ;;
        *)
            candidate=$base_dir/$path
            ;;
    esac

    if [ ! -e "$candidate" ]; then
        return 1
    fi

    candidate_dir=$(dirname -- "$candidate")
    candidate_name=$(basename -- "$candidate")

    if ! resolved_dir=$(cd -- "$candidate_dir" 2>/dev/null && pwd -P); then
        return 1
    fi

    resolved=$resolved_dir/$candidate_name
    case "$resolved" in
        "$base_dir"/*)
            printf '%s\n' "$resolved"
            return 0
            ;;
    esac

    return 1
}

resolve_runtime_socket() {
    path=$1
    base_dir=$2

    if ! resolved=$(resolve_runtime_path "$path" "$base_dir"); then
        return 1
    fi

    if [ ! -S "$resolved" ]; then
        return 1
    fi

    printf '%s\n' "$resolved"
}

resolve_default_pulse_socket() {
    base_dir=$1

    resolve_runtime_socket pulse/native "$base_dir"
}

append_unique_colon_path() {
    list_value=$1
    path_value=$2

    if [ -z "$path_value" ]; then
        printf '%s\n' "$list_value"
        return 0
    fi

    if [ -z "$list_value" ]; then
        printf '%s\n' "$path_value"
        return 0
    fi

    case ":$list_value:" in
        *:"$path_value":*)
            printf '%s\n' "$list_value"
            ;;
        *)
            printf '%s:%s\n' "$list_value" "$path_value"
            ;;
    esac
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

cmd=(
    bwrap
    --unshare-all
    --new-session
    --die-with-parent
    --clearenv
    --setenv HOME "$home_dir"
    --setenv PATH "$safe_path"
    --setenv PLAYER_EXTRA_RO_PATHS "$player_extra_ro_paths"
    --setenv TMPDIR /var/tmp
    --setenv XDG_CONFIG_HOME /tmp/.config
    --setenv XDG_CACHE_HOME /tmp/.cache
    --setenv XDG_DATA_HOME /tmp/.local/share
    --dir /dev
    --dev-bind /dev/null /dev/null
    --dev-bind /dev/zero /dev/zero
    --dev-bind /dev/full /dev/full
    --dev-bind /dev/random /dev/random
    --dev-bind /dev/urandom /dev/urandom
    --tmpfs /home
    --tmpfs /root
    --tmpfs /tmp
    --tmpfs /var/tmp
    --tmpfs /proc
    --tmpfs /sys
    --tmpfs /dev/shm
    --dir "$home_dir"
    --dir "$lf_config_parent"
    --dir "$parent_dir"
)

if ! bind_paths=$(PLAYER_EXTRA_RO_PATHS=$player_extra_ro_paths "$guard_bin" --print-bwrap-ro-paths "$target_ro_path" "$lf_config_dir"); then
    exit 1
fi

while IFS= read -r bind_path; do
    [ -n "$bind_path" ] || continue
    if [ -d "$bind_path" ]; then
        bind_mountpoint=$bind_path
    else
        bind_mountpoint=$(dirname -- "$bind_path")
    fi
    cmd+=(--dir "$bind_mountpoint" --ro-bind "$bind_path" "$bind_path")
done <<< "$bind_paths"

runtime_env_enabled=

if [ -n "$runtime_dir" ] && runtime_dir=$(resolve_runtime_dir "$runtime_dir"); then
    if [ -n "$wayland_display" ] &&
       wayland_socket=$(resolve_runtime_socket "$wayland_display" "$runtime_dir"); then
        wayland_socket_dir=$(dirname -- "$wayland_socket")
        player_extra_unix_socket_paths=$(append_unique_colon_path "$player_extra_unix_socket_paths" "$wayland_socket")
        cmd+=(--dir "$runtime_dir" --dir "$wayland_socket_dir" --bind "$wayland_socket" "$wayland_socket")
        cmd+=(--setenv WAYLAND_DISPLAY "$(basename -- "$wayland_socket")")
        runtime_env_enabled=1
    fi

    pulse_socket=
    if [ -n "$pulse_server" ]; then
        case "$pulse_server" in
            unix:*)
                pulse_candidate=${pulse_server#unix:}
                if pulse_socket=$(resolve_runtime_socket "$pulse_candidate" "$runtime_dir"); then
                    :
                fi
                ;;
            *)
                printf 'playSandbox.sh: non-unix PULSE_SERVER is not supported in sandbox mode: %s\n' "$pulse_server" >&2
                exit 1
                ;;
        esac
    elif pulse_socket=$(resolve_default_pulse_socket "$runtime_dir"); then
        :
    fi

    if [ -n "$pulse_socket" ]; then
        pulse_socket_dir=$(dirname -- "$pulse_socket")
        player_extra_unix_socket_paths=$(append_unique_colon_path "$player_extra_unix_socket_paths" "$pulse_socket")
        cmd+=(--dir "$runtime_dir" --dir "$pulse_socket_dir" --bind "$pulse_socket" "$pulse_socket")
        cmd+=(--setenv PULSE_SERVER "unix:$pulse_socket")
        runtime_env_enabled=1
    fi

    pipewire_base_dir=$runtime_dir
    if [ -n "$pipewire_runtime_dir" ] &&
       pipewire_runtime_dir=$(resolve_pipewire_runtime_dir "$pipewire_runtime_dir"); then
        pipewire_base_dir=$pipewire_runtime_dir
    fi

    if [ -n "$pipewire_remote" ] &&
       pipewire_socket=$(resolve_runtime_socket "$pipewire_remote" "$pipewire_base_dir"); then
        pipewire_socket_dir=$(dirname -- "$pipewire_socket")
        player_extra_unix_socket_paths=$(append_unique_colon_path "$player_extra_unix_socket_paths" "$pipewire_socket")
        cmd+=(--dir "$runtime_dir" --dir "$pipewire_base_dir" --dir "$pipewire_socket_dir" --bind "$pipewire_socket" "$pipewire_socket")
        cmd+=(--setenv PIPEWIRE_RUNTIME_DIR "$pipewire_base_dir")
        cmd+=(--setenv PIPEWIRE_REMOTE "$(basename -- "$pipewire_socket")")
        runtime_env_enabled=1
    fi

    if [ -n "$runtime_env_enabled" ]; then
        cmd+=(--setenv XDG_RUNTIME_DIR "$runtime_dir")
    fi
fi

cmd+=(
    --setenv PLAYER_EXTRA_RW_PATHS "$player_extra_rw_paths"
    --setenv PLAYER_EXTRA_UNIX_SOCKET_PATHS "$player_extra_unix_socket_paths"
    "$guard_bin_real"
    "$target_ro_path"
    "$lf_config_dir"
    "$player"
)

if [ "$player" = "mpv" ]; then
    # Prefer wlshm explicitly. This sandbox does not expose enough DRM/sys/udev
    # state for mpv's gpu/gpu-next backends to initialize reliably, and their
    # fallback to wlshm can race on Wayland.
    cmd+=(--force-window=yes --keep-open=yes --vo=wlshm)
else
    cmd+=(-autoexit)
fi

if [ -n "$player_extra_args" ]; then
    # Intentionally preserve previous unquoted shell-style splitting.
    # shellcheck disable=SC2206
    extra_args=( $player_extra_args )
    cmd+=("${extra_args[@]}")
fi

cmd+=(-- "$resolved_target")

SANDBOX_BACKEND_NAME=player
SANDBOX_BACKEND_MODE=$player_cgroup_mode
SANDBOX_CGROUP_ROOT=$cgroup_root
SANDBOX_TARGET_NAME=$target_name
SANDBOX_CPU_QUOTA=$player_cpu_quota
SANDBOX_MEMORY_HIGH=$player_memory_high
SANDBOX_MEMORY_MAX=$player_memory_max
SANDBOX_TASKS_MAX=$player_tasks_max
SANDBOX_TIMEOUT=
SANDBOX_USE_TIMEOUT=0
SANDBOX_DEBUG=0
SANDBOX_BACKEND_UNAVAILABLE=200
sandbox_backend_run "${cmd[@]}"
