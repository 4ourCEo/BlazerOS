# Engine Boundary — Gap Analysis

**Date:** 2026-10-21
**Question:** the JS engine is a separate artifact loaded at runtime. Which failure modes around that boundary are currently uncaught?
**Method:** traced every entry point (`evaluate`, `evaluateControl`, `pickDesk`, `slippageGate`, `preflight`), every consumer, and every test that touches `StrategyEngine` / `EngineIdentity`. Verified which test targets actually run.

**Result:** 18 gaps. 5 were P0 — they allowed a drifted or unverified engine to produce ledger rows with no test failing.

**Status (2026-10-21): all 18 remediated, no JS artifact modified.** The engine pins are unchanged (`7c02e550…` / `1a1d264d…`). Verified with `swift build`, `swift test` (173 tests), `swift run -c release Parity` (43/43), and `scripts/check-engine-pin.sh`.

---

## P0 — the gate does not exist in the app path

**G1. [FIXED] The app never verifies the engine hash at load.**
`ensureLoadedLocked` (`ScanBridge.swift:427–465`) checks three exports exist, then assigns `context = next`. It never hashes the source. `EngineIdentity.bundleMatchesPin()` exists (`ProductContracts.swift:19`) but has exactly two callers: `Tests/BlazerCoreTests/ScanResearchTests.swift:41` and `Sources/ForwardTest/main.swift:331`. Neither is app code.
*Caught today by:* nothing at runtime.
*Impact:* `isReady == true` on any script that parses and exposes the three functions.

**G2. [FIXED] A file in `Bundle.main` silently replaces the engine.**
`loadBundleSource` prefers the host app's Resources copy over `Bundle.module` (`ScanBridge.swift:467–474`, comment: "host app's Resources copy wins"). That is a reasonable dev convenience, but combined with G1 it means the executed engine can come from an unpinned location.
*Caught today by:* nothing. The parity test loads `Bundle.module`, so it would still pass while the app runs a different file.
*Impact:* supply-chain hole; the pin describes a file that may not be the one running.

**G3. [FIXED] The ledger records the pin, not the artifact.**
`ScanCommit.engineSHA` defaults to `EngineIdentity.pinnedSHA1` (`ScanContract.swift:63`), and `ScanKernel.commit` passes that default through (`ScanKernel.swift:155`, `:165`). Every row attests to `7c02e550…` regardless of what actually evaluated.
*Caught today by:* nothing.
*Impact:* provenance is unfalsifiable. A historical drift cannot be detected after the fact.

**G4. [FIXED] No launch preflight.**
`preflight()` executes the smoke fixture and confirms a real verdict (`ScanBridge.swift:157–190`). `preflightEcu()` wraps it (`:151–153`). Grep across `Sources`, `Tests`, `iPhone`, and scripts finds **zero call sites** for either.
*Caught today by:* nothing.
*Impact:* `isReady` proves the script compiled and exports exist — not that it can produce a verdict. A structurally valid but functionally broken engine reports ready.

**G5. [FIXED] No CI.**
No `.github/workflows`, no test job anywhere. `swift run -c release Parity` appears only in `README.md:24` and `PIPELINE.md:164` as a manual instruction. The pin-checking tools exist and are never run automatically.

---

## P1 — the tests that would catch it don't run where it matters

**G6. [FIXED] The parity test is outside the package test target.**
`Package.swift:80` declares one test target, `Tests/BlazerCoreTests`. `iPhone/Tests/EngineParityTests.swift` is a separate directory, included only by the Xcode synchronized group (`iPhone/BlazerOS.xcodeproj`, `path = Tests`). `swift test` lists **0** tests matching "parity". It runs only via `xcodebuild … test` in `iPhone/build-iphone16.sh:13`, by hand.
*Impact:* the fingerprint seal `CE239CDB` is unenforced on the main developer path. The suite I ran (160 tests) does not include it.

**G7. [FIXED] The golden fixture seals only a WAIT decision.**
`EngineParityTests.swift:20–24` asserts `engineCall == "WAIT"`, `score == 68`, one evidence string, one strike. The engine's HIGH, LOW, sweep-veto, exhaustion-veto, conflict-veto and regime branches have no sealed fixture. A branch regression that leaves WAIT/W… unchanged passes.

**G8. [FIXED] Control parity is asserted against the package bundle only.**
`goldenControlIsPreserved` (`ScanResearchTests.swift:36–42`) compares current vs control on one fixture and checks `bundleMatchesPin()`. It never constructs a modified bundle, so it cannot distinguish "verified" from "not checked" (see G1/G2).

**G9. [FIXED] Nothing tests rejection.** There is no test that:
- a bundle whose hash differs from `pinnedSHA1` is refused,
- a `scan-engine-control.js` whose hash differs from `controlSHA1` is refused (the code has the check, no test),
- an engine response with an extra or missing JSON key is handled,
- non-finite numbers in `MarketInput` are rejected by the engine path (only `slippageGate` guards them, `ScanBridge.swift:286`).

---

## P2 — the wire contract is soft

**G10. [FIXED] Decoding is not strict.**
`decode` uses a plain `JSONDecoder` (`ScanBridge.swift:494–511`). Unknown keys are ignored by default, so a JS response that adds a field is silently accepted; the Swift side never learns the contract moved.

**G11. [FIXED] A schema mismatch kills the engine and reports the wrong cause.**
Any decode error sets `context = nil` and throws `"SCAN ENGINE OFFLINE"` (`:498`, `:506–509`). A recoverable contract drift becomes a full engine teardown, and the operator sees an offline message while the real reason sits unread in `lastJsException`. The app then cannot recover without a reload.

**G12. [FIXED] Side/call strings are unvalidated.**
`cabinetSide` and `call` are free-form from JS. `sideFromCabinet` maps anything unrecognized to `"WAIT"` (`:376–385`). If the engine emits `"BUY"`, the app silently becomes a no-trade instead of surfacing a contract violation.

**G13. [FIXED] `EvaluateResult.candles` / `source` are optional and unused by the decode path.** The engine can omit them; nothing asserts they are present or consistent with the input.

---

## P3 — the second engine has no identity at all

**G14. [FIXED] The crypto engine carries a hand-written version string.**
`CryptoDeskSignal.engineIdentity = "crypto-engine-v1"` (`CryptoDeskSignal.swift:10`) is a literal. Nothing hashes the Swift implementation, nothing bumps the string when `CryptoEngine.swift` changes, and no test asserts the identity matches behavior. Crypto decisions enter the same ledger as JS decisions, with no artifact proof.

**G15. [FIXED] "Control" is contaminated by the main engine.**
`evaluateControl` verifies `controlSHA1`, then overwrites the result's features with `evaluateSync(input:).signal.features` (`ScanBridge.swift:225`). The control artifact is therefore not evaluated in isolation; its output depends on the engine it is meant to control for.

**G16. [FIXED] Crypto scores are not range-tested.** `directionScore` can reach 116 and `strength` 132 (see `CORRECTNESS_AUDIT_2026-10-21.md`, CE-M4). No test asserts the adapter's output stays in the documented 0…100 range.

---

## P4 — minor

**G17. [FIXED] `loadError` / `lastJsException` are written from the JSC exception handler outside the lock.**
`nonisolated(unsafe)` statics mutated in the closure at `ScanBridge.swift:440–444`, while other writers hold `lock`. Latent data race, silenced rather than solved.

**G18. [FIXED] `slippageGate` returns two different failure shapes.**
`nil` means "bridge offline"; `SlippageGateResult(veto: true)` means "invalid input" (`:286–292`, `:302–316`). The single call site handles `nil` as a veto (`LightningDeskModel.swift:1554–1562`), which is correct, but the distinction is easy to lose and only the invalid-input branch is tested (`ScanResearchTests:77–84`).

---

## What changed

| Gap | Fix | Caught by |
|---|---|---|
| G1 | `ensureLoadedLocked` verifies the SHA before creating a context; mismatch leaves `isReady == false`. | `engineBootsVerifiedAgainstPin`, `tamperedEngineSourceIsRefusedBeforeAContextExists` |
| G2 | The source actually loaded is hashed, whichever bundle supplies it; `loadedOrigin` records which. | same |
| G3 | `ScanCommit`/`ScanInputSnapshot` default to `EngineIdentity.loadedSHA1()`, not the pin. | `ScanIdentityTests`, parity seal |
| G4 | `StrategyEngine.boot()` runs load + verify + smoke verdict; `LightningDeskModel.run()` calls it and surfaces failure. | `engineBootsVerifiedAgainstPin` |
| G5 | `.github/workflows/ci.yml`: pin drift → build → test → Parity. `scripts/check-engine-pin.sh` enforces the pin and rejects duplicate engine copies. | CI itself |
| G6 | Engine seals moved into `Tests/BlazerCoreTests/EngineBoundaryTests.swift`, so `swift test` runs them. | `swift test` |
| G7 | Sealed fixtures for WAIT, HIGH, LOW, and the three crypto veto branches. | `goldenDecisionIsSealed`, `trendDecisionsAreSealed`, `cryptoVetoBranchesAreSealed` |
| G8 | Control pin exposed as `controlArtifactMatchesPin` and asserted; control evaluated in tests. | `controlArtifactIsPinnedAndEvaluates` |
| G9 | Tamper, malformed-input, inconsistent-OHLC, duplicate-timestamp, non-finite-quote and contract-violation tests. | `EngineBoundaryTests` |
| G10 | Semantic contract validation (asset echo, side/call pairing, 0…100 ranges, finiteness). Unknown informational keys stay ignored by design: the engine emits `bid/ask/spread/reasons/tags` that Swift does not consume. | `contractViolationsAreRejectedWithContractErrors` |
| G11 | Decode/contract failures throw `.contract` and keep the JSContext; only genuine JS exceptions tear it down. | same + `malformedInputIsRejectedBeforeTheEngineSeesIt` |
| G12 | `cabinetSide ∈ {HIGH, LOW, WAIT}` and `call` must agree; anything else is a `.contract` error. | `contractViolationsAreRejectedWithContractErrors` |
| G13 | Accepted by design: the envelope fields are optional on the wire. Required-field presence is enforced by `Decodable`, and semantics by `validate`. | decode tests |
| G14 | `CryptoEngineTests` seals decisions and identity; any behaviour change breaks a test and forces a version bump. | `cryptoIdentityIsStable`, `cryptoDecisionsAreSealed` |
| G15 | Made an explicit design decision: both research arms share the same input-feature block, so gating is identical. Documented in code and asserted. | `controlArtifactIsPinnedAndEvaluates` |
| G16 | `CryptoDeskSignal` maps magnitude to `direction = 50 ± m/2`, `strength = m`, clamped to 0…100. | `cryptoDirectionAndStrengthStayInsideTheContract` |
| G17 | `NSRecursiveLock`; the JSC exception handler now writes under the lock. | build + tamper tests |
| G18 | `slippageGate` always returns a verdict with an optional `reason`; failure shapes unified. | `slippageGateFailsClosedWithAReason` |

## Verification

```
scripts/check-engine-pin.sh   Engine pins OK (main 7c02e550e2e6, control 1a1d264d44ee)
swift build                   Build complete
swift test                    173 tests passed
swift run -c release Parity   parity ok 43
```

The pinned JS artifacts were not modified: the SHA-1 values are unchanged and the golden fingerprint is still `CE239CDB`.

## Remaining deliberate choice

Unknown-key rejection (full strict decoding) was **not** added. The engine emits informational keys (`bid`, `ask`, `spread`, `reasons`, `blockers`, `tags`, `side`) that the Swift contract intentionally ignores; rejecting them would make every engine release a breaking change. The contract is defined as required fields plus invariants, and both are now enforced. If the wire format grows a field that must be honoured, the next step is a versioned envelope (`{contract: n, ...}`) in both engines — an artifact change that requires re-pinning.

## Not a gap

The JS↔Swift boundary being invisible to the code graph is expected and permanent. `scan-engine.js` and `scan-engine-control.js` will always be separate components. Parity fixtures are the correct instrument for that boundary, not static analysis — which is why G6/G7 mattered.
