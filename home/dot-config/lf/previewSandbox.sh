#!/bin/sh

set -eu

# Preview launcher policy summary:
# - resolves the canonical target parent before sandboxing;
# - constructs a bwrap namespace with minimal /dev nodes and read-only binds
#   from preview-guard;
# - exposes the preview script directory through PREVIEW_EXTRA_RO_PATHS;
# - runs the selected backend with preview timeout and resource limits;
# - delegates final filesystem/seccomp enforcement to preview-guard.

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
sandbox_backend_lib="$lf_config_dir/sandbox-backend.sh"
# shellcheck source=/dev/null
. "$sandbox_backend_lib"
lf_config_parent=$(dirname -- "$lf_config_dir")
guard_bin="$lf_config_dir/preview-guard"
guard_bin_real=$(readlink -f -- "$guard_bin")
preview_script=$(readlink -f -- "$lf_config_dir/preview.sh")
preview_script_dir=$(dirname -- "$preview_script")
safe_path=/usr/bin:/bin
target_dir=$(dirname -- "$target")
target_name=$(basename -- "$target")
preview_timeout=${LF_PREVIEW_TIMEOUT:-5s}
preview_debug=${LF_PREVIEW_DEBUG:-0}
preview_cgroup_mode=${LF_PREVIEW_CGROUP:-auto}
cgroup_root=${LF_PREVIEW_CGROUP_ROOT:-/sys/fs/cgroup}
if ! parent_dir=$(cd -- "$target_dir" 2>/dev/null && pwd -P); then
    printf 'previewSandbox.sh: cannot resolve target parent: %s\n' "$target_dir" >&2
    exit 1
fi

resolved_target="$parent_dir/$target_name"
target_is_symlink=
target_link=
if [ -L "$resolved_target" ]; then
    target_is_symlink=1
    if ! target_link=$(readlink -- "$resolved_target" 2>/dev/null); then
        printf 'previewSandbox.sh: cannot read target symlink: %s\n' "$resolved_target" >&2
        exit 1
    fi
    target_ro_path=/__lf_sandbox_no_target__
elif [ -f "$resolved_target" ]; then
    target_ro_path=$resolved_target
else
    target_ro_path=/__lf_sandbox_no_target__
fi

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
        ::)
            printf '%s\n' "$path_value"
            ;;
        *)
            printf '%s:%s\n' "$list_value" "$path_value"
            ;;
    esac
}

append_existing_path() {
    list_value=$1
    path_value=$2

    if [ -z "$path_value" ] || [ "${path_value#/}" = "$path_value" ] || [ ! -e "$path_value" ]; then
        printf '%s\n' "$list_value"
        return 0
    fi

    if real_path=$(readlink -f -- "$path_value" 2>/dev/null) && [ -e "$real_path" ]; then
        path_value=$real_path
    fi

    append_unique_colon_path "$list_value" "$path_value"
}

append_ldd_closure() {
    list_value=$1
    binary_path=$2

    if ! command -v ldd >/dev/null 2>&1; then
        printf '%s\n' "$list_value"
        return 0
    fi

    for ldd_path in $(ldd "$binary_path" 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^\//) {
                    sub(/\(.*/, "", $i)
                    print $i
                }
            }
        }')
    do
        if [ -e "$ldd_path" ]; then
            list_value=$(append_unique_colon_path "$list_value" "$ldd_path")
        fi
        list_value=$(append_existing_path "$list_value" "$ldd_path")
    done

    printf '%s\n' "$list_value"
}

append_binary_closure() {
    list_value=$1
    shift

    for command_name do
        if ! command_path=$(command -v -- "$command_name" 2>/dev/null); then
            continue
        fi
        case "$command_path" in
            /*) ;;
            *) continue ;;
        esac
        if [ -e "$command_path" ]; then
            list_value=$(append_unique_colon_path "$list_value" "$command_path")
        fi
        if command_real=$(readlink -f -- "$command_path" 2>/dev/null) && [ -e "$command_real" ]; then
            command_path=$command_real
            list_value=$(append_existing_path "$list_value" "$command_path")
        fi
        if [ "$(dd if="$command_path" bs=2 count=1 2>/dev/null || true)" = '#!' ]; then
            list_value=$(append_existing_path "$list_value" "$(dirname -- "$command_path")")
        fi
        list_value=$(append_ldd_closure "$list_value" "$command_path")
    done

    printf '%s\n' "$list_value"
}

build_preview_system_ro_paths() {
    path_list=

    path_list=$(append_binary_closure "$path_list" "$guard_bin" /bin/sh file sed head perl readlink mktemp rm cat)
    path_list=$(append_binary_closure "$path_list" img2sixel magick ffmpeg pdftotext)

    for data_path in \
        /etc/ld.so.cache \
        /etc/mime.types \
        /etc/magic \
        /usr/share/misc/magic.mgc \
        /usr/share/file/magic.mgc \
        /usr/share/file/misc/magic.mgc \
        /usr/share/terminfo
    do
        if [ -e "$data_path" ]; then
            path_list=$(append_unique_colon_path "$path_list" "$data_path")
        fi
        path_list=$(append_existing_path "$path_list" "$data_path")
    done

    printf '%s\n' "$path_list"
}

preview_system_ro_paths=$(build_preview_system_ro_paths)

set -- \
    "$resolved_target" \
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
    --setenv LF_SANDBOX_SYSTEM_RO_PATHS "$preview_system_ro_paths" \
    --setenv TMPDIR /var/tmp \
    --dir /dev \
    --dev-bind /dev/null /dev/null \
    --dev-bind /dev/zero /dev/zero \
    --dev-bind /dev/full /dev/full \
    --dev-bind /dev/random /dev/random \
    --dev-bind /dev/urandom /dev/urandom \
    --tmpfs /home \
    --tmpfs /root \
    --tmpfs /tmp \
    --tmpfs /var/tmp \
    --tmpfs /proc \
    --tmpfs /sys \
    --dir "$home_dir" \
    --dir "$lf_config_parent" \
    --dir "$parent_dir"

bind_paths=$(LF_SANDBOX_SYSTEM_RO_PATHS=$preview_system_ro_paths PREVIEW_EXTRA_RO_PATHS=$preview_script_dir "$guard_bin" --print-bwrap-ro-paths "$target_ro_path" "$lf_config_dir")
old_ifs=$IFS
IFS='
'
for bind_path in $bind_paths; do
    if [ -d "$bind_path" ]; then
        bind_mountpoint=$bind_path
    else
        bind_mountpoint=$(dirname -- "$bind_path")
    fi
    set -- "$@" --dir "$bind_mountpoint" --ro-bind "$bind_path" "$bind_path"
done
IFS=$old_ifs

if [ -n "$target_is_symlink" ]; then
    set -- "$@" --symlink "$target_link" "$resolved_target"
fi

set -- "$@" \
    "$guard_bin_real" \
    "$target_ro_path" \
    "$lf_config_dir" \
    /bin/sh "$preview_script" \
    "$preview_target" \
    "$preview_width" \
    "$preview_height" \
    "$preview_xpos" \
    "$preview_ypos" \
    "$preview_mode"

SANDBOX_BACKEND_NAME=preview
SANDBOX_BACKEND_MODE=$preview_cgroup_mode
SANDBOX_CGROUP_ROOT=$cgroup_root
SANDBOX_TARGET_NAME=$target_name
SANDBOX_CPU_QUOTA=50%
SANDBOX_MEMORY_HIGH=256M
SANDBOX_MEMORY_MAX=512M
SANDBOX_TASKS_MAX=64
SANDBOX_TIMEOUT=$preview_timeout
SANDBOX_USE_TIMEOUT=1
SANDBOX_DEBUG=$preview_debug
SANDBOX_BACKEND_UNAVAILABLE=200
sandbox_backend_run "$@"
