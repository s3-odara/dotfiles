#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: review-orchestrator.sh --task TEXT --cwd DIR [options]

Options are forwarded to child review helpers where applicable: --timeout,
--model, --provider, --thinking, --pi-bin, --keep-pane, and --auto-exit.
USAGE
}

die() { printf 'review-orchestrator: %s\n' "$*" >&2; exit 2; }

slugify() {
  local raw=${1:-task} slug
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

status_value() {
  local file=$1 key=$2
  [[ -s "$file" ]] || return 1
  # Use Node's JSON parser rather than maintaining a shell JSON unescaper. Node
  # is already required by this package's TypeScript tests; keeping parsing in
  # one real parser preserves literal backslash paths without custom regex code.
  node -e 'const fs=require("fs"); const data=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const value=data[process.argv[2]]; if (value === undefined || value === null) process.exit(1); process.stdout.write(String(value));' "$file" "$key"
}

wait_for_status() {
  local status_file=$1 timeout_seconds=$2 elapsed=0 status
  while true; do
    if [[ -s "$status_file" ]]; then
      status=$(status_value "$status_file" status || true)
      if [[ "$status" != started && -n "$status" ]]; then return 0; fi
    fi
    if (( elapsed >= timeout_seconds )); then return 1; fi
    sleep 1; elapsed=$((elapsed + 1))
  done
}

stable_status_value() {
  local file=$1 key=$2 value
  for _ in 1 2 3; do
    value=$(status_value "$file" "$key" || true)
    if [[ -n "$value" || "$key" == failure_reason ]]; then
      printf '%s' "$value"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

last_json_path() {
  node -e 'const lines=require("fs").readFileSync(0,"utf8").trim().split(/\n/).filter(Boolean); const path=[...lines].reverse().find((line)=>line.endsWith(".json")); if (path) process.stdout.write(path);'
}

task=
cwd=
timeout_seconds=1800
model=
provider=
thinking=
pi_bin=
keep_pane=false
auto_exit=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) task=${2-}; shift 2 ;;
    --cwd) cwd=${2-}; shift 2 ;;
    --timeout) timeout_seconds=${2-}; shift 2 ;;
    --model) model=${2-}; shift 2 ;;
    --provider) provider=${2-}; shift 2 ;;
    --thinking) thinking=${2-}; shift 2 ;;
    --pi-bin) pi_bin=${2-}; shift 2 ;;
    --keep-pane) keep_pane=true; auto_exit=false; shift ;;
    --auto-exit) auto_exit=true; shift ;;
    --help) usage; exit 0 ;;
    --prompt-template|--artifact|--artifact-dir|--lock-key|--lock-timeout|--skill) die "$1 is not supported by this coordinator" ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$task" ]] || die "--task is required"
[[ -n "$cwd" ]] || die "--cwd is required"
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die "--timeout must be a positive integer number of seconds"
(( timeout_seconds > 0 )) || die "--timeout must be greater than zero"
[[ -d "$cwd" ]] || die "working directory does not exist: $cwd"
cwd=$(cd "$cwd" && pwd -P)

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
launcher="$script_dir/../spawn-skill-tmux-child.sh"
[[ -x "$launcher" ]] || die "central launcher is not executable: $launcher"

agents_dir="$cwd/.agents"
mkdir -p "$agents_dir/reviews" "$agents_dir/status" "$agents_dir/logs"
timestamp=$(date -u +%Y%m%d%H%M%S)
task_slug=$(slugify "$task")
run_id="pi-review-orchestrator-${task_slug}-${timestamp}-$$-$(random_suffix)"
aggregate="$agents_dir/reviews/${run_id}.md"

forward=(--skill code-reviewer --task "$task" --cwd "$cwd" --timeout "$timeout_seconds")
[[ -n "$model" ]] && forward+=(--model "$model")
[[ -n "$provider" ]] && forward+=(--provider "$provider")
[[ -n "$thinking" ]] && forward+=(--thinking "$thinking")
[[ -n "$pi_bin" ]] && forward+=(--pi-bin "$pi_bin")
[[ "$keep_pane" == true ]] && forward+=(--keep-pane)
[[ "$auto_exit" == true ]] && forward+=(--auto-exit)

set +e
reviewer_stdout=$("$launcher" "${forward[@]}" 2>"$agents_dir/logs/${run_id}-code-reviewer.launch.stderr")
reviewer_launch=$?
set -e
reviewer_status=$(printf '%s\n' "$reviewer_stdout" | last_json_path)
reviewer_poll_timeout=false

# Polling status JSON keeps completion detection tied to helper-owned artifacts
# rather than tmux pane text, which varies by terminal and shell configuration.
if [[ -n "$reviewer_status" ]] && ! wait_for_status "$reviewer_status" "$timeout_seconds"; then
  # The child helper owns the status JSON, so do not rewrite it from the
  # coordinator. Instead, remember that our polling budget expired and render a
  # parent diagnostic below if the child is still nonterminal.
  reviewer_poll_timeout=true
fi

reviewer_child_status=
reviewer_reason=
reviewer_artifact=
if [[ -n "$reviewer_status" && -s "$reviewer_status" ]]; then
  reviewer_child_status=$(stable_status_value "$reviewer_status" status || true)
  reviewer_reason=$(stable_status_value "$reviewer_status" failure_reason || true)
  reviewer_artifact=$(stable_status_value "$reviewer_status" artifact_path || true)
  if [[ "$reviewer_poll_timeout" == true && ( -z "$reviewer_child_status" || "$reviewer_child_status" == started ) ]]; then
    reviewer_child_status=failure
    reviewer_reason=timeout
  fi
fi

retained_count=0
tmp_aggregate="${aggregate}.$$.$RANDOM.tmp"
{
  printf '# Review Orchestrator Report\n\n'
  printf 'Task: %s\n\n' "$task"
  printf 'Run ID: %s\n\n' "$run_id"
  printf 'Aggregate artifact: %s\n\n' "$aggregate"
  printf '## Children\n\n'
  if [[ $reviewer_launch -ne 0 || -z "$reviewer_status" ]]; then
    printf -- '- code-reviewer: launch-failed (exit %s); see launch stderr log.\n' "$reviewer_launch"
  fi
  if [[ -z "$reviewer_status" || ! -s "$reviewer_status" ]]; then
    printf -- '- code-reviewer: missing status JSON\n'
  else
    printf -- '- code-reviewer: %s' "${reviewer_child_status:-unknown}"
    [[ -n "$reviewer_reason" ]] && printf ' (%s)' "$reviewer_reason"
    printf '; status=%s; artifact=%s\n' "$reviewer_status" "$reviewer_artifact"
  fi
  printf '\n## Retained Findings\n\n'
  if [[ "$reviewer_child_status" == success && -s "$reviewer_artifact" ]]; then
    retained_count=$((retained_count + 1))
    printf '### code-reviewer\n\n'
    cat "$reviewer_artifact"
    printf '\n\n'
  fi
  if (( retained_count == 0 )); then
    printf 'No retained findings: no successful child review artifact was available.\n'
  fi
  printf '\n## Notes\n\n'
  printf 'Missing or failed children above are diagnostics for the parent.\n'
} >"$tmp_aggregate"
mv -f "$tmp_aggregate" "$aggregate"

printf '%s\n' "$aggregate"
