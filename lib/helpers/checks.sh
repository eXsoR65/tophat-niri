# =============================================================================
#  checks.sh — Utility functions for checking system state
# =============================================================================

cmd_missing() { ! command -v "$1" &>/dev/null; }
cmd_present() { command -v "$1" &>/dev/null; }
pkg_missing() { ! rpm -q "$1" &>/dev/null; }
pkg_present() { rpm -q "$1" &>/dev/null; }
service_enabled() { systemctl is-enabled "$1" &>/dev/null; }
is_root() { [[ $EUID -eq 0 ]]; }
file_exists() { [[ -f "$1" ]]; }
dir_exists() { [[ -d "$1" ]]; }

# Read a line-oriented configuration file into a named array. Comments and
# surrounding whitespace are removed, duplicate entries are ignored, and each
# entry remains a single argument (it is never evaluated as shell code).
read_list_file() {
  local list_file="$1"
  local array_name="$2"
  local line=""
  local line_number=0
  local -A seen=()
  local -n result="$array_name"

  result=()

  if [[ ! -f "$list_file" ]]; then
    echo "List file is not a regular file: $list_file" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    if [[ "$line" == *[[:cntrl:]]* ]]; then
      echo "Invalid control character in $list_file at line $line_number" >&2
      return 1
    fi

    if [[ -z "${seen[$line]+present}" ]]; then
      result+=("$line")
      seen["$line"]=1
    fi
  done <"$list_file"
}

check_network_connectivity() {
  local host="${1:-dl.fedoraproject.org}"

  if cmd_present ping && ping -c 1 -W 3 "$host" &>/dev/null; then
    return 0
  fi

  timeout 5 bash -c ": >/dev/tcp/${host}/443" &>/dev/null
}

# Resolve the non-root user this setup should configure.
# Priority: explicit candidate, sudo user, current non-root user, logname,
# then the first regular UID from /etc/passwd.
resolve_target_user() {
  local candidate="${1:-}"
  local home=""

  if [[ -z "$candidate" || "$candidate" == "root" ]]; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      candidate="$SUDO_USER"
    elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
      candidate="$USER"
    else
      candidate="$(logname 2>/dev/null || true)"
      [[ "$candidate" == "root" ]] && candidate=""
    fi
  fi

  if [[ -z "$candidate" || "$candidate" == "root" ]]; then
    candidate="$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" { print $1; exit }' /etc/passwd)"
  fi

  [[ -n "$candidate" ]] || return 1

  home="$(getent passwd "$candidate" | cut -d: -f6)"
  [[ -n "$home" && -d "$home" ]] || return 1

  export TARGET_USER="$candidate"
  export TARGET_USER_HOME="$home"
}
