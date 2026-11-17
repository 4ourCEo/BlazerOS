# BlazerOS RC1 Implementation Reconciliation

Date: 2026-11-03  
Branch: `rc1/research-paper-trading`  
HEAD: `2aa339958c906ca48647cd638cd1ae07996e01e5`

## Repository and device state

- The working tree is dirty with 21 tracked modifications and two untracked implementation/report files. Existing changes were preserved; no reset, clean, merge, branch rewrite, or worktree deletion was performed.
- Worktrees present: the primary RC1 worktree plus `upgrade/blazeros-v2.4-otc-signal-engine` and `upgrade/blazeros-v2-market-data-modularization`.
- `origin` is configured as `https://github.com/4ourCEo/BlazerOS.git`. No remote RC1 branch was returned by the checked `git ls-remote` query.
- The connected iPhone reports `com.blazer.os`, version `1.7.0`, build `5`. The installed app is developer-signed. The app currently installed was produced before the provenance key was added, so its exact source commit is **not provable**.
- The reconciliation device build was installed/launched before the phone went offline; a physical screenshot is at `.build/reconciliation-device/physical-launch.png`.
- `BuildIdentity.swift` and `BLAZER_BUILD_ID` now embed a revision plus `-dirty` marker in subsequent builds. The provenance-enabled build was verified in the simulator as `2aa339958c90-dirty`, but has not yet been installed on the physical phone because the device is currently offline.

## Requirement reconciliation

| Requirement | Status | Evidence |
|---|---|---|
| FX-only OANDA user experience; crypto quarantined | **PARTIAL** | The active Desk selector now exposes only `FX · OANDA` (`DeskScreen.swift:90-101`) and the physical screenshot confirms it. Crypto remains compiled in the model/service (`DeskMarketDataService.swift:149-207`, `DeskDomainTypes.swift:5-7`) and can still be selected programmatically. |
| Final STRIKE Scan layout, readable candles, corrected watchlist | **PARTIAL** | `DeskScreen.swift` contains the moved scan control, enlarged chart, freshness row, and compact watchlist. Simulator suite passed 18/18; current phone evidence is from a non-commit-identifiable developer build and does not prove every state. |
| Obsolete Strike Contract controls removed | **PARTIAL** | The Desk sheet route and visible action were removed in the current tree. `StrikeTradeSheet.swift` remains compiled and contains legacy Crypto.com Strike semantics, so quarantine is not complete. |
| Late-entry recording and contradictory states repaired | **PARTIAL** | `LateEntrySheet.swift` now has validation/progress/receipt handling and `LightningDeskModel.swift:1942-2123` preserves late evidence rules. Physical interaction after the latest fix is not verified. Legacy binary terminology and state coupling remain. |
| Data-driven Radar with authentic optimized animation | **PARTIAL** | `MarketsScreen.swift` now has a seven-second sweep, fading trail, data-bound markers, and monitored/eligible/feed status. Contact illumination, performance measurement, and battery profiling remain incomplete. |
| Coach Ultimate evidence-first/proactive architecture | **PARTIAL** | `CoachScreen.swift`, `AssistantSession.swift`, and `AssistantValidation.swift` provide bounded legacy-context questions, deterministic fallback, and citation-ID checks. Review now has a bounded, accessible V3 close-completeness Insights inbox with exact plan/close/opening citations (`ReviewScreen.swift`, tests **4/4**; iPhone test plan **33/33**). Coach still cannot receive/cite V3 archive context for Q&A; cross-destination contextual entry points, proactive findings, and replay analytics remain open. See `reports/V3_REVIEW_INSIGHTS_INBOX_2026-11-16.md`. |
| Cost-adjusted OANDA Spot-60 shadow research | **PARTIAL** | `Sources/BlazerCore/Research/SpotFXHistoricalReplay.swift` evaluates fixed-horizon long/short results from executable bid/ask entry/exit observations, adds explicit per-unit cost, and keeps midpoint-only evidence unresolved. `SpotFXHistoricalReplayTests.swift` covers cost and missing-side behavior. Authenticated campaign data and promotion-grade validation evidence remain unverified; this does not replace the legacy midpoint proxy or establish edge. |
| Spot-FX research separated from binary settlement | **PARTIAL** | `ResearchContracts.swift` labels midpoint results as proxy and `OTCResearchService.swift` is read-only, but `LightningDeskModel.swift`, `StrikeTradeSheet.swift`, and Coach copy still expose binary contract semantics alongside FX. |
| Physical performance, recovery, accessibility | **PARTIAL** | Dynamic Type/layout and execution tests pass; device launch/feed screenshots exist. No Instruments report or complete physical interruption/recovery/accessibility workflow evidence exists. |
| Exact-commit CI, build identification, signed distribution | **PARTIAL** | Build identity is now embedded by `BuildIdentity.swift`/`App/Info.plist` and verified in the simulator. No CI result, clean exact-commit artifact, physical installation of the provenance-enabled build, or TestFlight/distribution artifact exists. |

## Verified test evidence

- Focused iPhone simulator suite: **18/18 passed**.
- Latest simulator build: succeeded.
- Latest signed physical-device build: succeeded.
- Reconciliation build installed and launched on iPhone 16; screenshot confirms FX · OANDA, Scan Now, fresh market observation, readable candles, chart focus control, and the current STRIKE verdict area.
- The phone is now reported offline by Xcode/CoreDevice, so the provenance-enabled replacement cannot yet be installed.
- Interactive Radar, Coach, late-entry, background/recovery, notification, weak-network, settlement, and accessibility workflows remain unverified on hardware.

## Correction priority

- **P0:** keep execution/state semantics authoritative, surface all late-entry failures, and prevent legacy contract controls from appearing in the FX Desk.
- **P1:** make the active iPhone experience FX-only and finish the data-bound Radar motion/status behavior.
- **P2:** add executable bid/ask Spot-60 shadow evaluation, then expand Coach and measure performance.

This report intentionally does not mark documentation, simulator-only evidence, or a successful build as physical-device acceptance.

## V3 M1 additive contract slice

- Added `Sources/BlazerCore/V3DomainContracts.swift` without changing V1 engine behavior or existing record decoding.
- Added explicit setup lifecycle transitions so invalidated/expired setups cannot silently resurrect.
- Added canonical provider/environment, bid/ask observation, source/receipt timestamp, sequence, freshness, and validation contracts.
- Added explicit outcome quality categories so proxy, ambiguous, and unresolved records cannot affect verified performance.
- Added a structural `V3TradePlan` contract with versioned strategy/engine identity, evidence references, stop/target ordering, spread cap, risk fraction, and reward/risk validation.
- Added a deterministic bid/ask Spot evaluator with explicit late/missing/out-of-order evidence rejection; it has no order authority.
- Added separate `v3-trade-plans` and `v3-spot-outcomes` durable namespaces with immutable plan snapshots, exact-replay idempotence, conflict detection, restart decoding, and a ForwardTest-facing evaluate-then-persist path. Legacy midpoint `outcomes` remain untouched.
- Added explicit V3 trade-plan and user/broker position lifecycle state machines, including terminal-state anti-resurrection and broker identity/exit validation.
- Corrected `V3TradePlan.state` to use the plan lifecycle rather than setup lifecycle, preventing cross-lifecycle state confusion.
- Added deterministic V3 risk/margin sizing with explicit rejected-plan reasons for malformed input, insufficient risk budget, and insufficient margin.
- Added `Tests/BlazerCoreTests/V3DomainContractTests.swift`: **12/12 passed** and `V3PersistenceTests.swift`: **6/6 passed**.
- iPhone regression suite after the additive contracts and macOS compatibility fix: **18/18 passed**.
- Full Swift package suite: **392/392 passed**; the two previously reported test warnings were cleaned up.
- Latest iPhone simulator build after the persistence path: **BUILD SUCCEEDED**.

## Physical iPhone verification — 2026-11-03

- Device: **Gilbert’s iPhone**, iPhone 16, UDID `00008140-00112D143CC3401C`, paired and available.
- Signed device build: **BUILD SUCCEEDED** for `com.blazer.os`.
- Installed and launched with `devicectl`; installed app reports version `1.7.0`, build `5`.
- Embedded build identity verified from the installed build artifact: `BLAZER_BUILD_ID=2aa339958c90-dirty`.
- Screenshot captured at `.build/reconciliation-device/physical-v3-launch.png`; it shows the FX/OANDA surface, live freshness, EUR/USD candles, and Scan verdict area.
- Configured `BlazerTests` as a host-tested bundle using `TEST_HOST=$(BUILT_PRODUCTS_DIR)/BlazerOS.app/BlazerOS`, the app target dependency, and duplicate-static-package diagnostic suppression required by this package layout.
- Focused physical XCTest execution: **18/18 passed** on Gilbert’s iPhone (`DeskLayoutTests` 3, `EngineParityTests` 3, `ExecutionFlowTests` 11, `PhoneTargetTests` 1).
- Added a navigation contract regression test for the three primary destinations; the focused simulator suite is now **19/19 passed**. The physical phone became unavailable during this iteration, so the new assertion has not yet been re-run on hardware.
- Added a saved `BlazerUITests` target, `iPhone/BlazerOS.xctestplan`, and three interaction tests for primary navigation, Review subsections, and contextual Coach. The runner is now executable by explicitly launching `com.blazer.os` and entering the simulator's demo desk on first run. Simulator UI suite: **3/3 passed**; full iPhone simulator XCTest suite: **21/21 passed**.
- Added append-only V3 position-event persistence and a Review summary of persisted V3 plans, position events, and spot outcomes. Swift package suite: **392/392 passed**; full iPhone simulator XCTest suite after this integration: **21/21 passed**.
- Release verification artifacts: unsigned Release archive completed at `.build/BlazerOS-unsigned.xcarchive`; a 5-second simulator Time Profiler trace was captured at `.build/BlazerOS-time-profiler.trace`; the current source identity is `2aa339958c906ca48647cd638cd1ae07996e01e5` plus uncommitted changes. No signed distribution or CI run is claimed because the worktree remains intentionally dirty and no CI configuration is present.
- Added `Sources/BlazerCore/Research/ORBBreakRetestV1.swift` and `Tests/BlazerCoreTests/ORBBreakRetestV1Tests.swift`: DST-aware 9:30–9:35 ET range sealing, completed-M1 breakout threshold, retest tolerance, directional confirmation, structural invalidation, expiry, look-ahead protection, complete V3 plan generation, and deduplicated stage notification planning. `ForwardTest --orb` evaluates live OANDA bundle payloads and persists confirmed immutable V3 plans without placing orders.
- Full Swift suite after ORB implementation: **399/399 passed**. Full iPhone simulator XCTest suite: **21/21 passed**.
- M2 added executable-side structural outcome contracts and persistence: immutable entry evidence, bid/ask-aware stop/target resolution, explicit winner/loser/untriggered/ambiguous/unresolved states, spread and additional-cost accounting, stale/missing/instrument guards, and replay conflict protection. `ForwardTest --orb` now restores entry evidence and resolves only observed OANDA Practice quote triggers; it does not force expiration or fabricate fills.
- M3 notification slice added stage-filtered ORB local scheduling, deduplicated IDs, notification deep-link payloads, and app-side Trade navigation that treats taps as revalidation prompts only. Deep-link regression test passed on simulator.
- M4 operational slice added native Trade/Markets ORB state rendering from the existing FX scan snapshots, including range levels, stage, entry/stop/target plan fields, unavailable messaging, and Markets-to-Trade reuse. The simulator UI suite now verifies the ORB Trade surface; full iPhone simulator XCTest: **22/22 passed**.
- Attempted `ForwardTest --orb --max-events 1` against the local OANDA Practice credential path. The process produced no authenticated session or market observation before the bounded run was stopped; no real ORB setup, fill, plan, or outcome is claimed. Existing daemon activity and the local credential/runtime state require operator-controlled credential/session verification before unattended collection.
- Background capability remains limited: the iPhone scan lifecycle cancels/invalidates active work on background; dependable unattended ORB delivery therefore requires an authenticated remote push/collector service. Local notification scheduling and deep-link handling are implemented, but physical delivery and APNs/server verification remain open.
- Added an `ORBRemoteNotificationEnvelope` contract with event/plan identity, strategy provenance, source and expiry timestamps, key ID/signature fields, deep-link matching, and stale-alert validation. This is the client-side payload boundary only; no APNs provider, signing-key service, or remote delivery result exists in this worktree.
- M4 regression result after Trade/Markets integration and remote payload validation: Swift **408/408 passed**, iPhone simulator **22/22 passed**, and `git diff --check` passed.
- Migrated the primary navigation shell to the PRD's three destinations: **Trade**, **Markets**, and **Review**. Existing Journal and Intel surfaces remain available as Review subsections; Coach is opened contextually from Review.
- Updated three-destination build installed/launched on the physical iPhone; screenshot evidence: `.build/reconciliation-device/physical-v3-review-nav-ready.png`.

## V3 Review archive-state follow-up — 2026-11-15

- Independent audit found Review read only the OANDA proxy archive, omitted setup-lifecycle and plan-entry evidence counts, and silently left zero defaults when reads failed. Active Live strategy plans are stored separately under `Research/live-oanda`.
- Review now reports `Research/live-oanda` and `Research/oanda-proxy` as distinct sources. Each source has loading, empty, populated, and unavailable states; it publishes six individually accessible V3 counts only after all reads validate. Legacy Journal and Research sections remain separate.
- `ResearchStore.v3PlanEntryEvidence()` now fails closed for unsafe IDs, malformed observation/timestamp evidence, and filename-to-ID mismatch. Regression tests cover malformed decoded evidence and renamed files.
- Independent design challenge and exact-diff QA: **PASS**. Full Swift suite **620/620 across 16 suites**; focused Review/persistence **16/16**; iPhone 17e simulator DeskLayout **3/3**, UI **4/4**; release Mac target build passed in the identical isolated source snapshot; `git diff --check` passed.
- The source-level actor-isolation and iOS 26 `UIWindow(frame:)` warnings are fixed. Xcode still emits App Intents metadata notices because no App Intents framework dependency exists. The hosted iOS unit tests now use a minimal `BlazerTestHost`, removing the app/test duplicate SwiftPM class diagnostics; full simulator unit (22/22) and UI (4/4) suites pass. The simulator emits an unrelated system WebKit/WebCore duplicate class notice during UI automation. The AVAudioSession main-thread hang-risk warning is now fixed; its current evidence and simulator-only remaining diagnostics are recorded in `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`. See `reports/IOS_TEST_HOST_DUPLICATE_CLASS_FIX_2026-11-15.md`.
- Remaining Review work: persisted plan/position timelines, cost and unresolved outcome details, and workflow-level acceptance. No manual position entry or order authority was added.


## Runtime and compile warning cleanup — 2026-11-15

- Audio lifecycle now uses one serialized owner coordinator. iOS 27 awaits AVAudioSession completion APIs; the iOS 26 synchronous path runs on a dedicated serial queue without blocking MainActor. Permission, recognition, and speech callbacks are generation/utterance guarded. Deactivation failure preserves uncertain ownership and requires successful deactivation recovery before another lease.
- Removed the app/test duplicate Swift package classes by hosting unit tests in `BlazerTestHost`; source actor-isolation and deprecated `UIWindow(frame:)` warnings were also fixed in the prior warning pass.
- Replaced the iOS 26 deprecated `Text + Text` composition in `MiniCandleChart.ohlcField` while retaining the separate tints and combined accessible value.
- Evidence: full primary iPhone simulator **27 unit + 4 UI passed**; focused expiry and audio lifecycle **6/6 passed** with no AVAudioSession hang-risk warning; full Swift **620/620 across 16 suites**; Release Mac product build passed; `git diff --check` passed. iOS 26 deployment-target build passed on the iOS 27.2 SDK; there is no iOS 26 simulator runtime available for runtime verification.
- Remaining diagnostics are tool/runtime generated: App Intents metadata notices (no framework dependency), simulator AVAudioSession unsupported-property notice, simulator WebKit/WebCore duplicate class, and VoiceDB fallback. See `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`.


## V3 Review plan detail — 2026-11-16

- Review now retains validated records from the six V3 collections per source and offers exact-plan read-only timelines with orphan/integrity sections. Source and per-observation provider/environment, timestamp meanings, available quality, persisted costs, and absent fields are shown explicitly.
- ResearchStore validates safe record identity and filename stems across all six collections. ORB Live plans publish only after durable persistence; write failure and non-Live refresh clear both Live candidate projections.
- Final exact-diff review **PASS**. Primary V3-focused tests **26/26**, isolated full Swift **629/629**, Release Mac build and final iOS simulator build **PASS**, final focused regressions **4/4**, `git diff --check` **PASS**. Full iPhone **27 unit + 4 UI** passed before the final small Review UI display additions; a final iOS simulator build compiled those additions.
- Review detail is implemented, but active Trade still lacks production lifecycle/entry/position/outcome writers. No order or manual position-entry authority was introduced; goal remains partial.


## V3 active Trade ORB lifecycle — 2026-11-16

- Integrated the reviewed ORB lifecycle writer for authenticated Live OANDA FX. It persists observation-only setup transitions from completed M1 bars into `Research/live-oanda`, with stable replay/conflict handling across store instances and an accessible lifecycle evidence status.
- Causative invalidation source is pinned to the failing bar close; the event hashes/cites the causal prefix through that bar and excludes later bars. Custom timeframe survives archive reload. A lifecycle-only write failure leaves the persisted candidate plan and ORB decision published and reports evidence unavailable.
- Final independent exact-diff review **PASS**. Primary integrated focused tests **21/21**; isolated full Swift **643/643 across 17 suites**; generic iOS simulator build **PASS**; primary iPhone 17e simulator **27 unit + 4 UI passed**; `git diff --check` **PASS**. This remains simulator evidence, not physical-device validation.
- Remaining: entry-evidence, position, and outcome production writers; physical-device recovery/accessibility/performance evidence; owner-signed strategy promotion; exact-SHA CI and signed distribution evidence. STRIKE V3 continuation goal remains **PARTIAL**.


## V3 user-reported position — 2026-11-16

- Added an explicit plan-scoped user-reported position flow from current Trade and exact Live OANDA Review plan detail. The append-only record is `.userReported` / `.manualTradeReport`; it cannot place an order, claim broker confirmation, mutate ORB lifecycle, or enter the legacy binary trade ledger.
- ResearchStore validates the exact persisted Live plan and serializes report/correction appends per archive root. Retries are deterministic, corrections are linear and append-only, invalid chains fail closed, and older optional-field records remain decodable. Review exposes reported price/time, provenance, correction status, and timing relative to terminal setup evidence.
- Independent exact-diff review **PASS**; primary focused tests **56/56**, isolated full Swift **651/651**, final simulator UI **1/1**, integrated primary Release simulator build **PASS**, hash-equal integration, and `git diff --check` **PASS**. See `reports/V3_USER_REPORTED_POSITION_2026-11-16.md` for logs and contract details.
- V3 remains **PARTIAL**. Next evidence gap: genuine market entry-evidence production, then position-close and outcome writers. Physical-device recovery/accessibility/performance, owner-signed promotion, exact-SHA CI, and signed distribution are still missing.


## V3 broker-confirmed position close — 2026-11-16

- **BLOCKED (production integration):** the required read-only, authenticated broker activity source is absent. `Sources/BlazerCore/OandaClient.swift` implements account pricing (`/v3/accounts/{accountID}/pricing`, around lines 373 and 433), streamed pricing (around line 667), and candle requests; it has no transactions, trades/positions, account-changes endpoint, transaction cursor, or close-fill model. Market quotes and sampled stop/target crossings cannot establish that an account position closed.
- **VERIFIED boundary:** the V3 close workflow is explicitly `.manualTradeCloseReport`; it records a user assertion and must remain distinct from `.brokerClosed`. The PRD requires separate user-reported and broker-confirmed lifecycles and rejects timer/market crossing as broker execution evidence (`reports/source/BlazerOS_STRIKE_V3_REBUILT_PRD.md:106-107, 165, 200-217`).
- **Prerequisites before production work:** authorized OANDA Practice activity access and verified endpoint/schema; explicit environment and account binding in the V3 archive; broker position plus opening/closing transaction identity; ordered cursor/replay/gap/correction semantics; partial-close units and residual-position confirmation; actual fill price/time and available costs; restart-safe reconciliation with fixtures/tests. No credentials or broker calls were used for this audit.
- Offline contract/decoder and fixture work can proceed once a bounded design is recorded. An authenticated polling producer or broker-confirmed close claim remains blocked until the source contract and account binding are established. Overall STRIKE V3 remains **PARTIAL**.


## V3 Review close-completeness Insights — 2026-11-16

- **VERIFIED:** Review derives a bounded Insights inbox only from validated archive snapshots. It shows incomplete, unsuperseded user-reported close leaves linked to the exact plan and opening; preserves superseded-opening status; cites plan, close, and opening IDs visibly and accessibly; caps each archive at six; and distinguishes loading, unavailable, empty, and populated-with-no-matches.
- **VERIFIED:** no broker/order/risk mutation or market/performance inference is introduced. Missing user-supplied close time/price remains explicitly unavailable. Notification delivery is absent.
- Two independent design/debate audits and independent exact-diff re-review **PASS** (one requested visible plan citation, which was added and retested). Primary focused Insights tests **4/4**, full Swift **675/675 across 17 suites**, iPhone 17e plan **33/33** (27 app + 6 UI), and `git diff --check` **PASS**. Primary xcresult: `/tmp/v3-primary-review-insights-full.xcresult`.
- Overall Coach requirement remains **PARTIAL** because the general Coach Q&A context does not yet include V3 archive records. STRIKE V3 remains **PARTIAL**.


## V3 Live entry market observation — 2026-11-16

- **VERIFIED (implementation and package behavior):** active Live OANDA FX monitor records at most one observed hypothetical entry reference for the exact persisted ORB plan. The immutable plan includes an optional, backward-compatible entry-deviation limit registered in the ORB configuration digest. Quote receipt/source times and provider/environment are retained; executable-side, freshness, chronology, spread, risk-band, terminal setup, exact-plan, and safe-ID checks are applied.
- **VERIFIED (stale-work boundary):** per-root archive serialization plus an append-time gate rechecks generation, selected pair, FX mode, scan ownership, and current Live environment. Timestamp conversion rejects out-of-range milliseconds before integer conversion. The two review-found defects have regression tests.
- **VERIFIED (safety):** this is `.observed` market evidence and explicitly labeled hypothetical; it does not assert execution or create order, fill, position, lifecycle, user-report, or outcome records. Storage failure leaves the plan and lifecycle projection intact.
- Independent exact-diff review **PASS**; primary full Swift suite **653/653 across 17 suites**; iPhone 17e simulator build **PASS**; `git diff --check` **PASS**. Sixteen allowlisted paths byte-match the reviewed snapshot.
- **PARTIAL (UI test):** targeted Xcode UI-test invocation exited 75 while saving its result log and recorded zero tests. The product build compiled; this interaction has no successful UI-test evidence yet.
- Warning status: no Swift compiler warnings in full Swift tests. Xcode’s device-specific build emits its App Intents metadata skip because the target has no App Intents dependency; generic simulator builds may print a simulator placeholder OS-version diagnostic. These are toolchain notices. Earlier actor-isolation, deprecated API/Text, duplicate package-class, and AVAudioSession hang-risk source warnings remain fixed.
- **Next highest-priority gaps:** production position-close and structural outcome writers; UI workflow acceptance; physical-device recovery/accessibility/performance; owner-signed strategy promotion; exact-SHA CI and signed distribution. Overall STRIKE V3 remains **PARTIAL**.


## V3 Live shadow structural outcome — 2026-11-16

- **VERIFIED:** the selected-pair Live monitor persists only a `.simulated` stop/target outcome for an exact persisted Live plan and observed Live OANDA entry reference. Review copy labels it “First sampled stop/target trigger” and simulated, preserving the sparse-sampling limitation. Untriggered polls do not become final outcomes.
- **VERIFIED:** independent entry/exit freshness is checked at each observation’s own receipt (five seconds each for Live). The store revalidates entry chronology, identity, OANDA Live provenance, spread, inclusive entry deviation, and strict structural bounds. Terminal setup invalidation/expiry cuts off outcomes at or after its source time. Per-root locking, exact retry, conflict rejection, and generation/pair/FX/scan/Live gates protect the one-result-per-plan write.
- Generic entry/outcome writers cannot append into `Research/live-oanda`; their Live-specific alternatives enforce the exact persisted plan/evidence contract. Generic evaluator defaults used by ForwardTest/replay remain unchanged. No position close, broker fill, order, lifecycle event, user report, or verified-performance update is generated.
- Independent exact-diff review **PASS**. Primary focused structural suite **18/18**, full Swift suite **663/663 across 17 suites**, iPhone 17e simulator build **PASS**, Review UI **1/1**, and `git diff --check` **PASS**. The final allowed files byte-match the reviewed sidecar.
- No Swift compiler warnings remain. Xcode retains the App Intents metadata skip because the app has no App Intents dependency. The targeted UI test completed successfully in this cycle; the previous result-log save failure did not recur.
- **Next highest-priority gap:** define and implement a distinct position-close evidence workflow, separating user-reported closing from broker-confirmed closing and preventing simulated market outcomes from mutating position lifecycle. Physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI and signed distribution remain open. Overall goal remains **PARTIAL**.


## V3 user-reported close UI acceptance — 2026-11-16

- **VERIFIED:** repaired the simulator-only close-correction fixture after evidence showed its prior ordering wrote a later entry correction before an earlier close. The close is now persisted against the immutable original opening first; a fresh versioned fixture plan avoids inheriting partial records from failed runs. No old simulator data was deleted.
- **VERIFIED:** close-correction form identifies the referenced opening and marks its supersession; the UI test taps the actual switch control, confirms it is On, and checks Save Correction is enabled. Independent exact-diff review **PASS**.
- **VERIFIED:** full Swift suite **671/671 across 17 suites**; full iPhone 17e simulator plan **33/33** (27 unit + 6 UI); targeted close correction **1/1**; `git diff --check` **PASS**. Result bundle: `/private/tmp/v3-close-full-iphone.xcresult`.
- Warning state: no Swift compiler warnings. A fresh non-quiet test build shows Xcode metadata-extraction warnings for `BlazerActivity`, `BlazerTestHost`, `BlazerTests`, `BlazerOS`, and `BlazerUITests`, all without a direct App Intents implementation. The functional `BlazerIntents` target is separate. `ENABLE_APP_INTENTS_METADATA_GENERATION=NO` did not suppress the processor. UI simulator logs contain system WebKit/WebCore duplicate-class and debugger lookup diagnostics; the full test xcresult reports zero runtime warnings.
- User-reported position close is still **PARTIAL** relative to actual position reconciliation: it proves only a manual user statement, not a broker-confirmed close. Physical-device recovery/accessibility/performance, broker-backed close evidence/authorization, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open. Overall STRIKE V3 remains **PARTIAL**.

## Continuation update — selected V3 Review insight brief in Coach — 2026-11-16

- A deterministic, read-only per-insight Coach brief now revalidates a selected close-completeness record against an uncapped targeted projection from its same archive. It requires full payload/evidence equality; changed, loading, unavailable, or empty archives show no selected facts. The existing generic Coach path is unchanged.
- Independent design challenge and exact-diff QA **PASS**. Primary focused Swift tests **8/8**, isolated-fixture iPhone 17e handoff UI **1/1**, `git diff --check` **PASS**; reviewed hashes and detailed behavior are in `reports/V3_COACH_SELECTED_INSIGHT_BRIEF_2026-11-16.md`.
- Overall Coach remains **PARTIAL**: general V3 Coach Q&A with validated V3 citations and uncertainty handling is not implemented. STRIKE V3 remains **PARTIAL**; physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open. Broker-confirmed close producer remains blocked by external account activity authorization/schema/reconciliation requirements.

## Continuation update — deterministic Coach intents for selected close insight — 2026-11-16

- Added five fixed, deterministic question intents to the revalidated selected-close brief. Answers cite only archive-qualified supporting close/opening records, preserve manual/unverified/not-broker-confirmed provenance, and do not assert a close, execution, or fill. Unsupported intent is explicit; the route adds no text field, LLM/model, legacy context, broker/network path, or write behavior.
- Independent design challenge and exact-diff QA **PASS**. Primary focused Swift tests **11/11**, iPhone 17e selected-insight intent UI **1/1**, package build independently passed, and `git diff --check` passed. Latest xcresult reports zero runtime warnings. Details/hashes: `reports/V3_COACH_INSIGHT_QUESTION_INTENTS_2026-11-16.md`.
- General natural-language V3 Coach Q&A remains **PARTIAL**. The wider STRIKE V3 goal remains **PARTIAL** with physical-device recovery/accessibility/performance, owner-signed promotion, exact-SHA CI, signed distribution, and broker-confirmed position-close requirements open or externally blocked.

## Mac Live-history archive integrity — 2026-11-17

- **VERIFIED (implementation):** OANDA Live historical candle capture is a separate explicit read-only research path. Archive append requires an opaque in-memory receipt created only by a successful Live fetch, so callers cannot submit a hand-built/decoded batch or caller-stamped retrieval time. The receipt binds `includeFirst` and fetch receipt time. The archive integrity digest binds its provenance envelope and candle batch; reads reject mismatched duplicated identities/intervals, non-M1 content, inconsistent gap counts, non-private files, and metadata tampering.
- URLSession stub and final focused `OandaHistoricalBidAskTests` passed **8/8**, including final receipt-bound parameter/time checks. Full Swift suite passed **709/709 across 17 suites**. Release `ForwardTest` product build passed in **151.87s** without compiler warnings, and `ForwardTest --help` displayed the explicit Live capture flags.
- **PARTIAL:** no real Live capture was run. This does not qualify or promote a strategy. No build artifacts were removed to obtain working space.
- Overall STRIKE V3 remains **PARTIAL**. Live strategy promotion remains blocked by the empty owner-approved promotion registry. Broker-confirmed close remains externally blocked pending authorized account-activity access and a verified reconciliation contract. Physical-device evidence, exact-SHA CI, and signed distribution remain open.

## SpotFX replay horizon identity — 2026-11-17

- Fixed unresolved replay IDs to use the configured horizon, matching valid outcome IDs. The prior code used `input.expirySeconds`, causing unresolved results from separate horizon arms to collide when the input expiry stayed at its default.
- Added a regression replaying the same missing-entry case at 60s and 180s; both remain unresolved and receive distinct horizon-qualified IDs. Targeted test **1/1**, full SpotFX replay suite **3/3**, full Swift package **709/709 across 17 suites**, `swiftc -parse` and `git diff --check` **PASS**.
- Release `ForwardTest` build passed. The implementation prevents cross-arm identity collisions but does not supply authenticated campaign data or qualify a profile for promotion.

## Mac UTC-day historical seam verification — 2026-11-17

- **VERIFIED:** independent daily M1 requests set `includeFirst=true` for every UTC window; the archive assigns source timestamps to `[start,end)` and rejects `sourceTime >= requestedTo`. Focused archive tests **8/8** pass, including all-window inclusion.
- **VERIFIED:** full Swift package **709/709 across 17 suites**; Mac Release `BlazerOS` build **PASS** (130 seconds) with no compiler warnings; `git diff --check` **PASS**.
- **PARTIAL:** OANDA documents the `from`/`includeFirst` behavior but does not clearly define `to` inclusivity. Exact-end candles fail closed. No Live capture was run. London Break + Retest remains unconfigured and unpromoted pending an owner-frozen profile, qualifying historical/forward campaign evidence, and owner approval; the production promotion registry is empty.
- STRIKE V3 remains **PARTIAL**. No user changes or build caches were deleted.
