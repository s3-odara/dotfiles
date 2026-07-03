#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-skill-background.sh --skill NAME --task TEXT --cwd DIR [options]

Options:
  --model MODEL           Optional Pi --model hint.
  --provider PROVIDER     Optional Pi --provider hint.
  --thinking LEVEL        Optional Pi --thinking hint.
  --timeout SECONDS       Child timeout, default 1800.
  --pi-bin PATH           Pi executable, default pi.
  --no-wait               Start the pane and return sentinel paths without waiting.
  --help                  Show this help.
USAGE
}

die() { printf 'run-skill-background: %s\n' "$*" >&2; exit 2; }

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

skill=
task=
cwd=
timeout_seconds=1800
model=
provider=
thinking=
pi_bin=
wait_for_child=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill) skill=${2-}; shift 2 ;;
    --task) task=${2-}; shift 2 ;;
    --cwd) cwd=${2-}; shift 2 ;;
    --timeout) timeout_seconds=${2-}; shift 2 ;;
    --model) model=${2-}; shift 2 ;;
    --provider) provider=${2-}; shift 2 ;;
    --thinking) thinking=${2-}; shift 2 ;;
    --pi-bin) pi_bin=${2-}; shift 2 ;;
    --no-wait) wait_for_child=false; shift ;;
  --keep-pane|--auto-exit) die "$1 is obsolete; panes close only via the finish helper on success" ;;
  --help) usage; exit 0 ;;
  --prompt-template|--artifact|--artifact-dir|--workspace-lock|--lock-key|--lock-timeout) die "$1 is internal to the central launcher" ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$skill" ]] || die "--skill is required"
[[ -n "$task" ]] || die "--task is required"
[[ -n "$cwd" ]] || die "--cwd is required"

artifact_dir=
workspace_lock=false
case "$skill" in
  explorer|internet-researcher)
    artifact_dir=research
    ;;
  code-reviewer|debugger|tester|plan-reviewer|review-orchestrator)
    artifact_dir=reviews
    ;;
  implementer)
    artifact_dir=impl-reports
    workspace_lock=true
    ;;
  *)
    die "skill is not tmux-managed: $skill"
    ;;
esac

forward=(--task "$task" --cwd "$cwd" --timeout "$timeout_seconds")
[[ -n "$model" ]] && forward+=(--model "$model")
[[ -n "$provider" ]] && forward+=(--provider "$provider")
[[ -n "$thinking" ]] && forward+=(--thinking "$thinking")
[[ -n "$pi_bin" ]] && forward+=(--pi-bin "$pi_bin")

skill_dir=$(cd "$script_dir/../$skill" && pwd -P)
common=(
  --skill "$skill"
  --artifact-dir "$artifact_dir"
  --prompt-template "$skill_dir/SKILL.md"
)
[[ "$workspace_lock" == true ]] && common+=(--workspace-lock)
launch_output=$("$script_dir/start-bg-pane.sh" "${common[@]}" "${forward[@]}")

# Trusted bundled helper output: shell-quoted KEY='value' lines.
eval "$(printf '%s\n' "$launch_output" | grep -E '^(ARTIFACT_PATH|SUCCESS_SENTINEL|FAILURE_SENTINEL)=')"

if [[ "$wait_for_child" == false ]]; then
  printf '%s\n' "$launch_output"
  exit 0
fi

if ! "$script_dir/wait-for-children.sh" --success "$SUCCESS_SENTINEL" --failure "$FAILURE_SENTINEL" --timeout "$timeout_seconds" --poll 1 >/dev/null; then
  reason=failure
  if [[ -f "${FAILURE_SENTINEL}.reason" ]]; then
    reason=$(cat "${FAILURE_SENTINEL}.reason")
  elif [[ ! -f "$FAILURE_SENTINEL" ]]; then
    reason=timeout
  fi
  printf 'child %s failed: %s\nartifact: %s\n' "$skill" "$reason" "$ARTIFACT_PATH" >&2
  exit 1
fi

print_kv() { printf "%s='%s'\n" "$1" "${2//\'/\'\\\'\'}"; }
print_kv ARTIFACT_PATH "$ARTIFACT_PATH"
