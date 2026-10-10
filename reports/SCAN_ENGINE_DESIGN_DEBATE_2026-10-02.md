# BlazerOS scan engine: peak-hour analysis, alternatives, and design debate

Date: October 2, 2026. Scope: the bundled JavaScript engine, Swift scan and selection paths, live forward tester, and local recorded outcomes. This is an analysis and implementation plan; the trading engine was not modified.

## Decision

The best next research candidate is **a deterministic regime router with separate continuation and reversal setups, explicit entry timing, and horizon-specific calibration**. First repair outcome measurement, score semantics, and instrument units. Keep the present engine as the frozen control.

No alternative has demonstrated a higher future win rate yet. Raising the existing threshold, increasing stake, or adding more indicators is not supported by this audit. A worthwhile improvement must increase out-of-sample expectancy while retaining useful signal volume; a higher win rate on a tiny hand-picked subset is insufficient.

## 1. What the actual records say

Read-only source: `~/Library/Application Support/BlazerOS/scan_ledger.csv`, joined to its journal and snapshots. Reproduction: `python3 reports/analyze_scan_ledger.py`. Aggregate output is in `scan-ledger-analysis-2026-10-02.json`.

The ledger contains 490 HIT/MISS rows from September 27 through October 1, 2026, Pacific time. Of these, 375 have no engine hash or v2 metadata; 115 carry `1a1d264d44eec606ded991cb4814df953bc07b34`, matching the present pin. Matching the hash establishes the recorded engine identity, not verified venue execution or a known filtering policy.

| Recorded cohort | Wins / records | Win rate | Nominal 95% Wilson interval | EV per unit stake at assumed 88% payout |
|---|---:|---:|---:|---:|
| All records, mixed provenance | 242 / 490 | 49.4% | 45.0–53.8% | −0.0715 |
| All morning records by settlement time | 168 / 322 | 52.2% | 46.7–57.6% | −0.0191 |
| Versioned morning records | 54 / 113 | 47.8% | 38.8–56.9% | −0.1016 |
| All late-night records, mixed provenance | 15 / 27 | 55.6% | 37.3–72.4% | +0.0444 |
| Versioned late-night records | 0 / 2 | 0% | 0–65.8% | −1.0000 |
| GBP/USD, all records | 67 / 119 | 56.3% | 47.3–64.9% | +0.0585 |
| USD/CAD, all records | 32 / 88 | 36.4% | 27.1–46.8% | −0.3164 |

These are descriptive tallies of stored labels. Most versioned morning observations come from a single day, September 29. Overlapping horizons and shared USD exposure reduce effective sample size, so the nominal intervals overstate precision if treated as independent-trade evidence. Window classification above uses settlement timestamps because that is what the ledger stores; entry-time cohorts must be reconstructed separately before formal validation.

The code advertises morning rates of 59.1–61.2%, late-night 69.2%, and a 372-contract prior. The available records do not establish those peak-window claims. The historical 372-record source is not explicitly identified or segregated, and legacy rows cannot safely be assigned to the current engine version.

### Score and setup observations

Across all 115 versioned records:

| Existing score / explanation group | Wins / records | Recorded win rate |
|---|---:|---:|
| Score 80 | 10 / 13 | 76.9% |
| Score 82 | 8 / 21 | 38.1% |
| Score 96 | 17 / 34 | 50.0% |
| Score 100 | 3 / 9 | 33.3% |
| Scores ≥90 combined | 32 / 70 | 45.7% |
| “The climb is still going” | 27 / 47 | 57.4% |
| “Dip then bounce” | 12 / 34 | 35.3% |
| “Swept the low and reclaimed” | 12 / 27 | 44.4% |
| “Broke the prior high” | 3 / 7 | 42.9% |

This does not justify deploying “score 80 only.” Those buckets were inspected after observing results, are small, and confound pair and time of day. It does justify testing whether the score is miscalibrated and whether the bounce family should be selectively withheld. The explanation is only the highest-priority narrative branch, not a complete feature attribution: a “Climb” can include a structural break or other evidence.

Direction coverage is severely imbalanced: 487 rows are labeled HIGH, two TAP HIGH, and one TAP LOW. All 115 versioned rows are HIGH. That is an observed data limitation, not proof the engine cannot generate LOW. Bearish performance cannot be estimated from this sample.

## 2. How the engine makes its decision

Primary file: `Sources/BlazerCore/scan-engine.js`, especially lines 358–584.

1. Use M5 bars for context when at least 30 exist; otherwise use M1.
2. Calculate EMA21, EMA55, M1 RSI7, and context ATR14. EMA21 is returned internally but contributes no score points.
3. Set trend from live price relative to EMA55, with a neutral band of 0.12 context ATR. There is no EMA slope or trend-strength test.
4. Start a signed direction score at 50. Add/subtract trend 18, structural break 16, reclaimed sweep 22, extension 12, and trend-aligned bounce/reject 14.
5. Compress the score toward 50 for a tight range without a sweep.
6. Block a two-bar countertrend bounce/reject. Otherwise issue HIGH at score ≥72 and LOW at score ≤28.
7. Apply the spread gate. Produce entry/exit guidance; expiry affects the wording, not the directional score.

The score is a weighted direction index. It is not an estimated probability of winning. Several inputs are correlated manifestations of the same recent price move, so additive points can double-count evidence.

Examples: trend alone gives 68 and WAIT; trend plus an extended climb gives 80 and HIGH; trend plus bounce gives 82; trend plus break gives 84. A high score can therefore reward late entry into an already stretched move. Calling 96 “96% confidence” would be unsupported.

## 3. Concrete weaknesses and their implications

### A. Confidence has opposite semantics for LOW

JavaScript assigns `confidence = score` and `opportunity = confidence`. LOW requires score ≤28. The Swift `ScanKernel.commit` copies that low number directly; the forward tester instead uses `100 - rawScore` for LOW.

Desk selection sorts higher raw confidence first after its historical preference and timestamp rules. A diagnostic with equal timestamps selected HIGH80 over equally strong LOW20. A second diagnostic selected newer LOW0 over older HIGH100, confirming timestamp priority can dominate signal strength.

Proposal: preserve a signed `directionScore`, introduce symmetric `strength = abs(directionScore - 50) * 2`, and keep `winProbability` as a separately calibrated quantity. This repair makes rankings coherent; it does not itself prove a win-rate increase.

### B. Mixed timeframes weaken the chop gate

`rangeIsTight` compares the last eight M1 bars' total range with ATR computed primarily on M5 bars. A larger M5 ATR can classify a legitimate M1 trend as tight. Conversely, trend is determined from position around EMA55 without slope, allowing price above a flat average to count as uptrend.

Proposal: normalize each feature on its own timeframe and distinguish directional efficiency, compression, trend, and shock. Preserve separate M1 ATR and M5 ATR.

### C. Extension and sweep logic need separate setup policies

The engine adds bullish points when an up-move is extended and bearish points when a down-move is extended. That can be appropriate for momentum, but risky for a short expiry after exhaustion. A wick crossing and reclaiming a ten-bar extreme is called a liquidity sweep without depth, wick/body, follow-through, or location tests. OHLC establishes a price pattern, not actual order-book liquidity removal.

An outside candle that sweeps both sides returns the low-sweep case first. A flat RSI series returns 100 when both gain and loss are zero. These are suitable diagnostic test cases; their financial impact requires replay evidence.

### D. Gold units differ by 1,000×

Swift treats XAU/USD pip size as $0.10. JavaScript's two pip helpers use $0.0001 for every non-JPY instrument, including gold. This affects the absolute spread floor and slippage threshold. The spread gate can still pass gold when the bar-range term dominates; the mismatch is not a claim that every gold scan is rejected.

Proposal: one versioned instrument-specification contract containing price increment, display precision, normalization unit, and explicit gold handling. Compare spread in price units and relative to horizon volatility rather than using a generic FX pip rule.

### E. Peak hours are a schedule, not an engine regime

`MarketEdgeWindow.current` uses 05:00–10:00 PT and 23:00–00:30 PT. JavaScript has no session input. Phone scans check whether FX is open, but do not enforce prime-only trading. ForwardTest enforces prime only when smart scheduling is enabled.

The stored “prime” comment equates Pacific hours to fixed UTC hours; that correspondence changes with daylight saving. The actual calendar implementation uses America/Los_Angeles and handles Pacific offsets. A London-open hypothesis requires Europe/London session timestamps, including weeks when US and UK DST transitions differ; 23:00 PT should not automatically be equated with London open.

Proposal: retain Pacific schedules for the user's display, add UTC timestamp and exchange-session tags for analysis, and test morning subwindows separately. Add currency-relevant scheduled-news exclusions. Research links announcement surprises to exchange-rate jumps; it does not establish an optimal exclusion duration for this engine. [Andersen et al., NBER](https://www.nber.org/papers/w8959)

### F. Entry price and signal timing can drift apart

The desk scans six assets sequentially, with a minimum 1.1 seconds per asset and shared HTTP rate limiting. It then refreshes the selected price and replaces the strike without rescoring. A newly fetched strike may no longer match the original setup. If that refresh fails, the path can continue using the earlier strike.

The current slippage gate principally catches adverse movement; a favorable move can also mean the opportunity has already run and now offers a poor entry. A “better price” and a “move in the predicted direction” are different concepts.

Proposal: cache completed bars, evaluate candidates against a common quote batch, track signal age and minute phase, and require an entry-envelope check on the newest verified quote before arming. Do not silently mutate the frozen setup. Research capture should retain local completed observations under a distinct schema and existing CloudKit exclusions.

### G. Forward testing and desk execution are different strategies

ForwardTest adds symmetric conviction, an FX spread maximum of 0.4 pips, a gold maximum of $0.35, and an anti-extension text filter. The desk does not apply the same policy. The conviction ≥70 filter is effectively redundant once the JS HIGH/LOW threshold has fired: actionable symmetric conviction is already ≥72.

The desk passes `trades: []` to `pickDesk`, so its built-in historical pair heat never influences selection. It passes 85% payout there, while settlement and stats assume 88%. Historical conviction labels are not a calibrated selection policy.

Proposal: one deterministic, versioned eligibility and selection contract shared by desk, replay, and forward runner. Use structured feature flags, not substring matching on English evidence.

### H. Outcome labels cannot yet verify actual execution edge

The UI settles from cached `currentPrice` without an expiry timestamp freshness requirement. ForwardTest obtains a fresh quote after its loop notices expiry, retries later when unavailable, and does not bound settlement lateness. Sequential six-pair scans require roughly 18 HTTP requests per full cycle; the shared limiter allows three per second, before settlement requests and latency. This can create variable scan phase and delayed labels.

The application tells the user to execute on Pocket Option but labels outcomes using OANDA midpoints. Those are proxy outcomes unless actual venue strike, expiry, payout, and resolution are reconciled. Do not model a fixed-payout contract as an OANDA spot bid/ask round trip; record the venue's real contract terms. OANDA spread can be a quality feature rather than the contract's literal transaction cost.

At least one stored versioned row has entry equal to exit. The code counts equality as MISS. Actual venue tie handling must be specified.

The synthetic benchmark uses a random walk, supplies the same M1 sequence as M5, writes to the same default persistence root, and records the journal outcome before calling `settle`; the coordinator then rejects an already-settled journal entry. Consequently dashboard counts and ledger writes can disagree. Do not run this benchmark against the production root to measure edge. The sampled ledger's bars are predominantly 119/120 bars rather than the benchmark's 61; this audit does not assert that synthetic benchmark results account for the existing legacy rows.

Snapshots contain M1 bars, but omit the M5 input, quote timestamp, spread, horizon, entry delay, and complete feature vector. A snapshot-only replay cannot exactly reproduce the original scan. Hashes are eight hexadecimal characters of M1 OHLC, excluding asset, M5 inputs, quote, engine version and horizon; they are useful display fingerprints, not unique research event IDs. Multi-horizon results at 180/300 seconds are held in runner memory and are not written as separate ledger outcomes.

Proposal: separate `research_events` and `research_outcomes`, with event UUIDs and full input digests, durable multi-horizon labels, source provenance, and VALID/UNRESOLVED/TIE/INVALID states. Never force missing expiry evidence into MISS.

## 4. Alternatives and design debate

The following is a structured debate among design positions, not claims of independently validated strategies.

| Alternative | Argument for it | Strongest objection | Decision |
|---|---|---|---|
| Raise existing threshold to 90 | Easy; fewer trades | Versioned ≥90 group won only 45.7%; score is not calibrated | Do not deploy; include only as an ablation |
| Use only historically strongest pair/hours | Fast selective improvement | Small samples, changing regimes, correlated exposures, post-selection bias | Shadow test; no permanent hard-coded winner |
| Separate continuation and reversal | Avoid blending incompatible entry logic; explainable | Router and setup boundaries introduce parameters | Preferred first challenger, with few frozen rules |
| Trend continuation only | Current narrative subgroup is strongest; peak directional sessions plausible | “Climb” narratives hide overlapping features; can buy exhaustion | Test independently before adding reversal |
| Sweep/rejection reversal only | Better entry after displacement/reclaim | OHLC does not prove liquidity; versioned sweep subgroup weak | Secondary challenger with location and wick gates |
| Longer fixed expiry, 180 or 300 seconds | Better match to M5 context; less sensitivity to a few seconds | Longer horizon can reverse the outcome and increases overlap | Paired shadow labels for every eligible event |
| Regularized logistic probability model | Calibrates features and payout-aware abstention | 115 versioned observations insufficient for many interactions | After clean data; pooled model with limited features |
| Gradient boosting / nonlinear model | Captures interactions and regimes | More overfitting, harder explanation and parity | Only if it beats the simpler model on untouched data |
| Tick/order-flow engine | Could improve entry timing | OANDA is a sampled broker feed, not centralized FX order-book flow | Use quote dynamics as features; no order-flow claims |
| LLM selects HIGH/LOW | Flexible narratives | No calibrated evidence, nondeterminism, violates core contract | Keep the coach explanation-only |

**Debate resolution:** the rules advocate argues for simplicity; the statistical advocate argues that existing point sums lack calibration; the execution advocate argues that any edge estimate is meaningless with ambiguous expiry labels. All three are partly right. Resolve this by repairing measurement first, testing two small interpretable setup families, then using a restrained probability calibrator only when the sample supports it.

More research trials increase the risk of selecting noise. Freeze candidate rules and maintain a trial registry rather than repeatedly promoting the latest attractive subgroup. [Bailey et al., The Probability of Backtest Overfitting](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf)

## 5. Proposed design

Flow: validated completed M1/M5 input → timeframe-normalized features → regime router → setup eligibility → fixed horizon policy → calibrated probability / evidence sufficiency → entry timing and payout gate → frozen decision → verified completed outcome.

### Continuation challenger

Require M5 directional slope and separation, M1 directional efficiency, a fresh break or controlled pullback, sufficient remaining room to the next opposing level, and acceptable spread relative to M1 ATR. Penalize chase distance from the trigger in ATR units. Exclude shock and compression regimes. Compare 60/180/300-second fixed policies; choose a horizon from prior training data, never from the subsequent observed result.

### Reversal challenger

Require a sweep of a level defined before the trigger candle, significant rejection wick, decisive reclaim close, and no ambiguous two-sided sweep. Require range/reversal context rather than strong opposing continuation. Compare immediate reclaim entry against one explicit confirmation rule. A confirmation may improve quality while worsening entry; measure that tradeoff at the actual delayed entry.

### Probability and selection

Calibrate the probability of a winning resolution conditional on setup, pair/session context, and horizon. Begin with pooled setup estimates and shrink sparse groups; later compare a regularized logistic model. The direction strength remains a descriptive feature, not a probability.

At net payout ratio `r`, binary no-tie expectancy per unit stake is `EV = p*r - (1-p)` and break-even is `p = 1/(1+r)`. At 88% payout break-even is **53.19%**; at 85%, **54.05%**; at 70%, **58.82%**. These formulas assume a loss costs one stake and exclude fees and refunds; adapt to actual tie/void terms.

Reject invalid inputs and uncertain entry evidence first. Rank eligible candidates by conservative payout-adjusted expectancy, calibrated uncertainty and correlation constraints. Freshness is an eligibility gate; a one-millisecond timestamp difference should not override a substantial quality difference among otherwise valid signals. Use WAIT when evidence is insufficient.

OANDA's stream can reduce polling delays, but provides at most four prices per second per instrument and does not deliver every price. It improves capture granularity without guaranteeing the exact contract settlement price. [OANDA pricing stream documentation](https://developer.oanda.com/rest-live-v20/pricing-ep/)

### Research event schema

Capture event ID; input digest; engine and policy versions; asset; quote source and timestamp; scan and entry times; UTC and Pacific/session tags; M1 and M5 completed bars with close boundaries; features and all vetoes; direction and strength; calibrated probability if available; intended horizon; actual venue strike and payout when available.

Outcome records reference event ID plus horizon and label source. Store target expiry, observed quote time, observation lateness, entry/exit values, tie policy, venue reconciliation and quality state. Keep quote observations local and out of CloudKit; exported research files require the existing document/data rules to be reconciled explicitly before implementation. Raw credentials never enter research capture.

## 6. Experiment and promotion plan

| Stage | Deliverable | Acceptance condition |
|---|---|---|
| 0. Measurement | Isolated research root, durable horizon outcomes, provenance, expiry quality checks | Every reported result has traceable input, entry and resolution; unknowns remain explicit |
| 1. Contract repairs | Symmetric strength, instrument specs, consistent policies, full-input replay | Same frozen inputs and policy produce identical decisions across replay, desk and runner |
| 2. Clean baseline | Capture all candidates and WAIT/veto reasons in both peak windows | Baseline coverage and missing-label rates are reported; no synthetic/live mixing |
| 3. Limited ablations | Baseline; baseline plus timing/quality gates; continuation-only; gated reversal | Rules and parameter budgets registered before opening evaluation data |
| 4. Walk-forward evaluation | Chronological training/validation/test periods with overlap purging | Entire trading days kept together; at least the maximum label horizon excluded around boundaries, extended where needed |
| 5. Shadow comparison | Frozen champion/challenger evaluated prospectively on common inputs | Improvement survives entry-delay and payout sensitivity, and is not one-day or one-pair driven |
| 6. Promotion | Versioned shared engine artifact and updated parity pin | Untouched test evidence supports positive expectancy and a credible improvement over control |

Use paired comparisons for shared events and day-block bootstrap intervals for expectancy and win-rate differences. For selective policies, report both eligible-event comparisons and full policy results including abstention. Cluster concurrent correlated pairs. Log every trial and any subsequent rule changes. Do not optimize on the final holdout.

Primary metric: payout-adjusted expectancy per stake with uncertainty. Parallel metrics: resolved win rate, accepted signals per peak hour, overall opportunity coverage, unresolved-label rate, drawdown, streaks, pair/session concentration, probability calibration, and sensitivity to realistic entry delays.

Investigate 0/2/5/8-second entry delays and fixed 60/180/300-second horizons as registered sensitivity scenarios, using actual later quotes for entry. These values are experiments, not optimized defaults. For venue contracts use their actual duration/expiry convention.

Do not declare an edge from “100 trades and ≥60%.” Roughly 100 independent trials at 60% have a Wilson lower bound near 50%, below 88%-payout break-even. Hundreds of clean outcomes across many days are a minimum starting point for a narrow policy; detecting small improvements reliably can require thousands. Plan sample size using the registered improvement target and observed day-level dependence, not a universal trade count. Avoid repeated significance checks without a sequential-testing plan.

The existing local sample is development evidence only. It cannot be the untouched final test after this analysis.

## 7. Priorities and limits

1. **First:** fix expiry labels, isolate synthetic testing, persist all horizons, and capture reproducible inputs. This improves trust in the measured win rate.
2. **Next:** repair score semantics and gold units, unify eligibility, and prevent late/chased entries. These are concrete engineering defects or mismatches; their performance impact must be measured.
3. **Then:** shadow continuation-only and gated reversal candidates by session and fixed horizon. This is the best-supported strategy research direction, not a promised increase.
4. **Later:** calibrate probability and payout-aware abstention; evaluate nonlinear models only against the simpler frozen challenger.

Audit validation: the earlier Swift build succeeded, with 43 parity checks and 58 persistence checks passing. During this analysis, Node diagnostics reproduced directional ranking and timestamp priority; the read-only Python ledger analysis completed successfully. Those checks establish software behavior, not profitable trading. No live market requests, credential reads, synthetic benchmark execution, or strategy modifications were performed for this report.
