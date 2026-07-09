# shellcheck shell=sh
# Shared backend and cgroup helpers for lf preview/player sandboxes.
# Callers set SANDBOX_* globals, build the command in "$@", then call
# sandbox_backend_run "$@". No command strings or eval are used.

sandbox_debug_log() {
    if [ "${SANDBOX_DEBUG:-0}" = "1" ]; then
        printf '%sSandbox.sh: %s\n' "$SANDBOX_BACKEND_NAME" "$*" >&2
    fi
}

sandbox_current_cgroup_path() {
    sed -n 's/^0:://p' /proc/self/cgroup
}

sandbox_safe_target_name() {
    safe_target_name=$(printf '%s' "${SANDBOX_TARGET_NAME:-}" | tr -c 'A-Za-z0-9._-' '_')
    if [ -z "$safe_target_name" ]; then
        safe_target_name=$SANDBOX_BACKEND_NAME
    fi
    printf '%s\n' "$safe_target_name"
}

sandbox_cpu_max_value() {
    cpu_max_value=max
    case "${SANDBOX_CPU_QUOTA:-}" in
        *%)
            cpu_percent=${SANDBOX_CPU_QUOTA%%%}
            if [ -n "$cpu_percent" ] &&
               [ "$cpu_percent" -gt 0 ] 2>/dev/null; then
                cpu_quota_us=$((cpu_percent * 1000))
                cpu_max_value="$cpu_quota_us 100000"
            fi
            ;;
    esac
    printf '%s\n' "$cpu_max_value"
}

sandbox_systemd_run_available() {
    command -v systemd-run >/dev/null 2>&1 &&
        systemd-run --user --scope --quiet true >/dev/null 2>&1
}

sandbox_systemd_run_supports_limits() {
    systemd-run --user --scope --quiet \
        -p "MemoryHigh=$SANDBOX_MEMORY_HIGH" \
        -p "MemoryMax=$SANDBOX_MEMORY_MAX" \
        -p "TasksMax=$SANDBOX_TASKS_MAX" \
        -p "CPUQuota=$SANDBOX_CPU_QUOTA" \
        true >/dev/null 2>&1
}

sandbox_run_with_systemd() {
    if ! sandbox_systemd_run_available; then
        sandbox_debug_log 'systemd-run --user is unavailable'
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    if ! sandbox_systemd_run_supports_limits; then
        sandbox_debug_log 'systemd-run backend unavailable: resource properties are not accepted'
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    sandbox_debug_log 'using systemd-run backend'
    if [ "$SANDBOX_USE_TIMEOUT" = "1" ]; then
        if command -v timeout >/dev/null 2>&1; then
            systemd-run --user --scope --quiet \
                -p "MemoryHigh=$SANDBOX_MEMORY_HIGH" \
                -p "MemoryMax=$SANDBOX_MEMORY_MAX" \
                -p "TasksMax=$SANDBOX_TASKS_MAX" \
                -p "CPUQuota=$SANDBOX_CPU_QUOTA" \
                timeout --foreground "$SANDBOX_TIMEOUT" "$@"
            return $?
        fi

        systemd-run --user --scope --quiet \
            -p "MemoryHigh=$SANDBOX_MEMORY_HIGH" \
            -p "MemoryMax=$SANDBOX_MEMORY_MAX" \
            -p "TasksMax=$SANDBOX_TASKS_MAX" \
            -p "CPUQuota=$SANDBOX_CPU_QUOTA" \
            "$@"
        return $?
    fi

    exec systemd-run --user --scope --quiet \
        -p "MemoryHigh=$SANDBOX_MEMORY_HIGH" \
        -p "MemoryMax=$SANDBOX_MEMORY_MAX" \
        -p "TasksMax=$SANDBOX_TASKS_MAX" \
        -p "CPUQuota=$SANDBOX_CPU_QUOTA" \
        "$@"
}

sandbox_setup_cgroupfs_dir() {
    current_path=$(sandbox_current_cgroup_path)
    if [ -z "$current_path" ]; then
        sandbox_debug_log 'cgroupfs backend unavailable: current cgroup is unknown'
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    parent_cgroup=$SANDBOX_CGROUP_ROOT$current_path
    if [ ! -d "$parent_cgroup" ] || [ ! -w "$parent_cgroup" ]; then
        sandbox_debug_log "cgroupfs backend unavailable: parent cgroup is not writable ($parent_cgroup)"
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    if [ ! -r "$SANDBOX_CGROUP_ROOT/cgroup.controllers" ]; then
        sandbox_debug_log 'cgroupfs backend unavailable: cgroup v2 controllers file is missing'
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    safe_target_name=$(sandbox_safe_target_name)
    SANDBOX_CGROUP_DIR=$parent_cgroup/lf-$SANDBOX_BACKEND_NAME-$PPID-$safe_target_name-$$
    if ! mkdir "$SANDBOX_CGROUP_DIR" 2>/dev/null; then
        sandbox_debug_log "cgroupfs backend unavailable: failed to create $SANDBOX_CGROUP_DIR"
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    for limit_file in cpu.max memory.high memory.max pids.max cgroup.procs; do
        if [ ! -w "$SANDBOX_CGROUP_DIR/$limit_file" ]; then
            sandbox_debug_log "cgroupfs backend unavailable: $SANDBOX_CGROUP_DIR/$limit_file is not writable"
            rmdir "$SANDBOX_CGROUP_DIR" 2>/dev/null || true
            return "$SANDBOX_BACKEND_UNAVAILABLE"
        fi
    done

    cpu_max_value=$(sandbox_cpu_max_value)
    if ! printf '%s\n' "$cpu_max_value" > "$SANDBOX_CGROUP_DIR/cpu.max" ||
        ! printf '%s\n' "$SANDBOX_MEMORY_HIGH" > "$SANDBOX_CGROUP_DIR/memory.high" ||
        ! printf '%s\n' "$SANDBOX_MEMORY_MAX" > "$SANDBOX_CGROUP_DIR/memory.max" ||
        ! printf '%s\n' "$SANDBOX_TASKS_MAX" > "$SANDBOX_CGROUP_DIR/pids.max"; then
        sandbox_debug_log "cgroupfs backend unavailable: failed to configure $SANDBOX_CGROUP_DIR"
        rmdir "$SANDBOX_CGROUP_DIR" 2>/dev/null || true
        return "$SANDBOX_BACKEND_UNAVAILABLE"
    fi

    return 0
}

sandbox_run_with_cgroupfs() {
    if sandbox_setup_cgroupfs_dir; then
        :
    else
        rc=$?
        return "$rc"
    fi

    sandbox_debug_log "using cgroupfs backend ($SANDBOX_CGROUP_DIR)"
    if [ "$SANDBOX_USE_TIMEOUT" = "1" ]; then
        (
            trap 'rmdir "$SANDBOX_CGROUP_DIR" 2>/dev/null || true' EXIT INT TERM
            # shellcheck disable=SC2016 # Variables expand inside the child shell.
            env SANDBOX_CGROUP_PROCS="$SANDBOX_CGROUP_DIR/cgroup.procs" \
                SANDBOX_TIMEOUT_VALUE="$SANDBOX_TIMEOUT" \
                sh -c '
                    printf "%s\n" "$$" > "$SANDBOX_CGROUP_PROCS" || exit 1
                    if command -v timeout >/dev/null 2>&1; then
                        exec timeout --foreground "$SANDBOX_TIMEOUT_VALUE" "$@"
                    fi
                    exec "$@"
                ' sh "$@"
        )
        return $?
    fi

    (
        trap 'rmdir "$SANDBOX_CGROUP_DIR" 2>/dev/null || true' EXIT INT TERM
        printf '%s\n' "$$" > "$SANDBOX_CGROUP_DIR/cgroup.procs" || exit 1
        exec "$@"
    )
}

sandbox_run_plain() {
    sandbox_debug_log 'using plain bwrap backend'
    if [ "$SANDBOX_USE_TIMEOUT" = "1" ] && command -v timeout >/dev/null 2>&1; then
        exec timeout --foreground "$SANDBOX_TIMEOUT" "$@"
    fi

    exec "$@"
}

sandbox_openrc_detected() {
    [ -e /run/openrc/softlevel ] || [ -d /run/openrc ]
}

sandbox_plain_fallback_allowed() {
    [ "${SANDBOX_BACKEND_ALLOW_PLAIN_FALLBACK:-0}" = "1" ] || sandbox_openrc_detected
}

sandbox_limits_unavailable() {
    printf '%sSandbox.sh: resource limits unavailable; refusing plain bwrap fallback (set SANDBOX_BACKEND_ALLOW_PLAIN_FALLBACK=1, use OpenRC, or set SANDBOX_BACKEND_MODE=none to opt out)\n' "$SANDBOX_BACKEND_NAME" >&2
    return "$SANDBOX_BACKEND_UNAVAILABLE"
}

sandbox_run_auto_backend() {
    if sandbox_run_with_systemd "$@"; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -ne "$SANDBOX_BACKEND_UNAVAILABLE" ]; then
        return "$rc"
    fi

    if sandbox_run_with_cgroupfs "$@"; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -ne "$SANDBOX_BACKEND_UNAVAILABLE" ]; then
        return "$rc"
    fi

    if sandbox_plain_fallback_allowed; then
        sandbox_run_plain "$@"
    fi

    sandbox_limits_unavailable
}

sandbox_backend_run() {
    case "$SANDBOX_BACKEND_MODE" in
        auto)
            sandbox_run_auto_backend "$@"
            ;;
        systemd)
            if sandbox_run_with_systemd "$@"; then
                rc=0
            else
                rc=$?
            fi
            if [ "$rc" -eq 0 ]; then
                exit 0
            fi
            if [ "$rc" -ne "$SANDBOX_BACKEND_UNAVAILABLE" ]; then
                exit "$rc"
            fi
            if sandbox_plain_fallback_allowed; then
                sandbox_debug_log 'requested systemd backend unavailable, falling back to plain bwrap'
                sandbox_run_plain "$@"
            fi
            sandbox_limits_unavailable
            ;;
        cgroupfs)
            if sandbox_run_with_cgroupfs "$@"; then
                rc=0
            else
                rc=$?
            fi
            if [ "$rc" -eq 0 ]; then
                exit 0
            fi
            if [ "$rc" -ne "$SANDBOX_BACKEND_UNAVAILABLE" ]; then
                exit "$rc"
            fi
            if sandbox_plain_fallback_allowed; then
                sandbox_debug_log 'requested cgroupfs backend unavailable, falling back to plain bwrap'
                sandbox_run_plain "$@"
            fi
            sandbox_limits_unavailable
            ;;
        none)
            sandbox_run_plain "$@"
            ;;
        *)
            sandbox_debug_log "unknown cgroup backend value: $SANDBOX_BACKEND_MODE"
            sandbox_run_auto_backend "$@"
            ;;
    esac
}
