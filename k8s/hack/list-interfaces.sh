#!/usr/bin/env bash

set -euo pipefail

# Read declared plugs from installed Snapcraft metadata, not general YAML.
# Block mappings and block/inline lists are supported; malformed lists fail.
# Include global definitions: unscoped plugs apply to every app and hook.
if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
  echo "Usage: $0 <readable meta/snap.yaml>" >&2
  exit 1
fi

awk '
function fail(message) {
  print "Cannot read snap interfaces: " message > "/dev/stderr"
  failed = 1
  exit 1
}
function trim(value) {
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+$/, "", value)
  return value
}
function add(value, quote) {
  value = trim(value)
  quote = substr(value, 1, 1)
  if ((quote == "\"" || quote == sprintf("%c", 39)) && substr(value, length(value)) == quote)
    value = substr(value, 2, length(value) - 2)
  if (value !~ /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/)
    fail("invalid plug name " value)
  if (!(value in seen)) {
    seen[value] = 1
    plugs[++count] = value
  }
}
{
  line = $0
  if (line ~ /\t/) fail("tabs are unsupported")
  sub(/[[:space:]]+#.*$/, "", line)
  sub(/[[:space:]]+$/, "", line)
  if (line ~ /^ *($|#)/) next
  if (in_list) {
    if (line ~ /^(    |      )- /) {
      sub(/^ +- /, "", line)
      add(line)
      list_count++
      next
    }
    if (!list_count || line ~ /^(      |    -)/) fail("empty or unsupported plug list")
    in_list = 0
  }
  if (line !~ /^ /) {
    section = (line == "apps:" || line == "hooks:" || line == "plugs:") ? line : ""
    entry = 0
    if (line ~ /^(apps|hooks|plugs):/ && !section && line != "plugs: {}")
      fail("apps/hooks/plugs must use block mappings")
  } else if (section == "plugs:" && line ~ /^  [^ ]/) {
    if (line !~ /:/) fail("unsupported top-level plug mapping")
    sub(/:.*/, "", line)
    add(line)
  } else if ((section == "apps:" || section == "hooks:") && line ~ /^  [^ ]/) {
    if (line !~ /^  [a-z][a-z0-9-]*:$/) fail("unsupported app/hook mapping")
    entry = 1
  } else if ((section == "apps:" || section == "hooks:") && line ~ /^    plugs:/) {
    if (!entry) fail("plugs have no app or hook")
    value = trim(substr(line, 11))
    if (value == "") {
      in_list = 1
      list_count = 0
    } else if (value ~ /^\[.*\]$/) {
      value = trim(substr(value, 2, length(value) - 2))
      if (value != "") {
        length_items = split(value, items, ",")
        for (i = 1; i <= length_items; i++) add(items[i])
      }
    } else fail("unsupported plug list")
  }
}
END {
  if (failed) exit 1
  if ((in_list && !list_count) || !count) fail("no usable plug declarations")
  for (i = 1; i <= count; i++) print plugs[i]
}
' "$1"
