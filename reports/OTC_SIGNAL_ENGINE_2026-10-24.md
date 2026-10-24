# OTC research signal engine — V2.4

Date: 2026-10-24
Branch: `upgrade/blazeros-v2.4-otc-signal-engine`
Stack: builds on the #12 market-data/scan boundary and the #13 read-only OTC provider (merge `61fc0d7`).

## What this delivers

BlazerOS now has an isolated, deterministic OTC-specific research pipeline alongside the existing
FX and crypto desks:

1. First-class instrument contracts for OANDA EUR/USD, Pocket Option EUR/USD, and Pocket Option
   EUR/USD OTC. They are distinct identities with distinct IDs and are never aliased.
2. A deterministic OTC challenger that consumes normalized, completed OTC candles and a vendor
   quote and emits typed HIGH / LOW / WAIT signals.
3. A dedicated OTC research market mode in Lightning Desk with signal, score, freshness, feed
   quality, 60-second horizon, vendor payout, source identity, connection health, and an explicit
   RESEARCH ONLY status.
4. A replay/comparison harness with non-overlapping 60-second horizons, look-ahead rejection,
   broker-confirmed-only outcomes, payout-adjusted expectancy, Wilson intervals, delay sensitivity,
   provider disagreement, and stale-refusal measurement.
5. Regression tests for identity separation, evaluator vetoes, determinism, replay leakage, store
   integrity, and the desk's research-only execution barrier.

## Instrument contracts

| Contract | ID | Market | Venue | Session | Settlement |
| --- | --- | --- | --- | --- | --- |
| OANDA EUR/USD | `oanda:EUR/USD` | standard | OANDA | regular | spot reference |
| Pocket Option EUR/USD | `pocketoption:EURUSD` | standard | Pocket Option | regular | venue displayed |
| Pocket Option EUR/USD OTC | `pocketoption:EURUSD_otc` | otc | Pocket Option | weekend | venue displayed |

`OTCInstrumentCatalog.otcWatchlist(from:)` expands the research watchlist only from provider rows
that already declare OTC market kind, weekend session, venue-displayed settlement, and a `_otc`
symbol. Unknown or near-match tickers are ignored, never reinterpreted.

## Evaluator

`OTCResearchEvaluator` is a pure function of a frozen `OTCResearchInput` and a fixed
`OTCResearchConfiguration`. It does not call OANDA, the pinned engine, the entry gate, or the ledger.

Input validation (every check is a typed veto):

- exact OTC instrument identity and venue symbol suffix;
- finite, positive quote and valid bid/ask;
- quote age ≤ 5 s, no future timestamps;
- market open and connection `live`;
- at least 24 completed, valid, strictly aligned 60-second candles;
- newest close not in the future and no older than one interval;
- quote inside the last candle's envelope (two ATRs or 0.5 pip, whichever is wider).

Deterministic features (score-driving values rounded to eight significant digits for
cross-platform stability without distorting FX-scale ATRs):

- EMA 8/21 trend separation relative to ATR;
- five-bar momentum normalized by ATR;
- RSI(14) as an overbought/oversold trim, never a standalone direction;
- swing structure (higher highs/lows vs lower highs/lows);
- compression (`ATR5/ATR14 < 0.8`) and expansion/breakout;
- reversal (engulfing close beyond the prior extreme against the prior trend);
- continuation (close beyond the prior candle's extreme in the candle's direction).

Scores are integer sums of those contributions, capped at 100. A directional result requires a
score ≥ 60 and no conflicting trend/momentum block. WAIT is returned with explicit reasons for
insufficient confluence, conflicting signals, stale data, incomplete data, session closure, or feed
degradation. `scoreIsCalibratedWinProbability` is always false.

## Replay and comparison

`OTCResearchReplay.run` re-evaluates every stored record from its frozen input. It:

- rejects records whose candles or quote post-date the evaluation (look-ahead contamination);
- accepts only one signal per non-overlapping 60-second horizon, independently per instrument, so
  a EUR/USD OTC signal cannot suppress a valid GBP/USD OTC horizon;
- requires an outcome window with an explicit start and end, starts it no earlier than the signal,
  and requires the window to match the frozen 60-second horizon; a window that began before the
  signal is never counted;
- deduplicates broker event IDs and signals, so repeated settlement rows cannot inflate a sample;
- counts direction only from broker-confirmed outcomes with a venue event ID and valid prices;
  synthetic and unconfirmed outcomes are excluded;
- excludes flat outcomes from win rates and expectancy instead of silently scoring them as losses,
  because venue tie rules vary;
- reports HIGH/LOW/WAIT frequencies, coverage, decimation, stale and feed-unavailable refusal
  rates, invalid-confirmed rows separately, mean signal delay, Wilson 95% intervals, effective
  sample size equal to matched directional outcomes, delay-bucket sensitivity with a separate
  overflow row, payout-adjusted expectancy only when every matched directional outcome has a valid
  payout, and agreement with pinned-engine and OANDA-proxy decisions when supplied;
- replays each record under the engine/strategy/configuration frozen with that record and flags a
  mixed-version archive;
- always reports `promotionEligible = false`; a research report cannot promote a strategy.

The pinned engine is reused only through `PinnedEngineOTCAdapter`, and only when the OTC data is
technically eligible: completed/aligned 60-second bars, real bid/ask spread, and enough history.
The adapter reports the engine's own answer; it does not assume OANDA timing, M5 construction, or
thresholds transfer to OTC. OTC signals never modify the pinned engine or its SHA. The current
vendor stream supplies price-only ticks, so the desk does not manufacture a spread for the
comparison arm; the report explicitly records that pinned agreement is unavailable until a real
spread is captured.

## Lightning Desk integration

- `DeskMarket` gains `.otc`. The `marketMode` transition itself clears any production commit,
  frame, armed beam, and selection before evaluating research; it refuses to switch while an entry
  is being persisted. The view only triggers the refresh.
- `OTCResearchDeskService` fetches instruments, completed candles, and one bounded live tick,
  filters out the forming candle, evaluates, and archives the record.
- `refreshOTCSignal()` is the only producer of `otcSignal`; it never writes `commit`, `frame`,
  `armedAt`, `armID`, the ledger, or an `ActiveTrade`.
- `lockInTrade` refuses OTC mode, and `DeskEntryGate` has an unconditional `.researchOnly` veto.
- The OTC card has no entry action. It shows the instrument, HIGH/LOW/WAIT, score, freshness, feed
  quality, 60-second horizon, vendor payout, source/venue, engine/strategy versions, snapshot, and
  RESEARCH ONLY.

## Verification

Local verification on the final head (before reviews):

| Check | Result |
| --- | --- |
| `swift test` | 301 / 301 |
| `swift run -c release Parity` | 43 / 43 |
| `swift run -c release CoreAudit` | 71 / 71 |
| `swift run -c release Persist` | 59 / 59 |
| `swift run -c release Soak` | 10 / 10 |
| Engine pin + intents constants | PASS |
| iOS Simulator Debug build | BUILD SUCCEEDED |

Reproduce the focused research suite:

```bash
swift test --filter "otc|OTC"
swift test
```

Fixtures are constructed in `OTCResearchEngineTests`, `OTCResearchReplayTests`, and
`OTCDeskIntegrationTests`. They are deterministic synthetic inputs and are explicitly marked
`syntheticTestFixture` or documented as test fixtures; they never become outcome evidence.

## What remains unverified with real Pocket Option observations

This build has not been run against a live Pocket Option/OTCharts account. Therefore:

- No real OTC observations, vendor payouts, or broker-confirmed 60-second outcomes are archived in
  this repository.
- Provider attribution to Pocket Option is vendor-declared, not independently verified.
- The vendor's documented UTC+2 clock correction is preserved as a declared normalization, not
  proven against a second source.
- No calibration claim is made or possible: the deterministic score is not a probability, and no
  promotion gate is satisfied.
- Weekend-session behavior, provider gaps, reconnect behavior under real throttling, and real
  payout variability are unmeasured outside mocks.
- The OANDA proxy comparison arm is implemented and tested with injected decisions, but the live
  model does not fabricate proxy signals when OANDA is closed or stale.
- Entry-delay sensitivity is computed only from broker-confirmed outcomes that carry a delay; no
  such outcomes exist yet.
- Flat 60-second outcomes are excluded because the venue's tie rule is unverified. A real capture
  must document whether a flat is a loss, a push, or a refund before it can enter expectancy.
- The pinned-engine comparison arm needs a real bid/ask spread. The current provider stream is
  price-only, so the desk records `comparable = 0` rather than manufacturing a spread or a result.
- The live evaluator requires a live tick for the `live` feed-quality gate. Candles alone are not
  treated as a live feed and produce WAIT with `feedNotLive`.
- The configuration frozen with each record prevents silent pooling, but no archive with multiple
  real configurations exists yet to exercise migration behavior.

Any future promotion requires real, non-synthetic, independently verified observations, venue
event IDs, a prospectively registered analysis plan, and the existing `PromotionEvidenceGate`.
Nothing in this PR authorizes live OTC trading, broker-session extraction, or strategy promotion.
