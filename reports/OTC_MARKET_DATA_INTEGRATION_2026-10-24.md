# BlazerOS V2.2 personal OTC market-data integration

Date: 2026-10-24  
Branch: `upgrade/blazeros-v2.2-personal-otc-data` (stacked on PR #11 head `8190b54`)  
Promotion status: **INSUFFICIENT EVIDENCE**

## Decision

Direct Pocket Option account connectivity is **not suitable for activation**. No current official
customer market-data API or broker-issued read-only authorization scope was found; the supposed
official API page returns 404. Established unofficial clients require a captured authenticated
`SSID`/Socket.IO session and include order methods. An application-side wrapper cannot make that
session genuinely read-only, so BlazerOS does not request, capture, store, or replay it.

The implemented research source is **OTCharts**, an independent provider, because its current
documented contract is the most complete iPhone-compatible data-only interface evaluated: HTTPS
bearer-key authentication, exact Pocket Option `EURUSD_otc` identity, a live instrument catalogue
with open/closed and payout fields, REST candles, and server-sent-event ticks. It requires no
Pocket Option password, browser cookie, or account session. Its claim that the `otc` book is
sourced from Pocket Option remains a vendor claim and is not treated as independent verification.

All connections remain disabled by default. The API key is optional, stored only in the local
device Keychain, removable immediately, never persisted with observations, and never supplied to
the trading engine or Foundation Models. No order or account endpoint exists in the implementation.

## Current provider comparison

| Source | What was verified from current documentation | Security / platform | Decision |
|---|---|---|---|
| Pocket Option official | [OTC assets](https://pocketoption.com/en/assets-otc/) document weekend OTC availability and variable payouts. The proposed [API page](https://pocketoption.com/en/api/) returns 404 and provides no quotes, candles, timestamps, read-only scopes, or customer API contract. | No documented scoped token; no native API contract. | **BLOCKED** for direct access. |
| Unofficial Pocket Option clients | Public clients such as [chipadevteam/pocketoptionapi](https://github.com/chipadevteam/pocketoptionapi) instruct users to capture the complete WebSocket authentication message/SSID; related client APIs also expose trade actions. | Full account session, undocumented endpoints, Python/Rust/JS dependencies, no broker-issued read-only scope, material session-theft and breakage risk. | Rejected; not integrated. |
| OTCharts | [API documentation](https://otcharts.com/api) documents `GET /v1/symbols`, `GET /v1/candles`, and SSE `GET /v1/stream`; `EURUSD_otc`; 5–60 second candles; open/closed state; paid payout fields; a 200-request first-month free tier without streaming; and documented Pocket Option UTC+2 timestamps. | Independent bearer key; HTTPS; platform-neutral REST/SSE works with native `URLSession`; no Mac companion. Vendor provenance, licensing permission, SLA, latency, and settlement equivalence are not independently verified. | **Selected, research-only, disabled by default.** |
| OTC Market API | [Documentation](https://otcmarketapi.com/api-documentation) advertises `X-API-Key`, REST quote/candles/pairs, WebSocket ticks/candles, ISO/epoch timestamps, and plans starting at $100. | Documentation recommends keeping keys behind a backend; no payout field, weekend guarantee, Pocket Option EUR/USD provenance proof, source-capture description, or broker authorization was found. | Not selected; weaker provenance and higher personal-use cost. |
| SignalBots | [Connector page](https://signalbots.ai/connectors/binary-options/mt5-pocket-option-otc) describes an unofficial terminal-to-MT5 mirror and claims it cannot trade. | Requires a logged-in Pocket Option terminal plus desktop MT5; no public REST/SSE/WebSocket contract, timestamp schema, iOS path, payout API, or broker-issued restricted credential. Access is affiliate/support dependent. | Not suitable for an independent iPhone app. |

No subscription was purchased and no third party received a Pocket Option credential.

## Implementation

- `ShadowMarketObservationProvider` extends PR #11's shadow architecture with typed source and
  venue identity, standard/OTC identity, quote/bid/ask, candle OHLC, raw and normalized provider
  timestamps, local receipt time, freshness, payout, market availability, connection state,
  verification state, provenance, and explicit research/entry-authority flags. A candle attached to
  a quote must carry the same instrument identity; payloads are validated before acceptance.
- `OTChartsProvider` is an actor using native `URLSession`, `Codable`, Swift concurrency, and the
  documented SSE transport. REST and stream transport plus the clock are injectable, so the
  controlled transport tests run without any network.
- Raw Pocket Option book timestamps are preserved. The documented UTC+2 value is normalized by
  `-7,200` seconds for comparison and is never silently discarded. A tick whose normalized time is
  more than five seconds ahead of the local receipt clock is rejected. Equal source-second prints
  are retained; only strictly older prints are rejected as out of order.
- Instrument mapping must remain exact (`Pocket Option`, `EURUSD_otc`, OTC,
  `venueDisplayed`). Wrong-symbol, malformed, non-finite, stale, or future-dated observations fail.
  Server-supplied SSE event ids are never persisted; observations receive a local UUID.
- The adapter reports connection, closed/dropped, replacement, throttling, and network failures.
  It does not retry invisibly, extend timestamps, or surface raw remote error text in the UI.
- One explicit Intel-screen action starts a bounded (default five-minute) capture. It never runs
  automatically, stops on backgrounding, and cancels a stalled stream through a watchdog. The
  session persists at most one sample per second while keeping a live tick counter and rate, so a
  dense stream cannot flood the main actor or the archive.
- `OTCValidationPipeline` persists immutable paired observations with a retention cap and
  chronological pruning. Direction is measured once per non-overlapping 60-second bucket, not per
  adjacent tick, so overlapping transitions cannot inflate agreement. Flat buckets do not count as
  agreement, and standard/OTC identity must be continuous across a pair.
- A stale weekend OANDA reference is excluded. The standard leg is reused only when the FX market
  is open, the desk quote is for EUR/USD and no more than five seconds old. OANDA remains a
  standard-market reference, never Pocket Option settlement data.
- The Intel screen can save/remove the independent API key and capture the visible Pocket Option
  instrument, broker price, optional provider price, candle time (ISO 8601), payout, screenshot
  reference, agreement, and confidence. Manual records are isolated research evidence and cannot
  settle or authorize a trade.

## Evidence state

| Category | Result |
|---|---|
| Real OTCharts EUR/USD OTC observations | **0 — no user API key was available** |
| Direct broker observations | **0 — no broker session was requested or captured** |
| Matched broker/provider observations | **0 — capture workflow is implemented, but no matched observation was supplied** |
| Measured real latency / skew / update rate | **UNVERIFIED — tests use synthetic fixtures only** |
| Weekend broker/provider comparison | **UNVERIFIED** |
| Live entry authorization | **DISABLED / PROHIBITED** |
| Research promotion | **INSUFFICIENT EVIDENCE** |

Documentation payloads and deterministic tests are not live market evidence. `capturedLiveVendorData`
means only that a real, non-synthetic OTC vendor print exists in the archive; it never means
verified, matched, settlement-equivalent, or promotion-ready. The report status distinguishes
"NO PAIRED COMPARISON" from "INDEPENDENT VALIDATION REQUIRED".

## Controlled transport coverage

Deterministic tests exercise disabled configuration, injected transport, out-of-order and
duplicate-second ticks, future-dated ticks, wrong symbols, candle identity mismatch,
cancellation-ignoring producers, connection interruption and explicit reconnect, replacement,
throttling, incomplete candles, expired quotes, Keychain loading/removal, archive corruption,
retention pruning, non-overlapping 60-second bucketing, flat-bucket exclusion, stale weekend
reference exclusion, and background capture stop. Scheduler tests continue to cover Siri/pending
scans, scan supersession, and background invalidation; the production eight-second gate is
unchanged.

## Independent reviews

Two delegated reviews (security/iOS architecture and market-data/quantitative integrity) ran
against the working tree. Findings corrected before delivery:

- Unbounded per-tick archive growth and a full-archive decode on every scan save removed: capture
  is rate-limited to 1 Hz, the archive is capped and pruned, and the report is refreshed at launch,
  on capture finish, or on explicit request.
- Per-tick `@Published` churn removed by publishing tick telemetry at most once per second and
  assigning connection state only on change.
- A cancelled capture can no longer mutate a newer session: the run id is checked before and after
  persistence.
- Remote-controlled error text is no longer rendered in the UI.
- The misleading `verifiedLiveEvidence` flag was replaced by `capturedLiveVendorData`, and the
  60-second metric was corrected to non-overlapping buckets.
- Future-dated ticks/candles, server-controlled event ids, transition identity continuity, manual
  archive ordering, and manual candle-time capture were corrected or added.

## Next concrete step

Create a personal OTCharts key without purchasing a plan, select its Pocket Option book if the free
tier permits, and use the Intel capture session during a visible EUR/USD OTC session to record
matched instrument, price, time, payout, and screenshot references. If the free tier does not
include live SSE, use one documented candle/catalog request only; do not poll. Do not enable
ranking or entry use until prospective weekday and weekend samples establish source identity,
clock behavior, latency, missingness, and price/direction agreement. Provider purchase or a request
for any Pocket Option session secret requires separate approval.

## Delivery classification

- **IMPLEMENTED:** common contract, native REST/SSE adapter, bounded Keychain-controlled capture,
  manual capture, validation archive/report with retention, and fail-closed transport seams.
- **TESTED:** deterministic adapter, persistence, retention, security-boundary, bucketing, and
  comparison behavior. Exact final suite/build totals are recorded in the pull request.
- **VERIFIED:** code behavior and default-disabled/read-only boundaries only.
- **RESEARCH-ONLY:** every provider observation, manual comparison, metric, and rolling evaluation.
- **BLOCKED:** direct broker API, live provider accuracy, matched broker prices, real latency, and
  any evidence-based promotion.
