#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building BlazerOS (release)..."
swift build -c release --target BlazerOSMac

BUILD_DIR="$REPO_ROOT/.build/out/Products/Release"
APP_NAME="BlazerOS"
APP_DIR="$REPO_ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# Copy SPM resource bundles if they exist
for bundle in "$BUILD_DIR"/*.bundle; do
  if [ -d "$bundle" ]; then
    echo "    Copying $(basename "$bundle")..."
    cp -R "$bundle" "$RESOURCES/"
  fi
done

# Create App Icon from highest-res icon if available
ICON_SRC="$REPO_ROOT/iPhone/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
if [ ! -f "$ICON_SRC" ]; then
  ICON_SRC="$REPO_ROOT/Sources/LightningDesk/BlazerMark.png"
fi

if [ -f "$ICON_SRC" ] && command -v sips &>/dev/null && command -v iconutil &>/dev/null; then
  echo "==> Generating AppIcon.icns from $ICON_SRC..."
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

# Write Info.plist
cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.blazer.BlazerOS.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

DEFAULT_MAC_SIGNING_IDENTITY="BlazerOS Local Development"
MAC_SIGNING_IDENTITY="${BLAZER_MAC_SIGNING_IDENTITY:-$DEFAULT_MAC_SIGNING_IDENTITY}"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$MAC_SIGNING_IDENTITY"; then
  echo "==> Signing $APP_DIR with stable identity: $MAC_SIGNING_IDENTITY..."
  codesign --force --deep --sign "$MAC_SIGNING_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
elif [[ -n "${BLAZER_MAC_SIGNING_IDENTITY:-}" ]]; then
  echo "No valid code-signing identity matches BLAZER_MAC_SIGNING_IDENTITY: $BLAZER_MAC_SIGNING_IDENTITY" >&2
  exit 1
else
  echo "==> Ad-hoc code signing $APP_DIR (Keychain may ask again after rebuilds)..."
  codesign --force --deep --sign - "$APP_DIR"
  echo "    Install the 'BlazerOS Local Development' identity or set BLAZER_MAC_SIGNING_IDENTITY to a stable identity to stop repeated Keychain trust prompts."
fi

echo "==> BlazerOS.app successfully created at $APP_DIR!"
