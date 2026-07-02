#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

usage() {
  cat <<'USAGE'
Usage: spawn-tmux-child-common.sh --skill NAME --task TEXT --cwd DIR --prompt-template FILE [options]

Options:
  --artifact PATH         Primary artifact path. Relative paths are resolved from --cwd.
  --artifact-dir NAME     .agents/ subdirectory used when --artifact is omitted.
  --model MODEL           Optional Pi --model hint.
  --provider PROVIDER     Optional Pi --provider hint.
  --thinking LEVEL        Optional Pi --thinking hint.
  --timeout SECONDS       Child timeout, default 1800.
  --lock-key KEY          Optional flock key. Use "workspace" to derive from --cwd.
  --lock-timeout SECONDS  Seconds to wait for --lock-key, default 60.
  --keep-pane             Keep the tmux pane open after child completion.
  --auto-exit             Exit the pane after success; failures are kept for inspection.
  --pi-bin PATH           Pi executable, default pi.
  --help                  Show this help.
USAGE
}

die() {
  printf 'spawn-tmux-child-common: %s\n' "$*" >&2
  exit 2
}

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}
  value=${value//"/\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

json_field() {
  printf '  "%s": "%s"' "$1" "$(json_escape "${2-}")"
}

json_bool_field() {
  printf '  "%s": %s' "$1" "$2"
}

json_number_field() {
  printf '  "%s": %s' "$1" "$2"
}

slugify() {
  local raw=${1:-task}
  local slug
  slug=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/^-+//; s/-+$//; s/-+/-/g; s/^(.{1,48}).*$/\1/; s/-+$//')
  printf '%s' "${slug:-task}"
}

random_suffix() {
  if command -v od >/dev/null 2>&1; then
    od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
  else
    printf '%s' "$RANDOM$RANDOM"
  fi
}

write_status() {
  local status=$1 reason=$2 exit_status=$3 ended_at=$4
  local tmp_status="${status_json}.$$.$RANDOM.tmp"
  # Status files are polled by the orchestrator while child runners rewrite them
  # at terminal transitions. Write to a sibling temp file and rename atomically so
  # readers never observe a truncated JSON document; a lock would add needless
  # coordination for a single-writer file.
  {
    printf '{\n'
    json_field skill "$skill"; printf ',\n'
    json_field cwd "$cwd"; printf ',\n'
    json_field task_slug "$task_slug"; printf ',\n'
    json_field session_name "$session_name"; printf ',\n'
    json_field started_at "$started_at"; printf ',\n'
    json_field ended_at "$ended_at"; printf ',\n'
    json_field status "$status"; printf ',\n'
    json_number_field exit_status "$exit_status"; printf ',\n'
    json_field failure_reason "$reason"; printf ',\n'
    json_field artifact_path "$artifact_path"; printf ',\n'
    json_field success_sentinel_path "$success_sentinel"; printf ',\n'
    json_field failure_sentinel_path "$failure_sentinel"; printf ',\n'
    json_field stdout_log_path "$stdout_log"; printf ',\n'
    json_field stderr_log_path "$stderr_log"; printf ',\n'
    json_field runner_log_path "$runner_log"; printf ',\n'
    json_number_field timeout_seconds "$timeout_seconds"; printf ',\n'
    json_field provider "$provider"; printf ',\n'
    json_field model "$model"; printf ',\n'
    json_field thinking "$thinking"; printf ',\n'
    json_bool_field lock_enabled "$lock_enabled"; printf ',\n'
    json_field lock_key "$lock_key"; printf ',\n'
    json_field lock_file "$lock_file"; printf ',\n'
    json_number_field lock_timeout_seconds "$lock_timeout_seconds"; printf ',\n'
    json_bool_field keep_pane "$keep_pane"; printf ',\n'
    json_bool_field auto_exit "$auto_exit"; printf '\n'
    printf '}\n'
  } >"$tmp_status"
  mv -f "$tmp_status" "$status_json"
}

write_failure_artifact() {
  local reason=$1 detail=${2-}
  # Keep generated diagnostics concise so the primary artifact remains useful to
  # parent prompts. Full stdout/stderr stay in logs; duplicating them here would
  # make failures noisy and brittle for automated consumers.
  {
    printf '# Child Run Failure\n\n'
    printf 'Reason: %s\n' "$reason"
    if [[ -n "$detail" ]]; then
      printf 'Detail: %s\n' "$detail"
    fi
    printf 'Stdout log: %s\n' "$stdout_log"
    printf 'Stderr log: %s\n' "$stderr_log"
  } >"$artifact_path"
}

skill=
task=
cwd=
prompt_template=
artifact_path=
artifact_dir=research
model=
provider=
thinking=
timeout_seconds=1800
lock_key=
lock_timeout_seconds=60
keep_pane=false
auto_exit=true
pi_bin=${PI_CHILD_RUNNER_PI_BIN:-pi}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill) skill=${2-}; shift 2 ;;
    --task) task=${2-}; shift 2 ;;
    --cwd) cwd=${2-}; shift 2 ;;
    --prompt-template) prompt_template=${2-}; shift 2 ;;
    --artifact) artifact_path=${2-}; shift 2 ;;
    --artifact-dir) artifact_dir=${2-}; shift 2 ;;
    --model) model=${2-}; shift 2 ;;
    --provider) provider=${2-}; shift 2 ;;
    --thinking) thinking=${2-}; shift 2 ;;
    --timeout) timeout_seconds=${2-}; shift 2 ;;
    --lock-key) lock_key=${2-}; shift 2 ;;
    --lock-timeout) lock_timeout_seconds=${2-}; shift 2 ;;
    --keep-pane) keep_pane=true; auto_exit=false; shift ;;
    --auto-exit) auto_exit=true; shift ;;
    --pi-bin) pi_bin=${2-}; shift 2 ;;
    --help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$skill" ]] || die "--skill is required"
[[ -n "$task" ]] || die "--task is required"
[[ -n "$cwd" ]] || die "--cwd is required"
[[ -n "$prompt_template" ]] || die "--prompt-template is required"
# Pi parses skill names strictly: lowercase a-z, 0-9, and hyphens only.
# Underscores were tolerated by an earlier shell-only check, but Pi's own
# skill loader rejects them, so reject them here to fail fast at the wrapper.
[[ "$skill" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "--skill must use lowercase letters, digits, and hyphens only"
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die "--timeout must be a positive integer number of seconds"
(( timeout_seconds > 0 )) || die "--timeout must be greater than zero"
[[ "$lock_timeout_seconds" =~ ^[0-9]+$ ]] || die "--lock-timeout must be a non-negative integer number of seconds"

command -v tmux >/dev/null 2>&1 || die "tmux is required and no other multiplexer is supported"
command -v "$pi_bin" >/dev/null 2>&1 || die "Pi executable not found: $pi_bin"
[[ -d "$cwd" ]] || die "working directory does not exist: $cwd"
[[ -f "$prompt_template" ]] || die "prompt template does not exist: $prompt_template"

cwd=$(cd "$cwd" && pwd -P)
prompt_template=$(cd "$(dirname "$prompt_template")" && pwd -P)/$(basename "$prompt_template")
agents_dir="$cwd/.agents"
for dir in research plans specs reviews impl-reports logs status locks; do
  mkdir -p "$agents_dir/$dir"
done

task_slug=$(slugify "$task")
timestamp=$(date -u +%Y%m%d%H%M%S)
run_id="pi-${skill}-${task_slug}-${timestamp}-$$-$(random_suffix)"
session_name="$run_id"
lock_enabled=false
lock_file=
if [[ -n "$lock_key" ]]; then
  lock_enabled=true
  if [[ "$lock_key" == workspace ]]; then
    # Scope write coordination to the canonical working directory. A short checksum
    # avoids leaking long paths into filenames and avoids collisions from slug
    # truncation alone; this is a lock name, not a security boundary.
    lock_key="workspace-$(slugify "$cwd")-$(printf '%s' "$cwd" | cksum | cut -d ' ' -f 1)"
  fi
  [[ "$lock_key" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "--lock-key must be workspace or a simple lowercase lock name"
  lock_file="$agents_dir/locks/${lock_key}.lock"
fi

if [[ -z "$artifact_path" ]]; then
  [[ "$artifact_dir" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "--artifact-dir must be a simple .agents/ child directory name"
  mkdir -p "$agents_dir/$artifact_dir"
  artifact_path="$agents_dir/$artifact_dir/${run_id}.md"
elif [[ "$artifact_path" != /* ]]; then
  artifact_path="$cwd/$artifact_path"
fi

# Keep all generated outputs under the target workspace .agents tree. The helper
# rejects broader paths instead of trusting role prompts to self-police writes.
case "$artifact_path" in
  "$agents_dir"/*) ;;
  *) die "artifact path must be under $agents_dir" ;;
esac
mkdir -p "$(dirname "$artifact_path")"
artifact_parent=$(cd "$(dirname "$artifact_path")" && pwd -P)
artifact_path="$artifact_parent/$(basename "$artifact_path")"
# Resolve the parent after creating it so pre-existing symlinks below .agents do
# not redirect artifacts outside the physical .agents tree. We still do an early
# lexical check above to avoid creating arbitrary out-of-tree directories first.
case "$artifact_path" in
  "$agents_dir"/*) ;;
  *) die "artifact path must be under $agents_dir" ;;
esac

stdout_log="$agents_dir/logs/${run_id}.stdout.log"
stderr_log="$agents_dir/logs/${run_id}.stderr.log"
runner_log="$agents_dir/logs/${run_id}.runner.log"
task_file="$agents_dir/status/${run_id}.task.txt"
runner_script="$agents_dir/status/${run_id}.runner.sh"
status_json="$agents_dir/status/${run_id}.json"
success_sentinel="$agents_dir/status/${run_id}.success"
failure_sentinel="$agents_dir/status/${run_id}.failure"
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat >"$task_file" <<TASK
You are running as a tmux child for Pi skill: $skill.

Primary artifact path: $artifact_path
Status file path: $status_json
Success sentinel path: $success_sentinel
Failure sentinel path: $failure_sentinel

Write your final result to the primary artifact path. The parent helper will
create sentinels after the Pi process exits; do not create sentinel files yourself.

Task:
$task
TASK

write_status "started" "" 0 ""

cat >"$runner_script" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "$cwd")
export PI_CHILD_RUNNER_SKILL=$(printf '%q' "$skill")
export PI_CHILD_RUNNER_ARTIFACT_PATH=$(printf '%q' "$artifact_path")
export PI_CHILD_RUNNER_STATUS_PATH=$(printf '%q' "$status_json")
export PI_CHILD_RUNNER_TASK_FILE=$(printf '%q' "$task_file")
export PI_CHILD_RUNNER_LOCK_FILE=$(printf '%q' "$lock_file")
export PI_CHILD_RUNNER_LOCK_KEY=$(printf '%q' "$lock_key")
export PI_CHILD_RUNNER_SKILLS_SCRIPTS_DIR=$(printf '%q' "$script_dir")
pi_args=(--prompt-template $(printf '%q' "$prompt_template") --no-session -p)
RUNNER

if [[ -n "$provider" ]]; then printf 'pi_args+=(--provider %q)\n' "$provider" >>"$runner_script"; fi
if [[ -n "$model" ]]; then printf 'pi_args+=(--model %q)\n' "$model" >>"$runner_script"; fi
if [[ -n "$thinking" ]]; then printf 'pi_args+=(--thinking %q)\n' "$thinking" >>"$runner_script"; fi

declare -f json_escape json_field json_bool_field json_number_field write_status write_failure_artifact >>"$runner_script"
cat >>"$runner_script" <<RUNNER
skill=$(printf '%q' "$skill")
cwd=$(printf '%q' "$cwd")
task_slug=$(printf '%q' "$task_slug")
session_name=$(printf '%q' "$session_name")
started_at=$(printf '%q' "$started_at")
artifact_path=$(printf '%q' "$artifact_path")
success_sentinel=$(printf '%q' "$success_sentinel")
failure_sentinel=$(printf '%q' "$failure_sentinel")
stdout_log=$(printf '%q' "$stdout_log")
stderr_log=$(printf '%q' "$stderr_log")
runner_log=$(printf '%q' "$runner_log")
status_json=$(printf '%q' "$status_json")
timeout_seconds=$(printf '%q' "$timeout_seconds")
provider=$(printf '%q' "$provider")
model=$(printf '%q' "$model")
thinking=$(printf '%q' "$thinking")
lock_enabled=$(printf '%q' "$lock_enabled")
lock_key=$(printf '%q' "$lock_key")
lock_file=$(printf '%q' "$lock_file")
lock_timeout_seconds=$(printf '%q' "$lock_timeout_seconds")
keep_pane=$(printf '%q' "$keep_pane")
auto_exit=$(printf '%q' "$auto_exit")
if [[ "\$lock_enabled" == true ]]; then
  set +e
  exec 9>"\$lock_file"
  flock -w "\$lock_timeout_seconds" 9
  lock_status=\$?
  set -e
  if [[ \$lock_status -ne 0 ]]; then
    ended_at=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
    write_failure_artifact "lock-timeout" "could not acquire lock_key=\$lock_key within lock_timeout_seconds=\$lock_timeout_seconds"
    write_status "failure" "lock-timeout" "\$lock_status" "\$ended_at"
    : >$(printf '%q' "$failure_sentinel")
    exit "\$lock_status"
  fi
fi
set +e
timeout $(printf '%q' "$timeout_seconds") $(printf '%q' "$pi_bin") "\${pi_args[@]}" "\$(cat $(printf '%q' "$task_file"))" >$(printf '%q' "$stdout_log") 2>$(printf '%q' "$stderr_log")
child_status=\$?
set -e
ended_at=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
failure_reason=""
final_status="success"
if [[ \$child_status -eq 124 ]]; then
  final_status="failure"
  failure_reason="timeout"
  write_failure_artifact "\$failure_reason" "child exceeded timeout_seconds=$(printf '%q' "$timeout_seconds")"
elif [[ \$child_status -ne 0 ]]; then
  final_status="failure"
  failure_reason="child-exit-\$child_status"
  write_failure_artifact "\$failure_reason" "child process exited non-zero"
elif [[ ! -s $(printf '%q' "$artifact_path") ]]; then
  final_status="failure"
  failure_reason="missing-artifact"
  write_failure_artifact "\$failure_reason" "child exited successfully without producing the required primary artifact"
fi
write_status "\$final_status" "\$failure_reason" "\$child_status" "\$ended_at"
if [[ "\$final_status" == success ]]; then
  : >$(printf '%q' "$success_sentinel")
else
  : >$(printf '%q' "$failure_sentinel")
fi
if [[ "$(printf '%q' "$keep_pane")" == true || ( "$(printf '%q' "$auto_exit")" == true && "\$final_status" != success ) ]]; then
  printf 'tmux child finished with %s (%s). Logs: %s %s\n' "\$final_status" "\$failure_reason" $(printf '%q' "$stdout_log") $(printf '%q' "$stderr_log")
  exec "\${SHELL:-/bin/sh}"
fi
exit \$child_status
RUNNER

chmod +x "$runner_script"

{
  printf 'run_id=%s\n' "$run_id"
  printf 'session_name=%s\n' "$session_name"
  printf 'artifact_path=%s\n' "$artifact_path"
  printf 'status_json=%s\n' "$status_json"
  printf 'success_sentinel=%s\n' "$success_sentinel"
  printf 'failure_sentinel=%s\n' "$failure_sentinel"
} >>"$runner_log"

printf '%s\n' "$status_json"
set +e
tmux new-session -d -s "$session_name" "$runner_script" 2>>"$runner_log"
tmux_status=$?
set -e
if [[ $tmux_status -ne 0 ]]; then
  ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  write_failure_artifact "tmux-new-session-failed" "tmux exited with status $tmux_status"
  write_status "failure" "tmux-new-session-failed" "$tmux_status" "$ended_at"
  : >"$failure_sentinel"
  exit "$tmux_status"
fi
