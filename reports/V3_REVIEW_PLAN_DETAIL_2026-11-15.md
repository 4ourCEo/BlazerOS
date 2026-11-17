# V3 source-specific plan detail and timeline

**Task:** `V3-REVIEW-PLAN-DETAIL`
**Status:** Debate and independent design challenge complete — PASS; implementation underway in isolated snapshot.
**Parent objective:** `reports/V3_AUTONOMOUS_CONTINUATION_LOOP.md`

## Debate

- Active Live Trade currently produces validated `V3TradePlan` snapshots through ORB and writes them under `Research/live-oanda/v3-trade-plans` (`ORBBreakRetestV1.swift`; `LightningDeskModel.publishORBDecision`). The Trade card labels them “research plan only.”
- The ORB publisher suppresses plan write failure with `try?` and still publishes the in-memory plan. A visible plan can therefore be missing from durable Review state. A separate LiveStrategyDecision persistence path does fail closed.
- Production LightningDesk currently has no writer for `V3SetupLifecycleEvent`, `V3PlanEntryEvidence`, `V3PositionRecord`, `V3DurableSpotOutcome`, or `V3StructuralOutcome`. ForwardTest writes simulated entry/structural outcomes in research; these are not active Trade fills or positions.
- Review loads Live and proxy archives separately and has six all-or-unavailable category counts, but no per-plan details or timeline.
- ResearchStore currently checks filename-to-ID agreement for setup lifecycle and plan-entry evidence, but not for plans, position events, spot outcomes, or structural outcomes.
- Exact joins are available through `planID`. Position records are not transition-stream validated and cannot be described as broker-authoritative current state. Spot outcome models do not expose explicit spread/additional cost fields; costs must not be inferred.

## Plan

**Goal:** make persisted V3 plan evidence inspectable in Review with accurate source, identity, provenance, quality, timestamps, costs, and unresolved states; do not let a failed Live ORB plan write leave a plan displayed as persisted.

**Ranked scope:**

1. Add safe, nonempty record ID validation and fail-closed filename-stem-to-ID validation for all six V3 collections (plans, lifecycle, entry evidence, positions, spot outcomes, structural outcomes) in `ResearchStore`. Use a strict filename-safe grammar for record IDs and a separate traversal-safe reference grammar for domain references such as slash-form instruments; validate each component of comma-composite ORB evidence references. Preserve legitimate optional nil plan references and whole-source-unavailable semantics.
2. Retain complete validated V3 record arrays in the Review archive snapshot while preserving all six metrics and separate Live OANDA/proxy roots.
3. Add an accessible, read-only per-plan detail/timeline. Join only records from the selected archive whose exact `planID` equals the selected plan ID. Keep orphaned/missing plan references in an explicit unlinked/unresolved section, not attached to a similar-looking plan.
4. Clearly label event quality/provenance and timestamp meanings, including the envelope and each entry/exit observation provider/environment independently. Show structural `netPnl`, `spreadCost`, and `additionalCosts` as persisted. For spot results, show only fields actually recorded and label costs unavailable; do not estimate missing costs.
5. Make the Live ORB publisher surface an unavailable/wait state and omit the in-memory plan when `ResearchStore.record(plan)` fails. Keep error text bounded and do not treat a plan as a fill or authorization.
6. In non-Live sessions, clear the Live Trade ORB projection and publish an unavailable Live status; do not show a transient Practice candidate as a persisted Live plan. Add persistence, link-integrity and projection regressions, plus simulator verification. No position writer or order workflow is introduced.

**Exclusions:** creating/editing positions, recording manual fills, broker synchronization, new order/entry authority, outcome fabrication, cross-archive joins, new dependencies, changing strategy evaluation, or changing the existing manual-only safeguards.

## Proposed design contract

- `V3ReviewArchiveSnapshot` is built only after every selected source collection decodes, validates, and passes filename identity. Any failure makes that source unavailable without partial arrays or counts.
- The source selector maps only to the fixed `live-oanda` or `oanda-proxy` root. Each archive gets its own snapshot and detail selection. The archive folder identifies storage origin only; row provenance uses each record’s actual provider/environment fields when available, and never infers them from the folder.
- A selected plan timeline filters each record collection by exact `planID`. Missing plan IDs and unknown plan references remain unlinked. A record with a matching `planID` but conflicting instrument or available strategy/engine version is placed in an integrity/unresolved group rather than presented as ordinary plan detail. No record from the other archive can be joined.
- Displayed position rows are labeled “position evidence” and include their provenance/state, not “current position” or “filled trade.” They are snapshots, not a validated transition stream. Never expose brokerPositionID or account identifiers.
- Setup entries show `recordedAt` separately from `sourceTime`/`receivedAt`. Plan uses `createdAt`; position uses only `updatedAt`; entry/outcome envelopes use `recordedAt` with observation `sourceTime` and `receivedAt` shown separately when present. Nil source times are “unavailable.” A combined timeline sorts by envelope/record timestamp then stable kind and ID; this is a display order, not a claim that differently sourced timestamps are equivalent. Preserve only quality fields actually present: entry/structural outcome quality and position provenance. Clearly mark quality unavailable for plans, lifecycle events, and durable spot outcomes.
- Structural costs are shown only from stored cost fields. Spot outcomes do not gain inferred cost estimates.
- Empty event categories explicitly say no record is stored. A plan alone never implies entry, fill, or outcome.
- ORB Live plan save happens before publishing either ORB map. On failure, recheck generation, clear both `orbPlans[asset]` and any candidate-bearing `orbDecisions[asset]`, then publish an unavailable decision with a safe reason. In non-Live sessions, clear the Live projection rather than presenting a Practice candidate as persisted Live evidence.
- Detail rows and controls have explicit accessible labels/values and remain read-only.

## Independent design challenge

First challenge: **CHANGES REQUIRED**. Independent reviewer accepted source-scoped exact `planID` joins, orphan separation, all-or-unavailable reads, and position-authority language, and required the amendments now incorporated: filename-safe record IDs plus traversal-safe slash references for every collection (including comma-composite ORB evidence); explicit provider/environment per record and per entry/exit observation; exact source/receipt/recorded timestamp distinctions and deterministic ties; per-type quality availability; neutral units for cost values; cross-plan instrument/strategy/engine conflicts in an integrity group; and clearing both ORB projections on failed write after a generation recheck. Non-Live behavior is specified as unavailable/no Live projection. An initial implementation review found the slash-reference, engine-version, success-path regression, and per-observation provenance gaps; all were corrected and independently re-reviewed. Final exact-diff review: **PASS**, no remaining design blocker.

## Checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-REVIEW-DETAIL-DEBATE` | Strategy + independent QA | Read-only | Current reports and source | None | Current producers, gaps, risks, bounded next work identified | Two independent audits | DONE |
| `V3-REVIEW-DETAIL-DESIGN` | Supervisor + independent challenger | Read-only | This report | Debate complete | Join, failure, cost, timestamp and authority contract challenged | Independent design challenge and re-review after amendments | ACCEPTED — PASS |
| `V3-REVIEW-DETAIL-IMPL` | LightningDesk/Research worker | `/private/tmp/blazeros-ios-test-host` isolated snapshot | `Sources/BlazerCore/Research/ResearchStore.swift`, `Sources/LightningDesk/Screens/ReviewScreen.swift`, `Sources/LightningDesk/LightningDeskModel.swift`, `Tests/BlazerCoreTests/V3PersistenceTests.swift`, `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`, `Tests/BlazerCoreTests/LiveDecisionFreshnessTests.swift` | Design PASS | Full identity validation; per-plan exact-join timeline; orphan visibility; source and cost distinctions; ORB write failure does not publish plan | Focused regressions, full Swift, iPhone tests, release Mac build, diff check | DONE — PASS |
| `V3-REVIEW-DETAIL-REVIEW` | Independent QA | Read-only | Exact diff and logs | Implementation complete | Provenance, source isolation, failed persistence, UI accessibility and no-authority audit | Exact-diff review | PASS — final re-review complete |
| `V3-REVIEW-DETAIL-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed allowlist and this report | Review PASS | Integrated bytes match; tests and report evidence recorded | SHA256 match on six files; primary V3 tests 26/26; `git diff --check` | DONE — PASS |

## Integration evidence — 2026-11-16

- Exact reviewed bytes integrated for all six allowed source/test files; SHA256 values match the isolated snapshot.
- Final isolated verification: full Swift **629/629 across 16 suites**, focused reviewer regressions **4/4**, full iPhone **27 unit + 4 UI passed** (before the final text/provenance and positive round-trip test additions), final Release Mac build **PASS**, and final generic iOS simulator build **PASS**. Final UI edits compile in the iOS build; no second full UI run was performed.
- Primary checkout verification after integration: V3-filtered Swift tests **26/26** and `git diff --check` passed.
- Logs: `/tmp/v3-final-full-swift.log`, `/tmp/v3-final-review-regressions.log`, `/tmp/v3-iphone-tests.log`, `/tmp/v3-final-mac-release.log`, `/tmp/v3-final-ios-build.log`, `/tmp/v3-primary-integrated-focused.log`.
- Final independent exact-diff review: **PASS**. The only compiler warning in final iOS builds is the existing App Intents metadata extraction notice because the app has no App Intents framework dependency.

## Preservation and safety

Primary checkout is extensively dirty. Preserve it: no reset, clean, stash, broad replacement, or commit. Implement only in the named isolated snapshot. Main supervisor owns integration after independent exact-diff review. No external service, credentials, network, broker order, or publication is needed.
