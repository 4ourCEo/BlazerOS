# Correctness Audit — CryptoEngine, MarketEdgeWindow, CompletedBarRing

**Date:** 2026-10-21
**Scope:** `Sources/BlazerCrypto/CryptoEngine.swift` (483 lines), `Sources/BlazerCore/MarketEdgeWindow.swift` (174), `Sources/BlazerCore/CompletedBarRing.swift` (116)
**Method:** full-file read, caller trace, dependency read (`CryptoCandle`, `CTAssets`, `CryptoDeskSignal`, `ScanKernel`, `FxSession`, `EngineSignal`), line-level verification of every claim.
**Baseline:** none — the three modules have **zero direct test coverage** (no `CryptoEngineTests`, `MarketEdgeWindowTests`, or `CompletedBarRingTests` exist).

**Totals:** 2 high, 7 medium, 9 low.

**Remediation (2026-10-21):** ME-H1, ME-M2 and ME-M3 are fixed — `MarketEdgeWindow.countdown(at:)` is now the single source of truth, backed by `FxSession.nextOpen(after:)` for the shut-market case. 7 regression tests added in `Tests/BlazerCoreTests/MarketEdgeWindowTests.swift`; full suite passes (160 tests). The remaining findings are open.

---

## 1. Summary of findings

### High

**CE-H1 — `Int(Double)` conversions are unguarded at the engine boundary.**
`CryptoEngine` converts computed `Double`s to `Int` in eleven places without a finiteness check:

- L99–100 `Int((momentumHigh / momentumMax) * 28.0)`
- L119 `Int(min(20.0, bodyRatio * 30.0))`
- L146 / L153 `min(15, Int((wick / atr14) * 20))`
- L167 / L173 `min(12, Int(sepPips * 2))`
- L191 / L196 `Int(... / 0.15 * 10)`
- L226 `min(10, Int((volSurge - 1.0) * 6))`
- L247 `min(5, Int((tradeSurge - 1.0) * 3))`

Swift traps on `Int(.nan)` and `Int(.infinity)`. There is no upstream gate: `CryptoCandle.from` (L56–78) validates only that the fields *parse*, and `CryptoCandle` has no `isFiniteOHLC` equivalent to the one `CompletedBar` already provides (`CompletedBarRing.swift:30`). A single `inf` or `nan` OHLC/volume/quoteVolume value from Binance or Kraken therefore reaches a trapping conversion.

Impact: hard crash on malformed feed data, in the signal path, with no recovery. Severity is high because the failure mode is a trap, not a bad signal.

Fix: add `CryptoCandle.isFiniteOHLC` (`time/open/high/low/close/volume/quoteVolume` finite, `high >= low`) and reject whole batches in `BinanceClient`/`KrakenClient`, or guard `evaluate` with `guard candles.allSatisfy(\.isFiniteOHLC)`. Additionally clamp before conversion (e.g. `Int((x * 28).rounded(.towardZero))` only after `x.isFinite`).

---

**ME-H1 — [FIXED] The live countdown targeted 9:00 AM for a window that ends at 10:00 AM.**
`IntelScreen.liveCountdownText()` (`Sources/LightningDesk/Screens/IntelScreen.swift:205`):

```swift
let remSec = max(0, (9 * 3600) - (totalMin * 60 + sec))
```

`MarketEdgeWindow.current` defines morning prime as `totalMinutes >= 300 && totalMinutes < 600`, i.e. 5:00–**10:00** AM PT (`MarketEdgeWindow.swift:63`). The countdown therefore reports `SUPREME PRIME ENDS IN: 00h 00m 00s` from 9:00 AM onward while the app still considers the desk in prime for another hour.

Impact: user-visible, wrong, and it occurs in the highest-attention window of the product. It also contradicts the status card on the same screen, which says prime is active.

Fix: derive the countdown end from the same constant the window uses, or better, move the countdown into `MarketEdgeWindow` so one implementation owns the schedule.

---

### Medium

**CE-M1 — Effective score floor is 75, but the reported conviction floor is 55.**
L369: `let conviction = min(97, max(55, domScore))`.
The engine emits a candidate at `domScore >= 25` (L285), but `CTAssets.minConviction = 75` (`CTAssets.swift:86`) vetoes anything below 75 (`CryptoDeskSignal.swift:84`). A 40-point signal is reported as 55 conviction and then silently vetoed. The number a user sees is neither the raw score nor the gate threshold, and the floor makes every candidate look at least "mid-conviction".

Fix: report the raw score (already available as `highScore`/`lowScore`) or drop the 55 floor and let conviction equal the clamped raw score. If the floor exists to avoid discouraging copy, it should not be in the engine.

**CE-M2 — Momentum/volume baselines use 13 bars while the comments say 14.**
L67–68 and L409: `Array(candles.suffix(14).dropLast(1))` yields **13** candles. The comments at L25, L212, L241 and the `Signal` docs call these 14-period averages. Either take `suffix(15).dropLast(1)` or correct the documentation. Low numeric effect, but it is a stated-contract mismatch in a scoring path.

**CE-M3 — Bollinger squeeze deducts from both scores, contrary to its own comment.**
L201–207 comments "Deduct 5 from the dominant score"; the code subtracts 5 from **both** `highScore` and `lowScore`. Because dominance is decided by *margin*, a symmetric deduction cannot change which side wins — it can only push a 25–29 point candidate below the 25-point emission threshold. Either the comment or the code is wrong. If the intent is "squeeze = direction unknown, reduce confidence", the deduction should apply to the emitted conviction, not to one side's score.

**CE-M4 — `directionScore` and `strength` can leave the 0…100 contract.**
`CryptoDeskSignal.make` (`CryptoDeskSignal.swift:23–25`) maps `HIGH → highScore` and `LOW → 100 - lowScore`. The engine's components sum to a maximum of **116** (28+20+15+12+10+10+5+16), so:

- HIGH directionScore ∈ 0…116
- LOW directionScore ∈ −16…100
- `strength = abs(directionScore - 50) * 2` ∈ 0…**132**

`ScanContract.swift:24` documents `score` as side-neutral and `EngineSignal.directionScore/strength` are plain `Double?` with no validation (`MarketModels.swift:39–40`). Anything downstream that assumes 0…100 (display, ledger analytics, research baselines) can receive out-of-range values.

Fix: clamp at the adapter (`max(0, min(100, …))`) and make the side mapping explicitly `HIGH → 50 + score/2`, `LOW → 50 - score/2`, which keeps the documented range by construction.

**ME-M2 — [FIXED] No countdown or weekend handling in the UI path.**
`MarketEdgeWindow.current` correctly returns `.offPeak(nextWindowDescription: "Market Closed", secondsUntilNext: 0)` when `FxSession.isOpen` is false (L48–50). `IntelScreen.liveCountdownText()` never inspects that case — it re-derives the next window from the clock alone (L218–231). On a Saturday at 10:00 PT it displays `NEXT PRIME IN: 13h 00m 00s` pointing at 23:00 Saturday, when FX is shut until Sunday 17:00. The countdown is wrong for the entire weekend.

Root cause is the same as ME-H1: a second, independent implementation of the schedule.

**ME-M3 — [FIXED] `secondsUntilNext` was computed and never read.**
The `offPeak` associated value is produced at L49, L54 and L88–90, but the only consumer (`detailText`, L41) discards it with `case .offPeak(let next, _)`. Grep across `Sources`, `iPhone`, and `Tests` finds **no reader**. The DST-aware arithmetic in L76–88 is dead code, while the UI re-implements a worse version (ME-H1/ME-M2).

Fix: delete the field, or make it the single source for the countdown and delete the duplicate in `IntelScreen`.

**ME-M4 — Pair conviction table disagrees with the shared caveat.**
`conviction(for:)` (L109–130) hardcodes win-rate strings for **8** assets (GBP/USD, USD/JPY, GBP/JPY, XAU/USD, USD/CAD, AUD/USD, EUR/USD, EUR/GBP). `EdgeEvidence.standardCaveat` (L142) claims "372 binary contracts across **6 pairs**, ~60 per pair". The tiles render `EDGE`/`CHOP` badges (`MarketsScreen.swift:190–201`) from this table while the caveat lives on other screens. Point estimates with no sample size attached to a specific pair are the kind of number that outlives its evidence.

Fix: attach `EdgeEvidence` (wins/sampleSize/CI) to each pair instead of string literals, and render the interval or the sample size next to the badge.

**CB-M1 — Ring load and read are not atomic under the shared instance.**
`ScanKernel.evaluate` does:

```swift
await ring.loadCompleted(completed)              // ScanKernel.swift:56
let ringBars = await ring.fetchLatestBars(...)   // ScanKernel.swift:57
```

Two separate `await`s on an actor. Interleaving is impossible for a private instance (the default parameter is `CompletedBarRing()`), but `CompletedBarRing.shared` / `EngineSupercharger` (`CompletedBarRing.swift:112–116`) is process-wide. Two concurrent scans sharing it can interleave, so scan B's `loadCompleted` lands between A's load and A's read — A then evaluates B's bars while labelling them A's asset.

Impact: silently wrong signals attributed to the wrong instrument. The default-argument pattern keeps this latent, but the singleton exists and is the named "Mac desk" entry point.

Fix: replace the pair of calls with one actor method that loads and returns in a single hop (`loadAndFetch(_:count:) async -> [CompletedBar]`), and/or remove the shared instance.

---

### Low

**CE-L1 — EMA smoothing is asymmetric for short histories.** `computeEMA` seeds on `period` bars and then updates over `suffix(period*3)` (L444). With 22 input candles, EMA(5) receives 10 updates and EMA(20) receives 2. The trend gate (`ema5 > ema20`) therefore compares a well-smoothed average against a barely-moved one. The comment "enough history for EMA to stabilise" is false at the 22-candle minimum. Require `>= period*3` history or document the seeding.

**CE-L2 — Doji counts as bullish.** `isBullish` is `close >= open` (`CryptoCandle.swift:41`). A flat candle is bullish, so it can satisfy the `prev.isBullish` precondition for bearish engulfing (L266). Body size is zero, so scoring impact is small.

**CE-L3 — Headline evidence matching can miss or contradict.** `directionalReason` (L392–403) keyword-matches. Engulfing evidence lines say "trapping sellers"/"trapping buyers" (L273/276), which match no keyword, so those signals always fall back to the generic headline. The bullish list contains "above" and the bearish list "below"; a LOW signal whose first matching line is "EMA(5) below EMA(20)" is correct, but the match is incidental to wording, not structure. Prefer structured evidence (a typed enum with a side), not string search.

**CE-L4 — Engulfing silently requires volume.** `volSurge >= 1.15` (L264/269); when `avgVol == 0` the surge defaults to 1.0 (L221), so the +16 component can never fire on a feed without quote volume. Reasonable, but undocumented.

**CE-L5 — WAIT path duplicates indicator work.** `waitSignal` (L406–416) recomputes ATR and average volume on every early return, including the `count < 22` path where ATR is 0. Minor cost on a hot path called per poll.

**ME-L1 — "Next prime: Market Closed".** `detailText` formats the closed sentinel as a next-window description (L41–42), and `PrimeScheduleSheet` renders `detailText` in the status card (`PrimeScheduleSheet.swift:99`). On weekends the card reads "Next prime: Market Closed".

**ME-L2 — Wilson interval accepts impossible inputs.** `wilsonScoreInterval` (L161–173) does not require `0 <= wins <= total`. Negative wins produce `p < 0` and a negative radicand, which `max(0.0, …)` silently masks into a degenerate interval instead of surfacing the bug. Add a precondition or return `nil`.

**ME-L3 — Two time zones in one feature.** Windows are Pacific (`MarketEdgeWindow`), session gating is New York (`FxSession`). This is intentional and correct today (5:00 AM PT = 8:00 AM ET), but nothing documents the relationship, and a future change to either constant silently shifts the effective window.

**CB-L1 — Ring assumes chronological append.** `loadCompleted` (L69–78) appends in input order and `fetchLatestBars` treats append order as time order. A descending batch produces a reversed ring whose "newest" bar is the oldest. No sort, no assertion. Document the precondition or sort defensively.

**CB-L2 — Silent truncation past capacity.** `loadCompleted` keeps only the last `capacity` bars (128), and `fetchLatestBars(count:)` clamps to `stored`. `ScanKernel` asks for `completed.count`, so a >128-bar history is silently shortened with no signal to the caller. Safe today (Oanda fetches 120 M1, `OandaClient.swift:250`), latent if the count changes.

**CB-L3 — O(n²) load.** `loadCompleted` calls `append` per bar, and `append` calls `indexOfTime`, which scans all stored bars (L97–107). At capacity 128 this is trivial; the capacity is caller-controlled, so the cost is unbounded in principle.

---

## 2. What is correct

Worth stating explicitly, because these are load-bearing:

- **Momentum normalisation is right.** `momentumMax = 12.0` matches the true maximum of `Σ weight × volMult × bodyFactor` (L96–100).
- **Ring index arithmetic is right.** `fetchLatestBars` is correct both before and after wrap; `start = stored < capacity ? 0 : head` and `(start + i) % capacity` return oldest→newest in order (L86–94). Duplicate-timestamp replacement does not disturb `head`/`stored` (L55–58).
- **Wilson score interval is the standard formula**, including the `z²/4n²` continuity term and clamping (L161–173).
- **FX session weekday logic is correct**: Sunday opens at 17:00 NY, Friday closes at 17:00 NY, Saturday shut (`FxSession.swift:8–22`).
- **Late-night window wrap is correct**: `totalMinutes >= 23*60 || totalMinutes < 30` covers 23:00–00:29 (L68).
- **DST is handled by `Calendar` + `TimeZone`, not by fixed UTC offsets** — the right call.
- **`CompletedBar` rejects incomplete and non-finite bars at append** (`CompletedBarRing.swift:54`), which is exactly the guard `CryptoCandle` is missing (CE-H1).

---

## 3. Recommended tests (currently zero)

Priority order — each maps to a finding above.

1. `CryptoEngineTests.finiteInputGate` — feed a batch containing `inf`/`nan`; assert no trap and a `WAIT` (CE-H1).
2. `MarketEdgeWindowTests.countdownMatchesWindow` — for every minute 00:00–23:59 in both DST regimes, assert the countdown end equals the window end (ME-H1).
3. `MarketEdgeWindowTests.weekendCountdown` — Saturday and Sunday pre-17:00 ET must not report a prime countdown (ME-M2).
4. `CompletedBarRingTests.concurrentLoadFetch` — two tasks sharing `.shared`; assert no cross-contamination, or assert the API makes it impossible (CB-M1).
5. `CryptoEngineTests.scoreBounds` — synthetic batch that maximises every component; assert `directionScore ∈ 0…100` and `strength ∈ 0…100` through `CryptoDeskSignal` (CE-M4).
6. `CryptoEngineTests.baselineWindow` — 14 prior bars, one current; assert averages use 14, not 13 (CE-M2).
7. `CompletedBarRingTests.ordering` — descending input either sorts or is rejected (CB-L1).
8. `MarketEdgeWindowTests.wilsonRejectsInvalid` — `wins > total`, `wins < 0` (ME-L2).

---

## 4. What this audit does and does not establish

**Establishes:** correctness defects in scoring, schedule arithmetic, range contracts, and concurrency semantics, each with a file:line citation.

**Does not establish:** performance. No profiling was run, no benchmarks, no Instruments traces. Nothing here says whether the engine is fast. Two observations are performance-adjacent but unmeasured:

- `CryptoEngine.evaluate` allocates several intermediate arrays per call (`suffix(3)`, `suffix(14).dropLast(1)` twice, `suffix(15)`, `map` in EMA/BB/ATR). At a 2 s poll this is irrelevant; if it ever moves to per-tick, it is the first thing to fix.
- `CompletedBarRing.append` dedupe is O(n) per bar, O(n²) per `loadCompleted`. At 128 bars, irrelevant.

Both should be measured before being optimised.

**Not verified at runtime:** the test suite was not executed for this audit; findings are from source reading and caller tracing. A `swift test` baseline should precede any of the fixes above.

---

## 5. Suggested fix order

1. ~~**ME-H1 + ME-M2** — one-hour countdown error and weekend countdown.~~ **Done 2026-10-21.** Consolidated on a single `MarketEdgeWindow.countdown(at:)`, which now owns the schedule arithmetic; `IntelScreen` only formats the phase. Weekend now reports `FX MARKET CLOSED · OPENS IN: …` using `FxSession.nextOpen(after:)`.
2. **CE-H1** — finiteness gate before any `Int` conversion. One crash class removed at the boundary.
3. **CB-M1** — make ring load+read a single actor hop, or delete `.shared`.
4. **CE-M4** — clamp direction score/strength at the adapter.
5. **CE-M1/M2/M3, ME-M4, CB-L1/L2** — contract and documentation corrections.
6. **Tests** — 1–4 above first; they lock in the fixes.
