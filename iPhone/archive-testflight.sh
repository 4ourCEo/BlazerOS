#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is required. Command Line Tools cannot compile the iPhone target."
  exit 1
fi
project="$root/iPhone/BlazerOS.xcodeproj"
archive_dir="$root/iPhone/build/TestFlight"
mkdir -p "$archive_dir"
archive_path="$archive_dir/BlazerOS.xcarchive"
app_group="group.com.blazer.os"
rm -rf "$archive_path"

echo "==> Archiving Release Candidate for TestFlight..."
# Automatic signing must be allowed to create or refresh profiles. The widget and
# Live Activity need the App Groups capability, and stale profiles without it are
# exactly how an archive ends up with blank extension entitlements. Never work
# around a missing capability by emptying an entitlements file: the widget would
# install but could not read the shared journal.
xcodebuild archive \
  -project "$project" \
  -scheme BlazerOS \
  -destination "generic/platform=iOS" \
  -configuration Release \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates

echo "==> Archive created successfully at: $archive_path"
ls -ld "$archive_path"

fail() {
  echo "error: $1" >&2
  exit 1
}

signature_problem() {
  echo "error: $1" >&2
  echo "       Do not blank the extension entitlements. Refresh the App Group" >&2
  echo "       capability for that bundle ID in Xcode > Signing & Capabilities," >&2
  echo "       then rerun this script with an Apple ID that can manage App Groups." >&2
  exit 1
}

verify_app_group() {
  local binary="$1"
  local label="$2"
  local entitlements
  entitlements="$(codesign -d --entitlements :- "$binary" 2>/dev/null)" \
    || signature_problem "$label is not signed correctly."
  if [[ "$entitlements" != *"<string>$app_group</string>"* ]]; then
    signature_problem "$label is missing $app_group in its signed entitlements."
  fi
  if [[ ! -f "$binary/embedded.mobileprovision" ]]; then
    signature_problem "$label has no embedded provisioning profile."
  fi
  local profile
  profile="$(security cms -D -i "$binary/embedded.mobileprovision" 2>/dev/null)" \
    || signature_problem "$label has an unreadable provisioning profile."
  if [[ "$profile" != *"<string>$app_group</string>"* ]]; then
    signature_problem "$label provisioning profile does not include $app_group."
  fi
  echo "    $label: signed, profile includes $app_group"
}

echo "==> Verifying signed entitlements and embedded profiles..."
app="$archive_path/Products/Applications/BlazerOS.app"
[[ -d "$app" ]] || fail "Archive does not contain BlazerOS.app."
verify_app_group "$app" "BlazerOS.app"
verify_app_group "$app/PlugIns/BlazerWidgets.appex" "BlazerWidgets.appex"
verify_app_group "$app/PlugIns/BlazerLiveActivity.appex" "BlazerLiveActivity.appex"

if [[ -f "$root/iPhone/exportOptions.plist" ]]; then
  echo "==> Exporting IPA using exportOptions.plist..."
  rm -rf "$archive_dir/Export"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$root/iPhone/exportOptions.plist" \
    -exportPath "$archive_dir/Export" \
    -allowProvisioningUpdates
  ipa="$(/bin/ls "$archive_dir"/Export/*.ipa 2>/dev/null | head -1)"
  [[ -n "$ipa" ]] || fail "Export did not produce an IPA."
  unpack="$(mktemp -d "${TMPDIR:-/tmp}/blazer-ipa.XXXXXX")"
  trap 'rm -rf "$unpack"' EXIT
  ditto -x -k "$ipa" "$unpack"
  echo "==> Verifying exported IPA..."
  verify_app_group "$unpack/Payload/BlazerOS.app" "IPA BlazerOS.app"
  verify_app_group "$unpack/Payload/BlazerOS.app/PlugIns/BlazerWidgets.appex" "IPA BlazerWidgets.appex"
  verify_app_group "$unpack/Payload/BlazerOS.app/PlugIns/BlazerLiveActivity.appex" "IPA BlazerLiveActivity.appex"
  echo "==> Export complete. IPA available at: $archive_dir/Export"
fi
