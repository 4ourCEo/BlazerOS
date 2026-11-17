#!/bin/bash
set -Eeuo pipefail

# Build a uniquely named, signed staging bundle without replacing or launching
# any installed application. A valid signing identity must be selected first.

APP_BUNDLE_ID="com.blazer.BlazerOS"
SIGNING_SHA1="${BLAZER_MAC_SIGNING_SHA1:-}"
unset BLAZER_MAC_SIGNING_SHA1
CONTROLLED_PATH='/usr/bin:/bin:/usr/sbin:/sbin'
PATH="$CONTROLLED_PATH"
export PATH
SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OWNER_PIN_SOURCE="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)/Sources/BlazerOSMac/OwnerSignerPin.swift"
OWNER_PIN_SHA1="$(/usr/bin/awk -F'"' '/static let certificateSHA1 =/ { print toupper($2); exit }' "$OWNER_PIN_SOURCE")"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

controlled_env() {
  local controlled_home="$1" controlled_tmp="$2" developer_dir="$3"
  shift 3
  /usr/bin/env -i HOME="$controlled_home" TMPDIR="$controlled_tmp" \
    PATH="$CONTROLLED_PATH" LANG=C LC_ALL=C DEVELOPER_DIR="$developer_dir" \
    MACOSX_DEPLOYMENT_TARGET=14.0 "$@"
}

validate_swiftpm_metadata() {
  local metadata_root="$1/.swiftpm" child workspace child_name
  [[ ! -L "$metadata_root" ]] || fail 'SwiftPM metadata root must not be a symlink.'
  [[ ! -e "$metadata_root" ]] && return 0
  [[ -d "$metadata_root" ]] || fail 'SwiftPM metadata root must be a directory.'
  [[ -z "$(/usr/bin/find "$metadata_root" -type l -print -quit)" ]] ||
    fail 'SwiftPM metadata symlinks are unsupported.'
  [[ -z "$(/usr/bin/find "$metadata_root" -mindepth 2 -name .DS_Store -print -quit)" ]] ||
    fail 'Nested SwiftPM metadata .DS_Store files are unsupported.'
  shopt -s nullglob dotglob
  for child in "$metadata_root"/*; do
    child_name="${child##*/}"
    case "$child_name" in
      .DS_Store)
        [[ -f "$child" && ! -L "$child" ]] || fail 'SwiftPM metadata .DS_Store must be a regular file.'
        ;;
      configuration)
        [[ -d "$child" && ! -L "$child" ]] || fail 'SwiftPM configuration root must be a real directory.'
        [[ -z "$(/usr/bin/find "$child" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
          fail 'SwiftPM configuration must be empty for staged packaging.'
        ;;
      xcode)
        [[ -d "$child" && ! -L "$child" ]] || fail 'SwiftPM Xcode metadata must be a real directory.'
        for workspace in "$child"/*; do
          if [[ "${workspace##*/}" == 'xcuserdata' ]]; then
            [[ -d "$workspace" && ! -L "$workspace" ]] || fail 'Invalid SwiftPM Xcode user data.'
            continue
          fi
          [[ "${workspace##*/}" == 'package.xcworkspace' && -d "$workspace" && ! -L "$workspace" ]] ||
            fail 'Unknown SwiftPM Xcode metadata entry.'
          for child in "$workspace"/*; do
            case "${child##*/}" in
              contents.xcworkspacedata) [[ -f "$child" && ! -L "$child" ]] || fail 'Invalid SwiftPM workspace data file.' ;;
              xcuserdata) [[ -d "$child" && ! -L "$child" ]] || fail 'Invalid SwiftPM workspace user data.' ;;
              *) fail 'Unknown SwiftPM workspace metadata entry.' ;;
            esac
          done
        done
        ;;
      *) fail 'Unknown repository-local .swiftpm entry.' ;;
    esac
  done
}

if [[ "${1:-}" == '--test-env-probe' ]]; then
  PROBE_ROOT="$(/usr/bin/mktemp -d /private/tmp/blazeros-env-probe.XXXXXX)"
  trap '/bin/rm -rf "$PROBE_ROOT"' EXIT
  /bin/mkdir -m 700 "$PROBE_ROOT/home" "$PROBE_ROOT/tmp"
  PROBE_DEVELOPER_DIR="$(/usr/bin/env -i PATH='/usr/bin:/bin:/usr/sbin:/sbin' LANG=C LC_ALL=C /usr/bin/xcode-select -p)"
  controlled_env "$PROBE_ROOT/home" "$PROBE_ROOT/tmp" "$PROBE_DEVELOPER_DIR" /usr/bin/env
  printf 'resolved-swift=%s\n' "$(controlled_env "$PROBE_ROOT/home" "$PROBE_ROOT/tmp" \
    "$PROBE_DEVELOPER_DIR" /usr/bin/which swift)"
  printf 'swift-version=%s\n' "$(controlled_env "$PROBE_ROOT/home" "$PROBE_ROOT/tmp" \
    "$PROBE_DEVELOPER_DIR" /usr/bin/swift --version | /usr/bin/head -n 1)"
  exit 0
fi

if [[ "${1:-}" == '--test-metadata-preflight' ]]; then
  REPO_ROOT="${2:?test fixture root is required}"
  validate_swiftpm_metadata "$REPO_ROOT"
  exit 0
fi

validate_swiftpm_metadata "$REPO_ROOT"

if [[ ! "$OWNER_PIN_SHA1" =~ ^[[:xdigit:]]{40}$ ]]; then
  fail 'Compile-time OwnerSignerPin.certificateSHA1 is empty or malformed; set the explicit owner trust anchor before packaging.'
fi
if [[ ! "$SIGNING_SHA1" =~ ^[[:xdigit:]]{40}$ ]]; then
  fail 'Set BLAZER_MAC_SIGNING_SHA1 to the exact 40-character SHA-1 fingerprint of one valid code-signing identity.'
fi
SIGNING_SHA1="$(printf '%s' "$SIGNING_SHA1" | /usr/bin/tr '[:lower:]' '[:upper:]')"
[[ "$SIGNING_SHA1" == "$OWNER_PIN_SHA1" ]] ||
  fail 'Selected signing identity does not match the separately compiled owner signer pin.'

IDENTITY_OUTPUT="$(/usr/bin/security find-identity -v -p codesigning 2>&1)" ||
  fail 'Could not query valid code-signing identities with security find-identity.'
MATCH_COUNT="$(printf '%s\n' "$IDENTITY_OUTPUT" | /usr/bin/awk -v wanted="$SIGNING_SHA1" '
  /^[[:space:]]*[0-9]+\)/ {
    fingerprint = toupper($2)
    if (length(fingerprint) == 40 && fingerprint ~ /^[[:xdigit:]]+$/ && fingerprint == wanted) count++
  }
  END { print count + 0 }
')"
[[ "$MATCH_COUNT" == '1' ]] ||
  fail 'The supplied fingerprint must match exactly one valid identity reported by security.'

cd "$REPO_ROOT"
SELECTED_DEVELOPER_DIR="$(/usr/bin/env -i PATH="$CONTROLLED_PATH" LANG=C LC_ALL=C /usr/bin/xcode-select -p)"
[[ "$SELECTED_DEVELOPER_DIR" == /* && -d "$SELECTED_DEVELOPER_DIR" ]] ||
  fail 'Could not resolve the selected Xcode developer directory.'

DIST_DIR="$REPO_ROOT/dist"
[[ ! -L "$DIST_DIR" ]] || fail "Refusing symlinked distribution directory: $DIST_DIR"
if [[ -e "$DIST_DIR" ]]; then
  [[ -d "$DIST_DIR" ]] || fail "Distribution path exists and is not a directory: $DIST_DIR"
else
  mkdir "$DIST_DIR"
fi

STAMP="$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
SCRATCH_PATH="$REPO_ROOT/.build/staged-release-${STAMP}-$$"
RESOURCE_TMP="$SCRATCH_PATH/strategy-resources"
CONTROLLED_HOME="$SCRATCH_PATH/home"
CONTROLLED_TMP="$SCRATCH_PATH/tmp"
mkdir -p "$RESOURCE_TMP" "$CONTROLLED_HOME" "$CONTROLLED_TMP"
chmod 700 "$CONTROLLED_HOME" "$CONTROLLED_TMP"
swiftpm() {
  controlled_env "$CONTROLLED_HOME" "$CONTROLLED_TMP" "$SELECTED_DEVELOPER_DIR" /usr/bin/swift "$@"
}
STAGE_PATH="$DIST_DIR/.BlazerOS-Mac-staging-${STAMP}-$$.app"
FINAL_PATH="$DIST_DIR/BlazerOS-Mac-staged-${STAMP}-$$.app"
[[ ! -e "$STAGE_PATH" && ! -L "$STAGE_PATH" && ! -e "$FINAL_PATH" && ! -L "$FINAL_PATH" ]] ||
  fail 'Unique staging or final path unexpectedly exists.'

printf 'Generating signed build-input and promotion resources...\n'
swiftpm run -c release --scratch-path "$SCRATCH_PATH/swiftpm" --triple "$(/usr/bin/uname -m)-apple-macosx14.0" StrategyManifestTool generate \
  "$REPO_ROOT" "$RESOURCE_TMP" "$APP_BUNDLE_ID" "$SIGNING_SHA1"

printf 'Building BlazerOSMac in release configuration...\n'
swiftpm build -c release --scratch-path "$SCRATCH_PATH/swiftpm" --triple "$(/usr/bin/uname -m)-apple-macosx14.0" --target BlazerOSMac

PRODUCT_DIR="$(swiftpm build -c release --scratch-path "$SCRATCH_PATH/swiftpm" --triple "$(/usr/bin/uname -m)-apple-macosx14.0" --target BlazerOSMac --show-bin-path)"
EXECUTABLE="$PRODUCT_DIR/BlazerOS"
[[ -x "$EXECUTABLE" ]] || fail "Expected release executable not found: $EXECUTABLE"

printf 'Revalidating all declared source/build inputs...\n'
swiftpm run -c release --scratch-path "$SCRATCH_PATH/swiftpm" --triple "$(/usr/bin/uname -m)-apple-macosx14.0" StrategyManifestTool verify \
  "$REPO_ROOT" "$RESOURCE_TMP/StrategyBuildInputManifest.json" "$APP_BUNDLE_ID" "$SIGNING_SHA1"

STAGE_CREATED=0
report_failure() {
  local status=$?
  if (( status != 0 && STAGE_CREATED == 1 )) && [[ -e "$STAGE_PATH" || -L "$STAGE_PATH" ]]; then
    printf 'Staged bundle retained for inspection: %s\n' "$STAGE_PATH" >&2
  fi
  exit "$status"
}
trap report_failure EXIT

CONTENTS="$STAGE_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
mkdir "$STAGE_PATH"
STAGE_CREATED=1
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 0755 "$EXECUTABLE" "$MACOS_DIR/BlazerOS"
mkdir -p "$RESOURCES_DIR/StrategyPromotions"
cp -R "$RESOURCE_TMP"/. "$RESOURCES_DIR/StrategyPromotions/"
shopt -s nullglob
for RESOURCE_BUNDLE in "$PRODUCT_DIR"/*.bundle; do
  [[ -d "$RESOURCE_BUNDLE" ]] && cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
done
shopt -u nullglob

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>BlazerOS</string>
  <key>CFBundleIdentifier</key><string>com.blazer.BlazerOS</string>
  <key>CFBundleName</key><string>BlazerOS</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Add :BLAZER_OWNER_SIGNER_SHA1 string $SIGNING_SHA1" "$CONTENTS/Info.plist"

/usr/bin/plutil -lint "$CONTENTS/Info.plist"
PLIST_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")"
[[ "$PLIST_IDENTIFIER" == "$APP_BUNDLE_ID" ]] ||
  fail "Plist bundle identifier mismatch (expected $APP_BUNDLE_ID)."

BUILD_UUIDS="$(/usr/bin/dwarfdump --uuid "$EXECUTABLE" | /usr/bin/awk '{print $2}' | /usr/bin/sort)"
STAGED_UUIDS="$(/usr/bin/dwarfdump --uuid "$MACOS_DIR/BlazerOS" | /usr/bin/awk '{print $2}' | /usr/bin/sort)"
[[ -n "$BUILD_UUIDS" && "$BUILD_UUIDS" == "$STAGED_UUIDS" ]] ||
  fail 'Staged executable UUIDs do not match the release build.'

printf 'Revalidating source snapshot immediately before signing...\n'
swiftpm run -c release --scratch-path "$SCRATCH_PATH/swiftpm" --triple "$(/usr/bin/uname -m)-apple-macosx14.0" StrategyManifestTool verify \
  "$REPO_ROOT" "$RESOURCE_TMP/StrategyBuildInputManifest.json" "$APP_BUNDLE_ID" "$SIGNING_SHA1"

/usr/bin/env -i PATH="$CONTROLLED_PATH" LANG=C LC_ALL=C BLAZER_MAC_SIGNING_SHA1="$SIGNING_SHA1" \
  /usr/bin/codesign --force --deep --sign "$SIGNING_SHA1" "$STAGE_PATH"
/usr/bin/codesign --verify --deep --strict "$STAGE_PATH"
SIGNED_IDENTIFIER="$(/usr/bin/codesign -dv --verbose=4 "$STAGE_PATH" 2>&1 | /usr/bin/awk -F= '$1 == "Identifier" && !found { print $2; found = 1 }')"
[[ "$SIGNED_IDENTIFIER" == "$APP_BUNDLE_ID" ]] ||
  fail "Signed bundle identifier mismatch (expected $APP_BUNDLE_ID)."
SIGNED_SHA1="$(cd "$SCRATCH_PATH" && /usr/bin/codesign -d --extract-certificates "$STAGE_PATH" >/dev/null 2>&1 && /usr/bin/shasum -a 1 "$SCRATCH_PATH/codesign0" | /usr/bin/awk '{print toupper($1)}')"
[[ "$SIGNED_SHA1" == "$SIGNING_SHA1" ]] || fail 'Signed bundle leaf certificate does not match the pinned owner identity.'
rm -f "$SCRATCH_PATH/codesign0" "$SCRATCH_PATH/codesign1" "$SCRATCH_PATH/codesign2"

# renameatx_np(RENAME_EXCL) treats FINAL_PATH as the destination path itself,
# fails atomically if any file, directory, or symlink appeared there, and never
# applies mv's existing-directory nesting behavior.
BLAZER_RENAME_SOURCE="$STAGE_PATH" BLAZER_RENAME_DEST="$FINAL_PATH" \
  /usr/bin/env -i HOME="$CONTROLLED_HOME" TMPDIR="$CONTROLLED_TMP" PATH="$CONTROLLED_PATH" LANG=C LC_ALL=C DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" \
    MACOSX_DEPLOYMENT_TARGET=14.0 BLAZER_RENAME_SOURCE="$STAGE_PATH" BLAZER_RENAME_DEST="$FINAL_PATH" \
    /usr/bin/swift -module-cache-path "$REPO_ROOT/.build/rename-helper-module-cache-$$" -e '
    import Darwin
    import Foundation
    let environment = ProcessInfo.processInfo.environment
    guard let source = environment["BLAZER_RENAME_SOURCE"],
          let destination = environment["BLAZER_RENAME_DEST"] else {
        fputs("Missing atomic rename paths.\n", stderr)
        exit(2)
    }
    let result = source.withCString { sourcePath in
        destination.withCString { destinationPath in
            renameatx_np(AT_FDCWD, sourcePath, AT_FDCWD, destinationPath, UInt32(RENAME_EXCL))
        }
    }
    if result != 0 {
        fputs("Atomic no-replace rename failed (errno=\(errno)).\n", stderr)
        exit(1)
    }
  '
[[ ! -e "$STAGE_PATH" && ! -L "$STAGE_PATH" && -d "$FINAL_PATH" && ! -L "$FINAL_PATH" ]] ||
  fail 'Could not publish staged app without replacing an existing artifact.'
FINAL_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FINAL_PATH/Contents/Info.plist" 2>/dev/null || true)"
FINAL_UUIDS="$(/usr/bin/dwarfdump --uuid "$FINAL_PATH/Contents/MacOS/BlazerOS" 2>/dev/null | /usr/bin/awk '{print $2}' | /usr/bin/sort)"
[[ "$FINAL_IDENTIFIER" == "$APP_BUNDLE_ID" && -n "$FINAL_UUIDS" && "$FINAL_UUIDS" == "$BUILD_UUIDS" ]] ||
  fail 'Published path does not contain the verified BlazerOS bundle; no existing artifact was accepted as output.'
trap - EXIT
printf 'Staged Mac application: %s\n' "$FINAL_PATH"
