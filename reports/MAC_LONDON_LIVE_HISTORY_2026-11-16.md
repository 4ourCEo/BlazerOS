# Mac London Break + Retest Live History Capture

## Goal and scope

Prepare an explicit, resumable OANDA Live M1 bid/ask history capture for the user-selected GBP/JPY London Break + Retest research profile. This is source/gap research only. Candle history cannot establish the evaluator's required post-retest quote time, qualify the campaign, promote a strategy, or authorize an order.

## Debate and design outcome

- Keep the existing deterministic London evaluator and production promotion gate.
- Use the OANDA instrument candle endpoint only, on the Live host, requesting GBP_JPY M1 bid/ask candles.
- Require an explicit `--confirm-live-market-data-read` flag, `--interactive-credentials`, and a bounded `--historical-days` value. Do not run this command during automation.
- Store Live history separately from Practice history, in UTC day chunks, with immutable payload hashes, source metadata, gap counts, and private file permissions.
- No account, position, order, or transaction endpoints are involved.
- Independent QA approved the design subject to these boundaries. User must explicitly initiate any real Live data capture.

## Implementation checklist

| ID | Status | Evidence |
|---|---|---|
| MAC-LONDON-LIVE-HISTORY-1: Add environment-gated Live candle request | Complete | `fetchLiveHistoricalBidAskCandles` requires `.live`; wrong-environment requests return before network access. |
| MAC-LONDON-LIVE-HISTORY-2: Add immutable, resumable UTC-day archive | Complete | Validates HTTP success, explicit Live provenance, GBP_JPY/M1 identity, day bounds, complete ordered valid candles; rejects conflicting hashes and nonprivate files. |
| MAC-LONDON-LIVE-HISTORY-3: Add explicit capture CLI | Complete | Requires Live confirmation, interactive credentials, and 1–3650 historical days; rejects Practice context and reports aggregate progress only. |
| MAC-LONDON-LIVE-HISTORY-4: Focused regression checks | Complete | Final `swift test --filter OandaHistoricalBidAskTests` passed: 8/8 with success-only receipt and receipt-bound `includeFirst`/fetch-time metadata. `swift test --filter SpotFXHistoricalReplayTests` passed 3/3; full Swift suite passed 709/709 across 17 suites. |
| MAC-LONDON-LIVE-HISTORY-5: Release ForwardTest build | Complete | `swift build -c release --product ForwardTest` passed in 151.87s; `ForwardTest --help` displayed the explicit Live capture flags. No compiler warnings were emitted. |
| MAC-LONDON-LIVE-HISTORY-6: Real Live capture | Awaiting explicit user action | Not run. Selecting the profile did not authorize a Live market-data request. |

## Current goal status

The Mac app has working strategy evaluators, including London Break + Retest, but no profile is promoted for production signals. The registry's empty promotion set still explains WAIT (`no_strategy_passed_live_promotion_gate`). This task improves the evidence collection path; it does not change that safety gate. The earlier authenticated Practice M1/M5 history probe returned HTTP 401, while the local GBP/JPY archive is labeled unauthenticated and has not met readiness criteria.

Next evidence needed: user-initiated Live history capture, independent archive validation, explicit strategy profile values supported by research, and a timestamped post-retest quote capture. Until then the strategy remains research-only and the Mac app may correctly show WAIT.

## Integrity follow-up — 2026-11-17

An implementation audit found that the original digest covered the candle batch but not the surrounding archive provenance. The canonical integrity digest now binds the full provenance envelope and candle batch, and archive reads cross-check duplicated request identity/interval fields, M1 granularity, retrieval timestamp, and recomputed gap count. A regression mutates `includeFirst` in an otherwise valid archive and confirms the archive is rejected. A URLSession protocol stub verifies the Live host/path and bounded M1 bid/ask query without contacting OANDA. Archive append now requires an opaque in-memory receipt issued only by a successful Live fetch; the receipt binds `includeFirst` and actual fetch time, so callers cannot archive caller-constructed/decoded batches or stamp a different retrieval time. Final focused tests **8/8**, SpotFX replay tests **3/3**, full Swift suite **709/709 across 17 suites**, Release `ForwardTest` product build, and `ForwardTest --help` all passed. No real Live capture was run.
