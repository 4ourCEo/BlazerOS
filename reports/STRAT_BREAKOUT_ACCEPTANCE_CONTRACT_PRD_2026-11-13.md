# STRAT-BREAKOUT-ACCEPTANCE-CONTRACT

**Document type:** Strategy family product requirements and research contract  
**Version:** Draft 0.2  
**Status:** Evaluator V1, provider-native range builder, and durable research lifecycle implemented; exact profile values and cost-adjusted validation remain incomplete  
**Strategy ID:** `BREAKOUT_ACCEPTANCE`  
**Execution authority:** Research/shadow only; no order placement

## 1. Purpose

Specify a deterministic, auditable breakout-continuation hypothesis for BlazerOS. The family distinguishes a breakout that is accepted beyond a pre-existing range from a transient excursion that closes back inside it. It is separate from the NY opening-range breakout-and-retest candidate: this contract does not require a retest and must not be implemented by wrapping or relabeling `ORBBreakRetestV1`.

This contract defines the intended decision sequence and data contract. `BreakoutAcceptanceV1` implements the confirmation/evaluation stage and consumes a supplied frozen level/range. `BreakoutAcceptanceRangeBuilderV1` constructs that frozen range from the prior completed-bar lookback as a separate deterministic stage. The V1 builder accepts only provider-native bars with a matching snapshot and per-bar identity; it fails closed on derived aggregation until constituent source records can be verified. `BreakoutAcceptanceLifecycleV1` now projects each distinct observation into the append-only `ResearchStore` lifecycle, binds configuration/input/engine/source bars and sequence in typed, versioned provenance, deduplicates exact replays, rejects older observations, and prevents terminal re-arm on the same frozen structure. Initial advanced states are recorded from their actual observation without invented history. Exact numerical profile values and cost-adjusted campaign validation remain open, so the registry marks the family `PARTIAL_RESEARCH`. It has no Live selector or order authority.

## 2. Goals and exclusions

### Goals

- Produce reproducible `LONG`, `SHORT`, or `WAIT` decisions from completed candles and a fresh bid/ask quote.
- Identify the range, breakout, acceptance, entry reference, invalidation, target, and rejection reasons in a machine-readable plan.
- Make replay results deterministic, attributable to an exact configuration, and testable without broker access.
- Keep this candidate independent from ORB, V1 policy votes, and other strategy families.

### Exclusions

- No OANDA order submission, position sizing, account-risk policy, or claim that a signal is a trade.
- No use of incomplete candles, midpoint-only executable prices, future bars, or inferred missing data.
- No silent defaults for lookback, acceptance count, buffers, spread, quote freshness, session, stop, target, or expiry.
- No promotion to Live based only on a passing test suite or agreement with another candidate.

## 3. Inputs and provenance

Each evaluation receives:

- Instrument, provider, environment, and exact strategy/configuration version.
- A chronological series of source candles with timestamps, OHLC, completion state, and source identity.
- A bid and ask quote with provider timestamp and local receipt timestamp.
- The pinned engine/build identity and a canonical digest of all inputs and parameters.
- An explicit profile containing every parameter listed in §8; missing or invalid parameters produce `WAIT / CONFIGURATION_INCOMPLETE`.

All timestamps are UTC internally. Session windows, if enabled in the frozen profile, must declare their IANA timezone and DST behavior.

## 4. Deterministic decision sequence

The evaluator processes one instrument and one decision timeframe at a time. Bars are ordered by source timestamp; duplicate or non-monotonic bars invalidate the evaluation. Aggregated bars must include the digest and completion state of their source bars.

### 4.1 Eligibility

Return `WAIT` with a stable reason code unless all conditions hold:

1. The configured minimum history exists.
2. The range and candidate breakout bar are completed and pass integrity checks.
3. The quote is newer than the final candle and no older than the frozen quote-freshness limit.
4. Bid is positive, ask is at least bid, and spread is within the frozen maximum.
5. The profile is complete, valid, and has a canonical digest.
6. The candidate is inside an enabled session and volatility regime, if those filters are configured.

### 4.2 Reference range

For each candidate breakout bar, construct a range from the preceding `rangeLookbackBars` completed bars, excluding the candidate bar:

- `rangeHigh` is the maximum high in that window.
- `rangeLow` is the minimum low in that window.
- `rangeWidth = rangeHigh - rangeLow`.

Reject as `WAIT / RANGE_INVALID` when the range is non-positive, exceeds the frozen maximum range width, or violates a configured minimum width. Range-width limits and any volatility normalization must be frozen in the profile.

`BreakoutAcceptanceRangeBuilderV1` implements this construction with an explicit versioned lookback and width profile, a frozen bar-grid origin, gap/session/tie policies, source snapshot identity, and deterministic causal/context digests. Its first version is provider-native-only; derived bars are rejected with `derived_aggregation_lineage_unverified` until each aggregate's source records can be checked. Session IDs are assigned by the caller's versioned calendar; this builder preserves the declared timezone/DST policy but does not calculate session boundaries.

### 4.3 Breakout observation

- Upward breakout: a completed close is greater than `rangeHigh + breakoutBuffer`.
- Downward breakout: a completed close is less than `rangeLow - breakoutBuffer`.
- A touch or wick through the boundary without a qualifying close is not a breakout.
- A close that qualifies in both directions is invalid input and returns `WAIT / AMBIGUOUS_BREAKOUT`.

The buffer may be expressed in price units or as a frozen multiple of a named volatility measure; the unit and volatility calculation must be explicit in the selected profile.

### 4.4 Acceptance

Starting after the breakout bar, inspect at most `acceptanceWindowBars` completed bars. Acceptance requires `acceptanceBarsRequired` consecutive closes beyond the broken boundary by at least `acceptanceHoldBuffer` in the breakout direction. A close at or inside the boundary before acceptance cancels the candidate as `WAIT / BREAKOUT_REJECTED`. No qualifying sequence before expiry returns `WAIT / ACCEPTANCE_EXPIRED`.

This is a persistence/hold condition. A retest is neither required nor inferred. A future implementation must not count the breakout bar itself as one of the post-break acceptance bars.

### 4.5 Entry reference and plan

After acceptance, use the first eligible fresh quote after the final acceptance candle as the plan's entry reference. Use ask for a long plan and bid for a short plan. If that quote is late, stale, outside the configured maximum adverse entry drift, or violates the spread cap, return `WAIT` with a stable rejection reason. Do not backdate entry to the breakout or acceptance candle close.

The plan must preserve:

- Range boundaries and source-bar IDs.
- Breakout and acceptance bar IDs/timestamps.
- Direction, entry quote, bid, ask, spread, and quote ages.
- Invalidation and target levels, their derivation, and the configured risk unit.
- Expiry, session/regime labels, configuration digest, and all rejection/eligibility results.

### 4.6 Invalidation, target, and expiry

The profile must specify exactly one stop/invalidation method and one target method before evaluation:

- Invalidation may be a completed close back through the broken boundary plus a frozen buffer, or a volatility-buffered structural extreme. The chosen method must be explicit; implementations may not choose between methods after seeing results.
- Target may be a fixed multiple of entry-to-invalidation distance or a predeclared structural level. The chosen method and all multipliers/buffers must be frozen before evaluation.
- If invalidation is not directionally beyond entry, target is not directionally beyond entry, or the resulting risk/reward value is non-finite, return `WAIT / PLAN_INVALID`.
- The candidate expires after `maximumBarsAfterAcceptance` completed bars or at the configured session end, whichever occurs first. No fresh acceptance or entry is inferred after expiry.

These alternatives are design slots, not selected defaults. The final profile must select one method for each field and provide its exact values.

## 5. Output states and reason codes

The evaluator returns one immutable result:

- `WAIT`: no accepted candidate or any failed eligibility/safety condition.
- `LONG_PLAN`: accepted upward breakout with valid plan levels and fresh quote.
- `SHORT_PLAN`: accepted downward breakout with valid plan levels and fresh quote.

Minimum stable reason codes: `CONFIGURATION_INCOMPLETE`, `HISTORY_INSUFFICIENT`, `BAR_INVALID`, `QUOTE_STALE`, `SPREAD_REJECTED`, `SESSION_REJECTED`, `REGIME_REJECTED`, `RANGE_INVALID`, `NO_BREAKOUT`, `AMBIGUOUS_BREAKOUT`, `BREAKOUT_REJECTED`, `ACCEPTANCE_EXPIRED`, `ENTRY_TOO_LATE`, `ENTRY_DRIFT_REJECTED`, `PLAN_INVALID`, `EXPIRED`, and `ACCEPTED`.

Any `LONG_PLAN` or `SHORT_PLAN` remains research information. It cannot create or submit an order, authorize size, or bypass the user's manual-execution and Practice-only safeguards.

## 6. Duplicate and overlapping event control

Each candidate has a deterministic event ID derived from instrument, timeframe, range window, breakout bar, direction, and configuration digest. A candidate cannot emit a second eligible plan until it expires or resolves. Research aggregation must apply a preregistered cluster block so overlapping events are not counted as independent evidence.

## 7. Failure handling

- Missing, stale, malformed, or contradictory data fails closed to `WAIT`.
- Partial feed failures remain visible in diagnostics and cannot be represented as a valid no-signal result.
- Evaluation errors include stable reason codes and sanitized diagnostics; they must not include credentials or account identifiers.
- Replays with identical inputs and profile must produce byte-identical decision, plan, reason codes, and digest.

## 8. Required frozen profile (owner decision required)

No values are assumed in this draft. Before implementation or backtest, create a named immutable profile and fill every row:

| Parameter | Required decision |
|---|---|
| Instruments and provider/environment | Exact allowlist; specify whether the profile is GBP/JPY-only or multi-market |
| Decision timeframe and aggregation | Exact timeframe, source bars, alignment, and timezone handling |
| `rangeLookbackBars` | Positive integer and rationale |
| Minimum/maximum range width | Exact units or normalized measure |
| `breakoutBuffer` | Exact units/formula and volatility source, if any |
| `acceptanceBarsRequired` | Positive integer |
| `acceptanceWindowBars` | Positive integer, at least `acceptanceBarsRequired` |
| `acceptanceHoldBuffer` | Exact units/formula |
| Maximum quote age and entry delay | Exact durations and timestamp basis |
| Maximum spread | Exact instrument-aware value or formula |
| Maximum adverse entry drift | Exact units/formula |
| Session filter | Enabled/disabled; exact IANA zone, window, and DST policy |
| Volatility/regime filter | Enabled/disabled; exact formula and bounds |
| Invalidation method | Select one method from §4.6 and freeze exact parameters |
| Target method | Select one method from §4.6 and freeze exact parameters |
| Maximum plan lifetime | Exact bars and session-end behavior |
| Cluster block and cooldown | Exact overlap grouping and re-arm rule |
| Profile version and owner | Immutable version identifier and approving owner |

Until this table is complete and approved, do not label the family formally specified, implement it as a Live vote, or treat this draft as an execution policy.

## 9. Verification and research acceptance

Before a candidate campaign:

1. Add deterministic fixtures for valid up/down breakouts, wick-only breaches, insufficient acceptance, close-back-inside rejection, acceptance expiry, gaps, duplicate/non-monotonic bars, stale quotes, spread rejection, delayed entry, session/DST boundaries, stop/target ordering, event duplication, and exact expiry boundaries.
2. Require at least 100 hand-authored edge cases; every case asserts decision, plan levels, reason code, event ID, and digest.
3. Verify no lookahead, no incomplete-bar entry, no same-candle future data, and byte-identical replay.
4. Run a 50-event smoke campaign only as an implementation check. It is not evidence of edge.
5. Preregister a chronological train/holdout split and compare against pinned V1 and a simple no-signal/null baseline on matched bid/ask data with conservative costs, measured latency, and explicit ambiguous outcomes.
6. Keep strategy status as research-only until the repository's promotion evidence gate is satisfied by cost-adjusted, out-of-sample results and independent review.

Passing deterministic tests does not establish profitability or Live readiness.

## 10. Ownership and implementation boundary

- Strategy owner: approves and versions the frozen profile and promotion evidence.
- Strategy engine owner: implements only the approved profile and reason-code contract.
- Independent QA: challenges lookahead, timestamp, quote, boundary, DST, overlap, and expiry behavior in a separate review.
- Main supervisor: owns task checklist, integration, registry/ledger updates, and final acceptance.

Implementation belongs in a dedicated `BREAKOUT_ACCEPTANCE` evaluator and tests. It must not alter ORB semantics or receive Live selector call sites until a separate promotion decision is recorded.

## 11. Decision log

- 2026-11-13: Draft created while the cited master PRD was not present in the repository. The recovered STRIKE V3 PRDs are now preserved under `reports/source/`; the acceptance outline supplies no numerical thresholds. No numerical thresholds or execution rules were invented. The provider-native range-builder slice closes range construction only; exact profile approval, durable lifecycle, evaluator orchestration, and cost-adjusted evidence remain open.
- 2026-11-13: Added a research-only lifecycle adapter over `ResearchStore`. Lifecycle events retain optional, backward-decodable schema-versioned evaluator provenance. Exact profile values, out-of-sample cost-adjusted validation, and any production promotion remain open.
- 2026-11-13: Independent lifecycle review passed. Root verification passed 30 focused V3/lifecycle tests, all 505 Swift tests, and the release `BlazerOSMac` target build. This qualifies implementation behavior only; it does not establish strategy expectancy or promotion evidence.
