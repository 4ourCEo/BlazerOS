# Statistical correctness follow-up

Starting head: `30bfb0255d7f49cf947a0a051364f8be93694a0c`, branch `upgrade/verified-execution-intelligence`. The starting working tree was clean. No reset, discard, ledger migration or snapshot rewrite was performed.

## Defect 1: outcome-dependent payouts

The existing row-based ledger path already aligned payouts with outcomes. The remaining public summary fallback could still combine an unordered, heterogeneous payout list with win rate. It now reports expectancy unavailable unless outcome alignment is known. `expectancyAvailable` must be checked on that compatibility API; `actualExpectancy` is optional and never substitutes assumed payouts.

`ConfirmedReturnSummary` is the shared actual-return implementation:

- Equal-risk unit return: a HIT contributes its own recorded net payout ratio; a MISS contributes -1 risk unit.
- Cash contribution: a HIT contributes its recorded stake times its own payout; a MISS contributes its recorded full stake loss.
- Missing winning payouts withhold actual unit expectancy. Missing or invalid stakes withhold cash totals. A losing trade's advertised payout does not affect the loss.
- Only unique venue-confirmed HIT/MISS records count. Proxy/synthetic/conflicting records cannot inflate actual returns.

The existing fixed-contract MISS semantics specify full-stake loss. Partial refunds or other settlements require explicit reconciliation; they cannot be inferred from these records. Cash totals use comparable recorded stake units, with no currency conversion or stake imputation.

Deterministic counterexample (regression fixture, not trading evidence): three wins pay 0.20 each; two losses advertise 2.00 each. Stakes are 10, 20, 30, 40 and 50.

| Measure | Result |
| --- | ---: |
| Incorrect mean-payout formula: 0.6 × 0.92 − 0.4 | +0.152 |
| Correct unit expectancy: (0.2 + 0.2 + 0.2 − 1 − 1) / 5 | **−0.280** |
| Recorded cash P&L: 2 + 4 + 6 − 40 − 50 | **−78.00** |
| Mean cash profit per trade | −15.60 |

## Defect 2: nominal counts and uncorrected selection

`PromotionEvidenceGate` now separates estimated clustering diagnostics from reviewed effective evidence. It requires an externally trusted statistical review, matching cohort digest, non-assumed dependence method, at least 250 verified effective events bounded by candidate blocks/nominal size, and a complete test family registered before the evaluated observations.

The registered family must enumerate every attempted policy, expiry, subgroup and sequential look. Missing, extra or duplicate IDs and invalid p-values fail closed. The gate applies Bonferroni correction over the complete registered family to reviewed one-sided p-values for non-positive payout-adjusted expectancy. It does not fabricate those tests from nominal Wilson counts.

A reviewer name/reference is not automatically trusted: the caller must supply a separate trusted-reviewer policy. The application supplies none by default. Archive content and Foundation Models cannot grant reviewer trust. External review must establish dependence, the raw test's validity and the full attempted-test history; code cannot infer these from timestamps.

`ResearchEvaluator` binds review to the exact held-out records and outcomes, requires the gate for screening, and retains all basket/window/policy/holdout constraints. Legacy persisted nominal acceptance flags cannot bypass the new evidence checks. Statistical qualification is not authorization for live promotion; generated reports still do not authorize any strategy change.

Reproductions:

- 280 wins in 300 nominal observations have nominal Wilson lower bound 0.8993, above the 88%-payout break-even rate. If these share one independent block, verified effective N is 1: **INSUFFICIENT EVIDENCE**.
- Uncorrected p=0.01 clears 0.05. Across ten registered tests, corrected p=0.10: **INSUFFICIENT EVIDENCE**.
- A separately trusted fixture review with verified N=250 and p=0.001 across ten tests qualifies statistically at corrected p=0.01. The identical metadata without an explicitly trusted reviewer fails. This positive control verifies that the statistical gate is not a constant rejection; it grants no live authority.

## Verification order and execution integration

Statistical fixes and their reproductions were verified first: model-disabled CoreAudit **68/68**, BlazerCore build PASS, Parity **43/43**, Persist **59/59**, then the full native Swift suite **234/234**. Execution-report integration began only after those checks passed.

The execution engine now uses the shared return implementation. Its v2 report separates unit expectancy, net recorded cash profit and mean cash profit per trade; it exposes missing independent/multiplicity evidence explicitly. Per-market cohorts use the same calculations. Missing losing quote terms do not erase a known full-stake loss. Ledger bytes remain identical during read-only reporting, and v1 reports still decode without manufacturing new cash/evidence fields.

Final native verification, Xcode 27.1 (27A9275), Swift 6.4, macOS 27 SDK:

| Exact command | Actual result |
| --- | --- |
| `swift test` | **237/237 PASS**, 39.136 seconds; `/tmp/blazeros-statistics-final-test.log` |
| `swift run -c release CoreAudit` | **71/71 PASS**; explicit original-defect/corrected outputs; `/tmp/blazeros-statistics-final-core.log` |
| `swift run -c release Parity` | **43/43 PASS**; `/tmp/blazeros-statistics-final-parity.log` |
| `swift run -c release Persist` | **59/59 PASS**; `/tmp/blazeros-statistics-final-persist.log` |
| `swift run -c release Soak` | **10/10 PASS**; `/tmp/blazeros-statistics-final-soak.log` |
| `scripts/check-engine-pin.sh` | PASS, main/control pins unchanged |
| `scripts/check-intents-constants.sh` | PASS |
| v2 read-only export, repeated against a fresh empty archive | PASS: byte-identical output, no source writes, verified N/significance absent |
| `git diff --check` | PASS |

Native Foundation Models tests ran with availability `ready`: exact token counting and raw on-device generation completed. Service cases that used deterministic fallback were labelled accordingly; they are not claimed as model-generated responses. The earlier model-disabled checks do not stand in for this native run.

## Exact historical log failure

`/tmp/blazeros-swift-test.log:49` first reports the generic wrapper failure: `SwiftCompile normal arm64 failed with a nonzero exit code`.

The first specific compiler diagnostic is at log line 51, `Sources/BlazerCore/Assistant/OnDeviceModelEngine.swift:184:8`:

```text
error: external macro implementation type 'FoundationModelsMacros.GenerableMacro' could not be found for macro 'Generable(description:)'; plugin for module 'FoundationModelsMacros' not found
```

That attempt stopped during compilation, before tests executed. It is evidence of a missing compiler macro plugin in that historical toolchain invocation. It is not evidence of a mathematical test failure, and no evidence attributes it to MCP warnings. The current developer directory is `/Applications/Xcode.app/Contents/Developer`; the native full-suite pass above demonstrates that the historical failure is not a current blocker.

## Review passes and remaining blockers

1. **Mathematical:** reproduced the sign reversal under mean payouts; verified outcome-aligned unit/cash sums; checked insufficient effective N, assumed ICC, family-wise correction, incomplete families and a controlled positive case.
2. **Reliability:** reviewed non-finite/missing input handling, duplicate identities, canonical review binding, prospective registration, default-deny reviewer trust and persisted nominal flags. Missing evidence remains unavailable rather than becoming a synthetic estimate.
3. **Integration:** verified the statistical-first sequence, consistent execution/assistant unit returns, legacy report decoding, unchanged ledger bytes, native on-device context tests, parity, persistence and soak. Strategy engine bytes, snapshot identity, manual gates and research/ledger separation remain untouched.

These are three review passes by the same agent, not an independent external audit. No real reviewed dependence model or complete preregistered comparison family has been supplied, so the live application remains **INSUFFICIENT EVIDENCE**. This follow-up's local results do not claim fresh iOS or physical-iPhone verification; those checks remain separate. No merge, deployment, trade or strategy promotion was performed.
