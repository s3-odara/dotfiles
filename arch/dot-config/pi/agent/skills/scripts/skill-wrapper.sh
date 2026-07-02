#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'skill-wrapper: %s\n' "$*" >&2
  exit 2
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
caller=${PI_SKILL_WRAPPER_CALLER:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}
caller_dir=$(cd "$(dirname "$caller")" && pwd -P)
skill_dir=$(cd "$caller_dir/.." && pwd -P)
skill_name=${PI_SKILL_NAME:-$(basename "$skill_dir")}

case "$skill_name" in
  explorer|internet-researcher) artifact_dir=research ;;
  code-reviewer|debugger|plan-reviewer|tester) artifact_dir=reviews ;;
  implementer) artifact_dir=impl-reports ;;
  *) die "unknown bundled skill: $skill_name" ;;
esac

common_args=(
  --skill "$skill_name"
  --artifact-dir "$artifact_dir"
  --prompt-template "${PROMPT_TEMPLATE:-$skill_dir/SKILL.md}"
)

if [[ "$skill_name" == implementer ]]; then
  # Keep write-capable child runs serialized at the shared helper layer. Doing
  # this here instead of in per-skill shell copies keeps the public wrapper path
  # stable while preventing later edits from accidentally dropping the lock.
  common_args+=(
    --lock-key "${PI_IMPLEMENTER_LOCK_KEY:-workspace}"
    --lock-timeout "${PI_IMPLEMENTER_LOCK_TIMEOUT:-60}"
  )
fi

exec "$script_dir/spawn-tmux-child-common.sh" "${common_args[@]}" "$@"
