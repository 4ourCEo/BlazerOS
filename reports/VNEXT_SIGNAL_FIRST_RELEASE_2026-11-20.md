# BlazerOS vNext signal-first release — 2026-11-20

## Objective and release boundary

Build a Mac-first GBP/JPY signal engine using existing evaluators and OANDA market data, with historical replay, read-only OANDA Practice observation, clear signal lifecycle and reasons, and manual execution only. Protect iPhone regressions. Friday is a release assessment, not a promise of signal frequency or profitability. No unattended orders or Live orders are in scope.

## Baseline and preservation

- Starting commit: `fbbcae3e67e8148f24183ea561e25965197fa091` (`origin/main`, PR #35 merge).
- The current checkout is clean on `docs/consolidation-report-final`, one documentation-only commit ahead of `origin/main`. Its report update is PR #36; it is not the vNext implementation branch.
- Prior PR #36 required CI run 44140136957: iPhone build passed; Engine tests failed at `V3UserReportedPositionCloseTests.userReportedCloseChronologyOptionalFactsAndCorrectionPreserveOpeningRevision` (`invalidReport`, line 45); correctness check skipped. Against clean `origin/main` in `/private/tmp/blazeros-vnext-integration`, `swift test --scratch-path /tmp/blazer-vnext-baseline --filter userReportedCloseChronologyOptionalFactsAndCorrectionPreserveOpeningRevision` passed **1/1** after a clean 122.16s build. Treat the CI failure as unreproduced/intermittent until explained; it is outside signal-first scope.
- No worktree, credentials, archives, generated exports, or user data have been modified for vNext. Debate was read-only.

## Phase 1 — Debate (complete)

Four bounded reviews examined strategy/evaluator code, research evidence, runtime path, and independent QA boundaries. Key evidence:

1. **Visibility is partly implemented already.** `MacResearchSignalProjector` can show eligible, fresh, exact-identity shadow candidates independently from Live promotion, but it accepts only `OANDA-LIVE`. The Practice card uses a separate persisted rehearsal path.
2. **Coverage is incomplete.** The Live selector evaluates ORB, Candidate001/002, and four Legacy policy variants. The Practice rehearsal runs the Legacy variants and ORB. Neither path runs GBP/JPY London Break + Retest, Trend Pullback, or Range Rejection. The registry has no production promotions.
3. **Diagnostics can hide evaluator failure.** Legacy evaluator exceptions are caught and skipped. Candidate001/002 failures are tracked, but current UI lists only ORB, Candidate001, and Candidate002. Adapter convenience APIs can collapse failure to an empty candidate list. The deterministic selector is not adaptive strategy/timeframe ranking; Candidate001/002 use equal fixed scores.
4. **Replay mechanics are not market evidence.** Existing deterministic fixtures exercise positive and negative evaluator behavior. The reviews found no authenticated positive GBP/JPY replay on a frozen production profile. The user-selected London Break + Retest evaluator requires an explicit configuration and has no default; the available Practice archive was previously assessed as insufficient/unauthenticated for campaign readiness.
5. **Practice and execution boundary.** Existing Practice rehearsal is read-only. No OANDA order-submission endpoint was found in source. A current authenticated GBP/JPY Practice scan has not been verified. Manual order testing must be initiated by the user in the Practice broker UI and reconciled only against actual broker evidence.
6. **Safety and durability.** Current research signals are display-only and expire in memory. Persistent Practice rehearsal records exist, but the proposed signal transitions/notifications are not a durable lifecycle ledger. The 1% risk maximum is a new cap; existing generic research math is not an FX order-size guard.

**Debate decision:** solve both evaluator coverage/diagnostics and candidate projection. Do not loosen eligibility, invent thresholds, equate no-candidate with no-setup, treat synthetic fixtures as strategy evidence, or mix Live and Practice data.

**User clarification — 2026-11-17:** Research evaluators must be invoked by the GBP/JPY monitoring path and produce visible, useful candidate output; documentation and diagnostic-only status are insufficient. Live promotion must not gate research-candidate generation or visibility. Practice-plan preview remains separately gated by account/risk/data checks; Live approval stays separate.

## Phase 2 — Plan (resolved)

### Ranked scope

**P0 — trustworthy evaluation and outcome visibility**

- Freeze a typed scan/evaluator outcome contract before implementation: requested instrument, environment, scan generation/identity, source freshness, strategy/version/config identity, timeframe, completion state, safe reason codes, source evidence, and any supported candidate lifecycle state.
- Distinguish `NO_SETUP`, `FORMING`, `CONFIRMED`, `ACTIONABLE`, `DATA_UNAVAILABLE`, `EVALUATION_FAILED`, `EXPIRED`, `INVALIDATED`, and `NOT_CONFIGURED` where the evaluator can support those meanings. Keep lifecycle separate from research/Practice/Live authorization.
- Trace every already-configured applicable GBP/JPY strategy through data, evaluator, projection, and UI. Preserve each evaluator's completion, candidates, and errors. Clearly identify unconfigured/unsupported families instead of silently counting them as no setup.
- Invoke applicable existing GBP/JPY research evaluators in the Practice scan/replay path. For evaluators with configured profiles (including Candidate001/002 where their contracts permit), retain their actual candidates for signal generation. For evaluators without approved configuration, produce an explicit not-configured result and keep profile preparation active; do not silently omit them.
- Preserve the existing Live promotion and manual execution gates. Research display has no order authority.
- Run continuous observation only while the Mac monitoring service is active. Reuse the existing scheduler; ensure one in-flight GBP/JPY scan, bounded retry/backoff, session/market closure handling, reconnect status, and explicit last-quote/candle/scan/stop reason. Never treat connection loss as no setup.

**P0 — replay and Practice evidence**

- Add deterministic integration coverage for positive, negative, forming, stale/missing data, evaluator failure, withheld promotion, identity mismatch, and stale/superseded scan cases.
- Replay an authorized, labeled GBP/JPY dataset with the selected frozen profile; retain per-strategy/timeframe counts and source provenance. Synthetic fixtures verify code mechanics only.
- Add/verify a Practice-only, read-only observation path, keeping its provider/environment identity separate from Live. Require fresh bid/ask and completed candles, and show its scan outcome.
- Keep 1% as a hard maximum proposed risk. Do not show Practice-order eligibility until entry, stop, pip conversion, costs, margin, and fresh quote inputs are proven; missing values block the plan.
- Manual Practice order, if performed, is initiated by the user in OANDA Practice. Agent/app does not place it; broker state is separately reconciled.

**P0 — ranking and timeframe choice**

- Rank every valid comparable candidate and select only among timeframes each strategy declares as supported. Explain readiness/freshness/completeness comparisons, preserve alternatives and rejected candidates, and use a documented stable tie-break. Do not synthesize M3, compare uncalibrated probability/score fields, or force every evaluator onto every interval.

OANDA's official v20 API lists native M1, M3, M5 and M15 candle granularities ([instrument definitions](https://developer.oanda.com/rest-live-v20/instrument-df/), [API comparison](https://developer.oanda.com/rest-live-v20/api-comparison/)); evaluator support must still be declared per strategy. TradingView's current policy says its market data are licensed for display-only and disallows algorithmic decision use ([Terms of Service, Section 3](https://www.tradingview.com/policies/)), so it stays human visual review only unless separate rights are documented.

**P0 — lifecycle, expiry, and history**

- Persist signal transitions and scan evidence across restart; apply expiry/invalidity before display and ensure exact repeats are idempotent.
- Notify on forming, newly actionable, expired, or invalidated transitions with stable signalID+transition deduplication. If alert delivery cannot be verified, withhold notifications and record the release blocker rather than emitting repeat alerts.

### Exclusions

- No guaranteed signal count; no threshold changes or new strategy family to increase activity.
- No automated order placement, auto-entry/re-entry/reversal, or Live order path.
- No TradingView market-data dependency for machine decisions.
- No use of unverified Live data as Practice evidence, and no display of a research plan as a broker fill.

### Open blockers (do not guess)

- London Break + Retest was previously selected as the first GBP/JPY family, but no owner-frozen full configuration is recorded. The user authorized a subagent to derive a research-candidate profile; it must be based on labeled chronological training data and independently reviewed before replay/candidate eligibility claims. Synthetic test values are excluded.
- The authorized historical dataset and campaign-suitable length are not yet established; previous Practice historical requests returned HTTP 401. No new archive is accepted until it carries source/environment provenance.
- Authenticated GBP/JPY Practice runtime access and continuous observation have not been demonstrated. The installed app showed `Scan missed the book` with zero quotes/candles. Separately, the sanitized `scripts/oanda-practice-research.py` preflight (which reads its owner-managed local Practice config) returned `INVALID_TOKEN` / HTTP 401; it is not confirmed that this config is the same credential source as the installed app. Read-only observation may proceed only through existing credential flows, without exposing credentials/account IDs.
- The 1% cap needs verified GBP/JPY pip-value/conversion, spread/cost and margin inputs before it can certify a Practice proposal. Account risk values are not inferred.
- Friday acceptance may therefore be PARTIAL/NO-GO even if local engineering checks pass.

## Phase 3 — Design (reviewed)

### Shared result contract

Each scan observation binds to an immutable `scanID` and generation, requested instrument, data environment, provider/source identity, candle/quote timestamps, evaluator/config identity, and supported timeframe. `signalID` is stable across polls and excludes `scanID`; derive it from instrument, strategy/version, config digest, timeframe, direction, and strategy-defined setup identity. Store `scanID` on each observation/event so repeated scans update one setup without producing a new signal or duplicate alert.

Evaluator completion is one of `COMPLETED`, `FAILED`, `DATA_UNAVAILABLE`, `NOT_CONFIGURED`, or `UNSUPPORTED`. `COMPLETED` carries zero or more candidates, including explicit `NO_SETUP` only when the evaluator completed with valid inputs and no setup. `FORMING` is a candidate lifecycle outcome only when the evaluator provides source-backed unmet conditions. Quote/candle rules are timeframe-specific: consume only completed candles with correct grid/source identity; require quote freshness at each evaluation's `asOf`; reject stale/future/partial/gapped inputs rather than mapping them to no-setup.

Lifecycle transitions are monotonic: `FORMING` → `CONFIRMED` only when all strategy confirmation predicates pass; `CONFIRMED` → `ACTIONABLE` only while entry conditions, required plan fields, fresh executable bid/ask, and the strategy's entry window pass. Any active state can transition to `EXPIRED` by its declared expiry rule or `INVALIDATED` by a declared thesis-negation rule. Terminal states do not silently reactivate; a later setup gets a new strategy-defined setup identity. Identical observations are idempotent. Corrections are explicit events that reference the prior event; restart restores the last valid state and applies expiry before displaying current actionability.

Lifecycle (`FORMING`, `CONFIRMED`, `ACTIONABLE`, `EXPIRED`, `INVALIDATED`) is independent of use/authorization (`RESEARCH_CANDIDATE`, `PRACTICE_PLAN_PREVIEW`, `LIVE_APPROVED`) and execution (`NOT_SUBMITTED`, `USER_REPORTED`, `BROKER_RECONCILED`). `RESEARCH_CANDIDATE` means an existing evaluator actually produced a source-bound candidate that the app surfaces for review; it is active signal output, not a dormant diagnostics-only state. `PRACTICE_PLAN_PREVIEW` means display-only under a verified Practice identity and risk/data checks; it is never order permission. `LIVE_APPROVED` remains a separate stricter gate. No component in this task gets unattended order authority.

The requested 1% is a strict maximum of account equity per proposed trade, never a target. A Practice plan preview requires verified account equity, GBP/JPY pip-value conversion to the account currency, executable bid/ask, spread/cost model, stop distance, units, and margin availability; reject/withhold eligibility if any input is missing or the estimated worst-case loss exceeds 1%. Do not reuse unrelated generic research risk math. This integration currently displays valid plan fields, but does not calculate account-sized risk or margin; the signal panel explicitly labels that gap. It adds no order endpoint.

### Platform and recovery

- Mac is the first UI target. Keep the existing all-markets and selected-pair request identities; reject stale generations and pair/environment changes.
- Preserve the existing Practice rehearsal persistence and keep Live/Practice archives, credentials, result stores, and labels separate.
- On missing/stale/partial candles, failed evaluator, unavailable profile, persistence failure, or app restart, show a typed safe state; never downgrade to `NO_SETUP` silently.
- Expired/invalidated states are retained for history and removed from current actionable display. The existing adaptive notification path now keys repeated notifications by stable candidate ID and state kind, but full lifecycle-event persistence and async stale-notice cancellation remain follow-up work.
- Keep accessible labels for each strategy/timeframe/status and provide concise source-backed reasons. Avoid raw errors, unsupported prices, and uncalibrated probabilities.

### Independent design challenge

**PASS WITH AMENDMENTS.** The high-level design was accepted with requirements for stable signal identity, typed outcomes/lifecycle, supported timeframe handling, the 1% cap, and clear ownership. The integrated VNX-02 contract is deliberately a non-authoritative identity/evaluator snapshot; it contains no authorization, execution, or broker evidence claims. Independent review accepted it only under that boundary. The user clarified that configured research evaluators must actively generate GBP/JPY candidates in Practice/replay; the implementation now does that for Candidate001/002, and projection no longer requires a Live-promotion profile. Account-risk sizing, full lifecycle storage, and expanded strategy coverage remain open.

## Phase 4 — Checklist (approved for assignment)

| ID | Owner | Isolated worktree | Allowed scope | Acceptance evidence | Verification | Status |
| --- | --- | --- | --- | --- | --- | --- |
| VNX-01 | Supervisor | `/private/tmp/blazeros-vnext-integration` | `LightningDeskModel.swift`, report and integration | Active GBP/JPY Practice scan invokes configured evaluators, checks current scan before projection/persistence, binds source from Practice session | focused tests + source review | CODE COMPLETE; async persistence/notice race remains a hardening item |
| VNX-02 | Agent A — shared contract | `/private/tmp/blazeros-vnext-scan-diagnostics` | `SignalFirstContracts.swift` and focused tests | Stable setup identity, environment/provider storage namespace, evaluator/timeframe candidate references, safe reasons; no claimed authorization | 12 focused tests + independent review | INTEGRATED `d0dfeed`; accepted as non-authoritative snapshot only |
| VNX-03 | Agent B — strategy/replay path | `/private/tmp/blazeros-vnext-practice-evaluators` | Existing adaptive rehearsal/adapters and focused tests | Practice/replay invokes Candidate001/002; preserves no-setup, raw expired/unconfirmed conditions, failures, timeframe and plans; no profile invention | 42 focused tests + integration suite | INTEGRATED `dc02168`; broader GBP/JPY families still uncovered |
| VNX-04 | Agent C — projection/UI | `/private/tmp/blazeros-vnext-practice-projection` | Mac projector and focused tests; supervisor owns model/screens | Practice candidates visible without promotion profile; environment/provider pair is constrained; stage and valid plan preview are explicit | 18 focused tests + integrated build | INTEGRATED `2a66f21` plus supervisor UI wiring |
| VNX-05 | Agent D — safety/history | Not started | Lifecycle event store and account-risk calculator | Persist monotonic lifecycle; compute 1% cap from verified account/pip/margin data; no order submission | dedicated tests and review | NOT IMPLEMENTED; account-risk eligibility unavailable |
| VNX-06 | Supervisor | `/private/tmp/blazeros-vnext-integration` | Integration, report, release evidence | Mac/iPhone builds pass; genuine replay and authenticated Practice evidence; manual-only boundary | 72 focused tests; `xcodebuild` iPhone Simulator build | CODE CHECKS PASS; release evidence PARTIAL pending Practice auth, risk sizing, full lifecycle and strategy coverage |
| VNX-07 | Supervisor | Existing safe Practice credential/runtime flow | Read-only authenticated scan only; no order API | Fresh GBP/JPY scan with source freshness, per-evaluator outcome and monitor status | sanitized preflight and UI observation | BLOCKED at last check by HTTP 401; user said they will refresh token through existing settings |
| VNX-08 | Agent B — profile preparation | Research evidence review complete | Profile evidence matrix only; no evaluator implementation | Derive profile values only from authorized chronological training data; preserve user-selected London Break + Retest | independent strategy review and replay | NO defensible defaults found; current local archive is one hour and insufficient. Await refreshed Practice data; fixture thresholds not reused |

Agents report changed files, tests, commits and blockers; the supervisor integrates. Actual VNX-03 ownership was existing rehearsal/adapters and focused tests; VNX-04 owned the Mac projector/tests; supervisor owns `LightningDeskModel.swift`, Mac screens, notifications, and final integration. VNX-05 lifecycle/risk work is still open. VNX-08 completed the profile evidence audit but cannot derive values without sufficient authenticated history. Configured evaluators run while unconfigured families remain explicitly uncovered.

## Release acceptance

Friday is **GO** only if a genuine reviewed GBP/JPY replay candidate reaches the visible research surface with provenance; deterministic ranking selects among explicitly supported strategy/timeframe combinations and explains alternatives; negative/setup/forming/unavailable/failure results are distinguished; a fresh OANDA Practice scan is verified; risk inputs are complete and capped at 1% of account equity; no unattended/Live order path exists; and all affected Mac/iPhone regressions pass. Otherwise record **PARTIAL** or **NO-GO** with exact evidence gaps. A manual Practice broker order is not claimed unless the user initiates it and an actual broker identifier/status is reconciled.

## Execution log

- 2026-11-17: four-role Debate completed read-only. No credentials accessed, no broker requests or orders made, no source changes made.
- 2026-11-17: Plan resolved from user's release brief and Debate findings. Independent design challenge returned PASS WITH AMENDMENTS; amendments and non-overlapping task ownership recorded above.
- 2026-11-17: clean integration worktree created at `/private/tmp/blazeros-vnext-integration`, branch `vnext/gbpjpy-signal-first`, based on `origin/main`. Baseline focused CI failure rechecked locally and passed 1/1. Shared-contract worktree created at `/private/tmp/blazeros-vnext-scan-diagnostics`; VNX-02 assigned.
- 2026-11-17: user authorized subagent profile preparation and clarified research evaluators must actively generate candidate signals. A read-only profile evidence review found no prior owner-approved numeric values and the checked-in historical manifest has no raw candidate series; fixture values are explicitly synthetic and will not be reused as defaults. The OANDA Practice preflight returned sanitized `INVALID_TOKEN` / HTTP 401, blocking training data and fresh scan until the existing credential is refreshed. No credential was printed or accessed directly; no orders were made.
- 2026-11-17: credential-free archive verification found local labeled GBP/JPY Practice M1/M5 batches covering only 2026-11-12 20:46–21:46 UTC (60 M1 / 12 M5 candles); integrity verification passed, but the one-hour window is insufficient for London Break + Retest profile fitting or campaign evidence.
- 2026-11-17: read-only installed-app Practice scan confirmed Quote source was labeled OANDA Practice, but GBP/JPY returned 0 quote/0 completed candles and UI `ERROR Scan` / `Scan missed the book`; no HTTP status was exposed, and no credentials or orders were accessed. The user said they will refresh the Practice token using existing settings. No refreshed-token scan has yet been verified.
- 2026-11-17: integrated VNX-02 non-authoritative evaluator identity snapshot as `e44c10a`; the reviewed source deliberately makes no authorization, broker-execution, or trusted-receipt claims. Focused contract tests passed 12/12.
- 2026-11-17: integrated VNX-03 as `5c7f83c` and QA amendments as `4603bdc`. Practice/replay now invoke existing Candidate001/002 evaluators for GBP/JPY, preserve positive candidates, raw expired/unconfirmed reasons, no-setup vs data-unavailable/failure, namespace IDs, and mark incomplete plans CONFIRMED rather than ACTIONABLE. The positive Candidate002 replay is a synthetic pipeline fixture, not market evidence. Agent-focused suite passed 42/42.
- 2026-11-17: integrated VNX-04 projector as `b5c8ed9` plus source-binding fix `d3a8f37`. Projection accepts Practice candidates without Live-promotion profiles, binds source from the environment enum, withholds stale/spread/risk-invalid candidates, and exposes a validated preview separately from execution eligibility. Agent-focused projector suite passed 18/18.
- 2026-11-17: supervisor wired the current Practice scan to candidate projection and per-evaluator diagnostics, checks current scan/session before persistence/projection, filters restored records to valid Practice records, and changed the UI from blanket "research only" wording to strategy stage and plan details. Notifications deduplicate on stable candidate identity plus transition kind. Independent QA passed the caller-bound source/persistence review with residual asynchronous persistence/notification race risks documented.
- 2026-11-17: integrated focused verification passed 72/72 tests across adaptive rehearsal, selector/notification, Mac signal projection, and signal identity contracts. `xcodebuild -project iPhone/BlazerOS.xcodeproj -scheme BlazerOS -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` succeeded. Full test suite, installed Mac app verification, authenticated Practice scan, account-risk sizing, durable lifecycle store, and broader GBP/JPY evaluator coverage remain outstanding.
- 2026-11-17: repeated the sanitized OANDA Practice preflight after the user said they would refresh the token; it still returned `INVALID_TOKEN` / HTTP 401. No authenticated scan was run.
- 2026-11-17: rechecked the shared `/Users/thagreat/Desktop/Blazer` folder size: 2.2 GB total, including a 457 MB `archive`, 584 MB `blazerCT`, and an 801 MB vNext Swift build cache. No files or caches were removed.
- 2026-11-17: final focused suite passed 72/72 after the notification and projection updates; the iPhone Simulator build completed successfully (Xcode warned that multiple simulator destinations matched).
- 2026-11-17: implementation and report committed as `0fb9fc9` on `vnext/gbpjpy-signal-first`, pushed to `origin`, and opened as draft PR #37. No merge to `main` was performed because release-critical evidence and safety work remain incomplete.
- 2026-11-17: no order endpoint was invoked and no order was submitted. Release status remains PARTIAL pending refreshed authenticated Practice data, risk/margin calculations, lifecycle persistence, and integration of the other GBP/JPY strategy families.
