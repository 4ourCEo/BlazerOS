# BlazerOS STRIKE V3 — Product, Engine & Release PRD

**Status:** Proposed master product specification with implementation-reconciliation gates  
**Prepared:** November 3, 2026  
**Target:** `4ourCEo/BlazerOS` — native SwiftUI iPhone-first FX research platform  
**Audience:** OpenCode, 4our Enterprises OS engineering, independent QA and product owner  
**Document type:** Product Requirements Document (PRD), **not** an agent prompt  
**Decision rule:** Existing verified working code takes precedence over speculative redesign.  

> **Non-negotiable:** This project is trading **research and manual practice execution support**, not a profitable-signal guarantee, an autonomous trading bot or approval to risk the user's $500. Historical results, simulated fills, manually reported trades and broker-confirmed executions must always be distinct.

---

## 1. Executive decision

BlazerOS is pivoting from a **fixed 60-second, directional CALL/PUT-style research workflow** to a **structure-based spot-FX research workstation**. A qualifying setup produces an immutable, explainable **trade plan**: instrument, strategy version, market context, observed evidence, entry trigger, structure-based stop, target, risk budget, expected transaction costs, validity conditions and provenance. Setups can remain untriggered or invalidated. Trade duration is not arbitrarily fixed to one minute. Research compares structural exits and preregistered fixed-horizon alternatives rather than choosing outcomes retrospectively.

The app remains native and iPhone-first. The primary destinations are **Trade**, **Markets** and **Review**. **Coach** is contextual and read-only, with event-driven insights and evidence citations. **TradingView** is a candidate for Pine-based strategy prototyping, sophisticated external charts and hosted alert delivery. **OANDA Practice** remains the authoritative existing programmatic research feed; **tastyfx** is a separate manual/demo broker workflow candidate, with capabilities verified before integration. **NinjaTrader** is optional futures/order-flow research, not a required FX execution dependency. A **Rust** engine is an evaluated option against a pure Swift implementation; a rewrite must earn its adoption through correctness, maintainability and measured performance. **Jev** remains shadow research only unless measurable incremental out-of-sample value is established.

**Do not replace the original pinned JSCore V1 engine.** Preserve it as the reproducible control and keep legacy records readable, including crypto and OTC/binary-contract histories.

### 1.1 What success means

A user can receive a **forming-setup warning**, review a live and still-valid risk-defined plan on an iPhone, decide manually whether to trade in a supported **demo** broker, and later examine reconciled evidence that correctly identifies whether the setup triggered, which exit happened, execution costs, and what remains unknown. Review can compare V1 against V3 research on identical evidence; Coach can explain findings without inventing certainty.

This operational success does **not** prove profitable trading. Strategy promotion requires prospective, cost-adjusted, independent evidence with uncertainty and drawdown measures.

---

## 2. Current engineering baseline — reconcile before modifying

### 2.1 Latest user-supplied test report (not independently reproduced in this document)

| Workstream | User-reported status | Required independent proof |
|---|---|---|
| Full Swift package tests | **382 / 382 passing** | Exact branch, commit SHA, command, raw test log |
| Focused iPhone suite | **18 / 18 passing** | Simulator/device type, OS and command |
| V3 contract tests | Expanded **6 → 8** | Source paths, assertions and test manifest |
| Quote provenance | Future source timestamps; source/receipt inversion; out-of-order handling covered | Failure injection and real feed replay |
| Cross-instrument isolation | Cross-instrument outcomes tested | Concurrent-switch and stale-response replay |
| Pricing and plans | Bid/ask executable pricing and structural-plan validation tested | Realistic FX instrument and margin fixtures |
| Evidence uncertainty | Unresolved and proxy-evidence handling tested | End-to-end persistence/recovery trace |
| Test compilation | Two warnings removed | Exact clean build output |
| Diff hygiene | `git diff --check` passed | Exact worktree state |
| Physical iPhone | Offline; latest provenance-enabled build **not installed** | Install and inspect build identity |
| UI taps | Radar, late-entry receipt and Chart Focus **not covered** | UI automation plus physical acceptance |
| Forward collection | V3 Spot evaluator **not wired into ForwardTest persistence** | Durable collector-to-record test |
| CI/release | No CI run for exact clean commit; no TestFlight artifact | CI permalink, signed build, distribution |
| Performance | No physical Instruments report | CPU, memory, frame pacing, energy and latency measurements |

**Interpretation:** The recent report demonstrates meaningful test progress; it does not justify rebuilding validated contracts, declaring the release complete, or claiming that the user has installed the latest implementation. OpenCode must first verify the local repository and report discrepancies rather than relying on this PRD as proof.

### 2.2 Preservation gate

Inventory and protect the actual local branch, HEAD, tracked/untracked/ignored files, worktrees, remote refs, pending PRs, pinned JS engine, local configurations, test outputs and device deployment state. Never reset, clean, force-push, merge, stash, move or delete user changes without explicit authorization. New changes belong on a dedicated, isolated V3 branch/worktree with incremental checkpoints. A clean `git diff --check` is not proof of a clean commit.

Reconcile implemented functionality with the current product spec. Classify each feature **VERIFIED / PARTIAL / MISSING / BLOCKED**, supported by file/function, commit, test, and device evidence. Preserve already implemented functionality rather than replacing it.

### 2.3 Immediate high-priority blockers

1. Wire the existing V3 Spot evaluation results to **durable ForwardTest persistence** without loss of provenance or cross-instrument isolation.
2. Complete and automate **Radar**, **late-entry receipt**, and **Chart Focus** UI interaction tests.
3. Produce a **clean exact commit**, then run CI on that precise SHA.
4. Install the provenance-enabled app on the **physical iPhone**, validate build/engine/config identity, and perform manual workflow acceptance.
5. Profile performance on physical hardware with Instruments and preserve a signed reproducible distribution artifact.

These are not optional merely because strategy research is evolving.

---

## 3. Three rounds of design debate and final decisions

### Round 1 — Does each existing screen earn navigation space?

| Legacy screen | Unique value | Problem | V3 decision |
|---|---|---|---|
| Scan | Setup analysis, chart and trade decision | Fixed-expiry semantics; unclear score/time freshness; controls need verification | **Trade**: primary screen, retain reusable SwiftUI code |
| Radar | Cross-instrument opportunity discovery | Decorative sweep and duplicated quotes can obscure evidence | **Markets**: real measurable surveillance and alert readiness |
| Intel | Comparative research, sessions, evidence | Legacy OTC and prime-window assumptions; duplicated metrics | **Review / Research** section |
| Coach | Contextual explanations and debrief | Static lessons and a dedicated tab create navigation overhead | **Contextual Coach**, available throughout |
| Journal | Persistent trade history and performance | Binary hit/miss framing inadequate for spot-FX | **Review / Trades**, preserving all records |

**Decision:** Three primary destinations: **Trade, Markets, Review**. Coach is cross-cutting. Strategy Lab is a secondary editor, not a fourth bottom tab. No existing data or useful services are deleted as a consequence of navigation changes.

### Round 2 — What can be bought, reused, or integrated?

| Candidate | Potential value | Constraint | Decision |
|---|---|---|---|
| Full TradingView service | Advanced chart research; Pine prototyping; hosted alerts; supported broker trading interfaces | External alerts are not guaranteed; alerts are not broker fills; external charts have different data feeds | **Use as externally integrated research/notification accelerator**, not ground truth |
| TradingView Lightweight Charts | Compact chart rendering | It is not full TradingView and lacks hosted Pine/alerts; WKWebView and native-UX tradeoffs | **Optional prototype against existing native chart**, no forced renderer swap |
| OANDA Practice | Existing feed, bid/ask, completed candles, practice record reconciliation | Stream may sample prices; venue-specific spreads and partial observation | **Keep primary programmatic research evidence** |
| tastyfx account | Existing manual/demo execution option; TradingView broker connection | API permissions, fills, funding, units and exports must be verified; not interchangeable with OANDA | **Separate broker adapter / manual evidence source** |
| NinjaTrader | Futures footprint/volume/order-flow research | Windows-oriented NinjaScript, futures ≠ spot FX, data/licensing complexity | **Optional isolated R&D** |
| NautilusTrader | Event-driven backtesting/risk/order simulation | Framework complexity, licensing, current provider/FFI/API suitability | **Research infrastructure evaluation only** |
| Rust | Strict portable state machines, repeatable replay, potential performance | Toolchain, Swift FFI, ABI, release complexity; no inherent forecasting advantage | **Benchmark a thin vertical slice vs Swift** |
| Jev | Structured evidence classification and failure triage | No demonstrated trading edge; inference quality/calibration must be validated | **Shadow classifier, no execution authority** |
| Apple Foundation Models | On-device natural language analysis | Context and OS/device limits; hallucinations | **Bounded read-only Coach**, no risk/order calculations |
| Swift Snapshot Testing | Automates layout regressions | Screenshots don't prove tap flows | **Adopt for approved iPhone screen states** |
| Swift Async Algorithms | Backpressure, stream transforms | Unnecessary library use can complicate pipeline | **Use only where telemetry or correctness warrants it** |
| QuantStats | Research report generation | Depends on trustworthy outcome data | **Optional Mac-side report layer** |

### Round 3 — Can this be relied on during a daily practice session?

- An alert can precede the trade **only if a real setup is forming**. Never fabricate lead time to meet a schedule.
- A strong engine score is **not** a winning probability or proof of executable opportunity.
- A trade plan is **not** an order, and a user-entered trade is **not** a broker-confirmed fill.
- An on-device timer is **not** proof a broker SL/TP fired or a position closed.
- Missing observations must remain **unresolved**, not assumed profitable or losing.
- $500 risk budgets constrain planned exposure; they are not a mandate to earn a fixed amount every day. Planned stop losses are not guarantees against slippage.
- Source-specific prices, commissions, account permissions and trading sessions must be modeled separately for OANDA, tastyfx and TradingView.
- The app must work when Coach, Jev, push notifications, or external TradingView alerts are unavailable. No AI or notification delivery may bypass deterministic gates.

**Architecture decision:** A small auditable strategy and risk core plus one authoritative evidence ledger, with modular adapters and three focused native destinations. Build quality first, validate strategy edge separately.

---

## 4. Product experience and user flows

### 4.1 Trade (primary destination)

**Job:** Inspect market structure and prepare a supported, risk-defined trade plan.

Required content: instrument, feed identity and quote freshness; readable multi-timeframe chart (M15 context, M5 setup, optional M1 confirmation; research M3/H1 variants); selected versioned strategy; structure levels; setup phase; exact remaining conditions; entry trigger/zone; structural SL/TP; expected spread/cost, R multiple, position units, margin feasibility and invalidation; clear scan/research action; recent relevant evidence; accessible Chart Focus and late/manual-entry receipts.

State names: `UNAVAILABLE`, `WATCHING`, `FORMING`, `APPROACHING`, `CONFIRMED`, `TRIGGERED`, `INVALIDATED`, `EXPIRED`, `UNRESOLVED`. Treat any broker position as a **separate lifecycle**. Never show contradictory EXPIRED and actionable states. Label what refreshed: market data versus last strategy evaluation.

### 4.2 Markets (Radar evolution)

**Job:** See where measured, potentially interesting setups are forming across supported FX instruments.

Rank observations by preregistered, measurable features such as proximity to a known structural level, setup completion, bid/ask spread, quality/freshness, and current regime; **do not** imply model scores equal predicted profits. Radar's 6–8s sweep is a visual aesthetic, not a data source. Stable instrument positions, source-grounded statuses, reduced-motion fallback, zero perpetual offscreen animation, straightforward pair-to-Trade deep link. Testing must verify taps and cancellation across instrument switches.

### 4.3 Review (Journal + Intel)

**Trades:** Immutable plan and broker-position timelines; setup evidence and outcomes; reconciled entries, exits and costs; account/simulation provenance; retained historical binary/crypto records in a labeled archive; export.  
**Performance:** Prospective net expectancy, return in R, profit factor, drawdown, adverse/favorable excursion where evidence permits, actionability, latency, fill mismatch, missing outcomes and uncertainty.  
**Research:** V1/V3 comparisons on matched observations; instrument/session/regime slices; predefined acceptance and stopping rules; configuration registry and reproducible dataset hashes. No mixed synthetic, midpoint or broker-confirmed statistics.

### 4.4 Contextual Coach

Accessible from each destination, as a sheet and/or contextual action, with a bounded Insights inbox in Review. Deterministic retrieval/calculation tools, citations back to individual records, explicit uncertain/unavailable responses, conservative notification defaults, no direct modification of risk or broker state, no placing orders. Preserve current Apple Foundation Models and deterministic fallback. Jev candidate isolated behind research interfaces.

### 4.5 Settings and diagnostics

Show exact app version, build number, Git SHA, strategy/config hashes, pinned V1 engine SHA, broker environment, active data provider, last source receipt, alert monitor status, diagnostic export and privacy-preserving support package. Never display or log API secrets. Separate practice and live access unmistakably; V3 does not authorize real-money execution.

---

## 5. Core engine specification — essential redesign, not patches

### 5.1 Primary design change

Replace the single-score/next-candle prediction contract with deterministic, **versioned strategy hypotheses** that advance through explicit event-driven states and produce a plan only on valid evidence. No strategy is permitted to use future candles, future quotes, outcomes or AI assessments to form a historical decision. The original JavaScriptCore engine is a preserved reference, not modified in place.

### 5.2 Shared architecture contracts

Define stable schema/versioned objects (names illustrative; align to existing contracts rather than duplicating):

- `MarketObservation`: provider, venue/account type, instrument, bid/ask, source/receipt timestamps, candle completion, spread and quote quality; monotonic sequence or equivalent ordering.
- `InstrumentSpec`: pip/tick size, decimal precision, base/quote currencies, minimum units, margin rules, trading hours, order features and broker-specific constraints.
- `StructureSnapshot`: confirmed swing highs/lows, preexisting range boundaries, higher-timeframe directional context, volatility/normalization and definition version.
- `StrategyConfig`: strategy ID/version, parameters, allowed instruments/regimes/timeframes, entry confirmation, invalidation/stop/target policy and registered evaluation horizon.
- `SetupCandidate`: originating snapshot hash, evidence IDs, pre-trigger level, deterministic phase, creation/expiry conditions and confidence semantics (not winning probability).
- `TradePlan`: immutable identity, source and config versions, intended entry side/zone/trigger, structural SL/TP, spread/slippage assumptions, risk budget, sized units/margin, no-trade/rejection reasons and creation timestamp.
- `PositionRecord`: separate user report versus broker-confirmed IDs/fills, trade side, quantity, protective order status, reconciliation status, fees and realized/unrealized result provenance.
- `EvaluationOutcome`: executable quote observations, first supported TP/SL event, costs, duration, R, resolution quality (`confirmed`, `proxy`, `unresolved`, `ambiguous`) and source IDs.
- `ResearchCampaign`: immutable hypothesis definitions, training/validation/test windows, embargo or split method, datasets and code hashes, pass/fail thresholds.

Prefer typed prices/units and checked arithmetic over unstructured doubles across instruments. Ensure schema evolution and migration for existing local records. Each event must retain enough information for deterministic replay.

### 5.3 Strategy candidates and objectively testable rules

**A. Auction Failure Reversal**

1. Derive a prior range from **completed** observations and a preregistered swing/range method; freeze boundaries before an attempted break.
2. Detect a price excursion beyond the boundary meeting minimum distance/volatility and quote-validity requirements.
3. Detect failure by a defined return into the prior range and a documented confirmation event (e.g., completed candle close/retest); do not enter immediately on an unconfirmed wick.
4. Require acceptable spread, data freshness, structural invalidation distance, risk/margin and room to target.
5. Set side and entry trigger from confirmation; stop beyond the frozen failure extreme plus a preregistered buffer; target a preregistered range level (e.g., midpoint or opposite boundary) only if valid and positive risk/reward.
6. Invalidate if acceptance outside the range is established, the setup ages out, market quality deteriorates, or prerequisite structure changes.

**B. Breakout + Acceptance**

1. Establish a range or key level using only previous completed data.
2. Detect an initial break meeting minimum displacement and measured regime criteria.
3. Require acceptance by deterministic confirmation: defined time/bars beyond the level, or a valid retest and hold; do not treat first crossing as proof.
4. Position entry, stop and target from frozen structure; prohibit target-selection hindsight.
5. Explicitly reject false breaks, wide spreads, insufficient expected movement and invalid risk.

**C. Trend Pullback Continuation**

1. Define trend/regime from higher-timeframe structure using a registered sequence of confirmed swing points; no repainting swings with future data.
2. Identify pullback zone relative to confirmed impulse/structure and volatility; exclude arbitrary percentage retracements unless prospectively tested.
3. Wait for completed lower-timeframe confirmation and a defined continuation trigger.
4. Set stop beyond structural invalidation and target a preregistered prior extreme/extension or risk multiple, selected in advance.
5. Invalidate on structure break, insufficient movement-to-cost ratio or stale evidence.

**Implementation note:** The above are formal **algorithm design requirements**, not hard-coded profitable parameter values. M0/M1 research should register exact thresholds, bar counts, tie rules and stop buffers with robust tests *before* scoring performance. No algorithm may claim futures delta, actual absorption, institutional inventory, iceberg orders or volume-at-price from OANDA OHLC/quotes alone.

### 5.4 Setup and position state machines must remain distinct

**Setup:** `WATCHING → FORMING → APPROACHING → CONFIRMED → TRIGGERED`, with branches to `INVALIDATED`, `EXPIRED`, or `UNAVAILABLE`. No invalid backward transitions or resurrection after app suspension. A setup trigger is not a fill.

**Trade plan:** `DRAFT → VALIDATED → OFFERED → TRIGGERED/INVALIDATED/EXPIRED`; immutable sealed snapshot once offered, subsequent changes represented as new version/events.

**Position:** `NOT_OPEN → USER_REPORTED → BROKER_PENDING/UNCONFIRMED → BROKER_OPEN → EXIT_REQUESTED → BROKER_CLOSED`, with separate `RECONCILIATION_REQUIRED`, `UNKNOWN`, and correction paths. Research-only shadow positions are separate entities. A broker-confirmed order and a plan's proposed order are different things.

Transition tests: duplicate events, out-of-order quotes, instrument switch, delayed responses, force quit/relaunch, corrupted records, partial fills, cancellations and actual broker corrections.

### 5.5 Broker-aware executable evaluation

- Long positions open at ask and close at bid; shorts open at bid and close at ask; correctly respect account currency, lot/unit conversions and quoted pip conventions.
- Include spread, commission, financing if relevant, modeled slippage and any explicitly assumed costs. Preserve **quoted** versus **filled** prices separately.
- Structural stop and target evaluations require sufficiently granular, time-aligned bid/ask observations and first-event ordering. When both could be touched between two observations or during one candle, outcome is `AMBIGUOUS`, not the favorable outcome.
- Unobserved exit or missing evidence is `UNRESOLVED`. Midpoint-only results are `PROXY` and excluded from executable net expectancy.
- Source/receipt inversion, future source timestamps, duplicate/out-of-order observations, cross-instrument contamination and stale data must fail closed or quarantine as appropriate.
- Test variable spreads, weekends/holidays, disconnections, broker quote differences, spread spikes and chart-candle versus tick/quote mismatches.
- Fixed duration comparisons (3/5 minutes) are separately preregistered **research arms**; they do not silently override structural exits.

### 5.6 Risk and position sizing

Initial research scenario: **$500 USD**. Configurable planned per-trade risk options may include **0.25%, 0.5%, 1%**, with explicit session/daily and account drawdown guardrails. Calculate units from structural stop distance, instrument unit and pip value, estimated total execution costs, minimum size, margin feasibility and provider restrictions. Return a **rejected plan** when risk/margin constraints cannot be met. Assume slippage and stop gaps can exceed planned loss; never display guaranteed protection. No daily profit quota and no autonomous live-capital behavior.

### 5.7 Evaluation design, hypotheses and evidence thresholds

**Primary endpoint:** Prospectively measured, executable, net-of-cost risk-adjusted outcome, separated by strategy/version and broker/venue.  
**Secondary:** Trade frequency, invalidation rate, data completeness, quote-to-alert latency, actionability at tap time, maximum drawdown, profit factor and stability by pair/regime/session.

Methodology:

1. Register each strategy and threshold set before evaluating held-out samples.
2. Use walk-forward or chronological splits; isolate parameter tuning from final holdouts; control selection bias from repeated testing.
3. Run V1 control and V3 challengers on identical permissible observations, explicitly reporting non-comparable samples.
4. Prevent look-ahead/repainting and survivorship bias; include all qualifying and rejected candidate events in audited logs.
5. Account for correlated trades and clustered markets when estimating uncertainty; use confidence intervals appropriate to returns/expectancy rather than a win-rate shortcut.
6. Verify bid/ask evidence coverage and unresolved rates before interpreting apparent edge.
7. Require multiple regimes and prospective periods, not a single losing morning or a handful of positive examples.
8. Record strategy degradation, stopping rules, transaction-cost sensitivity and account risk. No strategy enters user-facing trade-ready status solely because a backtest outperformed V1.

Do not invent a statistical threshold that the available sample cannot support. Define preregistered minimum evidence and escalation rules with independent QA before any promotion.

### 5.8 Language and third-party-engine decision gate

**Build the same representative vertical slice** in (a) pure Swift and (b) Rust exposed through a narrow, versioned Swift-compatible interface. Include: one market observation stream, one auction-failure setup, structural plan validation, bid/ask exit evaluation, deterministic replay and serialization. Run identical fixtures.

Compare:

- Behavioral equality, numeric exactness, error handling and deterministic replay.
- Build/toolchain complexity, reproducible iOS/macOS packaging, architecture portability and library licenses.
- p50/p95/p99 processing latency, memory, energy, binary size and actual iPhone startup/resume performance.
- Developer ergonomics, independent QA effort, update cadence and debugging support.

**Adopt Rust only if it materially wins overall and does not compromise mobile delivery.** Keep Native Swift as a legitimate first-class outcome. Evaluate NautilusTrader as optional Mac-side research infrastructure rather than embedding its full framework into the iPhone by default. Jev and Apple Foundation Models remain outside the authoritative trade-decision pipeline.

---

## 6. Early warning and alert delivery design

### 6.1 Requirement

Replace the eight-second V1 entry-window assumption in the V3 active workflow with **state-derived, staged setup notices**:

1. **FORMING:** A preidentified structural setup is developing. Target useful lead time (initially **3–5 minutes**, where the event can actually be recognized that early); never promise exact time-to-entry.
2. **APPROACHING:** The setup is near a registered confirmation condition. Target an **approximately 30–90-second** preparation window only when measurable evidence supports it.
3. **TRIGGERED:** All deterministic entry conditions met on valid evidence; distinct notification, **not** an automatic order or instruction guaranteeing success.
4. **INVALIDATED / EXPIRED / STALE:** Update or supersede alerts and prevent aged notifications from appearing actionable.

The alert itself is an evidence-based **heads-up**, not a profitable trade forecast. All alerts must include instrument, strategy version, evidence time, event phase, expiry/validity and deep-link identity. Limit sensitive account data in push payloads.

### 6.2 Reliability architecture

- Evaluate hosted TradingView alerts and Pine prototypes as **external inputs**, but do not treat webhook receipts as broker-confirmed quotes or fills.
- Build a canonical alert-state and event-ID deduplication service. Reject duplicate, delayed or instrument-mismatched events.
- Prefer an always-on monitor with explicitly scoped credentials for actual off-device surveillance; the existing Mac collector can be a research prototype, but must report when offline. iOS suspension means an app-only background monitor cannot promise uninterrupted alerts.
- Push with APNs where authorized. Do not promise second-perfect delivery; iOS Focus modes, connectivity, service availability and background budgets affect timing.
- A notification opens Trade on the exact planned setup, then requires **fresh broker/source, spread, setup validity and risk revalidation** before presenting a ready state.
- Provide quiet hours, per-strategy/per-pair preferences, cooldowns, notification log, incident handling and monitoring-service health. No flooding.
- A Live Activity may be evaluated for active monitored setups but is nonessential and must not be used as a real-time execution guarantee.

### 6.3 Metrics

Percent of forming alerts with meaningful subsequent triggers, prospective lead-time distribution, invalidation/cancel rate, stale-tap rate, alert delivery/tap latency, deduplication success, missed events, monitor uptime and cost. Display evidence limitations clearly.

---

## 7. Platform and data integrations

### 7.1 OANDA Practice

Retain existing authenticated practice/live environment separation and current completed-candle/price retrieval. Preserve account-specific bid/ask evidence and explicit live-account safeguards. Check any API availability, rate limits and stream sampling constraints against current docs and observed test logs. Practice reconciliation is the initial reliable workflow. Never mix OANDA bid/ask fills with tastyfx or TradingView outcomes.

### 7.2 tastyfx

User has an existing tastyfx account. Verify current demo access, TradingView broker connection, supported order types, minimum trade size, margin/spread schedule, protective stops and **actual developer API eligibility**. Do not assume a standard retail REST integration exists or is available to the user. In the absence of authorized programmatic access, support **manual demo execution plus independent statement/export reconciliation**, with transparent status labels. Keep broker identities and execution evidence partitioned.

### 7.3 TradingView

Evaluate two independent workflows:

- **External platform:** Professional charting, Pine prototype strategies, hosted alerts and tastyfx-enabled manual trading when supported.
- **Embedded app chart:** Lightweight Charts versus existing SwiftUI chart under a separate UX/energy/accessibility prototype. Lightweight Charts is **not** the full TradingView product.

Before webhook deployment, verify current plans/alert quotas, authentication/security model, integration terms, cost and whether receiving infrastructure can be kept reliable. Use an authenticated ingestion boundary with replay protection, rate limiting and idempotent event handling. TradingView alert states do not replace independently verified OANDA/tastyfx quote evidence.

### 7.4 NinjaTrader

Research only, based on actual verified need for futures market footprint/order-flow evidence. Do not infer exchange order-flow delta/iceberg liquidity from spot-FX candles. Confirm OS/Windows requirements, data licensing, ongoing costs and whether proxying a futures-derived signal into FX is scientifically defensible before any integration.

### 7.5 GitHub/open-source evaluation

Shortlist: NautilusTrader, OANDA sample code, Swift Snapshot Testing, Swift Async Algorithms, QuantStats and possibly Lightweight Charts. All additions require a current maintainer/activity check, license review, pinned version, minimal prototype, performance measurement, and an exit plan. Avoid cargo-cult dependencies or importing full trading platforms into the mobile binary.

---

## 8. Data, reliability, security and performance

### 8.1 One authoritative evidence store

Reuse existing durable persistence and RecoveryStore where appropriate. Event IDs, versioned schemas and provenance must make shadow evaluations, practice executions, user-entered observations and broker-confirmed records impossible to confuse. Export should include source environment, time metadata, strategy config and unresolved evidence. Preserve historical crypto and OTC data in a quarantined archive without mixing aggregate statistics.

**Near-term mandatory integration:** Connect existing V3 Spot evaluator to **ForwardTest durable persistence**. Validate record creation, crash/restart replay, idempotence, missing exit evidence, out-of-order quotes, cross-instrument isolation and export. This work has higher priority than a new engine language.

### 8.2 iPhone performance

Keep SwiftUI. Profile the current monolithic observable state and excessive invalidation risks; introduce narrower immutable snapshots or view models only where tests and Instruments data justify it. Bound chart data and AI retrieval; avoid unnecessary 100-ms main-thread repaints, offscreen animation and unbounded tasks. Compare actual iPhone cold start, quote-to-render latency, frame pacing, energy, memory and app resume. Do not claim speed gains from Rust without end-to-end measurements.

### 8.3 Security

Keychain credentials; separation of practice/live configuration; least privilege for any collector, TradingView webhook endpoint or notifications; encrypted transport; secrets never in logs, pushes or exports; redacted diagnostics; explicit consent for analytics. No unattended live orders. Avoid storing sensitive broker data in Jev/Foundation Models prompts unless necessary, permitted and privacy-reviewed.

### 8.4 Reliability test matrix

Unit fixtures + integration replay + iOS UI automation + physical-device test. Must include:

- Future timestamps, source/receipt inversion and clock jumps.
- Completed vs incomplete bars, look-ahead and swing repainting.
- Out-of-order quotes, duplicate events, stale instrument callbacks.
- Spread spikes, price gaps, ambiguous first-touch SL/TP.
- Stop placement, invalid lot size, currency conversion, margin and risk rejection.
- Crash between sealing plan, persisting outcome, journal write and replay.
- Offline/suspended/force-quit app and push delivery failure.
- Radar contact and instrument-selection taps, late-entry receipt, Chart Focus.
- VoiceOver, Dynamic Type, Reduce Motion, small/large screens.
- UI build identity and signed artifact matching tested SHA.

---

## 9. Dependency-ordered execution milestones

| Milestone | Deliverable | Release gate |
|---|---|---|
| **M0 — Reconcile and protect** | Exact repo, worktree, engine pins, current tests, device install, existing V3 contracts and blocker inventory | Evidence-based baseline; no destructive changes |
| **M1 — Complete existing correctness** | Wire V3 Spot evaluator to durable ForwardTest; harden provenance and persistence; automated Radar/late-entry/Chart Focus interactions | Reproducible end-to-end tests, no mixed or fabricated records |
| **M2 — Define and prototype V3 engine** | Typed contracts, structure algorithms, state-machine tests; Swift/Rust vertical-slice comparison | Deterministic replay, no look-ahead, documented language decision |
| **M3 — Forward research campaign** | Matched V1/V3 strategy evaluation with structural TP/SL, broker-aware costs and missing-data handling | Research report with uncertainty and prospective evidence; no unproven promotion |
| **M4 — Integrations and early warning** | Validated TradingView alert prototype, OANDA practice state and tastyfx manual reconciliation pathway; notify/deep link | End-to-end demo alert with fresh revalidation and delivery diagnostics |
| **M5 — Three-destination iPhone product** | Trade/Markets/Review, contextual Coach, polished chart and state UI, legacy quarantine | UI snapshot + tap tests; physical iPhone acceptance |
| **M6 — Release hardening** | Exact-commit CI, performance Instruments, signed TestFlight/distribution, rollback and recovery package | Release candidate is installable, provenance identified, known blockers documented |

**Sequencing flexibility:** M2 strategy prototypes may be developed in an isolated parallel worktree while M1 correctness is completed. Shared persistence and state contracts must have a single owner and an explicit integration gate. The whole project does not wait on Jev, Rust, NinjaTrader or embedded TradingView chart experiments.

### 9.1 OpenCode execution expectations

This PRD is a **specification**, not a command to delete or rewrite working code. For each milestone OpenCode should identify the relevant current source, smallest coherent implementation, explicit tests, independent QA result, exact commit, and missing physical verification. Reports and markdown alone do not count as completed milestones. Avoid reopening resolved design debate without concrete contradictory evidence.

### 9.2 M1 acceptance in detail

One sealed, instrument-specific structural plan evaluated against real or clearly marked fixture bid/ask observations; first permissible exit evidence correctly classified; outcome durably recorded by ForwardTest with source/config hashes; interrupted replay returns the same result without duplication; Review can retrieve it; wrong instrument or unavailable observations remain unresolved/quarantined. UI tests exercise Radar selection, Chart Focus presentation/dismissal, and late-entry receipt error/success paths.

### 9.3 M6 physical-iPhone acceptance

- App launches with verified build number, commit, broker environment and engine pin.
- Markets → Trade preserves exact instrument and strategy plan context.
- Trade shows valid plan or clearly labeled NO TRADE; no contradictory score/expiry claims.
- Setup warning opens exact plan, which is independently revalidated on tap.
- Manual practice entry/exit is reconciled or labeled unconfirmed.
- Review and Coach refer to the same source-linked evidence.
- After network loss, backgrounding, force quit and recovery, no phantom fill or closed position is produced.
- Real-device Instruments measures startup, rendering, latency, memory and energy; exact commit CI and signed artifact exist.

---

## 10. Promotion, rollback and stop conditions

**Do not promote a strategy** based on its engineering test count, UI polish, Jev output, a single morning, headline win rate or optimistic backtest. Require preregistered forward evidence, trustworthy executable pricing, enough observations for meaningful uncertainty, and acceptable drawdown/operational performance. Independent QA approves research-method validity; the product owner approves moving to the next deployment phase.

**Stop and investigate** on evidence cross-contamination, stale/actionable notification defects, wrong-side quotes, unverifiable broker position state, unexpected live endpoint access, failed recovery or missing source timestamps.

Keep a revertible V1 release, migration backup, feature flags for candidate engines and external integrations, signed artifact provenance, and a straightforward way to disable alerts independently of the app. The original frozen engine, journals and user modifications must remain recoverable.

---

## 11. Open decisions requiring data, not speculation

1. **Swift or Rust?** Choose after a measured, equivalent prototype—not from preference alone.
2. **What exact auction thresholds?** Register candidate parameters before prospective testing; avoid overfitting.
3. **tastyfx API versus manual reconciliation?** Verify actual account eligibility and current published interfaces.
4. **Hosted alert infrastructure?** Prove uptime, costs and notification reliability; existing Mac collector is a development option.
5. **TradingView embedded chart?** Compare interaction, accessibility, latency, offline behavior and maintenance against native implementation.
6. **NinjaTrader/order-flow data?** Introduce only with a specific testable hypothesis and justified licensing cost.
7. **Jev?** Compare shadow classification with simple deterministic baselines and evaluate incremental out-of-sample usefulness.
8. **Actual profitable edge?** Unknown until prospective, venue-specific, cost-adjusted results support it.

---

## 12. Final product acceptance statement

BlazerOS STRIKE V3 is successful as an engineering product when it reliably **discovers, explains, records and evaluates** versioned FX trade hypotheses on a physical iPhone, with coherent data provenance and no fictitious execution state. It is successful as a trading strategy only after separate forward research establishes an economically meaningful edge.

**Priority order today:** Preserve the passing work → wire ForwardTest persistence → verify UI actions → commit and run exact-SHA CI → install and profile the actual iPhone → implement the strategy-core and notification evolution against this trusted foundation.
