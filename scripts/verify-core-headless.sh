#!/bin/bash
# Verifies actual core/crypto sources when the host lacks Apple's UI/model macro plugins.
# This is not a substitute for full-package, model-enabled or iOS verification.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
verification_root="$(mktemp -d /tmp/blazeros-core-verification.XXXXXX)"
python3 - "$root" "$verification_root" <<'PY'
import pathlib, sys
root, dest = map(pathlib.Path, sys.argv[1:])
(dest / 'Sources').mkdir()
for target in ['BlazerCore', 'BlazerCrypto', 'Parity', 'Persist', 'CoreAudit', 'EdgeReport']:
    (dest / 'Sources' / target).symlink_to(root / 'Sources' / target, target_is_directory=True)
tests = dest / 'Tests' / 'BlazerCoreTests'
tests.mkdir(parents=True)
included, excluded = [], []
for path in sorted((root / 'Tests' / 'BlazerCoreTests').glob('*.swift')):
    if 'import LightningDesk' in path.read_text():
        excluded.append(path.name)
    else:
        (tests / path.name).symlink_to(path)
        included.append(path.name)
(dest / 'coverage.txt').write_text('Included:\n' + '\n'.join(included) + '\nExcluded (LightningDesk dependency):\n' + '\n'.join(excluded) + '\n')
(dest / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BlazerCoreVerification", platforms: [.macOS(.v14)], targets: [
.target(name: "BlazerCore", resources: [.copy("scan-engine.js"), .copy("Research/scan-engine-control.js")]),
.target(name: "BlazerCrypto", dependencies: ["BlazerCore"]),
.executableTarget(name: "CoreAudit", dependencies: ["BlazerCore", "BlazerCrypto"]),
.executableTarget(name: "EdgeReport", dependencies: ["BlazerCore"]),
.executableTarget(name: "Parity", dependencies: ["BlazerCore"]),
.executableTarget(name: "Persist", dependencies: ["BlazerCore"]),
.testTarget(name: "BlazerCoreTests", dependencies: ["BlazerCore", "BlazerCrypto"])
], swiftLanguageModes: [.v6])
''')
print('Verification root:', dest)
print('Test files included:', len(included), 'excluded:', len(excluded))
PY
if [ "${1:-}" != "--checks-only" ]; then
  swift test --package-path "$verification_root" -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS
fi
swift run --package-path "$verification_root" -c release -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS CoreAudit
swift run --package-path "$verification_root" -c release -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS Parity
swift run --package-path "$verification_root" -c release -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS Persist
