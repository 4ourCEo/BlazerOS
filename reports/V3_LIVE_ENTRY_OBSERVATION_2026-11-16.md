# V3 Live plan entry market observation

**Task:** `V3-LIVE-ENTRY-OBSERVATION`
**Status:** Integrated after independent exact-diff review PASS. Full Swift and iOS simulator build verified; targeted UI result unavailable due to Xcode result-log failure.
**Parent objective:** `reports/V3_AUTONOMOUS_CONTINUATION_LOOP.md`

## Debate evidence

- `V3PlanEntryEvidence` stores an exact `planID`, a bid/ask `V3MarketObservation`, quality, and record time. It is market evidence, not an order, fill, or position. ForwardTest and authentic replay currently produce only `.simulated` evidence.
- Active `LightningDeskModel.publishORBDecision` persists an immutable ORB plan and setup lifecycle event but receives no quote. In `refreshORBMonitor`, the publisher runs before the fetched quote is validated. The quote must never be read from the model's mutable cached property after an async suspension.
- The monitor validates a matching asset quote after the response, and `LiveQuote` carries bid, ask, OANDA source time (`asOfMs`), and provider label, but no receipt timestamp, sequence, or environment. The local response receipt time and authenticated session can supply receipt/environment; sequence must remain nil.
- `ResearchStore.record(V3PlanEntryEvidence)` validates the event itself and writes immutably but does not bind it to an exact persisted plan or serialize plan-check-plus-append across store instances. Review joins by exact plan ID and currently checks instrument identity.
- Three independent read-only audits agree the safe producer hook is after durable plan publication and quote validation in the authenticated Live OANDA FX refresh. They warned against equating ORB confirmation, plan validation, or a quote with a user/broker fill.

## Ranked scope proposal

1. In the active Trade Live OANDA FX monitor, consider evidence only for the exact candidate plan that has already been durably written to `Research/live-oanda`.
2. The observation is an eligible **hypothetical shadow-entry market reference**, not a claim of user intent, order, fill, or position. Add a separate optional `maxEntryDeviation` to immutable `V3TradePlan` and preregister it in ORB configuration; it is distinct from `maxSpread`. Existing records decode with nil deviation. Instrument-specific ORB defaults set `maximumEntryDeviation` to three pips, independently persisted and included in the strategy configuration digest. Accept only the first current-generation OANDA quote after the exact plan's `createdAt` whose executable entry side (ask for long, bid for short) lies inclusively within `plan.entryPrice ± plan.maxEntryDeviation`, remains strictly between that plan's stop and target, and has quote spread no greater than `plan.maxSpread`. If no quote qualifies, keep waiting; never persist an ineligible quote as the plan's entry anchor.
3. Require a successful OANDA quote fetch, exact instrument match, source `oanda`, authenticated `.live` session, finite noncrossed positive bid/ask, `sourceTime >= plan.createdAt`, V3 source timestamp age at most 5 seconds at captured receipt, and no terminal invalidation/expiry source time at or before the quote. Require no simulator/proxy/Practice environment. Quote market evidence may feed only shadow structural-outcome evaluation at `.observed` quality; it never proves actual execution.
4. Capture quote response receipt time in `LiveDeskMarketDataService.quotes()` immediately after the transport call returns and carry it in `MarketQuoteResult`; do not stamp receipt after waiting for unrelated candle requests. Construct `V3MarketObservation` directly from quote bid/ask and `asOfMs`; use the carried receipt time, provider `OANDA`, environment `.oandaLive`, and nil sequence. Do not synthesize price sides, quote sequence, or receipt time from candle or plan timestamps.
5. Allow one immutable market entry observation per exact plan ID. Under a per-standardized-root transaction, reload and validate the exact persisted plan, verify identity/instrument, validate the observation against plan time/risk band/spread/source/environment and terminal lifecycle evidence, and check for prior evidence before append. The first eligible **current generation** reaching the serialized append is accepted; an older generation is rejected by an in-transaction append gate immediately before the write. That gate checks the generation, selected pair, `.fx` mode, and that a scan is not taking ownership; a pair switch rejects the old append even if its per-asset generation counter remains current. The producer is only the selected-pair monitor, not the scan-universe publisher. Within one generation there is one quote response, so no source-time ordering race exists. Later polls return already-recorded without adding rows. Conflicting record-ID reuse fails closed. Missing plan or invalid archive is unavailable, never an orphan write.
6. Derive a stable safe evidence ID as a fixed prefix plus a SHA-256 digest of the exact plan ID; never use the raw plan ID as a filename component. Exact retries preserve the stored quote and `recordedAt`; no later poll overwrites it. Replays after restart return the existing record. Store actors sharing a normalized root serialize the plan/lifecycle/evidence read/validate/append transaction.
7. Keep quality scopes separate: the market quote record uses `V3PlanEntryEvidence.quality = .observed`; a future hypothetical structural outcome derived from it must be `.simulated`/shadow quality. This slice creates no outcome.
8. Add a separate per-asset entry-observation status: awaiting an eligible fresh observation, recorded/already recorded, or unavailable. A superseded generation neither appends nor updates visible status. Storage failure leaves the plan and lifecycle projection intact. Status/copy explicitly says “hypothetical market entry reference” and “not an order, fill, or position.”
9. Review retains exact-plan links and shows quote source/receipt times, bid/ask, OANDA Live provider/environment, `.observed` quality, and that the reference is a shadow observation. No user report, lifecycle transition, position, broker synchronization, order, or outcome is created.

## Design contract for challenge

- This milestone records only a first current-generation post-plan quote inside the explicit entry-price band and structural stop/target. It is a hypothetical shadow-entry anchor for market-path evaluation, not an execution claim. The actual user-reported execution path remains separately labeled.
- The producer runs only after the exact Live plan is durable and the same selected-pair monitor refresh's OANDA quote passes source, identity, freshness, entry-deviation, stop/target, spread, chronology, and terminal-plan checks.
- Plan observation and persistence are atomic with respect to same-root entry writers, but plan/lifecycle projection failure boundaries remain independent. A failed entry write never withdraws or rewrites the plan/lifecycle.
- Only one accepted entry observation per plan is retained; repeated quote polls cannot create an unbounded series or replace the original. The first eligible current generation reaching the per-root transaction wins; old generations and pair-switched refreshes fail their in-transaction append gate. Its original source/receipt timestamps remain durable.
- Existing optional data decoding, ForwardTest/replay `.simulated` quality, V1 behavior, manual-only execution, and broker boundaries remain unchanged.
- Adversarial tests cover missing/failed plan persistence, Practice/proxy/non-FX/mismatched source, stale/future/crossed/wide-spread/mismatched quote, source versus receipt time, quote earlier than plan creation, quote outside the preregistered entry-deviation band or beyond stop/target, terminal lifecycle before quote, exact replay and conflicting ID, path-safe IDs, concurrent store instances, stale generation/pair switch, write failure preserving plan/lifecycle, and absence of order/position side effects. A future structural outcome may consume this `.observed` quote only as a shadow-market anchor and its own quality remains `.simulated`, never broker/user verified.

## Checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-ENTRY-OBS-DEBATE` | Strategy + research + independent QA | Read-only | ORB live refresh, V3 contracts, ResearchStore, Review, current reports | User-reported position integrated | Real quote provenance, semantics, concurrency and safety hazards recorded | Three independent audits | DONE |
| `V3-ENTRY-OBS-PLAN` | Supervisor | This report | This report | Debate done | One bounded first-post-plan quote rule, exact gates, preservation boundary | Recorded here | DONE — PROPOSED |
| `V3-ENTRY-OBS-DESIGN` | Supervisor + independent challenger | Read-only | This report and named source contracts | Plan proposed | Challenge first-writer meaning, chronology, root locking, UI quality, failure behavior | Independent challenge: PASS after amendments for separate entry tolerance, shadow quality, quote receipt time, path-safe ID, and pair/generation gates | DONE — PASS |
| `V3-ENTRY-OBS-IMPL` | LightningDesk/Research worker | `/private/tmp/blazeros-ios-test-host` | The 16 allowlisted paths above | Design PASS | First fresh eligible Live quote for exact durable ORB plan; root-serialized idempotency; pair/generation/Live-session guarded; no fill/order authority; status keyed by exact plan ID | Full Swift **653/653 across 17 suites**; iOS simulator build PASS; `git diff --check` PASS. Targeted UI test stalled saving its result log (exit 75; zero tests reported). | DONE |
| `V3-ENTRY-OBS-REVIEW` | Independent QA | Read-only | Final allowlist and logs | Implementation complete | Exact provenance, causal time, replay/concurrency, no order/fill/position claim | Initial review found timestamp-conversion trap and missing Live-session recheck; both fixed with regressions. Revised exact-diff review: **PASS**. | DONE — PASS |
| `V3-ENTRY-OBS-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed allowlist | Review PASS | Hash-equal integration and primary verification | Applied only sidecar-to-primary unified patches; all 16 allowlisted paths byte-match reviewed snapshot. Primary `swift test`: **653/653 across 17 suites**; iOS 17e simulator build PASS; `git diff --check` PASS. | DONE |

## Integration evidence — 2026-11-16

- The Live OANDA FX Trade monitor now records at most one `.observed` hypothetical market entry reference for the exact durably persisted ORB plan. It captures quote response receipt time, applies the preregistered entry deviation and executable-side/spread/stop/target checks, and serializes exact-plan validation and immutable append per archive root.
- The final append gate rechecks refresh generation, selected pair, FX mode, scan ownership, and that the authenticated session is still Live. Quote timestamps outside positive `Int64` milliseconds are rejected before conversion. Review joins by exact plan ID and labels the reference as hypothetical, not an order, fill, or position.
- No position, lifecycle transition, order, user report, or outcome was created. Failures leave the plan and lifecycle projection intact and report entry evidence separately.
- Independent exact-diff QA: **PASS** after two fixes (timestamp overflow and Live-session switch). The reviewer found no remaining blocking issue; coverage for additional concurrency/terminal-edge cases remains a future expansion.
- Verification in the isolated snapshot and again in primary: full Swift **653/653 across 17 suites**. Focused overflow/session, contract, persistence, ORB, and market-data tests passed. iOS simulator build **PASS**. `git diff --check` **PASS**.
- Targeted simulator UI test did not produce a result: Xcode exited 75 while saving its result log and reported zero tests. UI behavior is compiled, but this workflow is not UI-test verified in this slice.
- Warning status: no Swift compiler warnings in the full Swift run. The device-specific Xcode build succeeded and emitted only `Metadata extraction skipped, no AppIntents.framework dependency found`; the app has no App Intents feature. Generic simulator builds can additionally print a missing OS-version placeholder diagnostic. These are toolchain notices, not source compile warnings.
- Worker and primary hashes were compared; all 16 allowlisted files now byte-match. Primary remained otherwise dirty; no existing user work was reset or replaced.

### Integrated source/test hashes

```text
d8b43eb4bdec9353755059f0212ab1989ac6d6c09919bb91eb461292614d8404  Sources/BlazerCore/V3DomainContracts.swift
0a9f032d43d7f8aa64e58e45e0f0f6b60b3cb21ddd2e8cb97f25caee60164f6e  Sources/BlazerCore/Research/ResearchStore.swift
7408d436fd56b2cae42e23f931b62fe9557f19cb8a26a96e422e10c81ddafca4  Sources/BlazerCore/Research/ORBBreakRetestV1.swift
50e150bd5d59f3eb5fddb6117691f61f8dcd997d5b5ece5420c304fb97e7fe49  Sources/LightningDesk/LightningDeskModel.swift
52e67f14cd1103bd862690ce3f951d8c551dbf9ccfb5ac0364fbfc41ba6f5b70  Sources/LightningDesk/Services/DeskMarketDataService.swift
829005b1a3a13679a06b21078e300af3836f7dee184a0e68cdc44cce5f4f7dcf  Sources/LightningDesk/Screens/DeskScreen.swift
5a098e8c26dd9bbb9139c71aa4881c660592abf48b98233a19660a7ec7949e32  Sources/LightningDesk/Screens/ReviewScreen.swift
494185ed787ef2fcb0956828941bb4261efdace6b85cdd806b25fdc226e7fac3  Tests/BlazerCoreTests/V3DomainContractTests.swift
7b559186c0eba5767de9db885e44f54580c4c30c7df1be11507db34228776792  Tests/BlazerCoreTests/V3PersistenceTests.swift
82f0fca44b595f319dd5b3c5effc191f26a3289a1b0455a5cf2d1f5799d56c59  Tests/BlazerCoreTests/ORBBreakRetestV1Tests.swift
7a1de1efb95c6e722ff0eb92e432f1837837b85f8c5c3cbda3ddd303f0267c3d  Tests/BlazerCoreTests/LiveDecisionFreshnessTests.swift
4fe2c1a80bd24db82fa7a6e663b968680bd8a853d6a03d14d1bec38c3e1c0365  Tests/BlazerCoreTests/MarketDataServiceTests.swift
```

## Preservation boundary

Primary checkout is extensively dirty. No reset, clean, stash, broad replacement, credential access, network order, broker synchronization, signing, or publication. Implementation begins only after the independent design challenge passes.
