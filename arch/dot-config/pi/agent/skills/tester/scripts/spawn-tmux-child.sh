#!/usr/bin/env bash
set -euo pipefail
PI_SKILL_WRAPPER_CALLER=${BASH_SOURCE[0]} exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)/scripts/skill-wrapper.sh" "$@"
