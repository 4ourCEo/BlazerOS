# Evidence-governance implementation — 2026-11-12

## Summary

The stale-quote issue reported in `EVIDENCE_BASED_RESEARCH_GOVERNANCE_AUDIT_2026-11-12.md` was reproducible. The historical builder selected the latest source-matched quote at or before evaluation but had no source-specific maximum age; replay only rejected future-dated quotes. An arbitrarily old valid bid/ask could therefore influence a historical engine decision.

## Stale-quote correction

- `HistoricalValidationSeries` now carries an optional source-declared `maximumSignalQuoteAgeSeconds`. The builder requires a finite non-negative value, rejects stale quotes with a durable build rejection, and never alters the observation timestamp.
- The generated `StrategyValidationCase` includes that contract in its canonical digest. Historical replay checks the quote timestamp against the signal time and contract before calling the pinned strategy. Missing contracts, including legacy decoded cases, remain `.unresolved`; stale/future data is not converted to a synthetic replacement.
- No universal threshold was introduced and the live 8-second/20-minute freshness thresholds were not reused as historical-data rules. The caller must provide the source cadence contract.
- The engine artifacts, production strategy calculations, production thresholds, entry authorization, and broker order paths are unchanged. Existing deterministic pinned replay remains covered.

GPT-5.6 Luna independently traced the data → case → replay → outcome path in an isolated read-only worktree and confirmed the defect and the separation from outcome settlement freshness. GPT-6 reviewed the implementation and regression tests in this branch.

## Durable attempt tracking

The new `ResearchExperimentAttempt` records append to the existing `ResearchStore` `experiments/` archive rather than introducing a separate database. Each immutable attempt links to an existing `ResearchExperiment` and records:

- strategy identity/version and falsifiable hypothesis;
- source identities and SHA-256 archive references;
- instrument, named timeframe roles, exit contract, and split assignment;
- parameter variations, sequential attempt number, benchmark, and explicit spread/slippage/delay/financing/fill assumptions;
- independent eligible, resolved, ambiguous, and unresolved counts; net expectancy in R; uncertainty bounds/method and evidence reference;
- pending/rejected/accepted-for-further-research decision, rationale, and optional link to the earlier attempt this one supersedes. The earlier hypothesis remains immutable; its superseded status is inferable from the linked later attempt.

The store verifies the parent experiment, required metadata, archive-hash shape, outcome counts, and uncertainty consistency. Attempt numbers must be contiguous and unique per experiment. Records are write-once; exact duplicate writes are idempotent, while ID reuse with changed content, missing attempts, and invalid supersession references fail closed. Rejected/superseded attempts remain readable. “Accepted for further research” is not strategy promotion or trade authorization.

## Verification

- `swift test --filter 'StrategyValidationTests|ResearchExperimentAttemptTests'`: **29 tests passed**.
- After rebasing onto current `main`, `swift test`: **454 tests passed across 5 suites**. The merged main test for incomplete path statistics was updated to carry forward its source freshness contract; that focused test and the full suite pass.
- `scripts/check-engine-pin.sh`: **PASS** (`main 7c02e550e2e6`, `control 1a1d264d44ee`).
- `git diff --check`: **PASS**.
- Regressions cover stale quote rejection in construction and replay, future quote rejection, missing source freshness contracts, legacy case decoding remaining unresolved, immutable attempt persistence, supersession, sequence enforcement, invalid archive hashes, and ID/content collisions.

These are software correctness checks, not market-performance results. No market dataset or strategy edge was evaluated; status remains **INSUFFICIENT EVIDENCE**.

## Integration / PR review

No files in the primary worktree or other worktrees were modified. Open PR #24 changes only adapter-role metadata files; open PR #25 adds separate structural-replay files. Rebasing the isolated branch onto current `main` exposed a `ResearchStore.swift` conflict because both main's V3 persistence work and this change add APIs to the shared actor. The conflict was resolved by preserving both sets of methods; a merge-tree preview is now clean. The primary checkout has independent uncommitted edits in `ResearchStore.swift` and `StrategyValidation.swift`; this branch's changes are scoped to historical signal-quote freshness and append-only experiment attempts, not the primary's V3 outcome persistence or validation-cohort drawdown logic. The primary owner retains integration authority. Do not merge this PR into `main` from this branch.

Verified branch commit `d7d2686` (implementation/report) follows audit commit `be4070d`. Review PR: [#26](https://github.com/4ourCEo/BlazerOS/pull/26). The PR is open and unmerged; no CI watch or merge was started.
