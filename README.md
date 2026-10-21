# BlazerOS

iPhone execution desk for the same deterministic scan BlazerMac already runs.

This repository starts with **BlazerCore**, the shared Swift package. The iPhone app is built on top of it after the parity tests stay green. Mac remains the command center. iPhone is the execution desk. Neither device needs the other running, and neither device syncs a live scan, a live quote feed, or an OANDA token.

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

## Check

```bash
swift run -c release Parity
swift test
swift run BlazerOS
```

`swift run BlazerOS` opens the Lightning Desk as a macOS window. The native iPhone project uses the same `LightningDeskView`; `iPhone/build-iphone16.sh` builds Debug and Release and runs the iPhone 16 simulator tests with Xcode.

`EngineIdentity.pinnedSHA1` is the SHA-1 of `Sources/BlazerCore/scan-engine.js`. If that file changes, update the pin in the same commit on every app that ships the package.

## Reliability release

The iPhone app is the execution desk. OANDA/Binance data, the pinned scan engine, and history
are local to the phone; no Mac, server, CloudKit, or broker automation is required. Entry is
manual and confirmed against the venue.

Reliability work in this tree covers entry gating, full-input scan identity, synthetic/reference
isolation, pending-settlement recovery, widget/Live Activity expiry, and Siri consumption. See
[the reliability release notes](reports/RELIABILITY_RELEASE.md) for the verification results and
the remaining physical-device checklist.

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

OANDA midpoint labels are proxies, not confirmed Pocket Option settlements. Statistics mark unknown or proxy ledger labels as unverified. Payout is assumed at 88% until actual venue terms are supplied. A calendar/news feed, trained probability calibrator and prospective promotion evidence remain future work; no higher live win rate is claimed.

See [the design report](reports/SCAN_ENGINE_DESIGN_DEBATE_2026-10-02.md) and [implementation notes](reports/SCAN_RESEARCH_IMPLEMENTATION.md).
