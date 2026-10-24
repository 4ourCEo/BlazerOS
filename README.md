# BlazerOS

[![CI](https://github.com/4ourCEo/BlazerOS/actions/workflows/ci.yml/badge.svg)](https://github.com/4ourCEo/BlazerOS/actions/workflows/ci.yml)

iPhone execution desk for the same deterministic scan BlazerMac already runs.

This repository starts with **BlazerCore**, the shared Swift package. The iPhone app is built on top of it after the parity tests stay green. Mac remains the command center. iPhone is the execution desk. Neither device needs the other running, and neither device syncs a live scan, a live quote feed, or an OANDA token.

## Requirements

- macOS 14 or later
- A full Xcode 26.3 or later installation, selected with `xcode-select`. Command Line Tools
  alone cannot expand the `FoundationModels` or SwiftUI macros the package uses; installing
  only the CLT produces a hard "plugin not found" compile error, not a graceful fallback.
- No third-party package dependencies

Foundation Models code is gated on `canImport` plus `BLAZER_DISABLE_FOUNDATION_MODELS`. On a
toolchain that has SwiftUI but predates the Foundation Models macro plugin, build with
`swift build -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS`; the assistant then uses its
deterministic path. The default build has no such flag and requires the full Xcode SDK.

## Build and test

```bash
./scripts/check-engine-pin.sh   # pinned engine SHA-1s
swift build
swift test                      # 237 tests, including statistical regressions and engine contracts
swift run -c release Parity     # 43 parity cases
swift run Persist               # 59 persistence checks
```

The iPhone app, widgets, Live Activity and intents are compiled by the Xcode project:

```bash
xcodebuild -project iPhone/BlazerOS.xcodeproj -scheme BlazerOS \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

`iPhone/build-iphone16.sh` builds Debug and Release and runs the iPhone 16 simulator tests with Xcode. CI runs the package checks, the simulator build, and the `BlazerTests` suite on every pull request; it selects the newest installed Xcode so the build matches the shipping SDK.

## What is in the package

- Market models, the 8-second beam, and quote freshness
- SHA-1 snapshot fingerprint (first 4 bytes, same algorithm as BlazerMac)
- JavaScriptCore bridge over the single `scan-engine.js`
- OANDA client that takes a Keychain session and never stores the token
- Completed-bar ring, ledger CSV, and snapshot JSONL
- Parity seal, desk frame, journal note, and voice command types
- Headless `FoundationCoach` intelligence and prompt synthesis (`Sources/BlazerCore/FoundationCoach/`) to explain a `ParitySeal` without scoring

SwiftUI rendering views (such as `CoachCard` and `CoachScreen` in `LightningDesk`), Dynamic Island, and Live Activities stay out of this core package. They render a `DeskFrame` or visual cards; they do not score.

BlazerMac links this package. `BlazerMac/build.sh` builds BlazerCore, then compiles the desk against it. The OANDA token still comes from the Mac Keychain adapter. The script in the app bundle is the same bytes as `Sources/BlazerCore/scan-engine.js`.

`swift run BlazerOS` opens the Lightning Desk as a macOS window. The native iPhone project uses the same `LightningDeskView`.

`EngineIdentity.pinnedSHA1` is the SHA-1 of `Sources/BlazerCore/scan-engine.js`. If that file changes, update the pin in the same commit on every app that ships the package.

## Reliability release

The iPhone app is the execution desk. OANDA data, the pinned scan engine, and history are
local to the phone; no Mac, server, CloudKit, or broker automation is required. Entry is
manual and confirmed against the venue. The default market is **FX/OANDA for Pocket Option
handoff**; the existing crypto desk remains available as an optional mode.

Reliability work in this tree covers entry gating, full-input scan identity, synthetic/reference
isolation, pending-settlement recovery, widget/Live Activity expiry, and Siri consumption. See
[the reliability release notes](reports/RELIABILITY_RELEASE.md) and
[Foundation Models evidence](reports/FOUNDATION_MODELS_EVIDENCE.md).

## On-device assistant

`DeskAssistant` uses Apple’s on-device system model (`FoundationModels`) for grounded scan
explanations, a conversational coach, a session debrief, scan comparisons, journal drafts, and
bounded research suggestions. It has read-only local tools, guided generation, semantic
validation, request serialization, timeouts, cancellation, and a clearly-labelled deterministic
fallback. It never writes engine direction, score, strike, veto, deadlines, stake, or confirmed
outcomes. No API key, remote model, or Private Cloud Compute is used.

## Scan research

The default desk uses the repaired baseline policy. The directional score is separate from symmetric conviction and neither is a calibrated win probability. Gold uses the same $0.10 normalization unit in Swift and JavaScript. Freshness, spread and entry displacement are checked before entry. Unverified expiry observations and ties require manual venue reconciliation; a failed save retains the outcome for retry.

`ForwardTest` now records local research rather than writing simulated results into the execution ledger. It captures complete M1/M5 inputs, policy and engine versions, entry observations, and durable 60/180/300-second outcomes. Quotes and these research files are never synced to CloudKit. Original engine bytes are archived as `Research/scan-engine-control.js`, with their original SHA-1 checked before every control evaluation.

```bash
# Isolated, deterministic synthetic software exercise; no Keychain or network access.
swift run ForwardTest --benchmark --all-policies --max-events 100

# Replay the synthetic archive without network access.
swift run ForwardTest --benchmark --replay

# Opt-in prospective OANDA proxy study using the device's existing Keychain session.
swift run ForwardTest --prime-only --all-policies --continuous

# Descriptive live research results, separated by source, engine and policy version.
swift run ForwardTest --stats
```

Available policies: `control`, `baseline`, `continuation`, `reversal`, and `regime`. Select one with `--policy`; challengers are research-only and are not promoted automatically. Defaults store synthetic and OANDA proxy studies in separate directories under Application Support/BlazerOS/Research. `--root PATH` selects an explicit research archive. Live mode never silently falls back to synthetic testing when credentials are unavailable.

OANDA midpoint labels are proxies, not confirmed Pocket Option settlements. Statistics mark unknown or proxy ledger labels as unverified. Actual payout expectancy matches each winning row to its recorded payout. The new verified report leaves actual expectancy unavailable when winning-payout coverage is incomplete; legacy descriptive pair summaries label their 88% fallback as assumed. Break-even is `1 / (1 + payout)`, so an 80% payout needs 55.6% and an 88% payout needs 53.2%. A positive estimate cannot authorize promotion.

Concurrent, correlated observations are collapsed into time blocks before a Wilson interval is computed. The adjustment uses an assumed intra-cluster correlation (default 1.0) and uses a size-weighted design effect for unequal connected time blocks. This is a sensitivity calculation, not measured covariance or proof of independence. Stored holdout boundaries cannot move as the archive grows; training outcomes overlapping the cutoff are purged. Retrospective frozen splits and repeated holdout inspection remain exploratory.

A calendar/news feed, trained probability calibrator and prospective promotion evidence remain future work; no higher live win rate is claimed.

See [the design report](reports/SCAN_ENGINE_DESIGN_DEBATE_2026-10-02.md) and [implementation notes](reports/SCAN_RESEARCH_IMPLEMENTATION.md).

## Verified execution intelligence

One expandable Intel card shows confirmed evidence, execution timing, quote coverage and market/expiry breakdowns. Entry and gate-rejection telemetry lives under `Research/execution-quality`, separate from the immutable execution ledger. It records scan-to-record timing; it cannot infer venue fill timing. Historical missing policy/regime/payout fields remain unknown.

Read-only, reproducible JSON export requires an explicit desk storage path and Unix cutoff:

```bash
swift run EdgeReport --root /path/to/exported/BlazerOS --as-of 1792796400
# Optional frozen chronological split; training expiries crossing it are purged.
swift run EdgeReport --root /path/to/exported/BlazerOS --as-of 1792796400 --split-at 1792191600
```

Exports include an input digest, matched payout returns, clustered evidence sensitivity, missing-data coverage and testable research findings. Export never writes the source archive. Corrupt source records abort export. `ForwardTest --edge-report --root PATH --as-of UNIX_SECONDS` invokes the same implementation.

`CoreAudit` runs macro-free deterministic regressions. `scripts/verify-core-headless.sh` creates a temporary package pointing at the actual source files; it is tooling diagnostics, not full application verification. `--checks-only` runs CoreAudit, Parity and Persist when Swift Testing macro plugins are also unavailable. Foundation Models is explicitly disabled in that harness. Production model behavior and iOS still require full Xcode.

Current release blockers, audit disposition and preserved local edits: [engineering upgrade audit](reports/ENGINEERING_UPGRADE_2026-10-23.md). No statistically defensible trading edge or TestFlight readiness is established by this upgrade.

## Known issues

- The physical-device gate in
  [the reliability notes](reports/RELIABILITY_RELEASE.md#remaining-gate-physical-device) still
  needs a person with the phone and the venue app.

Device verification for the current tree: [2026-10-22](reports/DEVICE_VERIFICATION_2026-10-22.md).

## License

No license is granted. This repository is public for review and reference only; all rights are
reserved. Do not redistribute or reuse the code without written permission.

Statistical correctness, actual stake-based P&L, externally reviewed effective N, and registered-family correction: [follow-up evidence and exact compiler diagnosis](reports/STATISTICAL_CORRECTNESS_FOLLOWUP.md). Default reviewer trust is empty; nominal counts or assumed ICC cannot qualify promotion evidence.
