#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# ---- defaults ----
GOV_AC="performance" # performance powersave
EPP_AC="performance" # default performance balance_performance balance_power power
PP_AC="performance" # low-power balanced performance

GOV_BAT="powersave"
EPP_BAT="power"
PP_BAT="low-power"

usage() {
  cat <<'EOF'
Usage: script.sh [--gov VALUE] [--epp VALUE] [--pp VALUE] [--help]

Overrides (optional):
  --gov VALUE   Scaling governor (performance powersave)
  --epp VALUE   Energy performance (default performance balance_performance balance_power power)
  --pp  VALUE   platform_profile (low-power balanced performance)

If overrides are omitted, values are chosen by AC state (type=Main*).
EOF
}

# ---- parse args ----
ARG_GOV=""
ARG_EPP=""
ARG_PP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gov)
      [[ $# -ge 2 ]] || { echo "ERROR: --gov needs a value" >&2; exit 2; }
      ARG_GOV="$2"; shift 2 ;;
    --epp)
      [[ $# -ge 2 ]] || { echo "ERROR: --epp needs a value" >&2; exit 2; }
      ARG_EPP="$2"; shift 2 ;;
    --pp)
      [[ $# -ge 2 ]] || { echo "ERROR: --pp needs a value" >&2; exit 2; }
      ARG_PP="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 2 ;;
  esac
done

# ---- root check ----
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: root 権限が必要です（sudo で実行してください）" >&2
  exit 1
fi

# ---- detect AC (type=Main*) ----
ON_AC=0
found=0
for ps in /sys/class/power_supply/*; do
  [[ -f "$ps/type" && -f "$ps/online" ]] || continue
  [[ "$(cat "$ps/type")" == Main* ]] || continue  # "Main" / "Mains" 想定
  found=1
  [[ "$(cat "$ps/online")" == "1" ]] && ON_AC=1 || ON_AC=0
  break
done

if [[ "$found" -eq 0 ]]; then
  echo "ERROR: type=Main* の power_supply が見つかりません" >&2
  exit 2
fi

# ---- choose values ----
if [[ "$ON_AC" -eq 1 ]]; then
  GOV="$GOV_AC"; EPP="$EPP_AC"; PP="$PP_AC"
else
  GOV="$GOV_BAT"; EPP="$EPP_BAT"; PP="$PP_BAT"
fi

# apply overrides if provided
[[ -n "$ARG_GOV" ]] && GOV="$ARG_GOV"
[[ -n "$ARG_EPP" ]] && EPP="$ARG_EPP"
[[ -n "$ARG_PP"  ]] && PP="$ARG_PP"

# ---- apply CPU (policy*/ only) ----
policies=(/sys/devices/system/cpu/cpufreq/policy*)
if [[ "${#policies[@]}" -eq 0 ]]; then
  echo "ERROR: cpufreq policy* が見つかりません" >&2
  exit 2
fi

for p in "${policies[@]}"; do
  govf="$p/scaling_governor"
  gova="$p/scaling_available_governors"
  if [[ -w "$govf" ]]; then
    if [[ -f "$gova" ]] && ! grep -qw -- "$GOV" "$gova"; then
      echo "WARN: governor '$GOV' は許容されないためスキップ: $govf" >&2
    else
      echo "$GOV" > "$govf"
    fi
  fi

  eppf="$p/energy_performance_preference"
  eppa="$p/energy_performance_available_preferences"
  if [[ -w "$eppf" ]]; then
    if [[ -f "$eppa" ]] && ! grep -qw -- "$EPP" "$eppa"; then
      echo "WARN: EPP '$EPP' は許容されないためスキップ: $eppf" >&2
    else
      echo "$EPP" > "$eppf"
    fi
  fi
done

# ---- apply platform_profile ----
PP_FILE=/sys/firmware/acpi/platform_profile
PP_CHOICES=/sys/firmware/acpi/platform_profile_choices

if [[ -w "$PP_FILE" ]]; then
  if [[ -f "$PP_CHOICES" ]] && ! grep -qw -- "$PP" "$PP_CHOICES"; then
    echo "WARN: platform_profile '$PP' は choices に無いためスキップ" >&2
  else
    echo "$PP" > "$PP_FILE"
  fi
fi

