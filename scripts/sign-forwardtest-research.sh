#!/usr/bin/env bash
set -euo pipefail

# Optional owner-controlled signing step for the explicit Keychain path. Do not
# substitute ad-hoc signing: a stable designated requirement is the point of
# this script. The identity is supplied by the local signing configuration and
# is never written to the repository.
: "${BLAZER_RESEARCH_SIGNING_IDENTITY:?Set BLAZER_RESEARCH_SIGNING_IDENTITY to an installed Developer ID or local signing identity}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_root}/.build/out/Products/Release/ForwardTest"

(cd "$repo_root" && swift build -c release --target ForwardTest >/dev/null)
codesign --force --timestamp --identifier com.blazer.os.forwardtest.research \
  --sign "$BLAZER_RESEARCH_SIGNING_IDENTITY" "$binary"
codesign --verify --strict --verbose=2 "$binary"
echo "Signed ForwardTest research helper: $binary"
