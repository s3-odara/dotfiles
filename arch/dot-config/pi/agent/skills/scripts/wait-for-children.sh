#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: wait-for-children.sh --success PATH --failure PATH [--success PATH --failure PATH ...] [options]

Block until each child has either its success or failure sentinel, then print a
simple key=value summary.

Options:
  --success PATH     Success sentinel for one child (repeatable).
  --failure PATH     Failure sentinel for one child (repeatable; pair by order).
  --timeout SECONDS  Total poll timeout across all children, default 600.
  --poll SECONDS     Poll interval in seconds, default 3.
  --help             Show this help.

Exit codes:
  0   All children succeeded.
  1   One or more children failed or timed out.
  3   Usage or input error.
USAGE
}

die() { printf 'wait-for-children: %s\n' "$*" >&2; exit 3; }

shell_quote_value() {
  local value=${1-}
  printf "'%s'" "${value//\'/\'\\\'\'}"
}
print_kv() { printf '%s=%s\n' "$1" "$(shell_quote_value "${2-}")"; }

success_paths=()
failure_paths=()
poll_timeout=600
poll_interval=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --success) success_paths+=("${2-}"); shift 2 ;;
    --failure) failure_paths+=("${2-}"); shift 2 ;;
    --timeout) poll_timeout=${2-}; shift 2 ;;
    --poll) poll_interval=${2-}; shift 2 ;;
    --help) usage; exit 0 ;;
    --agents-dir|--run-id) die "$1 is obsolete; pass --success PATH --failure PATH sentinel pairs" ;;
    *) die "unknown argument: $1" ;;
  esac
done

((${#success_paths[@]} > 0)) || die "at least one --success/--failure pair is required"
((${#success_paths[@]} == ${#failure_paths[@]})) || die "each --success must have a matching --failure"
[[ "$poll_timeout" =~ ^[0-9]+$ ]] || die "--timeout must be a non-negative integer"
[[ "$poll_interval" =~ ^[0-9]+$ ]] || die "--poll must be a non-negative integer"
(( poll_timeout > 0 )) || die "--timeout must be greater than zero"
(( poll_interval > 0 )) || die "--poll must be greater than zero"

declare -a results
for ((i = 0; i < ${#success_paths[@]}; i++)); do results[$i]=waiting; done

remaining=${#success_paths[@]}
start_sec=$SECONDS
while (( remaining > 0 && SECONDS - start_sec < poll_timeout )); do
  for ((i = 0; i < ${#success_paths[@]}; i++)); do
    [[ "${results[$i]}" != waiting ]] && continue
    if [[ -f "${success_paths[$i]}" ]]; then
      results[$i]=success
      remaining=$((remaining - 1))
    elif [[ -f "${failure_paths[$i]}" ]]; then
      results[$i]=failure
      remaining=$((remaining - 1))
    fi
  done
  (( remaining == 0 )) || sleep "$poll_interval"
done

elapsed=$(( SECONDS - start_sec ))
overall=success
success_count=0
failure_count=0
timeout_count=0
for ((i = 0; i < ${#success_paths[@]}; i++)); do
  if [[ "${results[$i]}" == waiting ]]; then results[$i]=timeout; fi
  case "${results[$i]}" in
    success) success_count=$((success_count + 1)) ;;
    failure) failure_count=$((failure_count + 1)); overall=failure ;;
    timeout) timeout_count=$((timeout_count + 1)); overall=failure ;;
  esac
done

print_kv OVERALL "$overall"
printf 'TOTAL=%d\n' "${#success_paths[@]}"
printf 'SUCCESS=%d\n' "$success_count"
printf 'FAILURE=%d\n' "$failure_count"
printf 'TIMEOUT=%d\n' "$timeout_count"
printf 'POLL_ELAPSED_SECONDS=%d\n' "$elapsed"
for ((i = 0; i < ${#success_paths[@]}; i++)); do
  n=$((i + 1))
  print_kv "CHILD_${n}_STATUS" "${results[$i]}"
  print_kv "CHILD_${n}_SUCCESS_SENTINEL" "${success_paths[$i]}"
  print_kv "CHILD_${n}_FAILURE_SENTINEL" "${failure_paths[$i]}"
done

[[ "$overall" == success ]]
