#!/bin/sh

set -eu

PATH=/usr/bin:/bin
export PATH

if [ "$#" -lt 6 ]; then
    printf 'previewSandbox.sh: expected 6 args, got %s\n' "$#" >&2
    exit 1
fi

target=$1
width=$2
height=$3
xpos=$4
ypos=$5
mode=$6
home_dir=${HOME:-/home/user}
lf_config_dir="$home_dir/.config/lf"
lf_config_parent=$(dirname -- "$lf_config_dir")
guard_bin="$lf_config_dir/preview-guard"
preview_script=$(readlink -f -- "$lf_config_dir/preview.sh")
preview_script_dir=$(dirname -- "$preview_script")
safe_path=/usr/bin:/bin
target_dir=$(dirname -- "$target")
target_name=$(basename -- "$target")
preview_timeout=${LF_PREVIEW_TIMEOUT:-5s}
preview_debug=${LF_PREVIEW_DEBUG:-0}
preview_cgroup_mode=${LF_PREVIEW_CGROUP:-auto}
cgroup_root=${LF_PREVIEW_CGROUP_ROOT:-/sys/fs/cgroup}
backend_unavailable=200

if ! parent_dir=$(cd -- "$target_dir" 2>/dev/null && pwd -P); then
    printf 'previewSandbox.sh: cannot resolve target parent: %s\n' "$target_dir" >&2
    exit 1
fi

set -- \
    "$parent_dir/$target_name" \
    "$width" \
    "$height" \
    "$xpos" \
    "$ypos" \
    "$mode"

preview_target=$1
preview_width=$2
preview_height=$3
preview_xpos=$4
preview_ypos=$5
preview_mode=$6

set -- \
    bwrap \
    --unshare-all \
    --new-session \
    --die-with-parent \
    --clearenv \
    --setenv HOME "$home_dir" \
    --setenv PATH "$safe_path" \
    --setenv PREVIEW_EXTRA_RO_PATHS "$preview_script_dir" \
    --setenv TMPDIR /var/tmp \
    --dev /dev \
    --tmpfs /home \
    --tmpfs /root \
    --tmpfs /tmp \
    --tmpfs /var/tmp \
    --tmpfs /proc \
    --tmpfs /sys \
    --dir "$home_dir" \
    --dir "$lf_config_parent" \
    --dir "$parent_dir"

bind_paths=$(PREVIEW_EXTRA_RO_PATHS=$preview_script_dir "$guard_bin" --print-bwrap-ro-paths "$parent_dir" "$lf_config_dir")
old_ifs=$IFS
IFS='
'
for bind_path in $bind_paths; do
    set -- "$@" --dir "$bind_path" --ro-bind "$bind_path" "$bind_path"
done
IFS=$old_ifs

set -- "$@" \
    "$guard_bin" \
    "$parent_dir" \
    "$lf_config_dir" \
    /bin/sh "$preview_script" \
    "$preview_target" \
    "$preview_width" \
    "$preview_height" \
    "$preview_xpos" \
    "$preview_ypos" \
    "$preview_mode"

debug_log() {
    if [ "$preview_debug" = "1" ]; then
        printf 'previewSandbox.sh: %s\n' "$*" >&2
    fi
}

run_with_timeout_exec() {
    if command -v timeout >/dev/null 2>&1; then
        exec timeout --foreground "$preview_timeout" "$@"
    fi

    exec "$@"
}

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout --foreground "$preview_timeout" "$@"
        return $?
    fi

    "$@"
}

systemd_run_available() {
    command -v systemd-run >/dev/null 2>&1 &&
        systemd-run --user --scope --quiet true >/dev/null 2>&1
}

systemd_run_supports_limits() {
    systemd-run --user --scope --quiet \
        -p MemoryHigh=256M \
        -p MemoryMax=512M \
        -p TasksMax=64 \
        -p CPUQuota=50% \
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

    debug_log 'using systemd-run backend'
    if command -v timeout >/dev/null 2>&1; then
        systemd-run --user --scope --quiet \
            -p MemoryHigh=256M \
            -p MemoryMax=512M \
            -p TasksMax=64 \
            -p CPUQuota=50% \
            timeout --foreground "$preview_timeout" "$@"
        return $?
    fi

    systemd-run --user --scope --quiet \
        -p MemoryHigh=256M \
        -p MemoryMax=512M \
        -p TasksMax=64 \
        -p CPUQuota=50% \
        "$@"
    return $?
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
        safe_target_name=preview
    fi

    preview_cgroup_dir=$parent_cgroup/lf-preview-$PPID-$safe_target_name-$$
    if ! mkdir "$preview_cgroup_dir" 2>/dev/null; then
        debug_log "cgroupfs backend unavailable: failed to create $preview_cgroup_dir"
        return "$backend_unavailable"
    fi

    for limit_file in cpu.max memory.high memory.max pids.max cgroup.procs; do
        if [ ! -w "$preview_cgroup_dir/$limit_file" ]; then
            debug_log "cgroupfs backend unavailable: $preview_cgroup_dir/$limit_file is not writable"
            rmdir "$preview_cgroup_dir" 2>/dev/null || true
            return "$backend_unavailable"
        fi
    done

    if ! printf '%s\n' '50000 100000' > "$preview_cgroup_dir/cpu.max" ||
        ! printf '%s\n' '256M' > "$preview_cgroup_dir/memory.high" ||
        ! printf '%s\n' '512M' > "$preview_cgroup_dir/memory.max" ||
        ! printf '%s\n' '64' > "$preview_cgroup_dir/pids.max"; then
        debug_log "cgroupfs backend unavailable: failed to configure $preview_cgroup_dir"
        rmdir "$preview_cgroup_dir" 2>/dev/null || true
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

    debug_log "using cgroupfs backend ($preview_cgroup_dir)"
    (
        trap 'rmdir "$preview_cgroup_dir" 2>/dev/null || true' EXIT INT TERM
        # shellcheck disable=SC2016
        env LF_PREVIEW_CGROUP_PROCS="$preview_cgroup_dir/cgroup.procs" \
            LF_PREVIEW_TIMEOUT="$preview_timeout" \
            sh -c '
                printf "%s\n" "$$" > "$LF_PREVIEW_CGROUP_PROCS" || exit 1
                if command -v timeout >/dev/null 2>&1; then
                    exec timeout --foreground "$LF_PREVIEW_TIMEOUT" "$@"
                fi
                exec "$@"
            ' sh "$@"
    )
}

run_plain_bwrap() {
    debug_log 'using plain bwrap backend'
    run_with_timeout_exec "$@"
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

case "$preview_cgroup_mode" in
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
        debug_log 'requested systemd backend unavailable, falling back to plain bwrap'
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
        debug_log 'requested cgroupfs backend unavailable, falling back to plain bwrap'
        run_plain_bwrap "$@"
        ;;
    none)
        run_plain_bwrap "$@"
        ;;
    *)
        debug_log "unknown LF_PREVIEW_CGROUP value: $preview_cgroup_mode"
        run_auto_backend "$@"
        ;;
esac
