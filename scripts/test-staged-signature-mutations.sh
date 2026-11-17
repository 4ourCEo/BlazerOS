#!/bin/bash
set -Eeuo pipefail

# Structural test only: ad-hoc signatures are intentionally not accepted as
# owner identity evidence. Verify that macOS seals both the executable and the
# embedded strategy manifest in the complete app bundle.
command -v codesign >/dev/null || { echo 'codesign is required (macOS only).' >&2; exit 2; }
TEST_ROOT="$(/usr/bin/mktemp -d /private/tmp/blazeros-signature-mutation.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

make_bundle() {
  local app="$1"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/StrategyPromotions"
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.blazer.BlazerOS</string>
<key>CFBundleExecutable</key><string>BlazerOS</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  printf 'fixture executable\n' > "$app/Contents/MacOS/BlazerOS"
  printf '{"schemaVersion":1,"fixture":true}\n' > "$app/Contents/Resources/StrategyPromotions/StrategyBuildInputManifest.json"
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
}

EXEC_APP="$TEST_ROOT/ExecutableMutation.app"
make_bundle "$EXEC_APP"
printf 'tampered executable\n' > "$EXEC_APP/Contents/MacOS/BlazerOS"
if codesign --verify --deep --strict "$EXEC_APP" >/dev/null 2>&1; then
  echo 'Executable mutation unexpectedly passed signature verification.' >&2
  exit 1
fi

MANIFEST_APP="$TEST_ROOT/ManifestMutation.app"
make_bundle "$MANIFEST_APP"
printf '{"schemaVersion":1,"tampered":true}\n' > "$MANIFEST_APP/Contents/Resources/StrategyPromotions/StrategyBuildInputManifest.json"
if codesign --verify --deep --strict "$MANIFEST_APP" >/dev/null 2>&1; then
  echo 'Manifest mutation unexpectedly passed signature verification.' >&2
  exit 1
fi

echo 'PASS: code signature rejected executable and embedded manifest mutation (ad-hoc structural check only).'
