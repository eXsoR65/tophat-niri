# Tophat

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/Tophat-logo_transparent-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="./assets/Tophat-logo_transparent-light.svg">
  <img src="./assets/Tophat-logo_transparent-light.svg" alt="Tophat logo" width="270" height="270">
</picture>

**An opinionated Fedora niri + dms workstation installer.**

Tophat transforms a Fedora Minimal installation into a complete scrollable-tiling
workstation using [niri](https://github.com/niri-wm/niri) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). Its staged installation flow is inspired by [Omarchy](https://github.com/basecamp/omarchy).

> [!NOTE]
> This is an evolving project. So make sure you read the instructions below.

## Prerequisites

- Fedora Minimal Install with only Core packages.
  - Can be done with Fedora Everything Network Install ISO and
    only selecting Fedora Custom Operating System in software selection.
  - Another option is copying and reviewing `kickstart/tophat-minimal.ks.example`.
- Internet connection
- Non-root user account created with `sudo` privileges

> [!WARNING]
> Only intended to be used with a Fedora Minimal install since it installs/configures
> dms greeter as the system greeter and will replace any greeter or display manager installed.

## What it installs/configures

- niri
- DankMaterialShell (dms)
  - dms Greeter through greetd
- PipeWire audio stack
- Enabled the repo's
  - RPM Fusion free/nonfree repositories
  - Official Brave Browser repository
  - COPR's for niri, dms, and Ghostty
- Applications of your choice
- Intel Wi-Fi firmware if Intel Wi-Fi hardware is detected
- Configures niri and dms systemd service
- Configures greetd PAM hooks so GNOME Keyring unlocks/starts on login
- Creates the target user's standard XDG directories (Desktop, Documents, Downloads, etc.)

## Usage

From the project root:

```bash
sudo ./install.sh
```

Configure an explicit target user when running directly as root or when the
intended account is not the sudo caller:

```bash
sudo ./install.sh --target-user alice
```

Verbose mode:

```bash
sudo ./install.sh --verbose
```

Dry run:

```bash
sudo ./install.sh --dry-run
```

Show the version (does not require root, and does not touch the system):

```bash
./install.sh --version
```

Force re-run stages even if state markers exist:

```bash
sudo ./install.sh --force
```

Allow package removals without an interactive confirmation prompt:

```bash
sudo ./install.sh --accept-package-removals
```

Run selected stages only:

```bash
sudo ./install.sh --select repos,packaging,config --verbose
```

Available stages:

```text
preflight, repos, packaging, config, services, extras, finalize
```

## Optional TUI

`./tophat` runs the same installer behind a small terminal UI: pick stages and
options, start, watch the log and the stage markers, then reboot if it worked.

```bash
./tophat              # TUI when possible, install.sh otherwise
./tophat --no-tui     # always the plain installer
```

The TUI is strictly optional. It needs [Bun](https://bun.sh) and its
dependencies installed once:

```bash
cd tui && bun install
```

Without Bun, without those dependencies, with any argument, or when stdin or
stdout is not a terminal, `./tophat` runs `install.sh` unchanged — the launcher
can never be the reason an install fails. `install.sh` remains the only engine:
the TUI passes flags and reads the log and `stage-*.done` markers, and does not
reimplement any installer logic.

## Optional applications

Application installs are controlled by:

```text
packages/applications.packages
```

A template is provided:

```text
packages/applications.packages.template
```

To install additional applications:

```bash
cp packages/applications.packages.template packages/applications.packages
$EDITOR packages/applications.packages
sudo ./install.sh --select packaging --force --verbose
```

Package list format:

- One package per line
- Blank lines are ignored
- `#` starts a comment

## Extras Flatpaks, Homebrew formulas, and Distrobox

These extras are disabled unless their local opt-in file exists. Copy only the
templates for features you want:

```bash
cp packages/flatpaks.packages.template packages/flatpaks.packages
cp packages/homebrew.packages.template packages/homebrew.packages
cp packages/distrobox.enable.template packages/distrobox.enable
```

Edit the Flatpak and Homebrew lists, then run:

```bash
sudo ./install.sh --select extras --force --verbose
```

- Flatpaks and Flathub are configured for the target user, not system-wide.
- Homebrew runs as the target user. Enabling it trusts Homebrew's official mutable installer.
- Distrobox uses Fedora's rootless Podman backend; containers are not created automatically.

Note: Removing an entry does not uninstall software automatically.

## Logs and state

Log files:

```text
/var/log/tophat/latest.log
/var/log/tophat/runs/
```

Dry runs write only to a temporary log under `${TMPDIR:-/tmp}`.

State directory:

```text
/var/lib/tophat
```

Stage completion markers are written there so stages can be skipped on later
runs unless `--force` is used.

## Repository layout

```text
install.sh                 Main installer
lib/stages.sh              Stage registry, dependency resolver, and CLI parsing
lib/helpers/               Logging, checks, package helpers
lib/preflight/             Environment, hardware, and update checks
lib/repos/                 RPM Fusion and COPR setup
lib/packaging/             Desktop, niri, DMS, and app packages
lib/config/                User-level DMS/niri configuration
lib/services/              System service setup, including DMS Greeter
lib/extras/                Optional Flatpak, Distrobox, and Homebrew setup
lib/finalize/              Cleanup and completion marker
packages/                  Package list files, including conditional Intel Wi-Fi firmware
kickstart/                 Fedora Minimal kickstart example and its safety validator
tests/                     Shell test suite (run by CI)
tophat                     Launcher: TUI when usable, install.sh otherwise
tui/                       Optional OpenTUI (React) front end, Bun project
docs/                      Improvement backlog and the TUI plan
```

## Local development

CI runs every gate on each push to `main`/`dev` and on pull requests. A second
job re-runs the Fedora-relevant subset inside a container matrix of
`fedora:latest` and `fedora:45` (bash syntax, kickstart validation, the test
suite, `--version`/`--help` smoke tests), and also checks on each release that
every package we install still resolves and that RPM Fusion plus the COPRs we
depend on publish a tree for it. Run the same checks locally before committing:

```bash
# 1. Bash syntax
find . -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
bash -n install.sh

# 2. ShellCheck (Fedora: sudo dnf install ShellCheck)
mapfile -t shell_files < <(find lib tests kickstart -type f -name '*.sh' -print | sort)
shellcheck -s bash -x -e SC1090,SC1091 install.sh "${shell_files[@]}"

# 3. Formatting (shfmt: go install mvdan.cc/sh/v3/cmd/shfmt@latest,
#    or download a release binary from https://github.com/mvdan/sh/releases)
shfmt -d -i 2 -ci install.sh lib tests kickstart

# 4. Kickstart safety validation
kickstart/validate-kickstart.sh

# 5. Test suite
for test_file in tests/*_test.sh; do "$test_file"; done
```

Tests are plain Bash scripts using PATH stubs for system commands (rpm, dnf,
runuser), so they run safely on any machine without root or a real Fedora
system. New test files matching `tests/*_test.sh` are picked up by CI
automatically.

## Releasing

Releases are cut from a tag; nothing is published by hand:

```bash
version="$(<VERSION)"
git tag -a "v${version}" -m "Tophat v${version}"   # tag must match VERSION
git push origin "v${version}"
```

The `Release` workflow then re-runs every gate, refuses to publish if
`VERSION` and the tag disagree, builds a source archive plus `SHA256SUMS`, and
creates the GitHub release using the annotated tag message as the release body.

## After install

A reboot is required for everything to work.

After the reboot, greetd will start DMS Greeter and allow you to log into the
configured niri + DMS desktop.

## At first login

Run the commands `dms setup` and `dms greeter sync` to complete the dms setup.
