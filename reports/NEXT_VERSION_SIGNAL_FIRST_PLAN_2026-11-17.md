# Next version plan: make market signals the primary product

**Status:** Planned; implement after the cleanup and integration baseline is committed and pushed.
**Product goal:** Make useful, explainable market opportunities visible while keeping Live approval and manual execution as separate, stricter decisions.

## Problem statement

The current app can show `WAIT` for several different reasons. The observed Live path returned `no_strategy_passed_live_promotion_gate` while `StrategyResearchRegistry.productionPromotionRecords` was empty. Research evaluators also returned no candidates on some scans, and the app did not make it clear whether that meant no setup, an incomplete condition, unavailable data, evaluator failure, or a promotion block. A valid research opportunity must not disappear just because no strategy is Live-approved.

The existing project notes also identify incomplete strategy-validation inputs: the GBP/JPY London Break + Retest profile is not fully frozen and its available Practice archive does not establish campaign readiness. This plan does not treat empty promotion state or missing validation data as evidence to loosen rules.

## Product contract

Each scan produces a timestamped outcome for every requested instrument:

- **Signal found** — one or more existing evaluators produced a valid candidate. Show strategy and version, direction, timeframe, setup rationale, observed quote time, and any entry, invalidation, or target values the evaluator actually supplies.
- **No setup** — data was usable, evaluators completed, and none qualified.
- **Forming** — an evaluator reports a specific unmet setup condition, such as an opening range that has not finished forming.
- **Data unavailable** — quote/history is missing, stale, incomplete, or rejected by a data-quality rule.
- **Evaluation failed** — the evaluator did not complete; preserve a safe, user-readable reason.

Signal state and approval state are separate:

- A research candidate is visible and labeled **RESEARCH ONLY · NOT LIVE-APPROVED · NO ORDER**.
- A candidate is Live-eligible only after passing the existing promotion, freshness, and risk gates.
- The Live Trade action remains `WAIT` unless a strategy is approved and all Live requirements pass.

Never invent a plan value, confidence score, setup reason, or execution result to make the screen look active. Do not silently relax eligibility thresholds.

## Design direction

Extend the current evaluator and selector path. Do not create a competing strategy engine. The signal projection should preserve each evaluator outcome before the Live promotion decision filters it. The scan result should bind to the requested instrument and scan identity so an all-markets scan cannot silently replace a pair-specific result.

The primary Signals view should show one row/card per scanned instrument with its outcome, strategy, timestamp, status, and concise reason. Selecting a research signal shows its available plan details and provenance. Keep a separate Live Trade state and make the promotion reason visible when it blocks that state.

First implementation target is the Mac workflow, which has the current research diagnostics and pair-specific scan. Preserve the iPhone and shared targets unless a follow-up explicitly includes them and provides acceptance for both.

## Implementation workstreams

### S1 — Freeze the signal contract and selected strategy

- Confirm the exact output fields for a candidate and the five scan outcomes above.
- Select the first strategy/profile to validate. For GBP/JPY London Break + Retest, resolve all required parameters through the existing product/strategy review path before collecting acceptance evidence.
- Record data environment, strategy version, rule/profile digest, and all gate reasons.

### S2 — Trace the full scan path

- Trace requested instruments from quote receipt through every evaluator, selector, projection, and UI update.
- Record per-instrument counts for requested, fresh-data, evaluator-completed, candidate, rejected, displayed, expired, and Live-approved states.
- Make pair-specific scans remain bound to the selected pair; make all-market scans retain all per-pair results.
- Verify stale or superseded scans cannot replace newer results.

### S3 — Separate research signal projection from Live approval

- Project eligible research candidates before the Live promotion gate.
- Keep promotion, risk, and Live freshness checks in the Live decision path.
- Show both the candidate and the reason it cannot enter the Live path when promotion is withheld.
- Keep research signals non-executable and clearly labeled.

### S4 — Build the Signals experience

- Present a per-instrument outcome list with distinct Signal, No setup, Forming, Data unavailable, and Evaluation failed states.
- Show direct reasons without raw error text or unsupported price/probability fields.
- Keep the Live Trade card separate; it may continue to display `WAIT` while a research signal is visible.
- Add notifications only after signal identity, deduplication, expiry, and withdrawal behavior are verified.

### S5 — Validate positive and negative cases

- Add deterministic integration coverage for a known positive candidate, a genuine no-setup case, a forming setup, stale/missing data, evaluator failure, and promotion withheld.
- Replay an authorized, labeled dataset that contains the selected strategy's required market conditions. Record candidate frequency and rejection counts by instrument and reason.
- If a reviewed sample has no positive case, investigate whether the data covers the setup and whether any gate is unintended. Keep the task open until a valid candidate is reproduced or evidence shows that the sampled period genuinely contained no qualifying setup.
- Do not use a fabricated signal or an unreviewed parameter change to satisfy acceptance.

## Acceptance criteria

1. With the production promotion registry empty, a deterministic valid candidate appears in the research Signals view as research-only; Live Trade remains blocked and no order path is invoked.
2. A positive historical/replay example for the selected, frozen profile passes from input data through evaluator and projection to a visible signal with provenance.
3. A negative example produces `No setup` with evaluator completion evidence and a reason; it is not collapsed into generic `WAIT`.
4. Forming, unavailable-data, and evaluator-failure cases remain distinct from `No setup`.
5. All-market and pair-specific scans retain the correct instrument identity; stale, superseded, and invalid quotes cannot produce an actionable display.
6. Candidate frequency and gate counts are measured on reviewed data. The product does not add a required signal quota or weaken rules to hit a target count.
7. Research signals never imply a fill, broker position, or executed trade. Only the existing approved Live path can enable Live action, and execution remains manual.
8. Existing Mac and iPhone safeguards remain covered by relevant tests/build acceptance before any shared or cross-target changes are accepted.

## Out of scope for the first implementation

- Promoting any strategy to Live without owner-approved evidence.
- Adding a new strategy family or arbitrary thresholds to increase signal frequency.
- Automated order placement, broker-confirmed execution claims, or changes to credential handling.
- Replacing existing evaluators with a new engine.
- Claiming strategy profitability from unit tests, a single example, or synthetic data.

## Relevant code and evidence

- Candidate and promotion registry: `Sources/BlazerCore/Research/StrategyResearchRegistry.swift`
- Live decision boundary: `Sources/BlazerCore/Research/LiveStrategyDecision.swift`
- Mac scan workflow: `Sources/LightningDesk/MacTradingWorkspace.swift`
- Mac research signal projection: `Sources/LightningDesk/MacResearchSignalProjection.swift`
- Existing runtime diagnosis and open validation dependencies: `reports/MAC_RESEARCH_SIGNAL_DIRECTION_2026-11-16.md`
- Cleanup/integration record: `reports/CONSOLIDATE_PUSH_MERGE_2026-11-17.md`
