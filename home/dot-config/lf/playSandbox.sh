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
pipewire_remote=${PIPEWIRE_REMOTE:-pipewire-0}
player_choice=${LF_PLAYER:-auto}
player_extra_args=${LF_PLAYER_ARGS:-}
player_cgroup_mode=${LF_PLAYER_CGROUP:-auto}
cgroup_root=${LF_PLAYER_CGROUP_ROOT:-/sys/fs/cgroup}
player_cpu_quota=${LF_PLAYER_CPU_QUOTA:-300%}
player_memory_high=${LF_PLAYER_MEMORY_HIGH:-2G}
player_memory_max=${LF_PLAYER_MEMORY_MAX:-3G}
player_tasks_max=${LF_PLAYER_TASKS_MAX:-256}
player_gpu=${LF_PLAYER_GPU:-0}
player_gpu_render_node=${LF_PLAYER_GPU_RENDER_NODE:-/dev/dri/renderD128}
player_extra_rw_paths=/dev/shm
runtime_uid=
backend_unavailable=200

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

resolve_gpu_render_node() {
    path=$1

    if [ -z "$path" ] || [ "${path#/}" = "$path" ]; then
        return 1
    fi

    path_dir=$(dirname -- "$path")
    path_name=$(basename -- "$path")

    if ! resolved_dir=$(cd -- "$path_dir" 2>/dev/null && pwd -P); then
        return 1
    fi

    resolved=$resolved_dir/$path_name
    if [ ! -c "$resolved" ]; then
        return 1
    fi

    printf '%s\n' "$resolved"
}

append_unique_colon_path() {
    list_value=$1
    path_value=$2

    if [ -z "$path_value" ]; then
        printf '%s\n' "$list_value"
        return 0
    fi

    case ":$list_value:" in
        *:"$path_value":*)
            printf '%s\n' "$list_value"
            ;;
        :)
            printf '%s\n' "$path_value"
            ;;
        *)
            printf '%s:%s\n' "$list_value" "$path_value"
            ;;
    esac
}

debug_log() {
    :
}

systemd_run_available() {
    command -v systemd-run >/dev/null 2>&1 &&
        systemd-run --user --scope --quiet true >/dev/null 2>&1
}

systemd_run_supports_limits() {
    systemd-run --user --scope --quiet \
        -p "MemoryHigh=$player_memory_high" \
        -p "MemoryMax=$player_memory_max" \
        -p "TasksMax=$player_tasks_max" \
        -p "CPUQuota=$player_cpu_quota" \
        true >/dev/null 2>&1
}

run_with_systemd() {
    if ! systemd_run_available; then
        debug_log 'systemd-run --user is unavailable'
        return "$backend_unavailable"
    fi

    if ! systemd_run_supports_limits; then
        debug_log 'systemd-run backend unavailable: resource properties are not accepted'
        return "$backend_unavailable"
    fi

    exec systemd-run --user --scope --quiet \
        -p "MemoryHigh=$player_memory_high" \
        -p "MemoryMax=$player_memory_max" \
        -p "TasksMax=$player_tasks_max" \
        -p "CPUQuota=$player_cpu_quota" \
        "$@"
}

current_cgroup_path() {
    sed -n 's/^0:://p' /proc/self/cgroup
}

setup_cgroupfs_dir() {
    current_path=$(current_cgroup_path)
    if [ -z "$current_path" ]; then
        debug_log 'cgroupfs backend unavailable: current cgroup is unknown'
        return "$backend_unavailable"
    fi

    parent_cgroup=$cgroup_root$current_path
    if [ ! -d "$parent_cgroup" ] || [ ! -w "$parent_cgroup" ]; then
        debug_log "cgroupfs backend unavailable: parent cgroup is not writable ($parent_cgroup)"
        return "$backend_unavailable"
    fi

    if [ ! -r "$cgroup_root/cgroup.controllers" ]; then
        debug_log 'cgroupfs backend unavailable: cgroup v2 controllers file is missing'
        return "$backend_unavailable"
    fi

    safe_target_name=$(printf '%s' "$target_name" | tr -c 'A-Za-z0-9._-' '_')
    if [ -z "$safe_target_name" ]; then
        safe_target_name=player
    fi

    player_cgroup_dir=$parent_cgroup/lf-player-$PPID-$safe_target_name-$$
    if ! mkdir "$player_cgroup_dir" 2>/dev/null; then
        debug_log "cgroupfs backend unavailable: failed to create $player_cgroup_dir"
        return "$backend_unavailable"
    fi

    for limit_file in cpu.max memory.high memory.max pids.max cgroup.procs; do
        if [ ! -w "$player_cgroup_dir/$limit_file" ]; then
            debug_log "cgroupfs backend unavailable: $player_cgroup_dir/$limit_file is not writable"
            rmdir "$player_cgroup_dir" 2>/dev/null || true
            return "$backend_unavailable"
        fi
    done

    cpu_max_value=max
    case "$player_cpu_quota" in
        *%)
            cpu_percent=${player_cpu_quota%%%}
            if [ -n "$cpu_percent" ] &&
               [ "$cpu_percent" -gt 0 ] 2>/dev/null; then
                cpu_quota_us=$((cpu_percent * 1000))
                cpu_max_value="$cpu_quota_us 100000"
            fi
            ;;
    esac

    if ! printf '%s\n' "$cpu_max_value" > "$player_cgroup_dir/cpu.max" ||
        ! printf '%s\n' "$player_memory_high" > "$player_cgroup_dir/memory.high" ||
        ! printf '%s\n' "$player_memory_max" > "$player_cgroup_dir/memory.max" ||
        ! printf '%s\n' "$player_tasks_max" > "$player_cgroup_dir/pids.max"; then
        debug_log "cgroupfs backend unavailable: failed to configure $player_cgroup_dir"
        rmdir "$player_cgroup_dir" 2>/dev/null || true
        return "$backend_unavailable"
    fi

    return 0
}

run_with_cgroupfs() {
    if setup_cgroupfs_dir; then
        :
    else
        rc=$?
        return "$rc"
    fi

    debug_log "using cgroupfs backend ($player_cgroup_dir)"
    (
        trap 'rmdir "$player_cgroup_dir" 2>/dev/null || true' EXIT INT TERM
        printf '%s\n' "$$" > "$player_cgroup_dir/cgroup.procs" || exit 1
        exec "$@"
    )
}

run_plain_bwrap() {
    exec "$@"
}

run_auto_backend() {
    if run_with_systemd "$@"; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -ne "$backend_unavailable" ]; then
        return "$rc"
    fi

    if run_with_cgroupfs "$@"; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -ne "$backend_unavailable" ]; then
        return "$rc"
    fi

    run_plain_bwrap "$@"
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

gpu_render_node=
gpu_render_node_dir=
if [ "$player_gpu" = "1" ] &&
   gpu_render_node=$(resolve_gpu_render_node "$player_gpu_render_node"); then
    gpu_render_node_dir=$(dirname -- "$gpu_render_node")
    player_extra_ro_paths=$(append_unique_colon_path "$player_extra_ro_paths" "$gpu_render_node_dir")
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

if [ -n "$gpu_render_node" ]; then
    set -- "$@" --dir "$gpu_render_node_dir" --dev-bind "$gpu_render_node" "$gpu_render_node"
fi

bind_paths=$(PLAYER_EXTRA_RO_PATHS=$player_extra_ro_paths "$guard_bin" --print-bwrap-ro-paths "$parent_dir" "$lf_config_dir")
old_ifs=$IFS
IFS='
'
for bind_path in $bind_paths; do
    set -- "$@" --dir "$bind_path" --ro-bind "$bind_path" "$bind_path"
done
IFS=$old_ifs

runtime_env_enabled=

if [ -n "$runtime_dir" ] && runtime_dir=$(resolve_runtime_dir "$runtime_dir"); then
    if [ -n "$wayland_display" ] &&
       wayland_socket=$(resolve_runtime_socket "$wayland_display" "$runtime_dir"); then
        wayland_socket_dir=$(dirname -- "$wayland_socket")
        player_extra_rw_paths=$(append_unique_colon_path "$player_extra_rw_paths" "$wayland_socket_dir")
        set -- "$@" --dir "$runtime_dir" --dir "$wayland_socket_dir" --bind "$wayland_socket" "$wayland_socket"
        set -- "$@" --setenv WAYLAND_DISPLAY "$(basename -- "$wayland_socket")"
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
        player_extra_rw_paths=$(append_unique_colon_path "$player_extra_rw_paths" "$pulse_socket_dir")
        set -- "$@" --dir "$runtime_dir" --dir "$pulse_socket_dir" --bind "$pulse_socket" "$pulse_socket"
        set -- "$@" --setenv PULSE_SERVER "unix:$pulse_socket"
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
        player_extra_rw_paths=$(append_unique_colon_path "$player_extra_rw_paths" "$pipewire_socket_dir")
        set -- "$@" --dir "$runtime_dir" --dir "$pipewire_base_dir" --dir "$pipewire_socket_dir" --bind "$pipewire_socket" "$pipewire_socket"
        set -- "$@" --setenv PIPEWIRE_RUNTIME_DIR "$pipewire_base_dir"
        set -- "$@" --setenv PIPEWIRE_REMOTE "$(basename -- "$pipewire_socket")"
        runtime_env_enabled=1
    fi

    if [ -n "$runtime_env_enabled" ]; then
        set -- "$@" --setenv XDG_RUNTIME_DIR "$runtime_dir"
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

set -- "$@" -- "$resolved_target"

case "$player_cgroup_mode" in
    auto)
        run_auto_backend "$@"
        ;;
    systemd)
        if run_with_systemd "$@"; then
            rc=0
        else
            rc=$?
        fi
        if [ "$rc" -eq 0 ]; then
            exit 0
        fi
        if [ "$rc" -ne "$backend_unavailable" ]; then
            exit "$rc"
        fi
        run_plain_bwrap "$@"
        ;;
    cgroupfs)
        if run_with_cgroupfs "$@"; then
            rc=0
        else
            rc=$?
        fi
        if [ "$rc" -eq 0 ]; then
            exit 0
        fi
        if [ "$rc" -ne "$backend_unavailable" ]; then
            exit "$rc"
        fi
        run_plain_bwrap "$@"
        ;;
    none)
        run_plain_bwrap "$@"
        ;;
    *)
        run_auto_backend "$@"
        ;;
esac
