# GBP/JPY Strategy Validation PRD

Date: 2026-11-10  
Status: Draft for implementation  
Scope: Research-only GBP/JPY validation in BlazerOS; no order placement or live-capital authorization.

## 1. Product decision

Build one deterministic GBP/JPY research campaign that compares three closely related
strategy families across 1-minute, 3-minute, and 5-minute decision bars:

1. London-session range breakout and retest.
2. Trend continuation after a completed-bar break of structure.
3. Mean-reversion rejection at a pre-defined session range boundary.

The campaign must use the same frozen inputs, quote authority, spread/slippage model,
chronological holdout, and outcome rules for every family. A YouTube result or nominal
win rate is only a hypothesis source; it cannot qualify a strategy.

## 2. Why this shape

The six external research references contribute complementary pieces:

| Input | Adopted idea | Boundary |
|---|---|---|
| [OANDA v20 samples](https://github.com/oanda/v20-python-samples) | Authentic practice-account candles, pricing, and instrument handling | Data adapter only; never a strategy authority |
| [pyprasad/fx-backtester](https://github.com/pyprasad/fx-backtester) | Bid/ask-aware fills, candle construction, walk-forward workflow | Adapt its mechanics to GBP/JPY and Swift contracts |
| [PTHAICAP/backtest-engine](https://github.com/PTHAICAP/backtest-engine) | Costs, lag, spread multipliers, purged splits, deflated statistics | Use as statistical design inspiration, not as an unreviewed dependency |
| [st3fansrb/forex-research](https://github.com/st3fansrb/forex-research) | No-lookahead checks, bootstrap intervals, regime/OOS reporting | Synthetic examples are not market evidence |
| [nateemma/fx-strategy-framework](https://github.com/nateemma/fx-strategy-framework) | Explicit causal rules, walk-forward optimization, parameter tracking | Daily/FRED-oriented pieces do not transfer directly to minute FX |
| [TradeTide](https://github.com/MartinPdeS/TradeTide) | Local experiments, bid/ask simulation, cost-aware research layout | Reimplement the minimum needed inside BlazerOS |

Video hypotheses to formalize and test:

- [London Breakout, 300+ trades backtested](https://www.youtube.com/watch?v=MeCReaTLX2Q)
- [London Open Breakout parameter comparison](https://www.youtube.com/watch?v=xWGSEjit6OY)
- [GBP/JPY supply/demand and liquidity, 5-minute](https://www.youtube.com/watch?v=SDaUX06-GAk)
- [GBP/JPY price-action technique](https://www.youtube.com/watch?v=IwTA-E0OGQk)

These videos are not validated claims. Their rules must be translated into executable,
unambiguous conditions before they enter the campaign.

## 3. User and non-goals

### User

The operator needs a morning research desk that can answer:

> “For GBP/JPY today, which of the three rule families is eligible on 1m, 3m, or 5m,
> what evidence supports it, and how uncertain is that evidence?”

### Non-goals

- No automatic broker or Pocket Option order placement.
- No conversion of OANDA proxy outcomes into Pocket Option settlement outcomes.
- No claim that engine score equals win probability.
- No tuning on the held-out cohort.
- No promotion from 50 nominal trades alone.
- No mixing of synthetic, OANDA proxy, OTC, and venue-confirmed records.

## 4. Strategy contract

Every candidate must implement the same interface:

```text
evaluate(asset, timeframe, completedBars, quote, sessionContext) -> CandidateDecision
```

`CandidateDecision` contains:

- strategy ID and version;
- timeframe: 1m, 3m, or 5m;
- direction: LONG, SHORT, or WAIT;
- signal timestamp and completed-bar cutoff;
- entry reference, stop reference, target reference;
- maximum allowed spread in pips;
- expected holding horizon;
- reason codes and all input IDs;
- deterministic input digest and engine/strategy version.

### Shared rules

- Only completed candles may create a signal.
- The entry quote must be newer than the final candle and within the freshness limit.
- Bid/ask must be preserved; midpoint-only outcomes are proxy-labelled.
- No overlapping event may count as independent evidence within the configured cluster block.
- A spread rejection is a valid result, not a missing trade.
- A signal is not an entry until the quote, time, direction, and risk constraints pass.
- Stop and target must be ordered correctly and sized from observed GBP/JPY volatility.
- Entry delay is measured and replayed; zero-latency assumptions are not accepted for promotion.

### Candidate A — London range breakout/retest

- Build the configured London opening range from completed 1m bars.
- Require a completed-bar close outside the range.
- Require a retest within a bounded number of bars.
- Enter only when the retest holds and direction agrees with the break.
- Stop: range boundary plus a configured volatility buffer.
- Target: fixed R multiple, with R values selected on training only.
- Session, range width, break distance, retest tolerance, and spread cap are recorded.

### Candidate B — trend continuation / structure break

- Detect a completed-bar break of a prior swing high/low.
- Require directional alignment from the higher aggregation available without lookahead.
- Enter on the first eligible pullback, not on an intra-bar assumption.
- Stop: invalidation swing plus volatility buffer.
- Target: fixed R multiple or time expiry, selected before holdout evaluation.
- Record structure ID, break bar, pullback bar, and regime label.

### Candidate C — range rejection / mean reversion

- Define a session range and its upper/lower boundary.
- Require rejection evidence: boundary touch, close back inside, and no spread violation.
- Enter opposite the rejected boundary only after the bar closes.
- Stop: beyond the boundary and volatility buffer.
- Target: range midpoint or fixed R multiple, chosen on training only.
- Disable the candidate during expansion conditions defined before the test.

## 5. Timeframes and outcome model

### Decision bars

Run the same candidates on 1m, 3m, and 5m bars. Where the source feed is 1m,
3m and 5m bars must be deterministically aggregated from completed 1m data and carry
their source-bar digest.

### Holding horizons

Evaluate at 60s, 180s, and 300s for comparability with the current ForwardTest runner.
Also record stop/target-first resolution for the spot-FX shadow path. The two outcome
families must never be combined into one win rate:

- Binary-style directional proxy: labelled proxy and unverified for venue claims.
- Bid/ask spot shadow: net movement after spread and configured additional costs.

Unknown, stale, missing, contradictory, and late observations remain unresolved and are
reported separately.

## 6. Data and provenance requirements

Required per event:

- GBP/JPY instrument identity and provider/environment;
- source candle timestamps, OHLC, and completed-bar status;
- bid, ask, spread, quote timestamp, and receipt timestamp;
- session and timezone/DST interpretation;
- strategy family/version and parameter digest;
- pinned engine SHA and repository build identity;
- input digest, event ID, cluster block, and duplicate key;
- entry delay and observation latency;
- outcome source, resolution quality, and reason for exclusion.

The OANDA practice feed is suitable for source-shaped research, but it is not Pocket
Option settlement evidence. Pocket Option remains read-only/research-only and quarantined.

## 7. Experiment design

### Phase 0 — deterministic fixture validation

- At least 100 hand-authored edge cases covering breakouts, false breaks, retests,
  spread rejection, stale quotes, DST boundaries, gaps, ties, and incomplete candles.
- Replay must reproduce the same decision, digest, and reason codes byte-for-byte.

### Phase 1 — 50-event smoke pass

- 50 eligible GBP/JPY events per candidate/timeframe combination where available.
- This is an implementation gate only, not evidence of an edge.
- Confirm zero lookahead, no duplicate events, and complete outcome coverage.

### Phase 2 — larger prospective sample

- Target at least 250 independent clustered eligible events for a candidate/timeframe.
- Keep a frozen 70/30 chronological split; freeze the boundary before holdout review.
- Training may choose parameters; holdout may only evaluate the frozen specification.
- Continue collecting if the effective sample size is materially below 250.

### Phase 3 — rolling revalidation

- Re-run the frozen candidate on rolling windows without changing rules mid-window.
- Track performance by session, spread bucket, volatility regime, direction, and delay.
- Any parameter change creates a new strategy version and a new holdout boundary.

## 8. Acceptance gates

A candidate is **research-promising** only if all are true:

- At least 250 independent clustered eligible events on the held-out cohort.
- No unresolved provenance or outcome-coverage defect that could change the result.
- Positive cost-adjusted expectancy under the conservative cost model.
- Cluster-adjusted lower Wilson bound clears the conservative break-even threshold.
- Results remain directionally consistent across at least two of the three timeframes,
  or the single-timeframe specialization is explicitly documented.
- No single session, day, or regime accounts for the majority of the apparent edge.
- Replay, export, and report generation are deterministic.
- Independent review signs the evidence; the report still cannot authorize live trading.

A candidate is **rejected/quarantined** if any are true:

- The apparent edge disappears after spread/slippage/entry-delay costs.
- The holdout was inspected to choose parameters.
- Effective sample size is below the gate and no uncertainty is shown.
- The result relies on synthetic or midpoint-only evidence while claiming venue performance.
- The strategy requires discretionary chart interpretation that is not encoded.
- The GBP/JPY feed repeatedly fails freshness or spread quality checks.

## 9. BlazerOS implementation plan

### P0 — research contracts

- Add a versioned `GBPJPYStrategyCandidate` contract for family, timeframe, session,
  parameters, and rule digest.
- Add deterministic 1m-to-3m/5m aggregation with source digest and DST-safe session windows.
- Generalize `ForwardTest` beyond the current hardcoded `[60, 180, 300]` outcome list only
  through an explicit campaign configuration; preserve legacy decoding.

### P1 — strategy runners

- Implement the three candidates as research-only evaluators.
- Store decisions before outcomes, using the existing event/persistence path.
- Add spread, slippage, delay, range-width, and volatility filters as recorded parameters.
- Keep candidate output separate from the pinned production scan authority.

### P1 — evidence and reporting

- Extend experiment reports with candidate ID, timeframe, cost model, regime, and session.
- Add a matrix report comparing 9 cells: 3 strategies × 3 timeframes.
- Report nominal N, clustered blocks, effective N, coverage, unresolved count, cost-adjusted
  expectancy, conservative break-even, and lower/upper Wilson bounds.
- Add a “why not enough evidence” explanation for every failed cell.

### P2 — operator workflow

- Add a read-only campaign command that runs only GBP/JPY and emits a manifest before capture.
- Add a Review surface for campaign status, last valid quote, spread rejection count,
  unresolved outcomes, and holdout lock state.
- Add export/import of an immutable campaign bundle for independent review.

## 10. Proposed CLI

```bash
swift run ForwardTest \
  --asset 'GBP/JPY' \
  --campaign gbpjpy-v1 \
  --timeframes 1m,3m,5m \
  --strategies london-break-retest,structure-continuation,range-rejection \
  --horizons 60,180,300 \
  --max-events 50 \
  --root /path/to/research-archive
```

Required commands after implementation:

```bash
swift run ForwardTest --campaign gbpjpy-v1 --stats
swift run ForwardTest --campaign gbpjpy-v1 --edge-report --as-of UNIX_SECONDS
swift run ForwardTest --campaign gbpjpy-v1 --replay
```

The existing `--asset 'GBP/JPY'` filter is already available. The campaign, timeframe,
strategy, and cost-model flags are the next missing slice.

## 11. Test plan

- Unit tests for each candidate's entry, rejection, invalidation, and expiry rules.
- Aggregation tests for 1m/3m/5m boundaries, missing bars, duplicates, and DST changes.
- Property tests proving no signal uses a candle newer than the decision cutoff.
- Spread/slippage/delay tests proving net results change when costs change.
- Persistence restart, duplicate, conflict, and exact-replay tests.
- Statistical tests for frozen holdout, cluster adjustment, minimum effective sample,
  conservative payout break-even, and multiple-candidate reporting.
- A 50-event end-to-end smoke test using a deterministic fixture archive.
- Full package suite, CoreAudit, Parity, and the existing iPhone simulator suite.

## 12. Delivery definition

This PRD is complete when the repository can produce a reproducible 9-cell report for
GBP/JPY, even if every cell is marked insufficient evidence, and a reviewer can trace any
row from report → outcome → quote → completed candles → strategy version → engine SHA.

The first acceptable outcome is not “a winning strategy.” It is a trustworthy answer to:

> “Which rule set, if any, survives realistic costs and frozen out-of-sample testing?”

