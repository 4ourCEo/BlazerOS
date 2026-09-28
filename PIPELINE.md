# BlazerOS Pipeline v1.0

Do not begin the iPhone target until Persistence, Ledger, Snapshot, and Journal survive relaunch with passing tests.

## Product mission

BlazerOS is the native iPhone execution companion for Blazer. It shares the deterministic trading engine with BlazerMac but delivers an Apple-first mobile experience.

Mac: Research + diagnostics

iPhone: Live execution companion

The strategy must remain identical.

## Architecture (locked)

No duplicate strategy logic inside UI views.

The engine does not move. Persistence, coach, and sync sit around it.

These stay off CloudKit and out of every document this layer writes:

- OANDA token
- Live quote
- Active scan

## Milestone roadmap

| Milestone | Name | Scope |
| --- | --- | --- |
| M0 | Foundation | Repo governance + project skeleton |
| M1 | Live Desk | OANDA, chart, scan, countdown |
| M1.2 | Persistence | Ledger, snapshot, journal, relaunch |
| M1.3 | Outcome | One HIT or MISS after EXPIRED |
| M1.4 | Foundation Coach | Explain a sealed scan only |
| M1.5 | CloudKit | Documents, never execution |
| M2 | Ecosystem | Real iPhone target, widgets, Live Activity, intents |
| M2.1 | Native iPhone Experience | 5-screen floating desk, modular cards, voice session, canvas fit |
| M3 | Apple Intelligence surfaces | Voice, Siri, journal speech, Dynamic Island |
| M4 | TestFlight RC | Polish, soak tests, release |

All milestones (M0 through M4) are complete, sealed, and verified across both macOS and iOS (iPhone 16). The codebase is ready for TestFlight distribution.

## M0 — Foundation

Brand: Blazer logo asset, app icon, launch screen, obsidian design system, typography tokens, color tokens, motion tokens.

Project: SwiftUI app lifecycle, iOS 26 target, asset catalog, unit test target, snapshot test target, folder structure, build configurations.

Security: OANDA token, account id, and environment selector live in the Keychain. Never read `.env`. Never embed credentials.

## M1 — Live Desk

Screen 1 contains only: Pair, live state, mini chart, score, why, scan, rail.

| State | Visible |
| --- | --- |
| CONNECTING | Hero |
| LIVE | Hero |
| SCANNING | Animated CTA |
| LOCKED | Hash + strike |
| TAP HIGH | Hero |
| TAP LOW | Hero |
| WAIT | Hero |
| VETO | Hero replacement |
| EXPIRED | Hero |

No additional dashboard.

Live quotes come directly from OANDA. Stream quotes. Request completed M1 candles. Freeze the snapshot on SCAN. Hash completed bars. The live quote only affects VETO. Never mutate the snapshot. Exactly like Mac.

Never fake LIVE. If the feed is not ready, show CONNECTING.

Foundation Models own explanation only. Allowed later: explain score, voice coaching, journal summaries, pattern tagging, screenshot OCR. Forbidden: HIGH vs LOW, score calculation, slippage, wick evaluation.

## M1.2 — Persistence

Package path:

```
Sources/BlazerCore/Persistence/
├── FileLocations.swift
├── LedgerStore.swift
├── SnapshotStore.swift
├── JournalStore.swift
└── PersistenceCoordinator.swift
```

Ledger CSV is canonical and append-only:

```
timestamp,pair,hash,score,side,veto,drift,outcome
```

One outcome per fingerprint. A second write is refused, including after relaunch. Writes are atomic. Rows are never overwritten.

Every committed scan writes one JSONL snapshot. Replay reads that file, not live memory.

```json
{"hash":"F9813E3C","pair":"EUR/USD","bars":[],"strike":1.17342,"score":76,"side":"HIGH"}
```

Journal entries survive quitting the app. `JournalEntry`, `VoiceNote`, `Tag`, `Emotion`, and `Lesson` are stored now. Speech fills them later.

## M1.3 — Outcome

After EXPIRED, the hero offers HIT or MISS. The choice writes the ledger once, keeps the snapshot, updates the journal, updates the tally, and dismisses. A second choice does not write again.

## M1.4 — Foundation Coach

`Sources/BlazerCore/FoundationCoach/` holds `PromptBuilder` and `CoachService`. `CoachCard` renders the result on the replay. The brief is pair, engine score, evidence, and hash. The card returns a summary, a confidence word (`Sealed` or `Limited`), and bullets. It does not return a side or a new score. A live quote is not an input. If the on-device model is unavailable, or its reply leaves that shape, the sealed card is used. The same brief always produces the same sealed card.

## M1.5 — CloudKit

Complete. `Sources/BlazerCore/CloudSync/` provides `CloudSyncCoordinator`, `CloudRecordMapper`, and `CloudSyncTransport`. Syncs ledger rows, snapshots, and journal entries via Apple CloudKit private database.

- Canonical `CloudSecurityGate` strictly forbids syncing OANDA tokens, live quotes, or active scans.
- Offline-first: local desk execution is never blocked or stalled when unauthenticated or offline.
- Merge idempotency: snapshots remain immutable; ledger outcomes are append-only and cannot overwrite existing results.
- Verified in `PersistCheck` with 12 dedicated CloudKit security, round-trip, idempotency, and offline tests.

## M2 — iPhone 16 & Ecosystem

Complete. The shipping device is iPhone 16. Targets in `iPhone/BlazerOS.xcodeproj`:

| Target | Job | Status |
| --- | --- | --- |
| BlazerOS | The desk. iPhone only. | Complete |
| BlazerWidgets | Last committed scan from shared App Group journal. Home & Lock screens. | Complete |
| BlazerLiveActivity | Dynamic Island and Lock Screen countdown for armed beam. | Complete |
| BlazerActivity | One activity type shared by the app and the island. | Complete |
| BlazerIntents | “Scan with Blazer” opens the existing six-market walk. | Complete |
| BlazerTests | Locks the iPhone 16 canvas and verifies layout bounds. | Complete |

Build and test verification:

```bash
iPhone/build-iphone16.sh
```

Verifies Debug build, Release build, and executes all `BlazerTests` (`DeskLayoutTests`, `EngineParityTests`, `PhoneTargetTests`) on the iPhone 16 simulator.

## Definition of done

M0 through M4 are completely sealed and verified:

- `swift run -c release Parity`: 43/43 PASS
- `swift run -c release Persist`: 41/41 PASS (includes 12 CloudKit tests + 2 voice note tests)
- `swift run -c release Soak`: 10/10 PASS (100 engine scans, 100 atomic settlements, 50 duplicate drops, 30 corrupt recoveries, 25 voice notes)
- `iPhone/build-iphone16.sh`: Debug SUCCEEDED, Release SUCCEEDED, 6/6 iPhone 16 tests PASS
- `iPhone/archive-testflight.sh`: TestFlight Release Candidate archive verified

## Status

Shipping iPhone 16 Release Candidate ready for TestFlight and App Store submission.
