#!/bin/sh

set -eu

# Preview launcher policy summary:
# - resolves the canonical target parent before sandboxing;
# - constructs a bwrap namespace and read-only binds from preview-guard;
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
