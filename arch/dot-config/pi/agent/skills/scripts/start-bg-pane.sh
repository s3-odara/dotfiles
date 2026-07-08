#!/usr/bin/env bash
set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_dir_part=${script_path%/*}
[[ "$script_dir_part" == "$script_path" ]] && script_dir_part=.
script_dir=$(cd "$script_dir_part" && pwd -P)

usage() {
  cat <<'USAGE'
Usage: start-bg-pane.sh --skill NAME --task TEXT --cwd DIR --prompt-template FILE [options]

Options:
  --artifact PATH         Primary artifact path. Relative paths are resolved from --cwd.
  --artifact-dir NAME     .agents/ subdirectory used when --artifact is omitted.
  --model MODEL           Optional Pi --model hint.
  --provider PROVIDER     Optional Pi --provider hint.
  --thinking LEVEL        Optional Pi --thinking hint.
  --timeout SECONDS       Metadata timeout for waiters, default 1800.
  --workspace-lock        Internal: serialize child startup by canonical --cwd.
  --pi-bin PATH           Pi executable, default pi.
  --help                  Show this help.
USAGE
}

die() { printf 'start-bg-pane: %s\n' "$*" >&2; exit 2; }

slugify() {
  local raw=${1:-task} slug
  slug=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/^-+//; s/-+$//; s/-+/-/g; s/^(.{1,48}).*$/\1/; s/-+$//')
  printf '%s' "${slug:-task}"
}

random_suffix() {
  if command -v od >/dev/null 2>&1; then od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'; else printf '%s' "$RANDOM$RANDOM"; fi
}

shell_quote_value() {
  # stdout is intentionally source-able KEY='value' text. Single-quote escaping
  # keeps paths with whitespace safe without pulling JSON or Node back in.
  local value=${1-}
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

print_kv() { printf '%s=%s\n' "$1" "$(shell_quote_value "${2-}")"; }

write_failure_artifact() {
  local reason=$1 detail=${2-}
  [[ -s "$artifact_path" ]] && return 0
  {
    printf '# Child Run Failure\n\nReason: %s\n' "$reason"
    [[ -n "$detail" ]] && printf 'Detail: %s\n' "$detail"
    printf 'Task file: %s\n' "$task_file"
  } >"$artifact_path"
}

skill= task= cwd= prompt_template= artifact_path= artifact_dir=research model= provider= thinking=
timeout_seconds=1800 workspace_lock=false pi_bin=${PI_CHILD_RUNNER_PI_BIN:-pi}

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
    --workspace-lock) workspace_lock=true; shift ;;
    --pi-bin) pi_bin=${2-}; shift 2 ;;
    --lock-key|--lock-timeout) die "$1 is obsolete; workspace locking is derived from --cwd only" ;;
    --keep-pane|--auto-exit) die "$1 is obsolete; panes close only via the finish helper on success" ;;
    --help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$skill" ]] || die "--skill is required"
[[ -n "$task" ]] || die "--task is required"
[[ -n "$cwd" ]] || die "--cwd is required"
[[ -n "$prompt_template" ]] || die "--prompt-template is required"
[[ "$skill" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "--skill must use lowercase letters, digits, and hyphens only"
[[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -gt 0 ]] || die "--timeout must be a positive integer number of seconds"
command -v tmux >/dev/null 2>&1 || die "tmux is required and no other multiplexer is supported"
command -v "$pi_bin" >/dev/null 2>&1 || die "Pi executable not found: $pi_bin"
[[ -d "$cwd" ]] || die "working directory does not exist: $cwd"
[[ -f "$prompt_template" ]] || die "prompt template does not exist: $prompt_template"

cwd=$(cd "$cwd" && pwd -P)
prompt_template=$(cd "$(dirname "$prompt_template")" && pwd -P)/$(basename "$prompt_template")
agents_dir="$cwd/.agents"
for dir in research plans specs reviews impl-reports logs status locks; do mkdir -p "$agents_dir/$dir"; done
agents_dir=$(cd "$agents_dir" && pwd -P)

task_slug=$(slugify "$task")
timestamp=$(date -u +%Y%m%d%H%M%S)
run_id="pi-${skill}-${task_slug}-${timestamp}-$$-$(random_suffix)"
lock_key= lock_file=
if [[ "$workspace_lock" == true ]]; then
  lock_key="workspace-$(slugify "$cwd")-$(printf '%s' "$cwd" | cksum | cut -d ' ' -f 1)"
  lock_file="$agents_dir/locks/${lock_key}.lock"
fi

if [[ -z "$artifact_path" ]]; then
  [[ "$artifact_dir" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "--artifact-dir must be a simple .agents/ child directory name"
  mkdir -p "$agents_dir/$artifact_dir"
  artifact_path="$agents_dir/$artifact_dir/${run_id}.md"
elif [[ "$artifact_path" != /* ]]; then
  artifact_path="$cwd/$artifact_path"
fi
case "$artifact_path" in "$agents_dir"/*) ;; *) die "artifact path must be under $agents_dir" ;; esac
mkdir -p "$(dirname "$artifact_path")"
artifact_parent=$(cd "$(dirname "$artifact_path")" && pwd -P)
artifact_path="$artifact_parent/$(basename "$artifact_path")"
case "$artifact_path" in "$agents_dir"/*) ;; *) die "artifact path must be under $agents_dir" ;; esac

task_file="$agents_dir/status/${run_id}.task.txt"
runner_script="$agents_dir/status/${run_id}.runner.sh"
finish_script="$agents_dir/status/${run_id}.finish.sh"
success_sentinel="$agents_dir/status/${run_id}.success"
failure_sentinel="$agents_dir/status/${run_id}.failure"
failure_reason_file="${failure_sentinel}.reason"
runner_log="$agents_dir/logs/${run_id}.runner.log"
tmux_session= tmux_window=agent tmux_window_target= tmux_pane_id= tmux_pane_target=

cat >"$task_file" <<TASK
You are running as an interactive tmux child pane for Pi skill: $skill.

Primary artifact path: $artifact_path
Task file path: $task_file
Finish helper path: $finish_script
Success sentinel path: $success_sentinel
Failure sentinel path: $failure_sentinel

Write your final result to the Primary artifact path. When the run is successful,
execute exactly:
"\$PI_CHILD_RUNNER_FINISH" --success

If the run fails, execute:
"\$PI_CHILD_RUNNER_FINISH" --failure "short reason"

The finish helper updates sentinel files. Do not create sentinels manually. A
successful finish closes this tmux pane automatically; failures leave the pane
open for inspection.

Task:
$task
TASK

cat >"$finish_script" <<FINISH
#!/usr/bin/env bash
set -euo pipefail
artifact_path=$(printf '%q' "$artifact_path")
success_sentinel=$(printf '%q' "$success_sentinel")
failure_sentinel=$(printf '%q' "$failure_sentinel")
failure_reason_file=$(printf '%q' "$failure_reason_file")
mode= reason=
case "\${1-}" in
  --success) mode=success; shift ;;
  --failure) mode=failure; shift; reason=\${1:-failure} ;;
  *) printf 'usage: %s --success | --failure REASON\n' "\$0" >&2; exit 2 ;;
esac
if [[ "\$mode" == success && ! -s "\$artifact_path" ]]; then mode=failure; reason=missing-artifact; fi
if [[ "\$mode" == success ]]; then
  rm -f "\$failure_sentinel" "\$failure_reason_file"
  : >"\$success_sentinel"
  # Let the shell finish flushing stdout/stderr before killing its own pane.
  if [[ -n "\${TMUX_PANE:-}" ]]; then ( sleep 0.2; tmux kill-pane -t "\$TMUX_PANE" >/dev/null 2>&1 || true ) & fi
else
  [[ -n "\$reason" ]] || reason=failure
  rm -f "\$success_sentinel"
  printf '%s\n' "\$reason" >"\$failure_reason_file"
  : >"\$failure_sentinel"
  printf 'Pi child marked failure: %s\nPane left open for inspection.\n' "\$reason" >&2
fi
FINISH
chmod +x "$finish_script"

cat >"$runner_script" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "$cwd")
export PI_CHILD_RUNNER_SKILL=$(printf '%q' "$skill")
export PI_CHILD_RUNNER_ARTIFACT_PATH=$(printf '%q' "$artifact_path")
export PI_CHILD_RUNNER_TASK_FILE=$(printf '%q' "$task_file")
export PI_CHILD_RUNNER_FINISH=$(printf '%q' "$finish_script")
export PI_CHILD_RUNNER_SKILLS_SCRIPTS_DIR=$(printf '%q' "$script_dir")
pi_args=(--prompt-template $(printf '%q' "$prompt_template"))
RUNNER
[[ -n "$provider" ]] && printf 'pi_args+=(--provider %q)\n' "$provider" >>"$runner_script"
[[ -n "$model" ]] && printf 'pi_args+=(--model %q)\n' "$model" >>"$runner_script"
[[ -n "$thinking" ]] && printf 'pi_args+=(--thinking %q)\n' "$thinking" >>"$runner_script"
cat >>"$runner_script" <<RUNNER
if [[ $(printf '%q' "$workspace_lock") == true ]]; then
  set +e; exec 9>$(printf '%q' "$lock_file"); flock -n 9; lock_status=\$?; set -e
  if [[ \$lock_status -ne 0 ]]; then
    printf '# Child Run Failure\n\nReason: workspace-lock-held\n' >$(printf '%q' "$artifact_path")
    $(printf '%q' "$finish_script") --failure workspace-lock-held
    exec "\${SHELL:-/bin/sh}"
  fi
fi
set +e
$(printf '%q' "$pi_bin") "\${pi_args[@]}" "\$(cat $(printf '%q' "$task_file"))"
child_status=\$?
set -e
if [[ ! -f $(printf '%q' "$success_sentinel") && ! -f $(printf '%q' "$failure_sentinel") ]]; then
  $(printf '%q' "$finish_script") --failure child-exit-without-finish
fi
if [[ -f $(printf '%q' "$failure_sentinel") ]]; then
  printf 'Interactive Pi exited (status %s) without successful finish. Pane left open.\n' "\$child_status"
  exec "\${SHELL:-/bin/sh}"
fi
exit "\$child_status"
RUNNER
chmod +x "$runner_script"

resolve_current_session() { tmux display-message -p '#{session_name}' 2>/dev/null || true; }
window_exists() {
  local session=$1 window=$2 line
  while IFS= read -r line; do [[ "$line" == "$window" ]] && return 0; done < <(tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null || true)
  return 1
}

tmux_session=$(resolve_current_session)
if [[ -z "$tmux_session" ]]; then
  tmux_session=${PI_CHILD_RUNNER_FALLBACK_SESSION:-pi-agent}
  if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
    tmux new-session -d -s "$tmux_session" -n agent
  fi
fi
tmux_window=agent
tmux_window_target="${tmux_session}:${tmux_window}"

set +e
if window_exists "$tmux_session" "$tmux_window"; then
  pane_info=$(tmux split-window -d -t "$tmux_window_target" -P -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id}' "$runner_script" 2>>"$runner_log")
  tmux_status=$?
else
  pane_info=$(tmux new-window -d -t "${tmux_session}:" -n "$tmux_window" -P -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id}' "$runner_script" 2>>"$runner_log")
  tmux_status=$?
fi
set -e
if [[ $tmux_status -ne 0 ]]; then
  write_failure_artifact "tmux-pane-failed" "tmux exited with status $tmux_status"
  printf '%s\n' tmux-pane-failed >"$failure_reason_file"
  : >"$failure_sentinel"
  # Keep stdout as the tiny public contract consumed by humans and callers.
  # Internal paths remain in the task/env/log files instead of leaking as extra
  # parseable keys that callers might accidentally depend on.
  print_kv ARTIFACT_PATH "$artifact_path"
  print_kv SUCCESS_SENTINEL "$success_sentinel"
  print_kv FAILURE_SENTINEL "$failure_sentinel"
  exit "$tmux_status"
fi
tmux_pane_target=${pane_info%% *}
tmux_pane_id=${pane_info#* }
[[ "$tmux_pane_id" == "$pane_info" ]] && tmux_pane_id=

{
  print_kv ARTIFACT_PATH "$artifact_path"
  print_kv SUCCESS_SENTINEL "$success_sentinel"
  print_kv FAILURE_SENTINEL "$failure_sentinel"
}

{
  printf 'run_id=%s\nartifact_path=%s\n' "$run_id" "$artifact_path"
  printf 'success_sentinel=%s\nfailure_sentinel=%s\n' "$success_sentinel" "$failure_sentinel"
  printf 'tmux_session=%s\ntmux_window=%s\ntmux_pane_target=%s\ntmux_pane_id=%s\n' "$tmux_session" "$tmux_window" "$tmux_pane_target" "$tmux_pane_id"
} >>"$runner_log"
