# ORB Structural Archive Replay — 2026-11-12

## Scope and evidence class

This is a retrospective, descriptive run on the previously explored OANDA Practice `historical-bid-ask` archive. It is **development-only**, not validation or a final holdout. The archive contains 20 successful Practice batches for EUR/USD and GBP/JPY at M1 and M5. All 20 SHA-256 values in the replay report matched the preserved source bytes during independent review. The output JSON records each filename, source hash, request range, transport/status, candle count, and observed time bounds.

The replay uses `ORB_BREAK_RETEST_V1` and its existing defaults: a 5-minute opening range, 120-minute setup window, structural stop from the range/retest, and 2R target. It does not tune configuration. The 120-minute value expires a setup **before plan generation**; it is not imposed as a post-entry trade horizon.

Plan-generation OHLC is a synthetic per-field bid/ask side-average. Bid and ask extrema may not be synchronous, so it is not an independently supplied authentic midpoint-candle path. Exit-touch evaluation then uses chronological M1 bid/ask OHLC bounds (long: bid; short: ask). A first candle touching both levels is ambiguous; a missing M1 interval before a later touch makes the outcome unresolved. A one-sided touch records only a candle time interval—not an exact touch time or fill.

## Results

| Instrument | Represented dates | Opening-range eligible | Full setup window covered | Insufficient opening range | Full-window sessions without plan | Unique plans | Entry quote within plan max spread | Structural classifications |
|---|---:|---:|---:|---:|---:|---:|---|
| EUR/USD | 10 | 8 | 8 | 2 | 3 | 5 | 5 | 3 stop touches; 1 target touch; 1 unresolved coverage gap |
| GBP/JPY | 10 | 8 | 8 | 2 | 4 | 4 | 0 | 4 entry spreads exceeded the unchanged `0.0003` plan limit |

Repeated candidate evaluations were deduplicated by plan ID: 537 repeated decisions for EUR/USD and 434 for GBP/JPY. These counts and the nine unique plans are **not** independent trade counts. No missing or incomplete opening-range day is counted as a no-plan session; no full-window session was censored in this archive slice.

The GBP/JPY entry-spread failures describe incompatibility with the existing ORB plan limit, not failed exits and not evidence to loosen the limit. The entry check is a source-matched candle-close quote feasibility observation only.

## Interpretation limits

- Stop/target touch classes are observations from candle OHLC bounds, not broker-confirmed executions, positions, or fills.
- No exact intrabar path, execution delay, slippage, commission, P&L, net R, expectancy, drawdown, or profitability is inferred.
- A structural touch is not converted to a 60/180/300-second fixed-duration result.
- OANDA pricing-stream events are not complete tick history; the archive is candle-based and cannot establish exact ordering within a dual-touch candle.
- The sample is short and already explored. It cannot provide independent validation, robust market-regime comparisons, or a trading-edge claim. The final holdout remains unused.

## Reproduction

Copy only the authorized `historical-bid-ask` input directory into a scratch root, then run:

```sh
swift run ForwardTest --orb-structural-archive \
  --root /path/to/scratch-root
```

The command reads `<scratch-root>/historical-bid-ask` and writes `<scratch-root>/structural-replay/orb-structural-report.json`. It validates Practice filename/range identity, transport, HTTP status, candle identity/integrity, and overlapping batches; conflicting duplicate candles fail closed. The JSON output SHA-256 for this run is `b3d0bca1cce013b0e85a5984265938361c1b42d7b0c9dc1f88507845aa6d3fbd`.

The source archive is read-only and must not be used as the output root. The report is a measured research artifact, not a trading recommendation.
