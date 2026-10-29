#!/bin/bash
# =============================================================================
#  exit_handler_scope_test.sh — cleanup must survive main() returning
#
#  install.sh loads the helpers from inside main(), so anything they declare with
#  `declare` becomes a local of main(). The EXIT trap runs *after* main() has
#  returned, so a registry scoped that way is gone by then: under `set -u` the
#  trap dies with "unbound variable" and no handler runs at all - which leaves
#  the run lock behind after a successful install.
#
#  This runs a child script shaped exactly like install.sh: helpers sourced inside
#  main(), a handler registered, main() returns, process exits.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

child="$tmp_dir/child.sh"
cat >"$child" <<'CHILD'
#!/bin/bash
set -euo pipefail

ROOT="$1"
STATE="$2"
LOG="$3"
MARK="$4"

export SETUP_LOG="$LOG"
export SETUP_STATE_DIR="$STATE"
export DRY_RUN=false VERBOSE=false FORCE=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''

_second_handler() { : >"$MARK"; }

main() {
  # Sourced here on purpose: this is what install.sh does, and it scopes
  # `declare` inside main().
  # shellcheck source=lib/helpers/run_logged.sh
  source "$ROOT/lib/helpers/run_logged.sh"
  mkdir -p "$SETUP_STATE_DIR"
  : >"$SETUP_LOG"

  acquire_run_lock
  register_exit_handler _second_handler
}

main
CHILD
chmod +x "$child"

state="$tmp_dir/state"
mark="$tmp_dir/second-handler-ran"
out="$("$child" "$ROOT" "$state" "$tmp_dir/log" "$mark" 2>&1)" || {
  echo "child exited non-zero:" >&2
  echo "$out" >&2
  fail "installer-shaped run failed"
}

[[ -z "$out" ]] || fail "unexpected output (an unbound-variable error shows up here): ${out}"
[[ ! -e "$state/.lock.d" ]] || fail "lock left behind: the EXIT handler never ran"
[[ -f "$mark" ]] || fail "the registered handler never ran"

echo "exit_handler_scope_test.sh: PASS"
