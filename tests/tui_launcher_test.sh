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

# --- diagnose explains the decision without a terminal ---------------------
fake_full="$tmp_dir/full"
mkdir -p "$fake_full/tui/src" "$fake_full/tui/node_modules/@opentui"
cp "$fake/install.sh" "$fake_full/install.sh"

# A controlled PATH: the developer's machine may well have bun installed, and a
# test that asserts "not found" must not depend on that.
clean_path="/usr/bin:/bin"
out="$(PATH="$clean_path" TOPHAT_ROOT="$fake_full" "$launcher" --diagnose)"
grep -qx 'deps=yes' <<<"$out" || fail "diagnose did not report deps: ${out}"
grep -qx 'bun=none' <<<"$out" || fail "diagnose found a Bun that is not there: ${out}"
grep -qx 'tty=no' <<<"$out" || fail "diagnose did not report a non-terminal"
grep -qx 'decision=fallback' <<<"$out" || fail "non-terminal decision should be fallback: ${out}"

# An explicit override is honoured.
fake_bun="$tmp_dir/fakebun"
printf '#!/bin/bash\nprintf "fake bun\\n"\n' >"$fake_bun"
chmod +x "$fake_bun"
out="$(PATH="$clean_path" TOPHAT_ROOT="$fake_full" TOPHAT_BUN="$fake_bun" "$launcher" --diagnose)"
grep -qx "bun=$fake_bun" <<<"$out" || fail "TOPHAT_BUN override ignored: ${out}"

# Missing dependencies are reported rather than guessed at.
fake_bare="$tmp_dir/bare"
mkdir -p "$fake_bare/tui/src"
cp "$fake/install.sh" "$fake_bare/install.sh"
out="$(PATH="$clean_path" TOPHAT_ROOT="$fake_bare" TOPHAT_BUN="$fake_bun" "$launcher" --diagnose)"
grep -qx 'deps=no' <<<"$out" || fail "missing dependencies not reported: ${out}"

# --- provisioning is opt-in: no terminal means no network, no install ------
# curl is replaced by a trap that fails the test if it is ever called.
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/curl" <<'CURL'
#!/bin/bash
echo "curl must not be called without a terminal" >&2
exit 99
CURL
chmod +x "$tmp_dir/bin/curl"
out="$(PATH="$tmp_dir/bin:$PATH" TOPHAT_ROOT="$fake_full" "$launcher" --install-runtime)"
[[ "$out" == "install.sh args: " ]] || fail "--install-runtime should still fall back without a terminal: '${out}'"

# --- the Bun dependency is stated, not implied ----------------------------
out="$("$launcher" --help)"
grep -q 'TUI needs Bun' <<<"$out" || fail "--help does not mention the Bun dependency"
grep -q 'bun upgrade' <<<"$out" || fail "--help does not say how to keep Bun patched"

# A fallback caused by a missing runtime must name the runtime.
err="$(TOPHAT_ROOT="$fake_full" PATH="/usr/bin:/bin" "$launcher" 2>&1 >/dev/null)"
grep -q 'needs Bun' <<<"$err" || fail "missing-runtime fallback did not mention Bun: ${err}"
grep -q -- '--install-runtime' <<<"$err" || fail "missing-runtime fallback did not point at --install-runtime"

# ...and a missing terminal says so instead of blaming Bun.
out="$(TOPHAT_ROOT="$fake_full" TOPHAT_BUN="$fake_bun" "$launcher")"
[[ "$out" == "install.sh args: " ]] || fail "fallback with a runtime present failed: '${out}'"

echo "tui_launcher_test.sh: PASS"
