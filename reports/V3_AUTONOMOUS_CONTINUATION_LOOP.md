# BlazerOS STRIKE V3 — Autonomous Continuation Loop

Use this as the continuation instruction for future implementation turns.

## Mission

Continue implementing the rebuilt STRIKE V3 PRD in the current BlazerOS repository until the remaining requirements are either implemented and verified or explicitly marked BLOCKED. Do not stop after a single successful build or test run.

## Operating loop

For every iteration:

1. Read the current reconciliation report and inspect the actual dirty worktree before editing.
2. Select the highest-priority unresolved PRD item, in this order:
   - correctness and provenance boundaries;
   - durable V3 setup/plan/position/outcome persistence;
   - Trade/Markets/Review UI behavior and interaction tests;
   - Coach evidence access and conservative contextual behavior;
   - physical-device recovery/accessibility/performance evidence;
   - exact commit, CI, signing, and distribution evidence.
3. Make the smallest additive change that preserves V1 JSCore behavior, legacy records, user changes, and research/live-capital boundaries.
4. Add regression tests for normal, missing, stale, duplicate, out-of-order, mismatched, restart, and corrupted-input paths where applicable.
5. Run the narrowest relevant test first, then the full Swift suite and affected iPhone build/tests.
6. If the iPhone is connected, install and inspect the newest signed build; capture evidence for the changed workflow.
7. Update `reports/RC1_IMPLEMENTATION_RECONCILIATION_2026-11-03.md` with VERIFIED/PARTIAL/MISSING/BLOCKED status and exact evidence.
8. Run `git diff --check` and preserve all unrelated dirty changes.
9. Immediately continue to the next unresolved item unless blocked by a real external dependency.

## Non-negotiable safety rules

- Never reset, clean, stash, discard, merge, force-push, delete, or overwrite existing user work.
- Do not replace or mutate the pinned V1 engine or reinterpret legacy binary/crypto/OTC records as V3 spot-FX evidence.
- No autonomous orders, live-capital authorization, AI execution authority, guaranteed protection, fabricated outcomes, or unverified profitability claims.
- Keep OANDA Practice, manual practice, broker-confirmed, midpoint proxy, synthetic, binary, crypto, and OTC evidence explicitly separated.
- Use bid/ask executable sides for spot outcomes; missing, stale, late, ambiguous, mismatched, or out-of-order evidence remains unresolved or quarantined.
- Keep the default 60-second V1 horizon unchanged; 3m/5m/10m are separate research arms.
- Do not call simulator evidence physical acceptance. Do not call a successful build reproducible until the exact clean SHA, CI result, signed artifact, and provenance-enabled device install are recorded.

## Current known gaps to burn down

- Full V3 setup/plan/position lifecycle integration into active Trade and Review state.
- Structural strategy candidates and risk/margin sizing with preregistered configuration identity.
- Automated Radar selection/cancellation, Chart Focus presentation/dismissal, and late-entry success/error UI tests.
- Review now separates Live OANDA and proxy V3 archives, reports six accessible counts, and shows loading/empty/populated/unavailable per source. Remaining Review work: plan and position timelines, cost details, unresolved-outcome inspection, and workflow tests; see `reports/V3_REVIEW_ARCHIVE_STATE_2026-11-15.md`.
- Contextual Coach evidence inbox with citations and unavailable/uncertain responses.
- Physical interruption/recovery, accessibility, Instruments performance, and energy evidence.
- Exact clean checkpoint commit and CI run on that SHA.
- Signed reproducible distribution/TestFlight evidence.

## Completion standard

Do not declare the PRD complete because tests pass. Declare each requirement only with source evidence, test evidence, and—where required—physical-device or CI evidence. At the end of every iteration, state the next highest-priority gap and continue working on it.

## Continuation update — 2026-11-15

- Independent Review audit found the prior summary read only `Research/oanda-proxy`, omitted V3 lifecycle/entry-evidence counts, and showed zero counts after read failure. The corrected Review loads `Research/live-oanda` and `Research/oanda-proxy` separately, publishes each source only after all six V3 record collections validate, and distinguishes loading, empty, populated, and unavailable states. Entry evidence now validates safe IDs, observation integrity, timestamps, and filename identity.
- Independent design challenge and exact-diff QA both passed. Primary integration verification: focused tests **16/16**, full Swift package **620/620 across 16 suites**, release Mac target build passed in the identical isolated snapshot, iPhone 17e simulator DeskLayout **3/3**, UI **4/4**, and `git diff --check` passed.
- No manual position-entry path, timelines, costs, or detailed unresolved-outcome inspection were added. Review integration remains **PARTIAL**.
- Remaining V3 UI gap: show persisted plan/position/outcome details while preserving evidence quality and unresolved labels. No signed production strategy promotion exists; the owner-pinned manifest remains an external gate.


## Continuation update — test warning cleanup — 2026-11-15

- Added a minimal `BlazerTestHost` for `BlazerTests`; its bundle ID is distinct and it links no SwiftPM products or production app-group entitlement. The unit-test process no longer emits the app/test duplicate Swift package class warning. UI tests still launch the shipping `com.blazer.os` app.
- Corrected one stale historical-entry assertion to match the existing user-facing model message; the nil-active-trade safety assertion remains. Full simulator unit tests **22/22**, UI tests **4/4**, app-group/OTC tests **2/2**, focused historical-entry **1/1**, and `git diff --check` passed.
- Remaining diagnostics at this checkpoint: iOS Simulator system WebKit/WebCore duplicate class output during UI automation, App Intents metadata extraction notices despite no App Intents implementation, and benign simulator voice-service diagnostics. The AVAudioSession hang-risk warning was addressed in the later audio/runtime warning pass below.
- Highest-priority documented V3 gap remains persisted setup/plan/position/outcome detail in Review (timelines, cost and unresolved outcome inspection) and active Trade lifecycle integration. Strategy promotion, physical-device evidence, and exact clean-SHA CI/signing remain open.


## Continuation update — audio/runtime warnings — 2026-11-15

- Fixed the AVAudioSession main-thread hang-risk by serializing ownership and awaiting iOS 27 activation/deactivation; the iOS 26 synchronous path executes on a dedicated serial queue. Failed deactivation keeps uncertain ownership and blocks/retries subsequent acquisition until recovery succeeds. iOS 27 expiry flow passed without the hang-risk diagnostic; iOS 26 target compile passed, but there is no iOS 26 runtime installed.
- Replaced deprecated `Text + Text` in the chart scrub label and retained separate colors plus combined accessibility. Full primary simulator suite: unit **27/27**, UI **4/4**; full Swift suite **620/620 across 16 suites**; Release Mac build and `git diff --check` passed.
- Remaining App Intents notices, simulator-only AVAudioSession property notice, simulator WebKit/WebCore duplicate-class notice, test-host app-group lookup notices without production entitlement, and VoiceDB fallback diagnostics are recorded in `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`.
- V3 remains partial. Next highest-priority documented gap: connect persisted V3 setup/plan/position/outcome details into active Trade and Review behavior; Review timelines, cost details, and unresolved-outcome inspection remain open. Physical-device recovery/accessibility/performance, signed strategy promotion, exact-SHA CI and distribution evidence remain open.


## Continuation update — Review plan detail — 2026-11-16

- Completed the highest-priority Review detail slice from `reports/V3_REVIEW_PLAN_DETAIL_2026-11-15.md`: all six V3 collections now validate filename identity and safe references atomically; selected plan timelines join only by exact `planID` within one source archive. Orphans stay unlinked, cross-plan instrument/strategy/engine conflicts are marked unresolved, and timestamps, per-record/per-observation provenance, quality, costs, and missing categories reflect stored fields.
- Active Live ORB plans now publish only after persistence succeeds. A failed write clears both Live projections and publishes an unavailable reason after a generation check; non-Live candidates clear the Live projection. This remains research evidence and adds no entry, fill, position, or order authority.
- Independent exact-diff review: **PASS**. Primary integrated V3 tests **26/26**; isolated full Swift **629/629 across 16 suites**; isolated iPhone simulator **27 unit + 4 UI passed** before final display-copy/round-trip changes; final generic iOS build and Release Mac build **PASS**; final focused reviewer regressions **4/4**; `git diff --check` **PASS**. The final Review UI edits were compiled but not rerun through the full UI suite.
- Warning status: actor-isolation, deprecated UIKit/Text composition, package duplicate-class, and AVAudioSession hang-risk warnings are fixed. The App Intents metadata extraction notice remains because the app has no App Intents dependency; simulator/runtime diagnostics remain documented in `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`.
- The ORB-only setup lifecycle writer using completed M1 evidence is implemented and integrated. It writes observation-only lifecycle events for authenticated Live OANDA FX, preserves plan/decision projection on lifecycle storage failure, uses causal-prefix bar evidence with the causative close as source, and exposes a separate accessible evidence status. Independent exact-diff review **PASS**; primary focused **21/21**, isolated full Swift **643/643 across 17 suites**, generic iOS build, primary iPhone 17e simulator **27 unit + 4 UI passed**, and diff check pass. Details and exact evidence are in `reports/V3_ACTIVE_TRADE_LIFECYCLE_2026-11-16.md`.
- V3 remains **PARTIAL**. Next highest-priority implementation is active-Trade entry-evidence persistence with explicit user/manual-only semantics; position and outcome writers remain absent. Physical-device recovery/accessibility/performance, owner-signed strategy promotion, and exact-SHA CI/signing/distribution evidence are also open.


## Continuation update — user-reported V3 position — 2026-11-16

- Implemented and integrated the plan-scoped Live OANDA user-reported position path described in `reports/V3_USER_REPORTED_POSITION_2026-11-16.md`. It records an explicit user statement about a position already opened outside BlazerOS; it does not create orders, broker fills, or lifecycle transitions.
- Independent exact-diff review **PASS**; primary focused **56/56**, isolated full Swift **651/651 across 17 suites**, final iPhone simulator UI **1/1**, integrated primary Release simulator build **PASS**, exact allowlist hashes match, and `git diff --check` passes.
- The only compiler/build warning in the new run is Xcode’s App Intents metadata extraction skip because no `AppIntents.framework` dependency exists. UI automation still shows the documented simulator WebKit/WebCore duplicate-class diagnostic; earlier source warnings and the AVAudioSession hang-risk warning are fixed.
- V3 remains **PARTIAL**. Next highest-priority durable-evidence work is genuine V3 entry-evidence production, followed by position-close and outcome writers. Physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open.


## Continuation update — Live V3 entry observation — 2026-11-16

- Completed and integrated the next highest-priority durable-evidence slice: the selected-pair Live OANDA FX monitor records one `.observed` hypothetical market entry reference only for the exact persisted ORB plan. Receipt-time provenance, preregistered entry tolerance, executable-side/stop/target/spread/freshness checks, root-serialized exact-plan append, path-safe identity, and generation/pair/FX/scan/Live-session gates are covered.
- Independent exact-diff review **PASS** after it caught and the implementation fixed a timestamp conversion trap and missing Live-session recheck in the serialized append gate. Timestamp overflow and session changes have focused regressions.
- The implementation creates no order, fill, position, lifecycle transition, user report, or outcome. Trade and Review explicitly label the record a hypothetical market reference. Entry-write failure leaves the plan/lifecycle projection intact.
- Primary integrated `swift test`: **653/653 across 17 suites**. iPhone 17e simulator build **PASS**. `git diff --check` **PASS**. All 16 allowlisted paths byte-match the reviewed sidecar. A targeted UI test could not yield a result because Xcode exited 75 while saving its result log (zero tests reported); this UI workflow remains unverified.
- No Swift compiler warnings remain in the full Swift run. The device-specific Xcode build emitted the known App Intents metadata skip because the app has no App Intents framework dependency; no App Intents dependency was added. The generic simulator placeholder diagnostic is also tool-generated.
- Goal remains **PARTIAL**. Next durable lifecycle gap: production position-close and structural outcome writers, using the `.observed` entry reference only as a shadow-market anchor and preserving simulated/shadow outcome quality. Other open gaps include physical-device recovery/accessibility/performance, UI workflow coverage, owner-signed promotion, exact-SHA CI, and signed distribution.


## Continuation update — Live shadow structural outcome — 2026-11-16

- Completed the next bounded outcome slice. The selected-pair Live monitor now records one `.simulated` structural stop/target result for an exact persisted Live ORB plan and its `.observed` entry reference. It reports a “first sampled stop/target trigger,” not an actual position close or proof of the first continuous market touch. Untriggered sparse polls remain open.
- The store revalidates the persisted entry against the plan, checks entry/exit freshness independently at each observation’s receipt, and applies a strict cutoff at terminal setup lifecycle source time. Per-root locking allows one terminal outcome per plan; exact retries are idempotent and conflicting results fail. Generic entry/outcome writes are rejected for `live-oanda`.
- Independent exact-diff review **PASS** after corrections for stale-entry timing, direct Live archive bypasses, plan-band revalidation, and preserving the existing ForwardTest/replay evaluator default. Primary focused structural suite **18/18**, full Swift **663/663 across 17 suites**, iPhone 17e simulator build **PASS**, targeted Review UI **1/1**, and `git diff --check` **PASS**.
- The only `warning:` line in the device-specific Xcode build is the App Intents metadata skip because the app has no App Intents dependency. No Swift compiler warnings remain; the generic simulator placeholder notice is avoided with the installed simulator destination. The prior targeted UI result-save failure did not recur.
- No actual position close is recorded by this slice. The next durable gap is an explicit position-close evidence contract, separately distinguishing user-reported close from broker-confirmed close. Physical-device recovery/accessibility/performance, owner-signed promotion, exact-SHA CI and signed distribution remain open. STRIKE V3 remains **PARTIAL**.


## Continuation update — user-reported position close — 2026-11-16

- Implemented and integrated a distinct user-reported close record bound to the exact opening revision and persisted plan. Corrections preserve that opening reference; store validation enforces same-root serialization, close chronology where known, and rejection of a claimed close time more than one second in the future. Review keeps manual/unverified/not-broker-confirmed provenance visible and accessible.
- Independent exact-diff QA **PASS**. Primary focused close tests **6/6**, domain contracts **15/15**, full Swift **671/671 across 17 suites**, iPhone 17e full test plan **33/33** (27 unit + 6 UI), and `git diff --check` **PASS**. The close-correction UI failure was a fixture ordering error: it attempted a close before the entry time in the latest revision. The fixture now creates a V3 plan identity, records the close against the original opening before the later entry correction, and the test targets the visible switch control and asserts its On state. Targeted correction UI **1/1** and the full plan pass.
- Warning status: no Swift compiler warnings remain in the full Swift run. Xcode still emits a metadata-extraction warning for `BlazerUITests`, which does not implement App Intents; the shipping app’s separate `BlazerIntents` target is present. Simulator logs print WebKit/WebCore duplicate-class and debugger-version lookup diagnostics; the xcresult records zero runtime warnings. AVAudioSession hang-risk, actor-isolation, deprecated Text composition, and package duplicate-class source warnings remain fixed.
- V3 remains **PARTIAL**. Next evidence work: define genuine broker-confirmed close synchronization or mark its required broker evidence/authorization gate explicitly; then physical-device recovery/accessibility/performance, owner-signed promotion, exact-SHA CI, and signed distribution. This user-reported close remains manual/unverified and adds no broker synchronization or order capability.


## Continuation update — broker-close source audit — 2026-11-16

- Independent source/contract reviews found no transaction, trade/position, account-changes, transaction-cursor, or close-fill path in the local OANDA client. It currently provides pricing, streamed pricing, and candles. Sampled market crossings remain simulated evidence and cannot write a broker-confirmed close.
- **BLOCKED (specific producer):** production broker-close synchronization needs authorized read-only Practice activity access, a verified endpoint/schema, account/environment binding, transaction identity and cursor/replay semantics, partial-close and residual-unit reconciliation, and restart-safe fixtures. Existing user-reported close remains a distinct manual assertion. No credentials or broker calls were used.
- Next eligible work remains durable V3 lifecycle/Review integration and contextual Coach evidence behavior; physical-device evidence, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open. Overall STRIKE V3 is **PARTIAL**.
- Warning follow-up: a fresh, non-quiet iPhone 17e test build succeeded, but `ENABLE_APP_INTENTS_METADATA_GENERATION=NO` did not suppress Xcode metadata extraction; five targets emitted the no-`AppIntents.framework` warning. No Swift compiler warnings remain in the latest full Swift suite. The failed opt-out is recorded in `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`; no dummy framework or no-op build setting was added.
- Coach §4.4 design challenge passed for a bounded Review inbox showing only linked user-reported close reports with missing exit facts. The inbox is integrated and verified in primary: focused tests **4/4**, full Swift **675/675 across 17 suites**, iPhone 17e plan **33/33** (27 app + 6 UI), exact reviewed hashes, and `git diff --check` **PASS**. V3 Coach Q&A context remains legacy-only; next work is bounded V3 context and individual-record citations. Broker-confirmed close production is **BLOCKED** on missing authorized activity access/schema/account binding. Overall STRIKE V3 remains **PARTIAL**.


## Continuation update — selected V3 Review insight brief in Coach — 2026-11-16

- Added a per-insight “Explain in Coach” action backed by a dedicated deterministic, read-only brief. It shows the same-source local archive snapshot, exact plan/close/opening citations and evidence rows, missing fields as unavailable, and manual/unverified/not-broker-confirmed provenance. The ordinary Coach path remains unchanged; the brief never invokes model, voice, legacy Q&A, market, performance, or broker context.
- Before showing facts, the route reloads the selected archive and uses an uncapped targeted lookup; the full projected insight and evidence must equal the original. Stale, loading, empty, and unavailable states carry no insight values. Focused tests cover live/proxy qualification, same-ID payload change, completed correction leaf, an insight beyond the six-card display cap, source mismatch, and non-ready archive states.
- The simulator fixture is compiled only for DEBUG+simulator. It uses a process-specific temporary storage root, bypasses App Group migration for that exact launch flag, and seeds a stable plan/opening/incomplete close without credentials, OANDA, or order paths. Normal/archive storage behavior is unchanged.
- Independent design challenge **PASS**; independent exact-diff QA **PASS**. Primary focused Swift route/projection tests **8/8**; primary iPhone 17e handoff UI **1/1**; isolated reviewer `swift build` **PASS**; `git diff --check` **PASS**; five integrated hashes are recorded in `reports/V3_COACH_SELECTED_INSIGHT_BRIEF_2026-11-16.md`.
- One earlier failed UI attempt used the regular report form and wrote test opening/close records into the simulator App Group before failing at the nested action. Those records were preserved without deletion or correction. The accepted test now uses the process-isolated root. Latest accepted xcresult reports zero runtime warnings; command output still has known simulator WebKit duplicate-class/debugger messages. Swift/compiler warning status and the App Intents metadata notice remain as recorded in `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`.
- STRIKE V3 remains **PARTIAL**. General V3 Coach Q&A/citation integration remains open. Broker-confirmed close production remains blocked on authorized Practice activity access and a verified reconciliation contract. Other open requirements include physical-device evidence, owner-signed strategy promotion, exact-SHA CI, and signed distribution.


## Continuation update — deterministic Coach questions for selected close insight — 2026-11-16

- Added five fixed question intents to the already revalidated single-insight brief: missing details, what the user-reported close record establishes, broker confirmation, linked plan/close/opening references, and opening supersession. There is also a closed unsupported-intent response and no free-text field.
- Every response is a pure mapping from the selected `.ready` insight. It uses source-qualified citations to supporting close/opening records; the plan ID remains a binding reference. The answer explicitly says a manual close report does not establish an actual close, execution, or fill. Nonready routes have no answers or question controls; changing to a nonready state clears the selection. Generic Coach, Apple Foundation Models, AssistantSession, legacy fallback, network, and mutation paths are unchanged.
- Independent design challenge and exact-diff QA **PASS**. Primary focused Swift tests **11/11**, iPhone 17e UI **1/1**, independent package build **PASS**, primary `git diff --check` **PASS**. Primary test bundle `/tmp/v3-primary-coach-insight-derived/Logs/Test/Test-BlazerOS-2026.11.16_17-50-54--0800.xcresult` reports zero runtime warnings. Exact integration hashes are in `reports/V3_COACH_INSIGHT_QUESTION_INTENTS_2026-11-16.md`.
- General natural-language V3 Coach Q&A remains **PARTIAL** and open. STRIKE V3 remains **PARTIAL**. Physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open; broker-confirmed close production is blocked on authorized Practice activity access and a verified reconciliation contract.
- Physical-device availability check (`xcrun devicectl list devices`) found the user iPhone 16 marked unavailable; no physical-device install/acceptance evidence was produced. The iPhone 17e tests are simulator evidence only. Next software gap is a bounded general V3 Coach question path; any model-backed version needs its own source-only request/validator/fallback design. Natural-language V3 Q&A remains open.

## Continuation update — Mac evaluator diagnostics — 2026-11-17

- Following the user's Mac-first direction, added a source-bound, quote-expiring diagnostic row for each connected Mac research evaluator (ORB, Candidate001, Candidate002). Empty completion, ORB conditions-not-met, validation-withheld candidates, and evaluator failure remain distinct. Allowlisted reason labels prevent raw error text or direction/plan/price fields from entering the diagnostic. Stale quote, invalid timestamp, mismatched source identity, and superseded generation fail closed.
- Summaries clear on refresh, app background, and withdrawal. The Trade decision, plan, CTA, notification, and order paths are unchanged. The Mac-only card retains “RESEARCH ONLY · NOT PROMOTED · NO ORDER” and scrolls details for enlarged text. Independent debate, three-round design challenge, and exact-diff QA passed.
- Primary verification: focused Mac diagnostics **16/16**, Release `BlazerOS` product build **PASS**, `git diff --check` **PASS**. New signed staged bundle `dist/BlazerOS-Mac-staged-20261117T060819Z-92019.app` passed the source-manifest and code-signature checks. Runtime scan loaded OANDA Live candles, completed with no eligible research candidates, displayed Candidate001/002 empty-completion diagnostics and the ORB `before_opening_range` result, and kept Trade at `WAIT / NO TRADE` with no plan.
- Physical UI evidence is partial: the runtime screenshot was not at the minimum 1040×708 size, and VoiceOver was not exercised. Source geometry estimates standard-size fit; this is not runtime acceptance evidence. After the quote freshness bound passed, diagnostics cleared to “Awaiting fresh scan.”
- STRIKE V3 remains **PARTIAL**. The user's Mac scope takes precedence for the next implementation; iPhone Coach Q&A is not the active Mac deliverable. The next Mac strategy addition requires one owner-frozen GBP/JPY profile and complete rule values; profile freeze is still awaiting product input. Broker-confirmed close production, physical-device evidence, exact-SHA CI, and distribution gates remain outstanding.

- Final broad-suite audit after integration found one stale assertion in the untracked `StrategyResearchRegistryTests.swift`: the test expected adapter digest `9e505e38…`, while both the pinned implementation constant and SHA-256 of `AdaptiveOpportunityAdapters.swift` are `e1870e51…`. Updated only that expectation. The focused digest test then passed and the full Swift suite passed **700/700 across 17 suites**. `git diff --check` and whitespace scans on the untracked Mac diagnostic/test files passed.
- Current staged Mac runtime recheck reached OANDA Live `6/6`. It reported no candidates: ORB's opening range had not formed, Candidate001/002 emitted none, and Trade remained `WAIT / NO TRADE` with no plan or orders. The current Release `BlazerOS` product rebuild passed in 121.46s with no compiler warnings. Minimum-window and VoiceOver acceptance remain open; next strategy-family integration still requires an owner-frozen profile and complete rule values (`reports/MAC_RESEARCH_SIGNAL_DIRECTION_2026-11-16.md`).
- Minimum-window follow-up: both staged processes remain alive but expose zero Accessibility windows; the UI bridge timed out, and LaunchServices activation did not reopen one. Source declares 1040×708 minimum and a fixed 160pt diagnostics region, but no runtime layout or VoiceOver claim is made without a window. No speculative UI changes were made (`reports/MAC_RESEARCH_SIGNAL_DIRECTION_2026-11-16.md`).
- Resolved the minimum-window evidence gap using the enabled File → New BlazerOS — Lightning Desk Window command. AX resized the staged window to 1040×736 including title bar (1040×708 content); a completed OANDA Live 6/6 scan showed all three diagnostics, the pinned research/no-promotion/no-order header, and lower cards without clipping. AX exposed evaluator labels/status values; Trade stayed WAIT with no plan/orders. Minimum-size visual/layout acceptance is verified; VoiceOver and enlarged-text operation remain open (`reports/MAC_RESEARCH_SIGNAL_DIRECTION_2026-11-16.md`).
- Targeted GBP/JPY runtime check found the existing SCAN intentionally walks all six markets, then `pickedSignal` may move the displayed pair to another asset; only that picked asset gets Candidate001/002 diagnostics. Debate confirmed this is a Mac research usability gap. Implemented the separate Mac `SCAN <pair>` action while preserving `SCAN ALL 6`; it captures pair at click time, rejects stale pair/mode before scheduling, and uses the existing pipeline/gates. Focused tests passed 5/5, Release product build passed without compiler warnings, signed staged app showed the selected pair and `1/1`, and independent review passed. The staged app stayed `OANDA LIVE · CONNECTING` with Quote unavailable, so fresh authenticated scan acceptance remains partial; changing pair cancelled the pending request, and no order was submitted (`reports/MAC_RESEARCH_SIGNAL_DIRECTION_2026-11-16.md`).
- Follow-up inspection of the same signed process showed OANDA Live connected with a 0–1s quote and 120 live USD/JPY candles. Trade still correctly returned WAIT with `no_strategy_passed_live_promotion_gate`; ORB reported `before_opening_range`. `StrategyResearchRegistry.productionPromotionRecords` is explicitly empty, so there is no production-eligible profile. The earlier connection delay was transient, not the durable signal blocker. Do not bypass the promotion gate or claim that an unpromoted evaluator is a Live signal. The pair-only manual scan's fresh-data terminal acceptance remains open; evidence and the recommended owner-approved profile/campaign path are in `reports/MAC_RESEARCH_SIGNAL_DIRECTION_2026-11-16.md`.
- The user selected GBP/JPY London Break + Retest as the first family to validate. Its evaluator is implemented, but complete parameters are intentionally mandatory. Existing Practice bid/ask archive covers only Nov 1–12, 2026 and does not prove campaign readiness; a bounded 120-hour Practice history probe returned HTTP 401 for both M1 and M5 and saved no data. The next research dependency is a valid authorized history source. Any Live-history route must be a separate read-only, environment-labeled archive. No Live promotion or thresholds were fabricated.

## Continuation update — Live research archive integrity — 2026-11-17

- A provenance audit found that the new Live-history archive digest covered candle batches but omitted the outer request/retrieval metadata. Corrected the digest to cover the complete canonical archive envelope and candle batch. Archive reads also compare duplicated instrument, granularity, and requested interval to the contained batch, require M1, validate retrieval time, and recompute the gap count.
- Added a corruption regression that changes `includeFirst` while preserving the candle batch; the archive now rejects it as invalid. A URLSession protocol stub verifies the Live host/path and bounded M1 bid/ask query without contacting OANDA. Archive append requires an opaque in-memory receipt issued by a successful Live fetch; it binds `includeFirst` and actual response receipt time, and hand-built/decoded batches cannot be passed as verified captures or caller-stamped with a different retrieval time. Final focused `OandaHistoricalBidAskTests` passed **8/8**, full Swift suite **709/709 across 17 suites**, and Release `ForwardTest` build passed in **151.87s** with no compiler warnings. `ForwardTest --help` confirmed the explicit capture flags.
- The Mac Live capture remains explicitly user-initiated; no credentials or Live data were read. This archive path does not qualify or promote a strategy.
- STRIKE V3 remains **PARTIAL**. Broker-confirmed close remains externally blocked on authorized account-activity access and a verified reconciliation contract. User-reported close and simulated shadow outcomes remain distinct. Mac signal promotion remains blocked by the empty owner-approved promotion registry. Physical-device recovery/accessibility/performance, exact-SHA CI, and signed distribution remain open.

## Continuation update — SpotFX replay horizon identity — 2026-11-17

- Fixed a deterministic identity collision in unresolved fixed-horizon replay results. Unresolved record IDs now use the configured replay horizon, matching valid results; they no longer inherit `input.expirySeconds` when evaluating a different research arm.
- Added a two-arm regression (60s and 180s) using the same case with missing bid/ask entry data. Both outcomes stay unresolved and receive distinct IDs. Targeted regression **1/1**, complete SpotFX replay suite **3/3**, full Swift suite **709/709 across 17 suites**, `swiftc -parse`, and `git diff --check` **PASS**.
- The reconciliation table now correctly marks executable cost-adjusted Spot-60 evaluation as **PARTIAL**, not missing: the evaluator and tests exist, while authenticated campaign data and promotion-grade validation remain outstanding. Release `ForwardTest` build passed in this pass; production strategy promotion remains gated.

## Continuation update — UTC-day historical candle seam — 2026-11-17

- The current primary workspace sets `includeFirst=true` for every independent UTC-day M1 request, and the regression asserts every generated window includes its first candle. Independent source/design reviews agree this is required because OANDA defines the flag as controlling inclusion of the candle covered by `from`; `false` on later midnight chunks can omit that day's first candle. The archive validator assigns candles to half-open `[start,end)` windows and rejects a candle at `requestedTo`.
- Verification in the current primary checkout: focused `OandaHistoricalBidAskTests` **8/8**, full Swift suite **709/709 across 17 suites**, Mac Release `BlazerOS` build **PASS** in 130 seconds with no compiler warnings, and `git diff --check` **PASS**. No Live API request was made. The Mac strategy gate is unchanged: London Break + Retest has no owner-frozen profile or qualifying campaign, and the production promotion registry remains empty.
- OANDA's documentation does not clearly settle `to` inclusivity; any `sourceTime >= requestedTo` remains rejected. The isolated task worktree is stale for the archive and test source; preserve the corrected primary files and do not copy the stale versions over them.
