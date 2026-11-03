# Post-audit implementation checklist — 2026-11-03

## Audit handoff

- [x] Comprehensive application audit reconciled with `reports/READINESS_REPORT_2026-11-02.md`.
- [x] No unresolved P0/P1 defect currently blocks signal integrity, entry timing, or persistence.
- [x] Current branch: `upgrade/strategy-validation-risk-research`; integrated PR #16 remains open.
- [x] Authorized baseline: pinned JavaScriptCore production engine; Candidate 001 remains research-only.
- [x] Existing parity, replay, journal, ledger, execution-observation, Intel, Coach, and gap-register infrastructure reviewed.
- [ ] Final physical-device interruption/background/manual-settlement gates remain open.
- [ ] Research and live-capital gates remain blocked pending independent forward evidence and broker verification.

## RC1 consolidation handoff — Chunk 0

- [x] Protected baseline branch: `rc1/research-paper-trading` created from local `0fb67aed38567097f869c10813fb29c359308273`.
- [x] Existing working-tree changes preserved; no reset, clean, stash, rebase, checkout, force-push, or branch deletion performed.
- [x] Baseline branch was synchronized with `origin/upgrade/strategy-validation-risk-research` before branching.
- [x] Current worktree includes the post-audit changes plus the new shadow quality, execution, and Candidate 002 work; all remain reviewable and uncommitted.
- [x] Full local Swift suite verified at **372/372 passed** after the current post-audit additions.
- [x] Open PR inventory refreshed: #9–#16 remain open; #16 is the primary consolidation reference; #15 remains a separate OTC research branch.
- [x] Existing T3 worktrees identified and left untouched: market-data modularization and direct OTC signal-engine branches.
- [ ] Physical-device verification of this RC1 branch remains pending.

## PR disposition — Chunk 1

| PR | Disposition | Evidence / release decision |
|---|---|---|
| #9 | Integrated and verified | Numeric guards and crypto fail-closed behavior are present in the consolidated source; focused crypto/numeric tests pass. The PR commit itself is not an ancestor of RC1, so no duplicate patch will be replayed. |
| #10 | Integrated and verified | `origin/upgrade/verified-execution-intelligence` is an ancestor of RC1; execution/statistical/promotion safeguards are present. |
| #11 | Integrated and verified | `origin/upgrade/blazeros-v2-60s-otc-research` is an ancestor of RC1; lifecycle/cancellation/research isolation remain covered. |
| #12 | Integrated and verified | `origin/upgrade/blazeros-v2-market-data-modularization` is an ancestor of RC1; service/cache/orchestration boundaries remain present. |
| #13 | Integrated and verified | `origin/upgrade/blazeros-v2.2-personal-otc-data` is an ancestor of RC1; bounded read-only research contracts remain present. |
| #14 | Integrated but release-quarantined | `origin/upgrade/blazeros-v2.3-otc-market-data-integration` is an ancestor of RC1; Pocket Option remains disabled by default and read-only at the app boundary. Provider suitability is not established for public distribution. |
| #15 | Deferred / separate research branch | `origin/upgrade/blazeros-v2.4-otc-signal-engine` is not an ancestor of RC1. Its unique OTC signal engine/replay/UI work is not required for a paper-only RC1 and will not be merged wholesale. |
| #16 | Primary consolidation reference | Published head `0fb67ae` is the RC1 base; current local post-audit changes are newer/uncommitted and are preserved. |

Chunk 1 result: no PR was merged, closed, replayed, or force-pushed. Duplicate stacked work is not being reintroduced.

## Chunk 2 result — critical safety

- [x] Focused crypto, numeric, engine-boundary, scheduler, entry-gate, and feed-health suite: **41/41 passed**.
- [x] Release `CoreAudit`: **71/71 passed**.
- [x] Release `Parity`: **43/43 passed**; engine pin remains `7c02e550e2e6ca656a258ceefc6083f098ff40b2`.
- [x] Finite-extreme arithmetic, malformed inputs, non-finite quotes/candles, cancellation, stale work, and duplicate scan handling remain fail-closed.
- [x] No production strategy, pinned engine artifact, completed-candle rule, or eight-second eligibility logic changed.

## Chunk 3 result — consolidated infrastructure

- [x] Targeted execution/research integration suite: **170/170 passed**.
- [x] Journal, snapshot, ledger, pending-settlement, and execution-observation corruption remain explicit and non-destructive.
- [x] Cancellation, stale-work suppression, market-data service boundaries, candle cache identity, and source attribution remain covered.
- [x] Foundation Model outputs remain bounded/read-only and cannot select signals, mutate research, or authorize entry.
- [x] OANDA proxy, Pocket Option research, synthetic data, and venue-confirmed outcomes remain provenance-separated.
- [x] No LightningDeskModel refactor was introduced solely for line-count reduction.

## Chunk 4 result — OTC integration decision

- [x] PR #15 unique `OTCResearchEngine`, replay, signal store, OTC desk card, and associated tests were identified as a separate implementation family.
- [x] PR #15 was not merged wholesale: it duplicates existing #13/#14 research boundaries and adds substantial divergent UI/desk state risk.
- [x] Existing #14 provider has no order-placement API, requires explicit configuration, and defaults to `enabled: false`.
- [x] Pocket Option credentials remain Keychain-scoped; the provider is only constructed for an explicit bounded research capture.
- [x] OTC instruments, OANDA proxy data, synthetic fixtures, and venue-confirmed ledger outcomes remain identity/provenance separated.
- [x] Existing OTC integration, replay, credential, disabled-provider, and research-only barrier tests passed in the 170-test Chunk 3 suite.
- [ ] Provider authorization/suitability and real OTC observations remain unverified; direct Pocket Option research is release-quarantined, not a public production capability.

## Chunk 5 result — durable signal-quality evidence

- [x] `ResearchEvent` now persists optional versioned `SignalQualityAssessment` data without changing event identity or entry authority.
- [x] Existing chronological research cohorts now expose shadow counts for supported, conditional, rejected, and unavailable classifications.
- [x] Older research archives remain decodable because the new fields are optional.
- [x] Research experiment/campaign tests: **21/21 passed**.
- [x] Local forward archive inspection: **1,750 events / 420 outcomes**; baseline and control each have 70 accepted 60-second events, 51 resolved (28 HIT / 23 MISS), and 19 explicit unresolved `No timely expiry observation` records.
- [x] Missing forward observations remain unresolved and are not treated as losses or fabricated outcomes.
- [ ] Filtered-versus-baseline performance remains unqualified until a frozen, source-matched, out-of-sample cohort with complete cost/latency evidence exists.

## Chunk 6 result — candidate comparison and execution analysis

- [x] Added matched-observation comparison scaffolding for baseline and independent research candidates.
- [x] Comparisons require stable observation identity, instrument/source agreement, explicit payout/cost data, and recorded latency.
- [x] Missing payout or cost withholds post-cost expectancy; unresolved outcomes remain unresolved.
- [x] Candidate comparison tests: **2/2 passed**.
- [x] Promotion is hard-disabled in the comparison report; no Candidate 001/002 result can alter production selection.
- [ ] Candidate 001/002 archive adapters and real out-of-sample cohorts remain pending prospective research data.

## Authorized milestones

- [x] **A — Research infrastructure:** add a shadow-only signal-support contract without changing engine or entry eligibility.
- [ ] **B — Execution intelligence:** extend prospective timing/adherence records and deterministic attribution reports.
- [ ] **C — Quality research:** integrate Candidate 001 measurements and add separate Candidate 002 feasibility research.
- [ ] **D — UI integration:** expose only compact quality state in existing STRIKE Scan/Radar/Intel/Journal surfaces.
- [ ] **E — Validation:** replay, walk-forward, out-of-sample, leakage, cost, latency, negative-control, and independent QA evidence.
- [ ] **F — Release decision:** retain research-only status unless explicit evidence and approval authorize promotion.

## Non-negotiable boundaries

The frozen engine, eight-second eligibility, completed-candle rules, manual-entry boundary, historical records,
parity seal, STRIKE presentation, and existing PR/worktree history remain unchanged. No broker automation,
fabricated data, AI-generated direction, or silent strategy promotion is permitted.
