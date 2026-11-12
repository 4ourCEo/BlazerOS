# Edge verification report — 2026-10-23

**INSUFFICIENT EVIDENCE. No statistically defensible trading edge has been established.**

The standard local application-support directory (`~/Library/Application Support/BlazerOS`) is absent on this host. No venue-confirmed dataset was supplied. Software regression fixtures are not market evidence. The accompanying empty-archive JSON demonstrates export behavior only; it does not assert that the user's phone has no trades.

## Reproduce on an exported desk archive

```bash
swift run -c release EdgeReport --root /path/to/exported/BlazerOS --as-of 1792796400 > edge-report.json
# Optional fixed chronological split; do not select it after inspecting outcomes.
swift run -c release EdgeReport --root /path/to/exported/BlazerOS --as-of 1792796400 --split-at 1792191600 > edge-report-held-out.json
```

Use the same archive, explicit cutoff, split and code revision to reproduce the input digest. The exporter only reads source records. Damaged ledger, journal, reference or telemetry records abort export. Identical or conflicting duplicate arm IDs are excluded from the resolved evidence count; they cannot inflate it.

Only `venue-confirmed` HIT/MISS rows enter measured performance. Synthetic and proxy labels remain separate. Payout-adjusted unit return is `(sum of winning recorded payouts - losses) / resolved`; it matches payouts to winning rows and is withheld if coverage is incomplete. Break-even is reported at the minimum recorded payout. A summary cannot authorize promotion.

Dependence sensitivity uses connected time blocks within coarse correlation groups, a window at least as wide as the longest observed expiry, full within-block dependence by default, and size-weighted block sizes. Fractional effective N avoids rounding evidence upward. The resulting Wilson bounds are **sensitivity diagnostics**, not empirically verified confidence coverage. Serial and cross-group dependence remain unknown.

The method follows the [NIST Wilson interval formula](https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm) and the general [design-effect / effective-sample-size principle](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-23). Applying coarse time groups to trading records is an engineering assumption; these references do not validate that grouping or establish a trading edge.

## Execution attribution

New manual-entry and gate-rejection observations capture scan-to-record latency, quote age, spread, strike displacement and remaining window in a local research archive. The ledger is unchanged. Market/expiry/engine/policy/regime cohorts retain unknown values on older records. Raw spread/displacement means are reported per instrument; mixed-instrument global means are withheld.

Reference disagreements join matching arm, expiry horizon and target expiry, and compare a timely persisted OANDA proxy against a separately venue-confirmed result. They do not overwrite outcomes or estimate counterfactual profit. Closed scans without recorded entries include deliberate passes and vetoes; missing entries are never imputed as losses or wins.

Optional chronological cohorts purge training expiries that overlap the fixed cutoff. Deterioration findings are descriptive comparisons with explicit payout/missingness/selection caveats. Frozen retrospective boundaries are not prospective validation. The research archive's experiments likewise remain exploratory unless their frozen boundary predates the prospective cohort and the complete policy requirements are met.

The next evidence step is an exported, provenance-bearing venue-confirmed history followed by a pre-registered prospective study across the six-asset prime-window basket. It must include at least 250 independently validated clustered events, payout coverage, fixed engine/policy identity, the full attempted-test family and an independent review. No automatic strategy promotion exists.
