# BlazerOS V2.3 direct Pocket Option OTC research feed

Date: 2026-10-25

Branch: `upgrade/blazeros-v2.3-otc-market-data-integration`

Pull request: <https://github.com/4ourCEo/BlazerOS/pull/14>

Promotion status: **INSUFFICIENT EVIDENCE**

## Decision

A real Pocket Option EUR/USD OTC market-data feed is technically viable for this private app.
Using the user's explicitly supplied **demo** Socket.IO authentication frame, a native Swift
provider connected directly to Pocket Option, received `EURUSD_otc` quotes, current payout and
open state, and normalized the broker's UTC+2 timestamps. No Mac companion is required during
normal iPhone operation.

This is not an official or broker-scoped read-only API. The session is an unrestricted account
session even though BlazerOS implements only market-data messages. The integration is therefore
disabled by default, demo-session-only, Keychain-backed, bounded, research-only, and incapable of
authorizing an entry. No order, position, balance, transfer, or account-setting interface exists.

The viable source is a **real broker observation feed**, not yet a viable predictive trading
signal. Exploratory 60-second rule screening did not produce a candidate that survived basic
cross-instrument checks. No strategy is promoted and profitability is not claimed.

## Sources evaluated

| Source | Actual status | Decision |
|---|---|---|
| Pocket Option official API | No current public customer market-data API or scoped read-only token was found. | Official path remains unavailable. |
| Pocket Option direct session | Live `EURUSD_otc` quote, asset, payout and availability frames were observed through the broker's Socket.IO endpoint. Authentication uses a full demo account session. | **Selected for private, explicit, research-only capture.** |
| [BinaryOptionsTools-v2](https://github.com/ChipaDevTeam/BinaryOptionsTools-v2) | Its maintained Rust/Python/Node implementation established the current protocol shape. It also exposes order operations and requires the full session. | Used as a protocol reference only; no dependency was added. |
| [TopTrenDev pocketoption-signal-bot](https://github.com/TopTrenDev/pocketoption-signal-bot) | EMA/RSI automation over an unofficial session plus Playwright fallback; includes order placement and has no independent edge evidence. | Not a reliable signal source; not integrated. |
| OTCharts | Existing native REST/SSE adapter remains in the stack, but the live service was unavailable/not usable in this investigation. Its Pocket Option provenance remains a vendor claim. | Retained only as a disabled fallback; not the selected source. |
| OTC Market API | Independent paid API with no verified Pocket Option settlement equivalence or payout field. | Not selected and no subscription purchased. |
| SignalBots | Desktop/MT5-oriented mirror without a suitable native iPhone market-data contract. | Not selected. |

No third party received the Pocket Option credential and no subscription was purchased.

## Authentication and security

- The Intel screen accepts a complete Pocket Option **demo** auth frame only after explicit user
  action. It does not ask for or store the Pocket Option password.
- The frame is validated as demo (`isDemo == 1`) and stored in the device Keychain. It is never
  written to an observation, report, log, source file, Foundation Models prompt, or Git history.
- A stored credential does not start a connection. Capture begins only after the user taps Start,
  is bounded to five minutes by default, stops on backgrounding, and can be disconnected and
  removed immediately.
- The native provider sends only Socket.IO handshake/auth and market-data subscription messages:
  `assets/load`, `changeSymbol`, and `subfor`. It deliberately ignores account, balance, deal and
  chart frames. There is no trading API in the contract.
- This is application-side read-only behavior, not broker-enforced least privilege. A stolen auth
  frame may carry more authority than BlazerOS uses; users should remove it when research ends.

## Implementation

- `PocketOptionReadOnlyProvider` is an actor-backed native `URLSessionWebSocketTask` provider using
  the existing `ShadowMarketObservationProvider` contract. It exposes source/venue/instrument
  identity, price, broker and receipt timestamps, freshness, payout, availability, connection and
  verification state.
- The provider supports only one active stream, rejects wrong instruments, future/stale/out-of-
  order ticks, requires current payout/open metadata before every quote, and clears metadata on
  each asset refresh. Authentication alone never reports a live feed.
- Raw broker timestamps are preserved and normalized by `-7,200` seconds. Every accepted
  observation remains `researchOnly == true`, `mayAuthorizeEntry == false`, and
  `unverifiedVendorData` unless that individual print is manually matched.
- Direct broker observations are archived with `.directBrokerData` provenance. OANDA remains an
  independent standard-market reference and is never treated as Pocket Option settlement data.
- Capture prefers the explicitly configured direct demo session; the existing OTCharts adapter is
  only a fallback. A ten-second no-tick watchdog fails closed.
- The manual Intel workflow records the visible instrument, broker price, provider price, candle
  time, payout, screenshot reference, agreement and confidence without expanding the trading UI.
- Quantitative comparison now rejects the starting pair when its timestamp skew is outside the
  gate and never constructs a 60-second transition across different provider IDs.
- Historical candles are not exposed by the direct adapter. The validated direct surface in this
  change is live quote plus asset metadata; candle acquisition remains blocked pending a permitted,
  stable contract.

The pinned deterministic engine, eight-second live gate, manual execution, immutable scan
snapshots, persistence/recovery, outcome provenance, payout math, evidence thresholds,
multiple-comparison controls, Foundation Models isolation, and existing desk screens are unchanged.

## Real observations captured

The native Swift probe connected to the broker's demo endpoint and produced:

```text
symbol=EURUSD_otc price=1.12244 payout=77.0 open=true
normalized=1792946093.476 researchOnly=true actionable=false
```

Additional consecutive live prices were received in the same run. Payout changed across separate
observations from 92% to 64% to 77%, confirming that payout must be captured contemporaneously and
must never be treated as a static instrument property.

A visible Pocket Option EUR/USD OTC chart at 2026-10-24 23:29:10 -0700 displayed `1.11433` and a
92% payout. Direct feed prints at 06:29:08–06:29:09Z were `1.11433`–`1.11434`: a matched difference
of 0 to 0.00001 for that short observation window. This validates the connection and instrument
mapping, not settlement equivalence or general accuracy.

The broker timestamp was consistently two hours ahead of UTC in the observed frames and normalized
cleanly with the existing `-7,200 s` correction. The short probes showed consecutive updates, but
they are not long enough to claim a stable latency or update-rate distribution. Weekend coverage
was observed for `EURUSD_otc`; a controlled weekend OANDA comparison was not completed.

An exploratory broker-data screen covered approximately 19,980 ticks (about 5.5 hours per
instrument) and tested 16 simple 60-second candidates. None passed the cross-instrument evidence
checks. This screening is exploratory and is not promotion evidence.

## Verification

| Check | Result |
|---|---|
| Focused direct-provider/security/quant tests | **12/12 PASS** |
| Full `swift test` | **305/305 PASS** |
| CoreAudit | **71/71 PASS** |
| Engine parity | **43/43 PASS** |
| Persistence/recovery | **59/59 PASS** |
| Soak | **10/10 PASS** |
| iOS Simulator Debug build | **PASS** |
| iOS Simulator Release build | **PASS** |
| iPhone simulator tests | **INTERRUPTED — Xcode 27/iPhone 17 runner stalled while materializing test workers; the serial retry stalled in the first existing test. No test failure was reported before termination.** |

The new deterministic coverage includes the Socket.IO text/binary handshake, disabled/default
state, demo-only credential validation, Keychain save/removal, raw-clock normalization, wrong
instrument, future/out-of-order ticks, missing/stale metadata, auth-without-data, overlapping
streams, absence of historical/trading surfaces, failed credential removal, cancellation,
backgrounding, provider switching, and provider/skew-safe 60-second transitions.

## Independent reviews

### Review A — security and iOS architecture

The review found two concrete issues, both corrected:

- concurrent/replacement streams could share one mutable socket; the provider now permits exactly
  one active stream and scopes cleanup to its stream ID;
- failed Keychain deletion could make the UI claim the unrestricted session was gone; the UI now
  keeps it visibly configured unless deletion succeeds.

The review found no credential logging, raw-secret persistence outside Keychain, trading operation,
or background capture path.

### Review B — market-data and quantitative integrity

The review found four concrete issues, all corrected:

- generic direct ticks were overstated as manually matched; they are now unverified vendor data;
- payout/open metadata could survive a partial asset refresh; caches are cleared and required for
  each accepted tick;
- 60-second transitions could bridge two providers; provider identity must now remain continuous;
- a skewed starting pair could enter a later transition; all paired inputs now pass the skew gate
  before bucketing.

No live-entry, settlement, promotion, or look-ahead path was found.

## Delivery classification

- **IMPLEMENTED:** native direct Pocket Option demo-session feed, Keychain lifecycle, bounded Intel
  capture, live quote/payout/availability ingestion, direct-source provenance, liveness watchdog,
  transport/clock seams, manual comparison workflow, and quantitative integrity fixes.
- **TESTED:** 305 package tests plus the audit, parity, persistence, soak and Debug/Release iOS
  builds. The local Xcode simulator test runner limitation is recorded above.
- **VERIFIED:** direct broker connection, `EURUSD_otc` identity, live broker prices, dynamic payout,
  market-open state, timestamp normalization, and one short manual chart match.
- **RESEARCH-ONLY:** every direct observation, comparison, exploratory strategy result, and rolling
  8/12/16/20-second evaluation. None can authorize or settle a trade.
- **BLOCKED:** official scoped read-only authorization, direct historical candles, independently
  measured long-run latency/missingness, settlement equivalence, and any statistically qualified
  60-second predictive signal.

## Next concrete step

Run prospective five-minute captures from the Intel screen while the same EUR/USD OTC chart is
visible, save matched screenshots and payout values, and collect both weekday and weekend sessions.
Then evaluate pre-registered 60-second rules on held-out data under the existing effective-sample,
multiple-comparison and venue-confirmation requirements. Until one passes those controls, the honest
answer is: **the app now has a viable real OTC data feed, but it does not yet have a verified OTC
trading signal.**
