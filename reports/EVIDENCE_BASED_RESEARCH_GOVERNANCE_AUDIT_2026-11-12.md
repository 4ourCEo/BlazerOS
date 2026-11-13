# Evidence-based research governance audit — 2026-11-12

## Scope and decision

Read-only audit of the current research contracts at starting commit `2aa339958c906ca48647cd638cd1ae07996e01e5`. The primary checkout and its uncommitted work were not changed. No strategy, replay contract, threshold, or broker behavior was changed here.

**Research conclusion: INSUFFICIENT EVIDENCE.** Existing code has meaningful controls for frozen inputs, chronological splits, proxy-vs-venue outcome separation, and fail-closed statistical promotion. The research record is not yet a complete experiment registry, and source freshness is not fully enforced in the historical case builder. No supplied/local venue-confirmed sample was evaluated in this audit; regression fixtures are not trading evidence.

## Existing safeguards verified by source inspection

- `ResearchExperiment.swift`: chronological training/test split, optional immutable `splitAt`, train-horizon purge at the boundary, held-out cohort digest, unresolved/tie counts, coverage, conservative payout accounting, and report text explicitly limits interpretation. Legacy unfrozen splits are marked. Mathematical screening does not itself pass the acceptance flag.
- `PromotionEvidenceGate.swift`: fail-closed without a trusted independent reviewer; binds review to a cohort digest; requires prospective family registration, complete test IDs and p-values, non-assumed dependence review, verified effective N ≥ 250, and Bonferroni family-wise correction. It grants no entry or strategy-change authority.
- `StrategyValidation.swift`: distinguishes historical replay, paper trading, and manual live observations; rejects future quotes/candles and incomplete candles; records input/configuration/case digests; preserves rejected cases as unresolved; excludes synthetic and inappropriate reference outcomes from performance eligibility.
- `ResearchStore.swift`: write-once local research records; verifies input and case identities and aborts on corrupt records rather than silently dropping them.
- `EvidenceClustering.swift`: discounts concurrent coarse correlation-group observations and labels its assumed-ICC/effective-N output as approximate, not proof of independence.
- `CandidateComparison.swift`: supports matched descriptive baseline/candidate comparisons with explicit cost coverage, but always sets `promotionEligible` false.
- Existing reports `STATISTICAL_CORRECTNESS_FOLLOWUP.md` and `EDGE_VERIFICATION_2026-10-23.md` document prior statistical safeguards and state that no live application archive/venue-confirmed dataset was available during those earlier checks. Those historical statements do not establish current archive contents.

## Material gaps / recommended next increments

### P0 — durable experiment registry and attempted-test accounting

`ResearchExperiment` currently records policy, engine SHA, creation time, split fraction/boundary, evaluation horizon, payout assumption, criteria, and notes. It does **not** durably require the complete protocol tuple requested for each experiment: falsifiable hypothesis, venue/instrument identity, archive/source hashes, timeframe roles, holding/exit contract, parameters and every variant/revision, benchmark, execution-cost assumptions, and counts of all prior looks. The independent review schema accepts registered test IDs and p-values, but those are externally supplied; there is no first-party immutable candidate/revision ledger proving that the family is complete. Add this as a separate, versioned research-governance record, not by changing engine selection or outcomes.

### P1 — stale-quote eligibility in historical case construction

`HistoricalValidationCaseBuilder.build` selects the latest matching quote at or before the evaluation time (`StrategyValidation.swift`, lines 363–380) and validates that it is not future-dated (lines 517–522), but imposes no maximum quote age. Consequently a stale quote can produce an otherwise valid frozen decision point. Record its age and make freshness an explicit, preregistered builder eligibility rule in a future isolated change; retain excluded cases and reasons. This audit did not alter replay contracts.

### P1 — comparison inference and horizons

Candidate comparisons currently report matched net expectancy descriptively and do not estimate uncertainty for paired candidate-minus-baseline returns. `StrategyValidationConfiguration` currently fixes expiry to 60 seconds. Do not infer a preferred horizon from this path or silently widen it; the separately maintained legacy fixed-duration pathway and structural replay contracts need an explicit, owner-approved comparison design.

### P2 — data provenance and reporting

Input digests establish record identity but are not a hash of the source archive or an independently reproducible market-data manifest. The validation input has M1/M5 candle arrays but the experiment record does not explicitly state each timeframe's research role. Reports should also surface eligible independent setups and unresolved/ambiguous denominators alongside cost coverage; do not turn nominal events or larger test counts into evidence of edge.

## Proposed acceptance lifecycle

Register the hypothesis, comparator, market, timeframe roles, exit contract, data manifest/hash, split, cost assumptions, parameters/variants, and test-family ID **before** evaluation. Preserve every attempted revision. Develop on chronological training data; use independent validation only for predeclared decisions; freeze holdout access until definitions and stopping rules are fixed; report prospective manual observations separately from simulation and broker-confirmed execution. A pass permits further research only—not automatic orders, strategy promotion, or claims of profitability.

## Measurement status

| Requirement | Audit result |
|---|---|
| Actual market strategies/timeframe-role performance | Not measured in this audit |
| Independent eligible setups / cost-adjusted expectancy | Not available; no data archive was supplied to this worktree |
| Ambiguous/unresolved outcomes | Represented by existing contracts, but no new sample was evaluated |
| Multiple-testing control | Statistical gate requires externally reviewed full family; no durable first-party attempt ledger found |
| Holdout integrity | Frozen boundary/digest protections exist; preregistration and source-data manifest remain incomplete |
| Statistical acceptance | **INSUFFICIENT EVIDENCE** |

No tests were run: this was a source-only audit and made no executable changes.
