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
rm -rf "$archive_path"

echo "==> Archiving Release Candidate for TestFlight..."
xcodebuild archive \
  -project "$project" \
  -scheme BlazerOS \
  -destination "generic/platform=iOS" \
  -configuration Release \
  -archivePath "$archive_path"

echo "==> Archive created successfully at: $archive_path"
ls -ld "$archive_path"

if [[ -f "$root/iPhone/exportOptions.plist" ]]; then
  echo "==> Exporting IPA using exportOptions.plist..."
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$root/iPhone/exportOptions.plist" \
    -exportPath "$archive_dir/Export"
  echo "==> Export complete. IPA available at: $archive_dir/Export"
fi
