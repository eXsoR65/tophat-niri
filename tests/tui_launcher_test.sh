#!/bin/bash
# Exercise the real launcher with isolated environments and stdlib PTYs. No Bun
# installation or network access is permitted: curl and Bun are always fakes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT/tophat" <<'PY'
import errno
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time

launcher = Path(sys.argv[1])
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1


with tempfile.TemporaryDirectory(prefix="tophat-launcher-") as temporary:
    base = Path(temporary)

    def fixture(name, deps=True, bun=None, curl="success", entry=True):
        root = base / name
        home = root / "home"
        bin_dir = root / "bin"
        (root / "tui/src").mkdir(parents=True)
        home.mkdir()
        bin_dir.mkdir()
        # No developer HOME, Bun override, PATH, or shell initialization leaks in.
        env = {"HOME": str(home), "PATH": str(bin_dir), "TOPHAT_BUN": "",
               "TOPHAT_ROOT": str(root), "TRACE": str(root / "trace"),
               "TERM": "xterm-256color", "CURL_MODE": curl}
        for command in ("bash", "dirname", "readlink", "mkdir", "cp", "cat"):
            (bin_dir / command).symlink_to(shutil.which(command))

        def script(path, content):
            path.write_text("#!/bin/bash\nset -eu\n" + content)
            path.chmod(0o755)

        script(root / "install.sh", '''printf 'fallback' >> "$TRACE"
printf 'install.sh args: <%s>\\n' "$@"
''')
        if entry:
            (root / "tui/src/index.tsx").touch()
        if deps:
            (root / "tui/node_modules/@opentui").mkdir(parents=True)
        fake_bun = root / "fake-bun"
        script(fake_bun, '''printf 'bun:%s:%s\\n' "$PWD" "$*" >> "$TRACE"
if [[ "${1:-}" == install ]]; then
  [[ "${DEPS_FAIL:-}" != yes ]] || exit 17
  mkdir -p node_modules/@opentui
else
  printf 'TUI started\\n'
fi
''')
        env["FAKE_BUN"] = str(fake_bun)
        script(bin_dir / "curl", '''printf 'curl:%s\\n' "$*" >> "$TRACE"
case "$CURL_MODE" in
  fail) exit 22 ;;
  partial) printf 'exit 0\\n'; exit 22 ;;
  installer-fail) printf 'exit 23\\n' ;;
  absent-runtime) printf 'true\\n' ;;
  *) printf 'mkdir -p "$HOME/.bun/bin"\\ncp "$FAKE_BUN" "$HOME/.bun/bin/bun"\\n' ;;
esac
''')
        if bun == "override":
            env["TOPHAT_BUN"] = str(fake_bun)
        elif bun == "path":
            (bin_dir / "bun").symlink_to(fake_bun)
        elif bun == "home":
            (home / ".bun/bin").mkdir(parents=True)
            (home / ".bun/bin/bun").symlink_to(fake_bun)
        return root, env

    def run(fix, args=(), tty=False, answer=None, input_tty=True, output_tty=True):
        root, env = fix
        command = [str(launcher), *args]
        if not tty:
            result = subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=10)
            code, output = result.returncode, result.stdout.decode()
        else:
            master, slave = pty.openpty()
            process = subprocess.Popen(command, env=env,
                                       stdin=slave if input_tty else subprocess.DEVNULL,
                                       stdout=slave if output_tty else subprocess.PIPE,
                                       stderr=slave)
            os.close(slave)
            data = bytearray()
            deadline = time.monotonic() + 10
            sent = False
            try:
                while True:
                    if time.monotonic() > deadline:
                        raise AssertionError(f"PTY timeout: {data!r}")
                    readable, _, _ = select.select([master], [], [], 0.1)
                    if readable:
                        try:
                            chunk = os.read(master, 65536)
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                            break
                        if not chunk:
                            break
                        data.extend(chunk)
                    if answer is not None and not sent and b"[y/N]" in data:
                        os.write(master, answer.encode() + b"\n")
                        sent = True
                code = process.wait(timeout=2)
                if not output_tty:
                    data.extend(process.stdout.read())
                output = data.decode()
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                os.close(master)
        trace = (root / "trace").read_text() if (root / "trace").exists() else ""
        return code, output, trace

    def fallback(result, label, network=False):
        code, output, trace = result
        check(code == 0 and "install.sh args:" in output, f"{label}: {result}")
        check("curl:" not in trace or network, f"{label}: unexpected network: {trace}")
        check("bun:" not in trace, f"{label}: unexpected Bun: {trace}")

    for mode in ("override", "path", "home"):
        result = run(fixture("startup-" + mode, bun=mode), tty=True)
        check(result[0] == 0 and "TUI started" in result[1], f"PTY startup {mode}: {result}")
        check("fallback" not in result[2] and "curl:" not in result[2], str(result))

    result = run(fixture("diagnose", bun="override"), ("--diagnose",), tty=True)
    check("tty=yes" in result[1] and "decision=tui" in result[1], str(result))
    check(result[2] == "", "diagnose must not execute Bun or curl")
    result = run(fixture("diagnose-bare", deps=False), ("--diagnose", "--install-runtime"), tty=True)
    check("deps=no" in result[1] and "decision=provision" in result[1], str(result))
    check(result[2] == "", "diagnose must not provision")

    for name, args, deps, bun in (
        ("no-tty", (), True, "override"),
        ("noninteractive-optin", ("--install-runtime",), False, None),
        ("no-tui", ("--no-tui", "--install-runtime"), True, None),
        ("args", ("--select", "packaging", "two words"), True, "override"),
        ("no-deps", (), False, "override"),
        ("bare", (), False, None),
    ):
        result = run(fixture(name, deps=deps, bun=bun), args, tty=name != "no-tty" and name != "noninteractive-optin")
        fallback(result, name)
        if name == "args":
            check("<two words>" in result[1], "argument boundaries were lost")
    fallback(run(fixture("no-entry", bun="override", entry=False), tty=True), "no entry")
    fallback(run(fixture("input-only", bun="override"), tty=True, output_tty=False), "piped stdout")
    fallback(run(fixture("output-only", bun="override"), tty=True, input_tty=False), "piped stdin")
    fallback(run(fixture("declined"), tty=True, answer="n"), "declined consent")
    fallback(run(fixture("empty-consent"), tty=True, answer=""), "empty consent")

    for name, deps, bun, args, answer in (
        ("fresh-optin", False, None, ("--install-runtime",), None),
        ("deps-only", False, "override", ("--install-runtime",), None),
        ("prompt-yes", True, None, (), "yes"),
    ):
        root, env = fixture(name, deps=deps, bun=bun)
        result = run((root, env), args, tty=True, answer=answer)
        check(result[0] == 0 and "TUI started" in result[1], f"{name}: {result}")
        check("fallback" not in result[2], str(result))
        if bun is None:
            check("curl:-fsSL https://bun.sh/install\n" in result[2], str(result))
            check((root / "home/.bun/bin/bun").is_file(), "official default location not discovered")
        else:
            check("curl:" not in result[2], "existing Bun should not be reinstalled")
        if not deps:
            check(f"bun:{root}/tui:install --frozen-lockfile\n" in result[2], str(result))

    for mode in ("fail", "partial", "installer-fail", "absent-runtime"):
        result = run(fixture("explicit-" + mode, deps=False, curl=mode), ("--install-runtime",), tty=True)
        check(result[0] != 0 and "fallback" not in result[2] and "bun:" not in result[2], str(result))
        result = run(fixture("prompt-" + mode, curl=mode), tty=True, answer="y")
        fallback(result, "prompt failure " + mode, network=True)

    fix = fixture("missing-curl", deps=False)
    (fix[0] / "bin/curl").unlink()
    result = run(fix, ("--install-runtime",), tty=True)
    check(result[0] != 0 and result[2] == "" and "curl is required" in result[1], str(result))
    fix = fixture("deps-failure", deps=False, bun="override")
    fix[1]["DEPS_FAIL"] = "yes"
    result = run(fix, ("--install-runtime",), tty=True)
    check(result[0] != 0 and "fallback" not in result[2] and "TUI started" not in result[1], str(result))
    check("curl:" not in result[2], "dependency failure must not reinstall Bun")

    fix = fixture("symlink", bun="override")
    copy = fix[0] / "tophat"
    shutil.copy2(launcher, copy)
    link = fix[0] / "bin/tophat"
    link.symlink_to(copy)
    env = fix[1].copy()
    del env["TOPHAT_ROOT"]
    result = subprocess.run([str(link), "--diagnose"], env=env, capture_output=True, text=True, timeout=10)
    check(f"root={fix[0]}\n" in result.stdout, "symlink resolved wrong checkout")
    check("tty=no" in result.stdout and "decision=fallback" in result.stdout, result.stdout)
    result = run(fixture("help"), ("--help",))
    check("TUI needs Bun" in result[1] and "bun upgrade" in result[1], str(result))
    fix = fixture("missing-installer")
    (fix[0] / "install.sh").unlink()
    check(run(fix, ("--no-tui",))[0] != 0, "missing installer silently succeeded")

print(f"tui_launcher_test.sh: PASS ({checks} assertions; isolated HOME/PATH/TOPHAT_BUN, real PTYs)")
PY
