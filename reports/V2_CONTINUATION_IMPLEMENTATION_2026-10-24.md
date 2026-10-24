# BlazerOS V2 continuation — 2026-10-24

## Repository reconciliation

- Working tree began clean on `upgrade/verified-execution-intelligence` at `f35fc69d158bf64f36b89c5bbe068f3fac77c5d3`, tree `b440493c6a5c12fe67da5d98154c03d56c831da7`.
- The existing PR #10 is open as a draft at <https://github.com/4ourCEo/BlazerOS/pull/10>, based on `main` at `4449fd03c7fdf9d537b0f4d430f1bbee491d5f0c`; its head is the baseline commit above. It is preserved unchanged.
- V2 work is isolated on `upgrade/blazeros-v2-60s-otc-research`, created from that verified PR #10 head. No existing worktree or branch was replaced.
- PR #10 already includes the statistical follow-up and execution-intelligence foundation. Mixed-payout return calculations, cash-P&L withholding for missing stake inputs, trusted/cohort-bound promotion review, effective N, preregistered complete test families, and Bonferroni correction are present. Their implementation and persisted ledger data were not changed here.
- Issue #6's duplicate BlazerCore linkage fix is already on `main` (PR #8 / commit `0d956bb`); issue #6 is closed.
- `LightningDeskModel.swift` remains large (about 2,300 lines after this work). Review found coupled scan orchestration and stale-response risks, so this change extracts only request scheduling. Execution state remains owned by the model.

## Implemented

### Scan lifecycle and bounded scheduling

`ScanRequestScheduler` carries a monotonically increasing generation and retains only the latest queued request. The desk runs one scan worker and one operation at a time. A superseding scan or pair selection cancels the active operation; FX requests retain their existing sequential asset order and pacing. Generation/mode checks after asynchronous fetch, pick, quote, credential, and persistence boundaries prevent obsolete results from publishing. `entryInFlight` joins the existing active-position, settlement, and awaiting-outcome scan locks.

Backgrounding invalidates outstanding requests and expires an unentered actionable beam. Foregrounding does not re-arm it. A closed-session early return cleans up scan UI state. Siri's queued scan is consumed after the worker relinquishes ownership, with a foreground guard, preventing a nested scan from awaiting its own worker and preventing a deferred request from starting after backgrounding.

Persistence still stores the original frozen scan. If its disk write completes after supersession, the historical record is retained while the old operation is prevented from reloading over newer visible state. Archive reloads are staged in locals and published only after asynchronous reads and a final generation check.

### Rolling revalidation research

`RollingRevalidation` evaluates candidate checkpoints at 8, 12, 16, and 20 seconds. The new evaluation calls the existing deterministic `StrategyEngine` with a fresh evaluation timestamp, then checks qualification, current quote age (2-second default), exact asset/source/venue/instrument, side, price envelope, expiry, engine/policy identity, and entry/settlement locks. It rejects future or incomplete 1-minute and 5-minute bars before calling the engine.

Each result binds its identity to the full baseline, input (including lock state), checkpoint, freshness limit, and engine/policy versions. It retains the original scan fingerprint and scan time, persists under the isolated `rolling-revalidation` research archive, and always marks itself research-only with `mayAuthorizeEntry == false`. Tests cover the four windows, stale/non-monotonic input, identities, locks, source/venue drift, envelope rejection, expiry, and isolated persistence.

Production entry behavior remains the existing 8-second gate. No automatic checkpoint collection, new live-entry path, or strategy decision change was added. 60 seconds remains the primary expiry; existing 180/300-second support is preserved.

### OTC shadow contract

`ShadowMarketDataProvider` is a read-only boundary. The only shipped provider is disabled and has no network transport, API key, or broker credentials. Synthetic examples are explicitly documentation-only. Standard EUR/USD and Pocket Option `EURUSD_otc` have distinct venue, symbol, session, and settlement identities.

Comparison only returns descriptive direction agreement, timestamp skew, and price displacement for synchronized standard/OTC observations. It validates identity, provenance, freshness, current and previous timestamp skew, and chronological ordering. The result cannot authorize entry or create a settlement.

Public documentation inspected:

- OTCharts API <https://otcharts.com/api> and Pocket Option API page <https://otcharts.com/pocket-option-api>: vendor documentation claims read-only OTC candle/tick access and uses `EURUSD_otc`; it describes bearer-key access, but does not document a clock/latency guarantee, redistribution terms, candle settlement equivalence, or a stability guarantee. The vendor's broker-sourcing statements were not independently verified.
- Pocket Option OTC assets <https://pocketoption.com/en/assets-otc/>: describes OTC availability/schedules and variable payouts, but not a timestamped price-feed contract or settlement data API.
- Pocket Option trading API article <https://pocketoption.com/blog/en/knowledge-base/trading/trading-api/>: no public price-data endpoint, provenance, timestamp, or candle semantics sufficient for this research was verified.
- OANDA instrument definitions <https://developer.oanda.com/rest-live-v20/instrument-df/>: reference candle timestamps and bid/ask/mid fields are documented. They do not establish equivalence with Pocket Option OTC settlement prices.

**Conclusion:** No OTC provider is independently verified for live use. Live OTC research remains disabled. There are no recorded/verified OTC fixtures yet; the included fixtures only test schema and fail-closed behavior.

### Existing execution-quality and assistant architecture

Execution attribution and the local read-only assistant context were already implemented on the baseline. They remain connected to confirmed records and isolated reference/proxy observations as before. This change did not invent a performance improvement or new statistical evidence. Foundation Models remain on-device, bounded, optional, and non-authoritative.

The native Xcode 27.1 run exposed an invalid `SystemLanguageModel.contextSize == 0` report even though availability and token counting worked. `SystemModelEngine` now treats nonpositive capacity as missing metadata and uses the existing conservative 4,096-token budget, preserving output reserve and safety margin. Positive capacity values are retained. The assistant stays available; a context-size metadata anomaly no longer makes every prompt appear too large. A deterministic regression covers zero, negative, and positive capacities.

## Measured results

The repeatable `ScanBenchmark` runs the same pinned `GoldenFixture.market()` input (80 M1 bars, 80 M5 bars) for 250 evaluations. It measures deterministic engine computation only.

| Measurement | Baseline | V2 working tree | Change |
|---|---:|---:|---:|
| p50 compute | 0.7441 ms | 0.7595 ms | +2.1% |
| p95 compute | 1.0804 ms | 1.2374 ms | +14.5% |
| mean compute | 0.7968 ms | 0.8477 ms | +6.4% |

The samples are too small to infer a meaningful regression or improvement; these numbers do not show a speedup. The engine SHA-1 remained `7c02e550e2e6ca656a258ceefc6083f098ff40b2`. Source age, provider fetch latency, publish latency, eligible-pair coverage, and provider failures are unavailable in this fixture-only benchmark and are not claimed. FX fetch remains sequential; OANDA limits were not independently established, so request fan-out was not increased.

## Verification

### Reported baseline, confirmed before this change

Native Xcode 27.1 / Swift 6.4 `swift test` passed 237/237, including available on-device Foundation Models tests. Release audits passed CoreAudit 71/71, Parity 43/43, Persist 59/59, and Soak 10/10. The exact existing outputs are retained under `/tmp/blazeros-v2-baseline-*.log`. Remote PR #10 CI was green at the baseline head and reported iOS Debug/Release plus 13/13 iPhone simulator tests on its CI Xcode image.

### Current V2 verification

- `swift test`: **252/252 PASS** on native Xcode 27.1 / Swift 6.4, including real on-device model generation/compaction cases where available. Output: `/tmp/blazeros-v2-integration-final-test.log`.
- Focused Foundation Models capacity tests: **2/2 PASS**, including native exact-budget probe and deterministic zero/negative fallback checks. Output: `/tmp/blazeros-v2-foundation-context-test.log`.
- `CoreAudit`: **71/71 PASS**, output `/tmp/blazeros-v2-core-final2.log`.
- `Parity`: **43/43 PASS**, output `/tmp/blazeros-v2-parity-final2.log`.
- `Persist`: **59/59 PASS**, output `/tmp/blazeros-v2-persist-final2.log`.
- `Soak`: **10/10 PASS**, output `/tmp/blazeros-v2-soak-final2.log`.
- `ScanBenchmark 250`: completed; output `/tmp/blazeros-v2-benchmark-final.log`.
- `EdgeReport`: reproduced against an explicitly empty scratch archive, fixed cutoff `2026-10-24T00:00:00Z`; [`EDGE_VERIFICATION_EMPTY_ARCHIVE_2026-10-24.json`](EDGE_VERIFICATION_EMPTY_ARCHIVE_2026-10-24.json) reports 0 resolved observations, effective N 0, and **INSUFFICIENT EVIDENCE**. This is a fail-closed control report, not a performance sample or a report of private app data. Reproduce with `swift run -c release -Xswiftc -DBLAZER_DISABLE_FOUNDATION_MODELS EdgeReport --root /private/tmp/blazeros-v2-empty-evidence-20261024 --as-of 1792800000` after creating that empty directory.
- `scripts/check-engine-pin.sh`: PASS (main `7c02e550e2e6`, control `1a1d264d44ee`).
- `scripts/check-intents-constants.sh`: PASS.
- `git diff --check`: PASS after implementation.
- iOS Debug build: **PASS**, `/tmp/blazeros-v2-ios-final-debug.log`.
- iOS Release build: **PASS**, `/tmp/blazeros-v2-ios-final-release.log`.
- iPhone Duo iOS 27.1 simulator suite: **13/13 PASS**, `TEST SUCCEEDED`, `/tmp/blazeros-v2-ios-final-simulator.log`.
- Independent current-diff quantitative review: no blocking findings; focused rolling/shadow tests 12/12 pass. Independent architecture review confirmed no remaining concrete finding after the worker-cycle and background guards. Both reviews inspected actual changed source. Architecture lifecycle interleavings were statically reviewed; no controlled suspended-transport integration seam was added.

An earlier full native run exposed the context-size-zero defect above (two assertions failed in the exact-budget test); it was repaired and the current 252-test run passes. The sandboxed SwiftPM/CoreSimulator attempts hit OS permission/service boundaries. Running SwiftPM, Xcode, and `simctl` outside the sandbox succeeded. Xcode logged `IDESchemeActionDeviceRecord`/`DVTBuildVersion invalidDigitCount(...)` while starting simulator tests; it eventually ran and passed all 13 tests. This was an Xcode diagnostic, not a source/test failure, and no MCP warning was implicated.

## Statistical result and independent engineering debate

**Promotion status: INSUFFICIENT EVIDENCE.** The current authoritative promotion gate is unchanged. The mixed-payout regression remains −0.280 per risk unit and −$78.00 cash P&L; missing stakes remain unavailable. The ten-test `p=0.01 → adjusted p=0.10` example still fails. No trading edge is established.

- **Reliability:** Keep one bounded worker and latest-request coalescing. Do not parallelize provider calls without verified provider limits. Keep existing frozen records and entry/settlement ownership in the desk.
- **Quantitative:** 8/12/16/20 seconds are preregistered research checkpoints only. Revalidation conditions select observations, so they must be analyzed as a dependent cohort and cannot be compared as four independent opportunities. No expectancy claim follows from passing code tests.
- **Market data:** OTCharts publishes claims but no independently verified timing/licensing/settlement contract was found. Keep its live adapter disabled until provenance, permissions, clock, candle, and weekend behavior are independently validated.
- **iOS:** Continue foreground-only fetch behavior. Backgrounding expires the actionable view; no unsupported background scan task was added. Foundation Models cannot affect the gate.
- **Execution:** BlazerOS cannot observe how long the user spends switching to Pocket Option on another device. No external-device delay estimate is fabricated. Freshness remains visible only from measured in-app data.

## Status

- **IMPLEMENTED:** bounded/generation-aware scan orchestration, background invalidation, research-only rolling evaluator and archive, disabled OTC adapter contract, deterministic tests, benchmark target.
- **TESTED:** current full Swift suite, focused context-budget tests, core/parity/persistence/soak audits, engine pins, intent constants, Xcode Debug/Release builds, and 13 simulator tests listed above.
- **RESEARCH-ONLY:** all rolling windows and OTC comparisons; no production gate or strategy policy changes.
- **BLOCKED:** independent live OTC data validation pending provider permissions, timestamp/latency contract, and trustworthy recorded observations.
- **UNVERIFIED:** physical iPhone manual instrument switching and background/force-quit recovery, Pocket Option execution/venue confirmation, airplane mode, Live Activities, Siri shortcuts on device. No real trade was placed.

## Remaining risks and next steps

1. Add a controlled injectable scan transport/clock seam to exercise cancellation-ignoring providers, out-of-order completion, and the Siri/credential lifecycle interleaving in tests.
2. Capture timestamped, permission-verified OTC observations before enabling any live research adapter; compare weekday/weekend windows separately.
3. Collect prospective manual-entry/venue-confirmed execution records and independently review dependence, missingness, and multiplicity before considering a strategy promotion.

No merge, deployment, live strategy promotion, or trade execution was performed.
