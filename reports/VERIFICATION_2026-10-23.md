# Upgrade verification — 2026-10-23

Host: arm64 macOS; active developer directory `/Library/Developer/CommandLineTools`; Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27 SDK. `/Applications` contains no Xcode installation. Model-disabled results below do not validate Apple's model-enabled branch.

| Command / gate | Actual result |
| --- | --- |
| `scripts/check-engine-pin.sh` | PASS; main `7c02e550e2e6…`, control `1a1d264d44ee…` |
| `scripts/check-intents-constants.sh` | PASS |
| `swift run -c release -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS CoreAudit` | **49/49 PASS**, exit 0; numeric/domain/conversion, concurrency, payout matching, provenance, stable digest, chronology, corruption preservation and telemetry isolation checks |
| Same flags, `Parity` | **43/43 PASS**, exit 0; golden fingerprint and parity contract preserved |
| Same flags, `Persist` | **59/59 PASS**, exit 0; persistence/recovery, measurement provenance and offline/CloudKit security checks |
| `swift build --target BlazerCore -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS` | PASS on the earlier core checkpoint; final release CoreAudit also compiles final core and crypto dependencies |
| `swift test` | BLOCKED before tests: FoundationModelsMacros plugin absent |
| `swift test -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS` | BLOCKED before tests: SwiftUIMacros.StateMacro plugin absent |
| `scripts/verify-core-headless.sh` | BLOCKED before tests: TestingMacros.TestDeclarationMacro plugin absent. This temporary package points at actual source files and excludes LightningDesk-dependent test files; it is not a full-suite result. |
| `swiftc -frontend -parse` on modified model/UI/runner and added regression sources | PASS syntax only; not type checking, macro expansion, linkage or runtime verification |
| `iPhone/build-iphone16.sh` | Exit 1: `Xcode is required. Command Line Tools cannot compile the iPhone 16 target.` No Debug/Release/simulator result claimed. |
| Full model-enabled app build, full suite, crypto Swift Testing regressions, Soak | Remain blocked by the missing Xcode macro plugins; no pass claimed |
| Foundation Models bounded-context/device runtime | No runtime result on this host; existing tests preserved, new deterministic context tested by CoreAudit |
| Duplicate-BlazerCore device/symbol check and physical venue checks | Not executed; requires full Xcode/device and operator |
| `git diff --check` | PASS |

One intermediate Persist run failed its old exact `UNVERIFIED PRIOR` wording assertion after the required `INSUFFICIENT EVIDENCE` label was added. Its assertion now requires both insufficient-evidence and unverified-provenance labels; the rerun passed 59/59. No persistence implementation was weakened to satisfy it.

Evidence logs are in `/tmp/blazeros-core-audit-final.log`, `/tmp/blazeros-parity-final.log`, `/tmp/blazeros-persist-final.log`, `/tmp/blazeros-swift-test.log`, `/tmp/blazeros-headless-test.log`, `/tmp/blazeros-core-verification-final.log` and `/tmp/blazeros-ios-verification.log` on this host.

CI now includes CoreAudit, Persist, Soak and iOS Release compilation in addition to the existing engine pin, full build/test, parity, Debug and simulator gates. Adding gates is not evidence that they passed. A draft PR must remain a draft until the required results and physical-device checks are available.
