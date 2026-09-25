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

Foundation Models, Dynamic Island, Live Activities, and SwiftUI stay out of this package. They render a `DeskFrame` or explain a `ParitySeal`. They do not score.

BlazerMac links this package. `BlazerMac/build.sh` builds BlazerCore, then compiles the desk against it. The OANDA token still comes from the Mac Keychain adapter. The script in the app bundle is the same bytes as `Sources/BlazerCore/scan-engine.js`.

## Check

```bash
swift run -c release Parity
swift run BlazerOS
```

`swift run BlazerOS` opens the Lightning Desk: pair, feed, completed candles, score, reason, strike, countdown, and Scan on one phone-sized screen. This Mac has no iOS SDK, so that view runs here as a macOS window. An iPhone project can host the same `LightningDeskView` once Xcode is installed.

`EngineIdentity.pinnedSHA1` is the SHA-1 of `Sources/BlazerCore/scan-engine.js`. If that file changes, update the pin in the same commit on every app that ships the package.
