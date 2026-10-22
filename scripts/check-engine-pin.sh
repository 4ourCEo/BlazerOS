#!/usr/bin/env bash
# Fails when the engine artifacts on disk do not match the pins the app enforces.
# This is the invariant that keeps scan-engine.js a pinned artifact rather than "whatever shipped".
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
contracts="$root/Sources/BlazerCore/ProductContracts.swift"
bridge="$root/Sources/BlazerCore/ScanBridge.swift"
main_js="$root/Sources/BlazerCore/scan-engine.js"
control_js="$root/Sources/BlazerCore/Research/scan-engine-control.js"

main_pin=$(grep -oE 'pinnedSHA1 = "[0-9a-f]{40}"' "$contracts" | grep -oE '[0-9a-f]{40}')
control_pin=$(grep -oE 'controlSHA1 = "[0-9a-f]{40}"' "$bridge" | grep -oE '[0-9a-f]{40}')

if [ -z "$main_pin" ] || [ -z "$control_pin" ]; then
  echo "FAIL: could not read engine pins from source"
  exit 1
fi

main_sha=$(shasum -a 1 "$main_js" | cut -d' ' -f1)
control_sha=$(shasum -a 1 "$control_js" | cut -d' ' -f1)

status=0
if [ "$main_sha" != "$main_pin" ]; then
  echo "FAIL: scan-engine.js changed without re-pinning"
  echo "      on disk: $main_sha"
  echo "      pinned : $main_pin"
  echo "      If the change is intentional, update EngineIdentity.pinnedSHA1 and seal the"
  echo "      new behaviour in Tests/BlazerCoreTests/EngineBoundaryTests.swift."
  status=1
fi

if [ "$control_sha" != "$control_pin" ]; then
  echo "FAIL: scan-engine-control.js changed without re-pinning"
  echo "      on disk: $control_sha"
  echo "      pinned : $control_pin"
  echo "      The control artifact is immutable by design; prefer reverting it."
  status=1
fi

# Exactly one source copy of each engine. A second copy is how a dev build silently diverges.
extra_main=$(find "$root" -name 'scan-engine.js' \
  -not -path '*/.build/*' -not -path '*/dist/*' -not -path '*/iPhone/build/*' \
  -not -path '*/graphify-out/*' -not -path "$main_js" | wc -l | tr -d ' ')
extra_control=$(find "$root" -name 'scan-engine-control.js' \
  -not -path '*/.build/*' -not -path '*/dist/*' -not -path '*/iPhone/build/*' \
  -not -path '*/graphify-out/*' -not -path "$control_js" | wc -l | tr -d ' ')

if [ "$extra_main" != "0" ] || [ "$extra_control" != "0" ]; then
  echo "FAIL: duplicate engine artifacts found (main=$extra_main, control=$extra_control)"
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "Engine pins OK (main ${main_sha:0:12}, control ${control_sha:0:12})"
fi

exit "$status"
