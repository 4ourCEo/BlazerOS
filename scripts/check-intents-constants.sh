#!/bin/bash
# The Intents framework cannot link BlazerCore (doing so makes Xcode embed a dynamic copy of
# the engine next to the app's static one, duplicating every class in the process), so it
# carries its own copy of the two constants it needs. Keep them in sync.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
phone="$root/Sources/BlazerCore/PhoneTarget.swift"
intent="$root/iPhone/Intents/ScanIntent.swift"

fail=0
for entry in "appGroup=group.com.blazer.os" "pendingScanKey=blazer.pendingScan"; do
  key="${entry%%=*}"
  value="${entry#*=}"
  for file in "$phone" "$intent"; do
    if ! grep -q "$key = \"$value\"" "$file"; then
      echo "$(basename "$file"): $key is not \"$value\"" >&2
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "Intents constants match PhoneTarget"
