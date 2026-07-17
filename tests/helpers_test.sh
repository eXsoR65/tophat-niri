#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export DRY_RUN=false VERBOSE=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR"

source "$ROOT/lib/helpers/run_logged.sh"
source "$ROOT/lib/helpers/checks.sh"

# List parsing keeps entries intact, removes comments, and deduplicates.
list_file="$tmp_dir/list"
cat >"$list_file" <<'EOF'
# comment
  org.example.App  # inline comment
formula@2
formula@2

EOF

entries=()
read_list_file "$list_file" entries
[[ ${#entries[@]} -eq 2 ]]
[[ "${entries[0]}" == "org.example.App" ]]
[[ "${entries[1]}" == "formula@2" ]]

printf 'bad\tentry\n' >"$list_file"
if read_list_file "$list_file" entries 2>/dev/null; then
  echo "FAIL: control characters were accepted" >&2
  exit 1
fi

# An intentionally skipped stage must not receive a state marker.
STAGE_STATUS[extras]="running"
STAGE_DURATIONS[extras]="$(date +%s)"
skip_stage extras "test skip"
log_stage_complete extras
[[ ! -e "$SETUP_STATE_DIR/stage-extras.done" ]]
[[ "${STAGE_STATUS[extras]}" == "skipped" ]]

echo "helpers_test.sh: PASS"
