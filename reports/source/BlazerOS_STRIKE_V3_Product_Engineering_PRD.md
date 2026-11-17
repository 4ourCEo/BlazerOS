# BlazerOS STRIKE V3 — Product & Engineering PRD

**Status:** Proposed architecture; implementation is NOT claimed complete  
**Version:** 1.0 — 2026-11-03  
**Audience:** Product owner, OpenCode/T3, 4our Enterprises OS engineering, QA, research  
**Repository:** `4ourCEo/BlazerOS`  
**Primary user/platform:** Personal, iPhone-first, native SwiftUI; Mac research service as supporting infrastructure  
**Working capital scenario:** $500, *not* an authorization for real-money deployment  
**Core principle:** Improve verified trading decisions, not the appearance or quantity of signals.

> **Scope warning.** This is a decision record and implementation-ready PRD, not a coding-agent prompt. The code observed through GitHub may be older than a local RC1 branch. All code-level claims must be reconciled locally. No strategy in this document is established as profitable; losses are possible and stop orders can slip.

## 1. Executive product decision

Evolve BlazerOS from a **fixed-expiry directional signal application** to **a structure-based, risk-defined FX research and trade-planning workstation**.

- Keep **native SwiftUI** as the iPhone application.
- Replace five bottom-level screens with **Trade / Markets / Review** and a **contextual Coach**.
- Preserve the pinned JavaScriptCore V1 engine as an immutable, reproducible control. Create V3 candidate engines rather than editing V1 in place.
- Move from 60-second expiration to **condition-based setup triggers and structural TP/SL**. Compare M3/M5 time exits only as separate registered research hypotheses.
- Use **OANDA Practice** for existing bid/ask research collection and account-specific evidence; use **TradingView** as an external professional charting/Pine-alert research tool; evaluate **tastyfx–TradingView** as a manual execution workflow. No unsupported assumption of a tastyfx API.
- Evaluate **Rust vs pure Swift** on a bounded engine vertical slice before selecting implementation. Investigate **NautilusTrader** for off-device simulation before embedding any dependency.
- Keep **Jev** as an experimental, evidence-bound shadow classifier; Apple Foundation Models as a read-only explanatory layer. Neither can generate broker orders or override deterministic risk gates.
- Add **early setup warnings**, then confirmation and invalidation, with source-linked state and freshness revalidation. Do not promise a notification N seconds ahead of a market event.
- No auto-order placement and no default live-capital workflow during V3 qualification.

### North-star questions

1. Can V3 identify a *well-defined* setup before the trigger, with enough lead time for a person to prepare?
2. Is the proposed entry feasible after spread, slippage assumptions, margin and position-size limits?
3. Can the entire hypothesis be reconstructed from immutable evidence and broker-confirmed outcomes?
4. Does the candidate outperform an untouched baseline **out of sample** after costs, including uncertainty and drawdown?
5. Is the iPhone app fast, usable, correctly labeled, and recoverable under interruptions?

**Primary release gates:** correctness and operational reliability first; prospective evidence of trading edge is a separate, later gate.

## 2. Three-round design debate — decisions and tradeoffs

### Debate A: Is this a signal engine, strategy platform, or trading terminal?

- **Option 1 — Keep short-expiry directional signals.** Lowest code churn, but fundamentally misaligned with transcripts discussing confirmation, stop placement and price targets. Outcome: **reject as primary mode; preserve V1 research history**.
- **Option 2 — Build a universal user-defined strategy editor.** Flexible but creates enormous validation surface, parameter overfitting and unbounded QA. Outcome: **reject for V3**.
- **Option 3 — Versioned, bounded strategy library + trade-plan state machine.** Constrained but auditable, measurable and usable. Outcome: **accept**. Start with auction failure, breakout acceptance, and trend pullback; permit only documented configuration parameters.

### Debate B: Build versus buy versus integrate?

- **Rebuild complete TradingView-style charting and hosted alerts:** costly and redundant. **Reject**. Use TradingView externally; compare existing native chart against Lightweight Charts only if an iOS spike demonstrates measurable usability benefit.
- **Use TradingView as the authoritative strategy/execution engine:** Pine historical fills and chart symbols may not match executable broker prices; webhooks can fail. **Reject as sole source of truth**. Accept as prototyping/third-party candidate events, clearly labeled and revalidated against the intended broker.
- **Port entire BlazerOS to NinjaTrader:** NinjaScript is Windows desktop C#, primarily aligned with futures ecosystem and order-flow tools. **Reject for iPhone FX core**. Retain optional future research into real futures footprint/delta, never infer those from OANDA OHLC.
- **Embed all of NautilusTrader:** high integration and licensing/API lifecycle complexity. **Reject by default**. Evaluate narrow off-device research use or borrow architectural ideas after license review.
- **Rewrite engine in Rust immediately:** sound type-state and performance potential, but no inherent alpha improvement and Swift FFI/packaging costs. **Defer choice pending representative benchmark** against Swift.

### Debate C: What earns permanent UI space?

- **Trade (keep, evolve Scan):** high daily value; chart, setup, plan, risk and manual action context.
- **Markets (keep, evolve Radar):** high value only if real discovery, prioritization, valid setup state and advance notice. Decorative sweep alone is insufficient; reduced-motion list must work just as well.
- **Review (merge Intel + Journal):** vital for accountable performance and replay. Distinguish simulated, proxy, manually reported and broker-confirmed data.
- **Coach (remove standalone tab):** retain only as contextual read-only investigation, session summaries and evidence-linked help. No generic instructional card landfill.
- **Crypto, OTC, CALL/PUT, binary expiry:** remove from active FX UI; quarantine implementation and preserve historical records.

**Resolution:** Three primary destinations, a shared evidence model, and a rigorous strategy lifecycle. No feature is retained for sunk-cost reasons.

## 3. Source-grounded baseline and unverified areas

### Confirmed from previously inspected published repository sources

- `Sources/LightningDesk/LightningDeskView.swift` routes five screens (`desk`, `radar`, `intel`, `coach`, `journal`).
- `Sources/LightningDesk/Screens/MarketsScreen.swift` has a Radar plot and per-pair tactical tiles; currently displays M1 and HIGH/LOW/CALL/PUT language.
- `Sources/LightningDesk/Screens/IntelScreen.swift` contains session/notification and optional OTC research controls.
- `Sources/LightningDesk/Screens/CoachScreen.swift` has Foundation Model explanation plus static expectancy/principles cards.
- `Sources/LightningDesk/Screens/JournalScreen.swift` emphasizes hits/misses and has an export/replay path.
- Published repo research configuration includes baseline, continuation, reversal and regime policies; several existing correctness and parity suites have been reported in earlier work.

### Must be established on the actual local workspace in M0

- Current branch, exact commit, dirty changes, worktrees, pinned engine SHA, existing candidate implementations, dependency versions and legal licensing constraints.
- Whether late-entry / Track Trade issues were fixed locally.
- Whether FX-only and UI corrections reached any **installed physical iPhone build**.
- Exact TradingView and tastyfx account entitlements, API/data rights and supported linking and manual practice path.
- OANDA account type, pricing source, data reliability and whether accessible historical bid/ask resolution supports intended TP/SL ordering.
- Available push/APNs credentials, entitlements, existing services and stable hosted infrastructure.

Do not treat report text, prior conversation approvals or passing simulator tests as proof of deployed functionality.

## 4. Personas, jobs to be done and out-of-scope

**Primary persona:** User trades/researches FX on an iPhone while moving between apps; wants meaningful setup warnings rather than frantic eight-second calls; plans small-account risk, values reliable manual execution and end-of-day improvement.

**Jobs:**

1. Know which pairs have emerging *documented* setup conditions, and why.
2. Receive early heads-up, prepare chart and broker app, then independently review fresh confirmation.
3. Inspect an entry, structural invalidation, TP, risk/reward, effective spread and feasible unit size.
4. Record or reconcile manual practice trades without pretending a fill occurred.
5. Understand outcomes, false leads, timing, avoided trades and strategy research findings without inflated win rates.

**Out of scope for V3:** automated real-money execution; guaranteeing daily profitability; managing funds for others; building an exchange/order book; synthetic claims of futures absorption/footprint from FX candles; full NinjaTrader or TradingView clones; unlimited strategy scripting; institutional-grade execution claims; unapproved subscription/backend sprawl.

## 5. Proposed product interaction design

### Navigation

**Bottom navigation:** `Trade | Markets | Review`. Persistent small Coach entry point (sheet/modal), not a full tab. Settings and Strategy Lab are secondary routes. Deep links use stable `instrument_id`, `plan_id`, `strategy_version` and `event_id`.

### 5.1 Trade — primary workstation

Information order: instrument/provider/environment/freshness → chart (selected M5 with M15 context and optional M1 confirmation) → setup state and reason → **conditional trade-plan card** → compact risk / feasibility → manual workflow actions.

Actions: select pair/strategy, inspect price levels, review proposed SL/TP, open linked TradingView/tastyfx app where supported, record manual entry/exit, compare source quotes, view evidence replay, dismiss invalid opportunity.

States: `NO_DATA`, `STALE`, `WATCHING`, `FORMING`, `APPROACHING`, `CONFIRMED`, `TRIGGERED`, `INVALIDATED`, `SETUP_EXPIRED`, `UNRESOLVED`. The presentation must never suggest a pending setup is a completed trade or an 85 score is an 85% win probability.

Screen constraints: one-handed tap targets, no clipped candles or watchlist prices, explicit timeframe, bid/ask display, legible axes and structural lines, VoiceOver, Dynamic Type and reduced motion. Show errors next to failed actions rather than silently doing nothing.

### 5.2 Markets — a useful Radar, not a screensaver

Prioritized list of pair/strategy monitors with current regime, distance from known levels, evidence completeness, projected readiness *category* (not fake timer), source freshness and latest warning stage. Radar visualization optional but synchronized to exact monitor state. Tap opens Trade at the corresponding pair/plan. User can choose which pairs and strategies to monitor.

Do not animate imaginary contacts or label data "LIVE" solely from UI repaint time. Pause animations offscreen.

### 5.3 Review — evidence and improvement

Internal sections: `Trades`, `Performance`, `Research`. Trades include plans, self-reported actions, broker confirmations, closures, missing data and export. Performance includes net R/dollars, fees, drawdown, distribution by session/strategy/provider, notification usefulness. Research includes V1 vs V3 controlled tests, confidence/uncertainty, experiment registrations and hypothesis rejection.

Do not combine results from binary, crypto, OTC, simulated midpoint proxy, OANDA shadow, OANDA Practice, tastyfx manual and live categories.

### 5.4 Coach — contextual, evidence-constrained

Can answer what is forming, why the last alert was sent, which criterion failed, whether a recorded trade deviated from plan, where latency accumulated, and which candidate has better *measured* evidence. All analyses link to record IDs. On-device model requests remain within bounded context and use deterministic fallback. No AI signal authority, no autonomous orders.

## 6. Strategy and data engine specification

### Engine principle

**Do not merely port existing directional-score JavaScript to Rust.** Define a new pure, deterministic, versioned state model first. Explicit input contracts, no look-ahead, invalidation and executable outcome evaluation are the core improvements.

### Market inputs

- Completed M1/M3/M5/M15/H1 candles if provider-supported; M3 can be aggregated deterministically from complete lower-timeframe bars.
- Account-specific OANDA bid/ask prices, quote source time, received time, sequence, bid/ask spread, instrument precision, trade-status and provider identity.
- Persist raw input or a legally permissible, reproducible reference to it; normalize to canonical units.
- Feed quality: gaps, future/out-of-order source time, spread anomalies, stale data and uncertainty.
- Broker/TradingView symbols must map explicitly, not by string similarity.

### Strategy research library (initial, not validated)

**Auction failure reversal:** detect prior range *from historical-only data*, boundary test/break, failure of acceptance and a measurable return/confirmation; stop outside structural invalidation; target registered range/value proxy. No false claim of real order-flow absorption.

**Breakout acceptance:** detect historically known boundary, sustained acceptance or objective retest, confirmation; predefined stop on acceptance failure; structural target. A single wick is insufficient.

**Trend pullback:** higher-timeframe directional definition, constrained pullback to objective level, resumed directional confirmation, invalidation beyond structure; prospective test only.

Every candidate emits an immutable `ResearchTradePlan` or explicit rejection reason, not generic BUY/SELL. Plans include source snapshot, entry trigger, setup validity, structural SL/TP, reward/risk, cost model, max spread, account-risk cap, instrument sizing, evidence references and version/hash.

### Timeframes versus exits

Default experiment: M15 context / M5 setup / optional M1 confirmation. A setup may become invalid before triggering. An **open spot trade is not automatically closed after 1, 3 or 5 minutes**. Compare 3m and 5m time exits in separate, pre-registered cohorts; primary study uses fixed and explicit structural exit rules. No best-of hindsight selection.

### Spot FX outcome correctness

Long: entry **ask**, exit **bid**. Short: entry **bid**, exit **ask**. Include spread, fees, quote granularity, latency, conversions, financing if relevant and slippage assumptions. Track bid/ask barrier hits. If historical evidence cannot establish whether stop or target happened first, use `AMBIGUOUS` rather than assign a win. If source gap/timing invalid, `UNRESOLVED`. Distinguish simulated TP/SL crossings from actual broker-side orders/fills. OANDA price stream is sampled at at most four updates/second/instrument and does **not** include every tick: do not market estimated fills as executable truth.

### Risk layer

Support configurable account capital, including $500. Example research presets: 0.25%, 0.5%, 1% planned risk per position; optional illustrative daily 2% loss budget. Actual risk can exceed planned due to stops, gaps and slippage. Compute size based on stop, spread/fees, currency conversion, order increments, allowed leverage and actual margin. Reject plans violating constraints; never change exposure automatically to meet a target daily profit. Keep all numerical precision and quote conventions explicit.

### Engine implementation decision gate

Build equivalent, independent **bounded vertical slices** in idiomatic native Swift and Rust (or justify not doing both). Compare a representative stateful strategy and risk calculation for deterministic parity, p50/p95/p99 latency on intended hardware, memory, battery, arm64/iOS packaging, exception/panic handling, auditability and maintenance. Choose Rust **only if evidence beats Swift sufficiently to justify FFI and distribution complexity**. Preserve V1 code and pinned artifact unchanged. Research NautilusTrader off-device if its backtester reduces labor, but confirm LGPL obligations, version pinning and suitability before integrating.

## 7. External systems and proven boundaries

| External system | Adopted V3 role | Integration caveat |
|---|---|---|
| **OANDA Practice** | Authoritative existing source for account-specific FX quote research and practice reconciliation | Streaming prices are sampled and account-specific; stop/target crossing can remain unresolved |
| **TradingView full service** | Charting, Pine prototypes, user-hosted technical alerts; optional webhook events | Webhook can fail and is not an authenticated broker fill; 2FA and HTTPS requirements; no sensitive credentials in payload |
| **tastyfx** | Existing account; verify TradingView connected broker workflow for **manual** trading | Account type/demo entitlement/API and exports must be independently verified; price source differs from OANDA |
| **NinjaTrader** | Optional futures order-flow study; not iOS platform dependency | NinjaScript is Windows desktop-only; futures footprint/delta not identical to spot FX |
| **NautilusTrader** | Conditional Mac/off-device backtest research engine candidate | LGPL licensing, Rust API instability and integration overhead require review |
| **Jev** | Bounded shadow classifier/diagnostic experiment | Must outperform simple out-of-sample baselines; no strategy/risk/order control |
| **Apple Foundation Models** | Read-only contextual explanations/debrief | No authoritative numeric calculations or execution authority |
| **Lightweight Charts** | Optional chart renderer spike | Apache 2.0 plus required TradingView attribution/link; not full TradingView product |

**Do not create a platform-integration dependency merely because the brand is attractive.** The product must remain operational when TradingView or Jev is unavailable.

## 8. Notification and monitoring design

**Problem:** An eight-second reaction rail is incompatible with on-the-move manual review and structure-based strategies. **Goal:** useful *early information*, not guaranteed foresight.

Event-sourced lifecycle: `WATCHING -> FORMING -> APPROACHING -> CONFIRMED -> TRIGGERED / INVALIDATED / EXPIRED`, with idempotent IDs and strict source freshness.

Proposed notification categories:

1. **Early watch**: meaningful boundary proximity + prerequisite conditions; aspirational 3–5 minute lead where evidence permits. Should say *forming*, not a promised entry.
2. **Prepare**: remaining prerequisites close to confirmation; optional target 30–90s lead, not a deterministic forecast.
3. **Confirmed / trigger observed**: sends event-driven notice only when pre-registered criteria are met on fresh source data. It is not an unconditional instruction to trade.
4. **Invalidated / stale / withdrawn**: update or suppress obsolete opportunity; clear current state in app.

For each alert record: rule, plan ID, source timestamp, service emission, APNs acceptance when available, device receipt/open time, stale-at-open flag and dedupe key. Track delivered/opened metrics separately and do not interpret missing receipt as delivery proof.

**Runtime options:** initial Mac collector for controlled research; hosted monitor only after service-availability requirements and budget/security assessed. iOS suspension prevents reliable always-on client evaluation. APNs/Focus/connection can delay or prevent delivery. A deep link always re-fetches and revalidates data, spread, strategy state, and account risk before presenting any current opportunity. Never auto-place orders.

**Security:** TradingView webhook ingestion via HTTPS endpoint, request validation, key rotation, rate limiting, idempotency, replay protection, schema validation, no credentials in alert bodies, audit logs. Design for provider outages and out-of-order event arrival. Avoid public endpoint until a threat model and operational owner exist.

## 9. Shared state and storage contracts

Use one **canonical append-only evidence ledger** plus derived, versioned projections. Evolve existing RecoveryStore; do not create a second contradictory truth store.

Recommended logical entities (map to existing types before adding new ones):

`MarketObservation`, `DataQualityAssessment`, `StrategyDefinition`, `StrategyConfiguration`, `SetupInstance`, `StateTransition`, `ResearchTradePlan`, `RiskEvaluation`, `NotificationEvent`, `ManualTradeReport`, `BrokerExecutionRecord`, `ExitObservation`, `ResearchOutcome`, `ResearchCampaign`, `BuildProvenance`.

Key invariants:

- A setup is not a position. An alert is not a setup confirmation. A manual note is not a broker fill.
- Source, account environment, instrument, units and versions mandatory for authoritative observations.
- No old/out-of-order quote may resurrect a setup or silently change an already sealed record.
- All writes idempotent under stable keys; corruption quarantined; crash recovery explicit.
- Unknown or missing TP/SL ordering is ambiguous, never forced into WIN/LOSS.
- Read-only Coach uses the same record IDs as Review and Trade.
- Legacy binary and crypto event types remain readable but excluded from active FX calculations.

## 10. Research rigor and success metrics

**Primary research metrics:** net expectancy per trade (R and dollars), credible uncertainty interval or confidence interval, maximum drawdown, profit factor with sample counts, frequency of executable opportunities, spread-adjusted excursion, valid TP/SL ordering rate, missing evidence rate, false/invalidated lead alerts, and paired performance against V1.

**Secondary product metrics:** alert warning lead-time distribution (including invalidated watches), time from alert to plan review, stale-at-open %, quote-to-render p50/p95, crash-free foreground/background recovery, notification duplicate rate, UI regressions, VoiceOver coverage, CPU/memory/battery on physical iPhone.

**Experiment protocol:** preregister candidate rules/parameters, data window and evaluation plan; separate development/validation/forward windows; cluster overlapping signals rather than treating correlated trades as independent; use matched market observations; compare across different sessions/volatility regimes; record fees, missing data and rejected plans; avoid optimizing based on the failed morning alone. If results are statistically inconclusive, mark **INCONCLUSIVE**, not "profitable".

**Jev evaluation:** three shadow tasks (regime label, failure attribution, evidence quality). Assess calibration, disagreement, incremental improvement and inference latency against explicit deterministic baselines; record abstentions; no use in actionable gates without independent qualification.

## 11. Delivery plan and dependencies

### M0 — Local reality check / safety boundary

- Capture branch, worktrees, HEAD, dirty state, exact pinned V1 engine, build metadata, existing test counts and installed iPhone provenance.
- Classify each prior approved capability as `VERIFIED / PARTIAL / ABSENT / BLOCKED` with source lines and tests.
- Identify miswired Track Trade, stale price labeling, false expiry, crypto/OTC coupling and existing alert behavior.
- Preserve all data and local source state before implementation.

**Exit:** No unknown local changes; reproducible baseline build; blockers catalogued. No unrequested destructive operations.

### M1 — Domain and correctness contracts

- Specify strategy setup lifecycle, instrument/money types, risk and plan contracts, provider identity, evidence ledger migration and recovery invariants.
- Implement canonical test fixtures, fake clock/network and paired replay golden vectors.
- Maintain V1 parity and legacy read compatibility.

**Exit:** Versioned model verified by unit/property-based tests, no broker orders.

### M2 — Engine research qualification

- Implement auction failure and breakout acceptance first; trend pullback next if warranted.
- Benchmark Swift vs Rust bounded vertical slice; decide engine runtime based on evidence.
- Evaluate NautilusTrader as off-device simulator only if it reduces work; register experiments, cost-aware TP/SL evaluator.

**Exit:** Reproducible, source-linked plans/outcomes; explicit ambiguity; untouched V1 reference.

### M3 — External pilot and notifications

- TradingView Pine prototype and webhooks only as independently sourced *candidate events*; build safe ingestion + monitor, deep links and freshness checks.
- Verify tastyfx connected TradingView account workflow and actual demo availability before claiming it.
- Keep OANDA Practice as stable research adapter; no mandatory hosted dependency until approved.

**Exit:** One forming → prepare → confirmed/invalidated alert flow can be replayed and tested, with actual delivery caveats measured.

### M4 — iPhone UX consolidation

- Trade, Markets, Review; contextual Coach. Preserve STRIKE visual identity.
- Compare native chart with Lightweight Charts spike if needed; freeze UI spec once usability reviewed.
- Working actions, consistent state, readable candle scaling, offline/empty/error screens, accessibility and snapshot baselines.

**Exit:** Physical-device screenshots and tap-path tests demonstrate all three destinations and Coach without dead controls.

### M5 — Practice lifecycle, recovery and independent QA

- Manual OANDA practice event reconciliation with actual fills where available; optional tastyfx manual trade import if verifiable.
- Verify stop/target ambiguity, app suspend, network loss, stale push, source change, double-tap, force-quit and journal recovery.
- Profile iPhone p50/p95 rendering, memory, energy; independently reproduce tests and exact-release CI.

**Exit:** Signed test distribution built from exact verified commit, reproducible end-to-end evidence, no fabricated broker executions. No automatic live-trading rollout.

### M6 — Research evaluation (separate from functional release)

- Collect prospective multi-session data; evaluate paired outcomes after all costs.
- Continue only if registered performance and risk thresholds are satisfied; otherwise revise candidate hypotheses in new version, not retroactively.

**Exit:** Honest classification: `NOT ENOUGH EVIDENCE / NEGATIVE / INCONCLUSIVE / PROMISING IN PRACTICE`; never infer live profitability solely from a demo.

## 12. Responsibility and implementation boundaries

- **Architecture/engineering lead:** interface contracts, migration order, preserved branches and dependency gates.
- **Research lead:** preregistered strategies, no-leakage replay, broker bid/ask calculations and confidence intervals.
- **iOS lead:** native UI, accessibility, deep links, device telemetry and iOS-specific tests.
- **Data/reliability lead:** provider adapters, capture quality, replay, event ledger, idempotency, background monitor and security.
- **QA (independent from implementation):** adversarial replay, corrupt data, cancellation, stale/duplicate notifications, screenshot regression and iPhone release verification.

Parallelize only independent work behind stable contracts; avoid concurrent modifications to pinned engine, shared ledger and active migration paths. Keep repository clean, preserve user edits, and issue narrow PRs with migration and rollback notes.

## 13. Acceptance test: end-to-end vertical slice

1. On an actual iPhone, load a correctly labeled OANDA Practice pair and valid completed candle context.
2. A versioned strategy detects a pre-registered **forming** setup; historical-only boundaries demonstrated.
3. An early-watch event arrives or its nondelivery is recorded honestly; opening the notification deep-links to the correct pair and plan.
4. App independently rechecks source timestamp, price, spread, strategy, risk and setup state.
5. An immutable plan specifies entry condition, structural stop, target, planned R and feasible size, or gives a clear rejection.
6. Forward shadow evaluation observes valid bid/ask outcomes, or records `AMBIGUOUS/UNRESOLVED`; no synthetic broker fills.
7. A manually executed OANDA Practice trade, if performed, is reconciled separately against confirmed broker transactions.
8. Review reconstructs all events; Markets reflects identical state; Coach cites the same evidence.
9. Suspend, kill, relaunch, disconnect network and replay duplicate/stale alerts without duplicating trades or misreporting closure.
10. Build information displays exact branch/commit/build, provider environment and pinned engine version; CI and physical installation match.

**Passing proves operational implementation, not a financial edge.**

## 14. Open decisions and kill criteria

| Decision | Default | Evidence to change |
|---|---|---|
| Rust on-device engine | **Conditional** | Clear correctness/latency/maintainability advantage over Swift FFI cost |
| NautilusTrader | **Off-device evaluation only** | Proven research-labor reduction, licensing approval, adapter suitability |
| TradingView alerts | **Research candidate source** | Verified symbol mapping, timing, webhook delivery, security and cost |
| tastyfx manual execution | **Pilot only** | Confirm linked account and testable practice/manual flow, export correctness |
| NinjaTrader | **Defer** | Genuine need and licensed access to futures order-flow data + Windows research path |
| Jev | **Shadow experiment** | Prospective incremental value beyond deterministic baseline |
| Live account orders | **Excluded** | Separate independent approval process, broker controls and proven practice safety |
| Hosted always-on monitor | **Not presumed** | Defined availability/security owner, measured need and acceptable monthly spend |
| Native vs WKWebView chart | **Keep native until benchmark** | Demonstrably superior interactions/rendering and attribution compliance |

**Kill or narrow a feature** if it duplicates established platforms, introduces unclear market provenance, raises maintenance burden without measured value, cannot be independently tested, or degrades physical-iPhone reliability.

## 15. PRD handoff contract for OpenCode

This file is the **single product/engineering source of truth**. OpenCode should translate it into implementation tickets and a dependency-ordered plan **within the existing repo**, retaining the stable headings/acceptance gates. It must not treat unverified source claims as verified, invent strategy profitability, modify live-money accounts, or claim deployment without device evidence. Implementation status belongs in PRs/tests and a concise traceability matrix, not endless parallel architecture documents.

### External references (checked 2026-11-03)

- TradingView webhook docs: https://www.tradingview.com/support/solutions/43000529348-how-to-configure-webhook-alerts/
- TradingView webhook credential safety: https://www.tradingview.com/support/solutions/43000722015-using-credentials-for-webhooks/
- tastyfx TradingView integration: https://www.tastyfx.com/platforms/tradingview/
- OANDA v20 pricing / streaming limits: https://developer.oanda.com/rest-live-v20/pricing-ep/
- NinjaScript developer docs (Windows desktop): https://docs.ninjatrader.com/ninjascript
- NinjaTrader Order Flow volumetric reference: https://ninjatrader.com/support/helpGuides/nt8/order_flow_volumetric_bars.htm
- NautilusTrader Rust docs: https://nautilustrader.io/docs/latest/concepts/rust/
- NautilusTrader LGPL licensing metadata: https://docs.rs/crate/nautilus-backtest/latest
- TradingView Lightweight Charts project + attribution: https://github.com/tradingview/lightweight-charts

---

**Final decision:** Ship a compact, trustworthy iPhone research workstation with structural trade plans and evidence-driven early warnings; buy/reuse charting and broker capabilities where appropriate; only replace core runtime technology after a measured prototype; keep all trading conclusions empirically conditional.
