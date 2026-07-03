#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: spawn-skill-tmux-child.sh --skill NAME --task TEXT --cwd DIR [options]

Options:
  --model MODEL           Optional Pi --model hint.
  --provider PROVIDER     Optional Pi --provider hint.
  --thinking LEVEL        Optional Pi --thinking hint.
  --timeout SECONDS       Child timeout, default 1800.
  --keep-pane             Keep the tmux pane open after child completion.
  --auto-exit             Exit the pane after success; failures are kept for inspection.
  --pi-bin PATH           Pi executable, default pi.
  --help                  Show this help.
USAGE
}

die() { printf 'spawn-skill-tmux-child: %s\n' "$*" >&2; exit 2; }

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
manifest="$script_dir/tmux-managed-skills.tsv"

skill=
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
    --skill) skill=${2-}; shift 2 ;;
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
    --prompt-template|--artifact|--artifact-dir|--lock-key|--lock-timeout) die "$1 is internal to the central launcher" ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$skill" ]] || die "--skill is required"
[[ -n "$task" ]] || die "--task is required"
[[ -n "$cwd" ]] || die "--cwd is required"
[[ -f "$manifest" ]] || die "manifest not found: $manifest"

artifact_dir=
mode=
lock_key=
lock_timeout_env=
lock_timeout_default=
while IFS=$'\t' read -r entry_skill entry_artifact_dir entry_mode entry_lock_key entry_lock_timeout_env entry_lock_timeout_default _; do
  [[ -n "${entry_skill:-}" && "${entry_skill:0:1}" != "#" ]] || continue
  if [[ "$entry_skill" == "$skill" ]]; then
    artifact_dir=$entry_artifact_dir
    mode=$entry_mode
    lock_key=$entry_lock_key
    lock_timeout_env=$entry_lock_timeout_env
    lock_timeout_default=$entry_lock_timeout_default
    break
  fi
done <"$manifest"

[[ -n "$mode" ]] || die "skill is not tmux-managed: $skill"

forward=(--task "$task" --cwd "$cwd" --timeout "$timeout_seconds")
[[ -n "$model" ]] && forward+=(--model "$model")
[[ -n "$provider" ]] && forward+=(--provider "$provider")
[[ -n "$thinking" ]] && forward+=(--thinking "$thinking")
[[ -n "$pi_bin" ]] && forward+=(--pi-bin "$pi_bin")
[[ "$keep_pane" == true ]] && forward+=(--keep-pane)
[[ "$auto_exit" == true ]] && forward+=(--auto-exit)

case "$mode" in
  normal)
    skill_dir=$(cd "$script_dir/../$skill" && pwd -P)
    common=(
      --skill "$skill"
      --artifact-dir "$artifact_dir"
      --prompt-template "$skill_dir/SKILL.md"
    )
    if [[ -n "$lock_key" ]]; then
      # The lock policy lives in the manifest so callers cannot accidentally run
      # write-capable skills without serialization. The env override keeps the
      # timeout tunable without reintroducing per-skill wrapper scripts.
      lock_timeout=$lock_timeout_default
      if [[ -n "$lock_timeout_env" ]]; then
        lock_timeout=${!lock_timeout_env:-$lock_timeout_default}
      fi
      common+=(--lock-key "$lock_key" --lock-timeout "$lock_timeout")
    fi
    exec "$script_dir/spawn-tmux-child-common.sh" "${common[@]}" "${forward[@]}"
    ;;
  coordinator)
    coordinator="$script_dir/coordinators/$skill.sh"
    [[ -x "$coordinator" ]] || die "coordinator is not executable: $coordinator"
    exec "$coordinator" "${forward[@]}"
    ;;
  *)
    die "unknown manifest mode for $skill: $mode"
    ;;
esac
