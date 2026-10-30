#!/bin/bash
# =============================================================================
#  tui_launcher_test.sh — ./tophat always falls back to install.sh
#
#  The launcher must never be the reason an install cannot run. Every condition
#  that is not a clean interactive TUI with Bun and dependencies present has to
#  end in `exec install.sh "$@"` with the arguments intact.
#
#  The TUI branch itself needs a real terminal and Bun, so it is exercised
#  manually; everything here is about the fallback paths, which are the ones that
#  matter when something is missing.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

fake="$tmp_dir/root"
mkdir -p "$fake/tui/src"

cat >"$fake/install.sh" <<'FAKE'
#!/bin/bash
printf 'install.sh args: %s\n' "$*"
FAKE
chmod +x "$fake/install.sh"

launcher="$ROOT/tophat"
[[ -x "$launcher" ]] || fail "launcher is not executable"

# --- --no-tui hands everything else to install.sh ----------------------------
out="$(TOPHAT_ROOT="$fake" "$launcher" --no-tui --dry-run)"
[[ "$out" == "install.sh args: --dry-run" ]] || fail "--no-tui did not strip itself: '${out}'"

out="$(TOPHAT_ROOT="$fake" "$launcher" --no-tui)"
[[ "$out" == "install.sh args: " ]] || fail "--no-tui alone should pass no arguments: '${out}'"

# --- explicit arguments mean the caller knows what they want ----------------
out="$(TOPHAT_ROOT="$fake" "$launcher" --select packaging)"
[[ "$out" == "install.sh args: --select packaging" ]] || fail "arguments were not passed through: '${out}'"

# --- no terminal (stdin/stdout are pipes here) falls back -------------------
out="$(TOPHAT_ROOT="$fake" "$launcher")"
[[ "$out" == "install.sh args: " ]] || fail "non-interactive run did not fall back: '${out}'"

# --- no Bun in PATH falls back even if a terminal existed -------------------
out="$(PATH="/usr/bin:/bin" TOPHAT_ROOT="$fake" "$launcher")"
[[ "$out" == "install.sh args: " ]] || fail "missing Bun did not fall back: '${out}'"

# --- missing TUI entry point or dependencies fall back ----------------------
out="$(TOPHAT_ROOT="$fake" "$launcher")"
[[ "$out" == "install.sh args: " ]] || fail "missing TUI sources did not fall back: '${out}'"

# --- no installer at all is an error, not a silent success ------------------
empty="$tmp_dir/empty"
mkdir -p "$empty"
if TOPHAT_ROOT="$empty" "$launcher" --no-tui >/dev/null 2>&1; then
  fail "launcher reported success with no install.sh present"
fi

echo "tui_launcher_test.sh: PASS"
