# BlazerOS Book and Strategy Hypothesis Register

This register records the recovered handoff's descriptions of the books, how those themes map to code, and what is still unverified. **The current workspace contains no cited book PDFs or EPUBs** (checked with `rg --files` on 2026-11-14), so the chapter/page references below are handoff/register assertions, not source-verifiable citations in this checkout. Reconfirm them against the actual files before describing them as inspected or implementing a book-derived entry rule. The register is a research input, not a claim that a book or candidate proves a profitable Live signal.

## Handoff-reported research principles — source files unavailable

| Handoff/register reference (not verified from a local book file) | Reported topic | BlazerOS research implication, not an entry rule | Current code and gap |
|---|---|---|---|
| David Aronson, *Evidence-Based Technical Analysis* (2007 PDF), ch. 1 pp. 15+, ch. 3 p. 103+, ch. 4 p. 165+, ch. 5 p. 217+, ch. 6 p. 255+ | Objective rules, scientific testing, statistical inference, hypothesis testing, data-mining bias | Version exact rules before scoring; preregister a null/benchmark and holdout; report uncertainty and the number of configurations tried | `StrategyValidation`, `PromotionEvidenceGate`, `ResearchExperiment`, and `SpotFXHistoricalReplay` exist. A complete per-family campaign and promotion evidence are still missing. |
| Ernest Chan, *Algorithmic Trading* (2013 PDF), ch. 1 pp. 1+, ch. 2 p. 39+, ch. 5 p. 107+, ch. 6 p. 133+, ch. 7 p. 155+, ch. 8 p. 169+ | Backtesting/execution; mean reversion; currencies/futures; interday and intraday momentum; risk | Register separate momentum and mean-reversion hypotheses; test both on identical chronological FX quotes with spread, latency and slippage assumptions | V1 continuation/reversal and Candidate001/002 provide partial related code. There is no validated, cost-adjusted FX momentum-versus-mean-reversion comparison. Book chapter headings do not define production thresholds. |
| Ernest Chan, *Quantitative Trading*, 2nd ed. (EPUB; chapter headings inspected) | Finding ideas, backtesting pitfalls and transaction costs, risk management, mean-reversion versus momentum | Include costs and controls in the experiment contract; compare candidates on matched data and avoid selecting on the same sample used for tuning | Replay and research storage exist; a complete matched campaign with uncertainty and held-out periods remains open. EPUB has no stable print page references. |
| Robert Carver, *Systematic Trading* (EPUB; chapter headings inspected), ch. 2–4 and 7–11 | Rule construction/fitting, forecast combination, volatility targeting, sizing and portfolios | Keep raw candidate scores distinct from probabilities; combine only comparable evidence; calculate size only from explicit account/risk inputs | `AdaptiveOpportunitySelector` and V3 risk request/result contracts exist. Scores are not calibrated probabilities; Live risk limits and an accepted forecast/sizing policy are absent. EPUB has no stable print page references. |
| Joe Duarte, *Trading Futures For Dummies* (2008 PDF), ch. 7–8 pp. 101+, ch. 11 p. 185+, ch. 17–21 pp. 295–335 | Technical analysis, currency futures, trading plans, risk and execution | Use for instrument/mechanics checklists; do not treat futures examples as spot-FX edge evidence | OANDA spot-FX quote correctness and V3 plan contracts exist. Broker eligibility, conversion, margin and approved order sizing remain separate acceptance items. |

Only the listed pages/chapters or headings were inspected in this research pass. Do not claim to have implemented a complete book-derived trading rule from these broad topics.

## Candidate-to-engine map

| Candidate family | Rule source | Current status | Live decision role |
|---|---|---|---|
| Legacy V1 baseline / continuation / reversal / regime | Pinned `Research/scan-engine-control.js` | Existing control policies; not four independent validated strategies | Directional policy votes; no standalone structural stop/target |
| ORB Breakout + Retest | `ORBBreakRetestV1.swift`, PRD research definition | Versioned, tested NY session candidate; edge unproven | Structural plan candidate; a plan alone cannot pass the Live selector |
| London GBP/JPY range breakout + retest | `GBPJPYLondonBreakRetestV1.swift`; GBP/JPY validation PRD Candidate A | `GBPJPY_LONDON_RANGE_BREAK_RETEST_V1` is a deterministic M1, London-session research evaluator with required explicit thresholds, provider-native lineage, bid/ask, and causal quote gates; no validated parameter profile or edge claim | Registered as a research candidate only; no Live selector, notification, sizing, or order role |
| CHoCH + FVG + Fibonacci | `Candidate001.swift` (`candidate-001-v1`) | Completed-bar research analyzer with tests; edge unproven | Directional research vote; requires M15 confirmation in the Live adapter |
| Auction Failure Reversal | `Candidate002.swift` (`candidate-002-auction-failure-v1`) | OHLC-only research analyzer with tests; edge unproven | Live adapter aggregates M5 to M15 and can form a plan using the failed wick as stop and the prior range boundary as target; no broker size is authorized |
| Breakout + acceptance | Recovered STRIKE V3 PRDs and `STRAT_BREAKOUT_ACCEPTANCE_CONTRACT_PRD_2026-11-13.md` | `BREAKOUT_ACCEPTANCE_V1` implements deterministic confirmation with provenance and quote/cost gates. `BreakoutAcceptanceRangeBuilderV1` builds the prior completed-bar range for provider-native candles only; unverified derived bars fail closed. `BreakoutAcceptanceLifecycleV1` persists versioned evidence, source ordering, and terminal/re-arm behavior in `ResearchStore`; 10 focused lifecycle cases cover persistence, recovery, stale data, expiry, dedupe, and re-arm. Exact profile values and cost-adjusted edge evidence remain incomplete. | Partial research; no Live selector or order call sites |
| Trend pullback continuation | `scan-engine-control.js`; GBP/JPY validation PRD | V1 continuation is a partial policy; no dedicated multi-timeframe pullback evaluator | Registered as partial research; cannot claim independent family confirmation |
| Range rejection / mean reversion | GBP/JPY validation PRD; Chan mean-reversion research | `GBPJPYRangeRejectionV1` now implements the PRD's configurable Candidate C as a deterministic, provenance-carrying research evaluator; exact parameters still require preregistered campaigns and cost-adjusted evidence | Research candidate only; not wired into Live and cannot authorize orders |
| Liquidity sweep + reversal | V1 control features | Sweep/reclaim features exist in V1; no independent strategy contract/evaluator | Registered as partial research; V1 remains one correlated control family |
| Market regime router | V1 control policies | Regime features/policies exist; unified candidate selector has no separately validated regime-router candidate | Registered as partial research |
| Adaptive multi-timeframe selection | GBP/JPY validation PRD | No adaptive M1/M3/M5/H1 selector; current Live selector compares only present candidates | Registered as hypothesis; unavailable higher timeframes are not synthesized |
| Tokyo / Asian session sweep | Research hypothesis; Duarte is futures context only | No validated spot-FX session-sweep rule or cost-adjusted evidence | Registered as hypothesis; cannot vote in Live |
| Late-night tactical scalp | `PrimeScheduleSheet.swift` | The 11:00 PM–12:30 AM Pacific window is schedule-only, not evidence of edge | Registered as schedule-only partial research |
| Morning prime / New York focus | `PrimeScheduleSheet.swift`; ORB session rule | Session prioritization exists; separate edge and session-rule validation remain open | Registered as schedule-only partial research |
| Momentum / trend following | Chan momentum chapters; V1 continuation policy | No independent book-derived FX momentum rule or cost-adjusted campaign | Registered as hypothesis/partial control only; cannot vote in Live independently |
| Fixed-horizon comparisons | `ResearchExperiment.swift`, `SpotFXHistoricalReplay.swift` | Research arms exist; they are outcome comparisons, not additional BUY/SELL generators | Registered as research-only comparison family |

## Live signal composition rule

The Live strategy decision is assembled from one fresh OANDA observation. The evaluated candidates are the four pinned V1 policy variants (grouped as one Legacy V1 family), ORB, Candidate001, and Candidate002. A directional result requires:

1. A valid structural candidate with entry, stop and target.
2. At least one eligible, fresh vote from a different strategy family that agrees with the plan.
3. No eligible opposing vote, invalid spread, stale/missing quote, or malformed plan.

If any condition fails, the decision is `WAIT` with a reason. Candidate scores are ranking inputs only; they are not probabilities or evidence of expected profit. Candidate agreement is a deterministic rejection/confirmation rule, not a validated edge claim. Structural levels are informational until owner-approved risk sizing and order safeguards exist. Candidate001 does not yet create a structural plan; it can support or reject another family's plan.

## Research gates still required

- Register exact configuration, timeframe, source, stop/target policy and invalidation for every new strategy before evaluating returns.
- Compare candidates against pinned V1 and simple null benchmarks on matched chronological bid/ask data.
- Include transaction costs and conservative execution assumptions; resolve same-bar stop/target ambiguity as `AMBIGUOUS`.
- Report sample size, uncertainty, parameter-search count, regimes/sessions and untouched holdout performance.
- Keep candidates in research/shadow status until the promotion gate is satisfied; never infer Live order size from a strategy default.
