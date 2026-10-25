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

### Repository-level evaluation

The community repositories that actually connect to Pocket Option all authenticate with a full
`PO_SESSION`/SSID and most expose order methods. They were evaluated but not integrated:

| Repository | What it is | Why not integrated |
|---|---|---|
| [otcharts/pocket-option-api](https://github.com/otcharts/pocket-option-api) (MIT) | Official examples and client for the OTCharts data API; no SSID, no broker login, read-only | **Selected.** This is the repository behind the adapter in this branch. |
| [otcharts/otcharts-python](https://github.com/otcharts/otcharts-python) (MIT) | Dependency-free official Python client; used to verify the HTTP/SSE schema | Reference only; no Swift dependency. Confirmed the `-7,200 s` Pocket Option clock and the line-oriented tick stream. |
| [ChipaDevTeam/BinaryOptionsTools-v2](https://github.com/ChipaDevTeam/BinaryOptionsTools-v2) (custom personal licence) | Maintained Rust/Python/Node Pocket Option client with candles, streams and orders | Requires SSID; execution-capable; not read-only; Python/Node bridge, not native iOS. |
| [ChipaDevTeam/PocketOptionAPI](https://github.com/ChipaDevTeam/PocketOptionAPI) (MIT) | Older async SSID client, now superseded by the above | Same SSID/order boundary; no longer actively developed. |
| [lordralinc/pocket_option](https://github.com/lordralinc/pocket_option) (MIT) | Async session-based SDK with candle/deal storage and order management | Requires SSID; execution-capable; not read-only. |
| [TopTrenDev/pocketoption-signal-bot](https://github.com/TopTrenDev/pocketoption-signal-bot) (no licence) | EMA/RSI bot with unofficial API and Playwright fallback | Requires `PO_SESSION` + `PO_UID`; same adapter calls `place_order`; desktop-only. |

No native Swift Pocket Option client exists. A direct broker connection would therefore need a
Mac/VPS Python/Node bridge and a trading-capable session, which conflicts with the iPhone-first,
read-only design. OTCharts is the only evaluated repository that provides OTC data without either.

## Integration with PR #12

This branch is stacked on `upgrade/blazeros-v2-market-data-modularization` and merges PR #13's
research layer into it rather than replacing either branch. `LightningDeskModel` keeps PR #12's
`DeskMarketDataServing`, `MarketDataTransporting`, `CandleCache` and `ScanOperationCoordinator`
boundaries for OANDA/Binance and scan-worker lifetime. A new `DeskOTCResearchServing` boundary owns
OTC provider construction, streaming, validation persistence and the manual archive, so the facade
has no `URLSession`, `OandaClient`, `BinanceClient`, provider construction or scan-worker lifetime.
Research capture and scan scheduling are independent; backgrounding cancels both, and neither can
publish execution state.

## Implementation

- `ShadowMarketObservationProvider` extends PR #11's shadow architecture with typed source and
  venue identity, standard/OTC identity, quote/bid/ask, candle OHLC, raw and normalized provider
  timestamps, local receipt time, freshness, payout, market availability, connection state,
  verification state, provenance, and explicit research/entry-authority flags. A candle attached to
  a quote must carry the same instrument identity; payloads are validated before acceptance.
- `OTChartsProvider` is an actor using native `URLSession`, `Codable`, Swift concurrency, and the
  documented SSE transport. REST and stream transport plus the clock are injectable, so the
  controlled transport tests run without any network. The wire schema was cross-checked against
  the official `otcharts-python` client: `/v1/candles` returns `{"candles":[...]}` without a
  top-level symbol; `/v1/stream` dispatches one `data:` JSON line per tick with no required blank
  separator; a single-instrument tick may omit `symbol`; and a tick may carry `close` instead of
  `price`. The adapter accepts all documented forms and rejects a wrong or missing symbol when
  several instruments are requested.
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
  returned stream also has an explicit cancellation handle, so a stop finishes the consumer even
  when the provider never yields another element. The session persists at most one sample per
  second while keeping a live tick counter, rate, clock skew and interruption count, so a dense
  stream cannot flood the main actor or the archive.
- `OTCValidationPipeline` persists immutable paired observations with a retention cap and
  chronological pruning. Direction is measured open-to-open once per non-overlapping 60-second
  bucket keyed on the OTC provider's source time, not per adjacent tick. The compared prints must
  span 40–80 seconds and pass the same 3-second skew gate as the descriptive metrics. Flat buckets
  do not count as agreement, and standard/OTC identity must be continuous across a pair. The report
  exposes its retained coverage window and synthetic-sample count instead of implying that the
  archive is complete or clean.
- A stale weekend OANDA reference is excluded. The standard leg is reused only when the FX market
  is open, the desk quote is for EUR/USD and no more than five seconds old. OANDA remains a
  standard-market reference, never Pocket Option settlement data. The service, not the facade,
  constructs that reference observation.
- The Intel screen can save/remove the independent API key and capture the visible Pocket Option
  instrument, broker price, optional provider price, candle time (ISO 8601), payout, screenshot
  reference, agreement, and confidence. Manual records are isolated research evidence and cannot
  settle or authorize a trade.
- A systematic provider-clock offset is surfaced as a live diagnostic rather than silently
  excluding every sample. The fixed UTC+2 correction remains an unverified vendor assumption.

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

Documentation payloads and deterministic tests are not live market evidence.
`hasProviderOTCObservation` means only that the retained archive contains a non-synthetic-flagged
OTC print from a configured provider source; it never means verified, matched,
settlement-equivalent, or promotion-ready. The report status distinguishes
"NO PAIRED COMPARISON" from "INDEPENDENT VALIDATION REQUIRED", and a synthetic sample forces
`UNVERIFIED`.

## Verification (integrated head)

| Check | Result |
|---|---|
| `swift build` | PASS |
| `swift test` | **293/293 PASS** |
| Engine pin / intents drift | PASS |
| Parity | **43/43 PASS** |
| CoreAudit | **71/71 PASS** |
| Persist | **59/59 PASS** |
| Soak | **10/10 PASS** |
| iOS Simulator Debug | PASS |
| iOS Simulator Release | PASS |
| iPhone simulator tests | **15/15 PASS** |

## Controlled transport coverage

Deterministic tests exercise disabled configuration, injected transport, out-of-order and
duplicate-second ticks, future-dated ticks, wrong symbols, candle identity mismatch,
cancellation-ignoring producers, connection interruption and explicit reconnect, replacement,
throttling, incomplete candles, expired quotes, Keychain loading/removal, archive corruption,
retention pruning, non-overlapping 60-second bucketing, flat-bucket exclusion, stale weekend
reference exclusion, and background capture stop. Integration tests exercise scan scheduling and
OTC capture together, background cancellation of both, candle-cache isolation, archive/manual
evidence persistence across relaunch without ledger mutation, demo-cache freshness, and the iOS
Siri handoff after the scan coordinator releases ownership. Scheduler tests continue to cover
Siri/pending scans, scan supersession, and background invalidation; the production eight-second
gate is unchanged.

## Independent reviews

Two delegated reviews (Swift concurrency/architecture and execution
integrity/quantitative provenance) ran against the integrated tree. Findings corrected before
delivery:

- OTC capture cancellation now has an explicit stream handle. A stop or backgrounding finishes the
  consumer even when the provider never yields, so no stalled socket or task survives the session.
- The OTC service owns instrument identity, provider construction, streaming, standard-reference
  construction, validation persistence and the manual archive. The facade has no `URLSession`,
  `OandaClient`, `BinanceClient`, provider construction or scan-worker lifetime.
- Provider-domain types were removed from the facade; the desk now asks the service for its
  research identity and standard reference.
- The evidence flag was renamed to `hasProviderOTCObservation`. A synthetic-verification sample
  forces `UNVERIFIED`, and the report exposes the synthetic count and retained coverage window.
- The 60-second metric buckets on provider source time, compares the first print of each bucket,
  requires 40–80 seconds of spacing, and applies the same 3-second skew gate as the descriptive
  metrics. Overlapping adjacent-tick transitions no longer inflate agreement.
- A dead `providerDisconnections` field was removed; the desk now counts real connection
  interruption events from the capture stream.
- Demo bars are cached as stale display fixtures, never as fresh transport data.
- A systematic provider clock offset is surfaced as a diagnostic instead of silently emptying the
  comparison.
- Siri ingress now requires an idle scan coordinator, so it cannot replace an in-flight user scan.
- Scan-triggered reloads no longer erase a live research error message.
- Integration tests assert archived `researchOnly`/`mayAuthorizeEntry` flags, queue a real pending
  Siri request on iOS, and cover cancellation, demo-cache, synthetic-labeling and coverage behavior.
- The wire schema was verified against the official `otcharts-python` client and corrected: candles
  may omit the top-level symbol, SSE ticks are line-oriented without blank separators, a
  single-instrument tick may omit `symbol`, and `close` is an accepted price field.

Residual risks:

- The fixed UTC+2 provider normalization is a vendor claim. A DST or epoch change will produce a
  visible clock-skew diagnostic and failed observations, not silently wrong comparisons. No live
  key was available to validate it.
- `ScanOperationCoordinator` still awaits a cancellation-ignoring transport. Real transports are
  bounded by their own request timeouts; a provider that never returns would park scan ingress.
- Backgrounding an armed but never-entered beam still offers an outcome prompt (pre-existing PR #11
  behavior). It cannot create research evidence, but it is not a substitute for venue confirmation.
- Retention keeps the newest 5,000 samples. Coverage shrinks as evidence ages; the report now
  states the retained window rather than implying a complete archive.

## Next concrete step

Create a personal OTCharts key without purchasing a plan, select its Pocket Option book if the free
tier permits, and use the Intel capture session during a visible EUR/USD OTC session to record
matched instrument, price, time, payout, and screenshot references. If the free tier does not
include live SSE, use one documented candle/catalog request only; do not poll. Do not enable
ranking or entry use until prospective weekday and weekend samples establish source identity,
clock behavior, latency, missingness, and price/direction agreement. Provider purchase or a request
for any Pocket Option session secret requires separate approval.

## Delivery classification

- **IMPLEMENTED:** common contract, native REST/SSE adapter behind a `DeskOTCResearchServing`
  boundary, bounded Keychain-controlled capture, manual capture, validation archive/report with
  retention and coverage, and fail-closed transport seams. The facade keeps PR #12's market-data
  and scan-coordinator boundaries and contains no direct broker networking.
- **TESTED:** deterministic adapter, persistence, retention, security-boundary, bucketing,
  integration, and comparison behavior. Exact final suite/build totals are recorded in the pull
  request.
- **VERIFIED:** code behavior and default-disabled/read-only boundaries only.
- **RESEARCH-ONLY:** every provider observation, manual comparison, metric, and rolling evaluation.
- **BLOCKED:** direct broker API, live provider accuracy, matched broker prices, real latency, and
  any evidence-based promotion.
