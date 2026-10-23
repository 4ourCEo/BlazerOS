# Upgrade verification — 2026-10-23

Host: arm64 macOS; active developer directory `/Library/Developer/CommandLineTools`; Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27 SDK. `/Applications` contains no Xcode installation. Model-disabled results below do not validate Apple's model-enabled branch.

| Command / gate | Actual result |
| --- | --- |
| `scripts/check-engine-pin.sh` | PASS; main `7c02e550e2e6…`, control `1a1d264d44ee…` |
| `scripts/check-intents-constants.sh` | PASS |
| `swift run -c release -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS CoreAudit` | **52/52 PASS**, exit 0; numeric/domain/conversion, concurrency, payout matching, provenance, stable digest, chronology, corruption preservation and telemetry isolation checks |
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

Evidence logs are in `/tmp/blazeros-core-audit-executed.log`, `/tmp/blazeros-parity-final.log`, `/tmp/blazeros-persist-final.log`, `/tmp/blazeros-swift-test.log`, `/tmp/blazeros-headless-test.log`, `/tmp/blazeros-core-verification-final.log` and `/tmp/blazeros-ios-verification.log` on this host.

CI now includes CoreAudit, Persist, Soak and iOS Release compilation in addition to the existing engine pin, full build/test, parity, Debug and simulator gates. Adding gates is not evidence that they passed. A draft PR must remain a draft until the required results and physical-device checks are available.

## Remote Xcode evidence

[CI run #29](https://github.com/4ourCEo/BlazerOS/actions/runs/40014210620), initial published head `f966f8be49a45ac66ded8902dbd260eab212f902`, used Xcode 26.3.0 / Swift 6.2.4. The full build and **221/221 Swift tests** passed, along with Parity 43/43, CoreAudit 49/49, Persist 59/59 and Soak 10/10. The iOS Debug and Release build steps also passed; simulator tests were still running at this report checkpoint. These remote results resolve the local compiler limitations for that exact head, not for later changes.

Final review preserved caller-supplied finite risk configurations and recorded net payouts above 100%; only invalid numerics and arithmetic overflow fail closed. Local CoreAudit now passes **52/52**, including the added configuration/payout cases. The draft PR's latest checks must validate this follow-up. Refer to [PR #10](https://github.com/4ourCEo/BlazerOS/pull/10) for final head and CI results. No physical-device/model-generation or venue-data evidence is inferred from CI.

The report exporter was also verified for byte-identical repeat output, matching the committed empty-archive artifact, no source writes, and corrupt-input refusal with source preservation.
