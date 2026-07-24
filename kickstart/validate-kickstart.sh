#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0

shopt -s nullglob
ks_files=("$SCRIPT_DIR"/*.ks "$SCRIPT_DIR"/*.ks.example)

if [[ ${#ks_files[@]} -eq 0 ]]; then
  echo "No Kickstart files found in $SCRIPT_DIR" >&2
  exit 1
fi

check_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -Eq -- "$pattern" "$file"; then
    echo "ERROR: $file: $message" >&2
    status=1
  fi
}

for file in "${ks_files[@]}"; do
  check_pattern "$file" 'ChangeMe123' 'contains public plaintext password placeholder ChangeMe123'
  check_pattern "$file" 'passphrase[[:space:]]+""' 'contains an empty encryption passphrase'
  check_pattern "$file" '^[[:space:]]*selinux[[:space:]]+--permissive\b' 'sets SELinux to permissive'
  check_pattern "$file" '^[[:space:]]*firewall[[:space:]]+--disabled\b' 'disables the firewall'
  check_pattern "$file" '^[[:space:]]*network\b.*--noipv6\b' 'disables IPv6'
  check_pattern "$file" '^[[:space:]]*clearpart\b.*--drives=nvme0n1\b' 'hardcodes destructive partitioning to nvme0n1'
  check_pattern "$file" '^[[:space:]]*user\b.*--plaintext\b' 'uses a plaintext account password'

  if grep -Ev '^[[:space:]]*#' "$file" | grep -Eq 'REPLACE_ME|Your_Public_SSH_Key|UserName'; then
    echo "ERROR: $file: contains unresolved placeholders in active directives" >&2
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "Kickstart validation passed"
fi

exit "$status"
