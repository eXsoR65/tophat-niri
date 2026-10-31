#!/bin/bash
# =============================================================================
#  events_test.sh — the NDJSON event stream the TUI consumes
#
#  With TOPHAT_TUI=1 the installer appends one JSON object per line to
#  $SETUP_STATE_DIR/events.ndjson. This pins the contract: valid JSON, the event
#  types the TUI renders, values escaped rather than breaking the line, and
#  nothing emitted at all for a plain CLI run.
# =============================================================================
# Child-script strings deliberately expand their variables in the child shell.
# shellcheck disable=SC2016
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
  helper_rc=0
  TOPHAT_TUI="$tui" SETUP_STATE_DIR="$tmp_dir/state" SETUP_LOG="$tmp_dir/log" \
    DRY_RUN=false VERBOSE=false FORCE=false CURRENT_STAGE="" \
    CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET='' \
    env -u TOPHAT_EVENTS_FILE bash -c 'set -euo pipefail; source "'"$ROOT"'/lib/helpers/run_logged.sh"; mkdir -p "$SETUP_STATE_DIR"; : >"$SETUP_LOG"; '"$*" \
    >"$tmp_dir/output" 2>&1 || helper_rc=$?
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

# --- real marker-based skip emits exactly one terminal event ----------------
run_helpers 1 '
tophat_events_reset
stage_marker_write repos
tophat_events_reset
log_stage_start repos
stage_already_run repos || exit 99
log_stage_complete repos
'
[[ "$helper_rc" == 0 ]] || fail "marker skip failed: $helper_rc"
python3 - "$(events_file)" <<'PY' || fail "marker skip has no terminal event"
import json, sys
events = [json.loads(line) for line in open(sys.argv[1])]
assert [e['event'] for e in events] == ['stage_start', 'stage_skipped'], events
assert events[1]['stage'] == 'repos' and events[1]['reason'], events
PY

# --- all failure paths preserve rc, emit once and compose cleanup ------------
for failure in 'exit 1' 'false' 'return 23' 'error_exit "bad input"' 'run_logged "bad command" bash -c "exit 17"'; do
  run_helpers 1 '
on_error() { exit "$?"; }
trap on_error ERR
main() {
  source "'"$ROOT"'/lib/helpers/run_logged.sh"
  tophat_events_reset
  acquire_run_lock
  cleanup() { : >"$SETUP_STATE_DIR/cleaned"; return 91; }
  register_exit_handler cleanup
  log_stage_start repos
  '"$failure"'
}
main
'
  expected_rc=1
  [[ "$failure" != 'return 23' ]] || expected_rc=23
  [[ "$failure" != 'run_logged "bad command" bash -c "exit 17"' ]] || expected_rc=17
  [[ "$helper_rc" == "$expected_rc" ]] || fail "$failure changed rc to $helper_rc"
  [[ ! -e "$tmp_dir/state/.lock.d" ]] || fail "$failure left lock behind"
  [[ -f "$tmp_dir/state/cleaned" ]] || fail "$failure skipped composed cleanup"
  python3 - "$(events_file)" "$expected_rc" <<'PY' || fail "$failure did not emit one failure"
import json, sys
events = [json.loads(line) for line in open(sys.argv[1])]
failures = [e for e in events if e['event'] == 'stage_fail']
assert len(failures) == 1, events
assert failures[0]['stage'] == 'repos' and failures[0]['exit'] == sys.argv[2], failures
PY
done

# --- every representable JSON control character round-trips -----------------
run_helpers 1 '
tophat_events_reset
payload=""
for ((i = 1; i < 32; i++)); do
  printf -v escaped "\\\\u%04x" "$i"
  printf -v char "%b" "$escaped"
  payload+="$char"
done
event_emit control "value=$payload" "$payload=key"
'
[[ "$helper_rc" == 0 ]] || fail "control payload failed"
python3 - "$(events_file)" <<'PY' || fail "control characters broke JSON"
import json, sys
lines = open(sys.argv[1]).readlines()
assert len(lines) == 1, lines
event = json.loads(lines[0])
controls = ''.join(chr(i) for i in range(1, 32))
assert event['value'] == controls, event
assert event[controls] == 'key', event
PY

# --- dry-run defaults are isolated; explicit paths work in both modes --------
printf 'live sentinel\n' >"$(events_file)"
for run in 1 2; do
  run_helpers 1 '
DRY_RUN=true
TMPDIR="'"$tmp_dir"'"
tophat_events_reset
printf "%s" "$(tophat_events_file)" >"'"$tmp_dir"'/dry-path-'"$run"'"
log_stage_start extras
skip_stage extras "dry preview"
log_stage_complete extras
'
  [[ "$helper_rc" == 0 ]] || fail "dry run failed"
done
python3 - "$tmp_dir" <<'PY' || fail "dry run touched live events or reused stream"
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
assert (root / 'state/events.ndjson').read_text() == 'live sentinel\n'
paths = [(root / f'dry-path-{n}').read_text() for n in (1, 2)]
assert paths[0] != paths[1], paths
for path in paths:
    assert pathlib.Path(path).parent == root, path
    events = [json.loads(line) for line in open(path)]
    assert [e['event'] for e in events] == ['stage_start', 'stage_skipped'], events
PY

run_helpers 1 '
DRY_RUN=true
TMPDIR="'"$tmp_dir"'"
SETUP_STATE_DIR="'"$tmp_dir"'/absent-live-state"
tophat_events_reset
event_emit preview stage=extras
'
[[ "$helper_rc" == 0 ]] || fail "dry run without live state failed"
[[ ! -e "$tmp_dir/absent-live-state" ]] || fail "dry run created live state directory"

for mode in false true; do
  run_helpers 1 '
DRY_RUN='"$mode"'
SETUP_STATE_DIR="'"$tmp_dir"'/must-not-create-'"$mode"'"
TOPHAT_EVENTS_FILE="'"$tmp_dir"'/explicit/'"$mode"'/events.ndjson"
tophat_events_reset
event_emit log path="$SETUP_LOG"
'
  [[ "$helper_rc" == 0 ]] || fail "explicit path failed in dry-run=$mode"
  [[ ! -e "$tmp_dir/must-not-create-$mode" ]] || fail "explicit path created state dir"
  [[ -s "$tmp_dir/explicit/$mode/events.ndjson" ]] || fail "explicit event stream absent"
done

# A bad event destination is not an installation failure.
run_helpers 1 '
TOPHAT_EVENTS_FILE="$SETUP_LOG/not-a-directory/events.ndjson"
tophat_events_reset
log_stage_start repos
error_exit "original failure"
'
[[ "$helper_rc" == 1 ]] || fail "event I/O replaced original failure"
run_helpers 1 '
TOPHAT_EVENTS_FILE="$SETUP_LOG/not-a-directory/events.ndjson"
tophat_events_reset
event_emit log path="$SETUP_LOG"
'
[[ "$helper_rc" == 0 ]] || fail "event I/O failed an otherwise successful run"

echo "events_test.sh: PASS"
