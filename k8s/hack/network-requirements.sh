#!/usr/bin/env bash

set -euo pipefail

# Read-only host checks for the strict Cilium setup. Run on the target host;
# required changes belong in its configuration, not generated snapd profiles.
status=0
for filesystem in cgroup2 bpf; do
  if [ "$filesystem" = cgroup2 ]; then
    mountpoint=/sys/fs/cgroup
  else
    mountpoint=/sys/fs/bpf
  fi
  if ! findmnt -rn --mountpoint "$mountpoint" -t "$filesystem" >/dev/null; then
    echo "Missing $filesystem mount at $mountpoint." >&2
    status=1
  fi
done

if ! forwarding="$(sysctl -n net.ipv4.ip_forward)"; then
  echo "Cannot read net.ipv4.ip_forward." >&2
  status=1
elif [ "$forwarding" != 1 ]; then
  echo "net.ipv4.ip_forward must be 1 (found $forwarding)." >&2
  status=1
fi

if ! filters="$(sysctl -a --pattern '^net\.ipv4\.conf\..*\.rp_filter$')" || [ -z "$filters" ]; then
  echo "Cannot read IPv4 reverse-path filter settings." >&2
  status=1
else
  while read -r key equals value; do
    if [ "$equals" != = ] || [ "$value" != 0 ]; then
      echo "$key must be 0 for this Cilium setup (found $value)." >&2
      status=1
    fi
  done <<< "$filters"
fi

if [ "$status" = 0 ]; then
  echo "Network prerequisites are satisfied. No host settings were changed."
fi
exit "$status"
