#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$(PATH=/poison/path LANG=xx_XX LC_ALL=poison DEVELOPER_DIR=/poison/xcode \
  HOME=/poison/home TMPDIR=/poison/tmp SWIFT_EXEC=/poison/swift \
  SWIFTFLAGS=-DPOISONED BLAZER_MAC_SIGNING_SHA1=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
  "$SCRIPT_DIR/package-mac-app-staged.sh" --test-env-probe)"

for forbidden in '/poison' 'SWIFT_EXEC=' 'SWIFTFLAGS=' 'BLAZER_MAC_SIGNING_SHA1='; do
  if [[ "$OUTPUT" == *"$forbidden"* ]]; then
    printf 'Caller environment leaked into controlled SwiftPM environment: %s\n' "$forbidden" >&2
    exit 1
  fi
done
[[ "$OUTPUT" == *'PATH=/usr/bin:/bin:/usr/sbin:/sbin'* ]]
[[ "$OUTPUT" == *'LANG=C'* && "$OUTPUT" == *'LC_ALL=C'* ]]
[[ "$OUTPUT" == *"DEVELOPER_DIR=$(/usr/bin/xcode-select -p)"* ]]
[[ "$OUTPUT" == *'HOME=/private/tmp/blazeros-env-probe.'* ]]
[[ "$OUTPUT" == *'TMPDIR=/private/tmp/blazeros-env-probe.'* ]]
echo 'PASS: poisoned caller overrides are absent from the isolated SwiftPM environment.'

RENAME_ROOT="$(/usr/bin/mktemp -d /private/tmp/blazeros-rename-env-probe.XXXXXX)"
trap '/bin/rm -rf "$RENAME_ROOT"' EXIT
/bin/mkdir "$RENAME_ROOT/source.app"
printf 'rename fixture\n' > "$RENAME_ROOT/source.app/payload"
HOME="$RENAME_ROOT/home" TMPDIR="$RENAME_ROOT/tmp" /bin/mkdir -m 700 "$RENAME_ROOT/home" "$RENAME_ROOT/tmp"
DEVELOPER_DIR="$(/usr/bin/xcode-select -p)"
BLAZER_RENAME_SOURCE="$RENAME_ROOT/source.app" BLAZER_RENAME_DEST="$RENAME_ROOT/destination.app" \
  /usr/bin/env -i HOME="$RENAME_ROOT/home" TMPDIR="$RENAME_ROOT/tmp" \
    PATH='/usr/bin:/bin:/usr/sbin:/sbin' LANG=C LC_ALL=C DEVELOPER_DIR="$DEVELOPER_DIR" \
    BLAZER_RENAME_SOURCE="$RENAME_ROOT/source.app" BLAZER_RENAME_DEST="$RENAME_ROOT/destination.app" \
    /usr/bin/swift -module-cache-path "$RENAME_ROOT/module-cache" -e '
      import Darwin
      import Foundation
      let environment = ProcessInfo.processInfo.environment
      guard let source = environment["BLAZER_RENAME_SOURCE"],
            let destination = environment["BLAZER_RENAME_DEST"] else { exit(2) }
      let result = source.withCString { sourcePath in
        destination.withCString { destinationPath in
          renameatx_np(AT_FDCWD, sourcePath, AT_FDCWD, destinationPath, UInt32(RENAME_EXCL))
        }
      }
      if result != 0 { exit(1) }
    '
[[ ! -e "$RENAME_ROOT/source.app" && -f "$RENAME_ROOT/destination.app/payload" ]]
echo 'PASS: the isolated atomic-rename helper receives only its explicit source/destination paths.'
