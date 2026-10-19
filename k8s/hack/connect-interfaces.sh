#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" != 0 ]; then
  echo "Please run this script as root." >&2
  exit 1
fi

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Parse the complete list before connecting anything; a failed read cannot
# accidentally become a successful empty loop.
INTERFACES="$(bash "$SCRIPT_DIRECTORY/list-interfaces.sh" "$SCRIPT_DIRECTORY/../../meta/snap.yaml")"

# Retry snapd service-control conflicts while an install or refresh settles.
# Example: 'k8s::connect::interface network'
k8s::connect::interface() {
  local interface="$1" attempt output
  for ((attempt = 1; attempt <= 15; attempt++)); do
    if output="$(LC_ALL=C snap connect "k8s:$interface" 2>&1)"; then
      if [ -n "$output" ]; then
        printf '%s\n' "$output"
      fi
      return 0
    fi
    printf '%s\n' "$output" >&2
    case "$output" in
      *'"service-control" change in progress'*)
        if [ "$attempt" -lt 15 ]; then
          sleep 2
          continue
        fi
        ;;
    esac
    return 1
  done
}

status=0
while IFS= read -r interface; do
  if ! k8s::connect::interface "$interface"; then
    echo "Failed to connect k8s:$interface" >&2
    status=1
  fi
done <<< "$INTERFACES"
exit "$status"
