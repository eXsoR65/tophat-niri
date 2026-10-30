#!/bin/bash
# =============================================================================
#  check_action_pins.sh — wrapper around check_action_pins.py
#
#  Kept as a shell entry point so CI and tests/verify_all.sh stay uniform, and so
#  a missing parser is a clear failure rather than a stack trace.
#
#  Usage: check_action_pins.sh [repo-root]
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required to parse workflow YAML" >&2
  exit 1
fi

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "FAIL: PyYAML is required to parse workflow YAML (python3 -c 'import yaml')" >&2
  echo "  install: dnf install python3-pyyaml | apt-get install python3-yaml | pip install pyyaml" >&2
  exit 1
fi

exec python3 "$ROOT/tests/check_action_pins.py" "${1:-$ROOT}"
