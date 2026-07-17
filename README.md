# Tophat

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/Tophat-logo_transperant-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="./assets/Tophat-logo_transperant-light.svg">
  <img src="./assets/Tophat-logo_transperant-light.svg" alt="Tophat logo" width="270" height="270">
</picture>

**An opinionated Fedora niri + dms workstation installer.**

Tophat transforms a Fedora Minimal installation into a complete scrollable-tiling
workstation using [niri](https://github.com/niri-wm/niri) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). Its staged installation flow is inspired by [Omarchy](https://github.com/basecamp/omarchy).

> [!NOTE]
> This is a evolutioning project. So make sure you read the instructions below.

## Prerequisites

- Fedora Minimal Install with only Core packages.
  - Can be done with Fedora Everything Network Install ISO and
    only selecting Fedora Custom Operating System in software selection.
  - Another option is using the example kickstart file in the root of the repo.
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

## Usage

From the project root:

```bash
sudo ./install.sh
```

Verbose mode:

```bash
sudo ./install.sh --verbose
```

Dry run:

```bash
sudo ./install.sh --dry-run
```

Force re-run stages even if state markers exist:

```bash
sudo ./install.sh --force
```

Run selected stages only:

```bash
sudo ./install.sh --select repos,packaging,config --verbose
```

Available stages:

```text
preflight, repos, packaging, config, services, extras, finalize
```

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

Log file:

```text
/var/log/tophat.log
```

State directory:

```text
/var/lib/tophat
```

Stage completion markers are written there so stages can be skipped on later
runs unless `--force` is used.

## Repository layout

```text
install.sh                 Main installer
lib/helpers/               Logging, checks, package helpers
lib/preflight/             Environment, hardware, and update checks
lib/repos/                 RPM Fusion and COPR setup
lib/packaging/             Desktop, niri, DMS, and app packages
lib/config/                User-level DMS/niri configuration
lib/services/              System service setup, including DMS Greeter
lib/extras/                Optional Flatpak, Distrobox, and Homebrew setup
lib/finalize/              Cleanup and completion marker
packages/                  Package list files, including conditional Intel Wi-Fi firmware
```

## After install

A reboot is required for everything to work.

After the reboot, greetd will start DMS Greeter and allow you to log into the
configured niri + DMS desktop.

## At first login

Run the commands `dms setup` and `dms greeter sync` to complete the dms setup.
