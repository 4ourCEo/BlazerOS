# V3 user-reported position close

**Task:** `V3-USER-REPORTED-POSITION-CLOSE`
**Parent:** `reports/V3_AUTONOMOUS_CONTINUATION_LOOP.md`
**Status:** Implemented and integrated; independent review, full Swift suite, and full iPhone simulator plan pass. The close-correction UI fixture failure was fixed and verified.

## Debate findings

- The existing `V3PositionRecord` models a user-reported position opening only. `.userReported` requires `.manualTradeReport`, forbids broker identity and exit price, and has no close timestamp. `.brokerClosed` requires broker IDs and exit price, so it cannot truthfully represent a user assertion.
- `recordUserReportedPosition` binds an exact persisted plan and serializes entry corrections per root. Corrections form a validated, linear append-only chain. There is no close event, no user-reported closed state, and no rule that serializes close against entry corrections.
- Generic `record(V3PositionRecord)` does not bind plan/position identity or validate lifecycle transitions. It is unsuitable for a manual close writer.
- The active Trade plan card already has an explicit “Record position I opened” form. Review shows the current report and corrections with unverified/manual provenance. There is no position close flow.
- `V3StructuralOutcome` is now a separate simulated sampled stop/target path. A quote trigger cannot establish that a user closed a position. The legacy `activeTrade` / binary expiry and venue settlement path is also unrelated.
- No broker account/position synchronization or broker-close producer was found. Broker-confirmed close requires a separate future contract and evidence source.

## Proposed bounded scope

1. Add a distinct immutable `V3UserReportedPositionClose` evidence type. Do not modify `.brokerClosed`, overload `.userReported`, or reuse simulated structural outcomes.
2. Bind a close to the exact `positionID`, `planID`, and current leaf `V3PositionRecord` produced by the user-reported entry chain. Store a stable close identity, predecessor link for corrections, optional user-reported exit price and effective close time, required `.manualTradeCloseReport` provenance, and separate `recordedAt`.
3. Accept writes only in `Research/live-oanda`, under the same normalized per-root lock as entry/correction writers. Reload and validate the exact persisted plan, position report archive, latest entry-report leaf, and close correction chain. One close root per logical position; exact retries are idempotent; divergent concurrent closes and correction forks fail closed.
4. If both opening time and close time are supplied, require close time not earlier than `userReportedEnteredAt` on the immutable entry revision referenced by that close chain. Do not compare against a later entry correction. If either time is absent, chronology is unknown and no time is inferred. Because the action asserts that the user already closed the position, reject `closedAt` more than one second after `recordedAt` on both write and archive read; the one-second tolerance accommodates local clock precision. Missing optional exit details remain explicitly unknown; do not synthesize a close price/time from quotes, stops, targets, candles, or sampled structural outcomes.
5. Define entry-correction interaction: the initial close cites the exact entry-report revision current at append. A close correction stays in its own linear chain and preserves that same opening revision reference. Entry-report corrections remain allowed. For a close correction, the form must display and validate against the immutable opening revision named by the existing close, while also flagging if a newer opening revision superseded it. Review identifies the exact revision without silently rebinding history.
6. Trade UI requires an explicit “I already closed this position outside BlazerOS” confirmation and allows optional exit price/time. Show inline validation/persistence failures. Review visible and VoiceOver/accessibility content must preserve “user-reported/manual, unverified, not broker-confirmed,” the referenced opening revision, and explicitly unavailable exit time/price when absent. It must not claim broker confirmation, alter broker state, create an order, mutate legacy `activeTrade`, create a structural outcome, or affect verified performance.
7. Broker-confirmed close remains out of scope. A future broker close contract must include venue/account identity, broker position/transaction IDs, exit time/price and source evidence, correction/replay rules, and explicit authorization for broker synchronization.

## Challenge questions

- Is a separate close evidence type the right way to preserve the current `.userReported` entry invariants?
- Is it safe to allow entry-report corrections after a close if the close permanently references the opening revision it saw?
- Close chronology must use only the opening time in the immutable opening revision referenced by the close; is that adequate under later corrections?
- Are optional exit time/price useful without making “closed” sound broker verified? What copy/accessibility states must Review preserve?
- Do same-root locking and one-close-root-per-position prevent close/entry-correction races and divergent user statements?
- Is this contract adequately separate from simulated structural outcomes, `.brokerClosed`, and the legacy binary trade ledger?

## Checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-USER-CLOSE-DEBATE` | Research + product + independent QA | Read-only | Position contracts/store, Trade/Review UI, lifecycle/outcome contracts | Shadow outcome integrated | Existing close/open gaps, sources, corrections, races and safety boundary recorded | Three read-only audits | DONE |
| `V3-USER-CLOSE-PLAN` | Supervisor | This report | This report | Debate complete | Separate user-close contract, provenance, correction and no-broker boundaries | Amendments add immutable opening revision in correction UI and one-second future-time rejection | DONE — AMENDED |
| `V3-USER-CLOSE-DESIGN` | Supervisor + independent challenger | Read-only | This report and named contracts | Plan proposed | Challenge entry-revision binding, close corrections, chronology, UI language and serialization | Independent design challenge **PASS** after immutable correction revision and +1s future-close rejection were specified | DONE — PASS |
| `V3-USER-CLOSE-IMPL` | LightningDesk/Research worker | `/private/tmp/blazeros-ios-test-host` | `Sources/BlazerCore/V3DomainContracts.swift`, `Sources/BlazerCore/Research/ResearchStore.swift`, `Sources/LightningDesk/LightningDeskModel.swift`, `Sources/LightningDesk/Screens/DeskScreen.swift`, `Sources/LightningDesk/Screens/ReviewScreen.swift`, `Tests/BlazerCoreTests/V3DomainContractTests.swift`, `Tests/BlazerCoreTests/V3PersistenceTests.swift`, new `Tests/BlazerCoreTests/V3UserReportedPositionCloseTests.swift`, `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`, `iPhone/UITests/BlazerUITests.swift` | Design PASS | Exact entry revision and plan binding; ordered append-only close/correction chain; optional exit facts; chronology against referenced revision; visible/accessibility unverified provenance; no order/broker/simulated/legacy side effects | Focused/full Swift, iOS build and UI | DONE — PASS |
| `V3-USER-CLOSE-REVIEW` | Independent QA | Read-only | Final allowlist and logs | Implementation complete | Exact chain/recovery/concurrency, safety, accessibility and provenance review | Independent exact-diff review | DONE — PASS |
| `V3-USER-CLOSE-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed allowlist | Review PASS | Hash-equal integration and primary verification | Focused close 6/6, domain 15/15, full Swift 671/671; iPhone 17e plan 33/33 (27 unit + 6 UI); `git diff --check` PASS; correction UI flow passes | DONE — PASS |

## Integration and verification — 2026-11-16

- Exact reviewed allowlist was integrated from `/private/tmp/blazeros-ios-test-host`; all ten allowed paths byte-match the reviewed snapshot. The integration includes the new `V3UserReportedPositionCloseTests.swift`.
- Primary focused close tests **6/6**, V3 domain contract tests **15/15**, and full Swift suite **671/671 across 17 suites** pass. Device-specific iPhone simulator build succeeds. `git diff --check` passes.
- The prior close-correction UI fixture failed because it appended an entry-time correction before recording a close whose timestamp preceded that corrected opening. The store correctly rejected the close, leaving the credential cover visible. The simulator fixture now uses a fresh V3 plan identity and records the close against the original opening before adding the later entry correction. The UI test targets the switch control, asserts it is On, and verifies Save Correction is enabled. Targeted UI **1/1** and the full iPhone 17e test plan **33/33** pass.
- The full Swift suite **671/671** passes without Swift compiler warnings. A fresh build later confirmed Xcode emits `Metadata extraction skipped, no AppIntents.framework dependency found` for `BlazerActivity`, `BlazerTestHost`, `BlazerTests`, `BlazerOS`, and `BlazerUITests`; the functional app-intents target is separate. No unused framework dependency was added. The UI test process also prints simulator WebKit/WebCore duplicate-class and debugger-version lookup diagnostics; the result bundle reports **0 runtime warnings**. AVAudioSession hang-risk, actor-isolation, deprecated Text composition, and Swift package duplicate-class source warnings remain fixed.
- Close remains a user-authored assertion, unverified and not broker-confirmed. Broker position sync, physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open. Overall V3 is **PARTIAL**.

## Close-correction UI fixture repair — 2026-11-16

- Independent read-only diagnosis confirmed the root cause: the old fixture persisted an opening and later entry correction first; the subsequent close time was earlier than the latest opening and was correctly rejected. The App Group archive retained those partial V2 fixture records, so the repaired UI fixture uses a new V3 plan identity without deleting prior test data.
- The repaired fixture writes the close against the immutable original opening before adding the later entry correction. Its close and report times remain ordered. The correction form displays the referenced opening revision and supersession message. The UI test now taps the switch’s control area and asserts its accessibility value is On before asserting Save Correction is enabled.
- Independent exact-diff review **PASS**. Targeted iPhone 17e test **1/1**; full iPhone test plan **33/33** (27 unit + 6 UI); full Swift suite **671/671**; `git diff --check` **PASS**. Result bundle: `/private/tmp/v3-close-full-iphone.xcresult`.
- Xcode App Intents metadata extraction warnings affect `BlazerActivity`, `BlazerTestHost`, `BlazerTests`, `BlazerOS`, and `BlazerUITests` in a fresh build. Simulator logs also include system WebKit/WebCore duplicate-class and Xcode debugger-version diagnostics; the result bundle reports zero runtime warnings. No product source warnings were introduced.

## Broker-confirmed close boundary

- **BLOCKED:** the current OANDA client exposes price, stream, and candle operations, but no account transactions, trades/positions, activity cursor, or close-fill schema. No price or simulated barrier result can prove an account position closed.
- Keep this workflow `.manualTradeCloseReport`; do not relabel it `.brokerClosed`. Production integration requires verified, authorized read-only Practice activity access, account/environment isolation, transaction ordering and replay rules, partial-close handling, residual-unit confirmation, actual fill data, and restart reconciliation fixtures. The source audit used no credentials or broker calls.
- This specific producer is blocked pending those prerequisites. Overall STRIKE V3 remains **PARTIAL**.

## Warning cleanup follow-up — 2026-11-16

- A clean derived-data, non-quiet iPhone 17e test build passed. Setting `ENABLE_APP_INTENTS_METADATA_GENERATION=NO` still ran Xcode’s processor and emitted the metadata-skip warning for `BlazerActivity`, `BlazerUITests`, and test/helper targets. It is not an effective fix and was not added to the project.
- No Swift compiler warnings were observed in the latest full Swift suite. Simulator WebKit/WebCore duplicate-class and debugger-version lookup messages are runtime/tool diagnostics; the full result bundle reports zero runtime warnings. No dummy framework dependency was added.

## Preservation and safety boundary

Primary remains heavily dirty. No reset, clean, stash, broad replacement, credentials access, broker synchronization/order, or publication. No market quote or simulated outcome is evidence that the user closed a position. No broker-confirmed close is implemented without an authenticated broker evidence source.
