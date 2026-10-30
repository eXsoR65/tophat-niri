#!/bin/bash
# =============================================================================
#  events_test.sh — the NDJSON event stream the TUI consumes
#
#  With TOPHAT_TUI=1 the installer appends one JSON object per line to
#  $SETUP_STATE_DIR/events.ndjson. This pins the contract: valid JSON, the event
#  types the TUI renders, values escaped rather than breaking the line, and
#  nothing emitted at all for a plain CLI run.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

events_file() { echo "$tmp_dir/state/events.ndjson"; }

run_helpers() { # $1 = TOPHAT_TUI value, rest = script body
  local tui="$1"
  shift
  TOPHAT_TUI="$tui" SETUP_STATE_DIR="$tmp_dir/state" SETUP_LOG="$tmp_dir/log" \
    DRY_RUN=false VERBOSE=false FORCE=false CURRENT_STAGE="" \
    CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET='' \
    bash -c 'source "'"$ROOT"'/lib/helpers/run_logged.sh"; mkdir -p "$SETUP_STATE_DIR"; : >"$SETUP_LOG"; '"$*" 2>/dev/null || true
}

# --- a stage lifecycle produces the events the TUI renders ------------------
run_helpers 1 '
tophat_events_reset
log_stage_start packaging
run_logged "installing things" true
log_stage_complete packaging
skip_stage extras "no opt-ins"
'
[[ -f "$(events_file)" ]] || fail "no event stream was written"

python3 - "$(events_file)" <<'PY' || fail "event stream is not valid JSON/expected shape"
import json, sys
events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
kinds = [e["event"] for e in events]
for want in ("stage_start", "command", "stage_done", "marker", "stage_skipped"):
    assert want in kinds, f"missing {want} in {kinds}"
start = next(e for e in events if e["event"] == "stage_start")
assert start["stage"] == "packaging", start
done = next(e for e in events if e["event"] == "stage_done")
assert done["stage"] == "packaging" and "seconds" in done, done
skipped = next(e for e in events if e["event"] == "stage_skipped")
assert skipped["reason"] == "no opt-ins", skipped
for e in events:
    assert isinstance(e["at"], int), e
PY

# --- a failure is reported, so the TUI can stop waiting --------------------
run_helpers 1 '
tophat_events_reset
log_stage_start repos
run_logged "does not matter" false
'
python3 - "$(events_file)" <<'PY' || fail "failure was not reported as stage_fail"
import json, sys
events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
failures = [e for e in events if e["event"] == "stage_fail"]
assert failures, [e["event"] for e in events]
assert failures[0]["stage"] == "repos", failures[0]
PY

# --- awkward payloads stay on one line and round-trip ----------------------
run_helpers 1 '
tophat_events_reset
log_stage_start config
run_logged "quote \" back\\slash tab	here" true
'
python3 - "$(events_file)" <<'PY' || fail "escaping broke the event stream"
import json, sys
lines = [line for line in open(sys.argv[1]) if line.strip()]
events = [json.loads(line) for line in lines]
desc = next(e["desc"] for e in events if e["event"] == "command")
assert 'quote " back\\slash tab\there' == desc, repr(desc)
PY

# --- reset truncates a previous run ---------------------------------------
printf '{"event":"stale"}\n' >"$(events_file)"
run_helpers 1 'tophat_events_reset; log_stage_start preflight'
if grep -q '"stale"' "$(events_file)"; then
  fail "reset did not truncate the previous stream"
fi

# --- nothing at all for a plain CLI run -----------------------------------
rm -f "$(events_file)"
run_helpers 0 'tophat_events_reset; log_stage_start preflight; log_stage_complete preflight'
[[ -e "$(events_file)" ]] && fail "events were written without TOPHAT_TUI=1"

echo "events_test.sh: PASS"
