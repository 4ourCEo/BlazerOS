# G1 Live decision freshness and withdrawal — execution checklist

**Task:** `G1-LIVE-DECISION-FRESHNESS`  
**Owner:** Main Codex supervisor (integration); Mac product worker (implementation)  
**Status:** DONE · integrated into root checkout  
**Scope:** Ensure the visible Live strategy decision cannot remain BUY/SELL after its evaluation becomes unavailable, and display evaluation age/status in the native Mac desk.

## Debate and design

The read-only strategy pipeline audit and independent book/research audit both found that failed or empty M1/M5 candle refreshes can leave a previous BUY/SELL visible. The manual scan's no-result path and malformed/insufficient snapshot paths also bypass the common persistence/withdrawal publisher. Closed-market and unavailable-session monitor skips can leave the projection unchanged. Existing restore correctly revalidates a saved decision as WAIT, but currently retains its old plan in the Live projection.

The independent design challenge accepted a fail-closed change with these constraints:

- Invalidate by instrument and refresh generation. An old or canceled async result must not replace a newer decision.
- A scan intentionally skipped because another scan is active is deferred, not a failure. The active scan owns the final result.
- Partial failures affect only attempted instruments. Do not clear unrelated pairs.
- A Live WAIT has no visible actionable plan. Preserve the old plan only in append-only history/journal.
- Recovered market data can restore BUY/SELL only after a new successful fresh-data evaluation.
- Show decision age and the actual unavailable reason. Do not call a setup expired merely because its quote is older than the selector's 8-second eligibility limit; setup expiry remains strategy-specific.
- Withdrawal notifications are transition-based and repeated identical failures must not spam. Persistence failure must not leave the UI showing an actionable result.

## Implementation plan

1. Route each Live evaluation failure through one timestamped WAIT publication path: no Live credentials, closed session, failed/empty candles, missing/stale quote, malformed snapshot, insufficient valid candles, and manual scan failure for the attempted asset set.
2. Preserve scan generation and asset ownership checks across async work. Do not let an obsolete monitor/scan publish over a newer result.
3. Clear current ORB plan projection when Live data is unavailable while retaining its already-recorded research/history record.
4. Show "Evaluated … ago" and current unavailable/revalidation status in the Mac notification banner. Keep plan levels visible only for current actionable decisions.
5. Add focused regression checks for transition, persistence/display projection, deduplication, partial failure, stale task races, recovery, and the quote-freshness/setup-expiry distinction.

## Exclusions

- No strategy thresholds, candidate ranking, strategy authority, ORB lifecycle, or setup-duration changes.
- No broker order submission, position sizing, or manual execution changes.
- No iOS layout or behavior changes.
- No deletion of prior decisions, plans, or user data.

## Acceptance evidence

- After BUY/SELL, each relevant refresh failure publishes and persists WAIT without a current plan and schedules exactly one withdrawal transition.
- Repeating the same failure does not spam notifications; unrelated instruments retain their current state.
- An older async result cannot overwrite a later generation's WAIT or decision.
- Closed-market and unavailable-session states withdraw once with truthful reason text.
- Fresh successful evidence can create a new actionable decision; restoration alone cannot.
- Mac banner displays evaluation age/status and never calls the 8-second quote gate setup expiry.
- Focused tests, full Swift suite, and release Mac target build pass; `git diff --check` passes.

## Checklist

| Task | Owner | Worktree | Files | Dependency | Status |
|---|---|---|---|---|---|
| `G1-LIVE-DECISION-FRESHNESS-DESIGN` | Independent strategy QA | Read-only audit | None | Debate complete | ACCEPTED |
| `G1-LIVE-DECISION-FRESHNESS-IMPL` | Mac product worker | `/private/tmp/blazeros-live-decision-freshness` (isolated worktree based on allowlisted current source snapshot) | `Sources/LightningDesk/LightningDeskModel.swift`, `Sources/LightningDesk/MacTradingWorkspace.swift`, focused tests only | Design challenge accepted | IN_PROGRESS |
| `G1-LIVE-DECISION-FRESHNESS-REVIEW` | Independent QA | Read-only review of exact diff | Same implementation files | Worker completion | ACCEPTED · initial FAIL fixed; independent follow-up PASS for successful-but-unselected assets |
| `G1-LIVE-DECISION-FRESHNESS-INTEGRATE` | Main Codex supervisor | Root checkout | Reviewed allowlisted files and this checklist/ledger | Independent review PASS | DONE · integrated allowlisted model, Mac workspace, and focused test files |

## Preservation boundary

The root checkout contains extensive user-owned modified and untracked work. Do not reset, clean, stash, overwrite unrelated files, or reuse the dirty `/private/tmp/blazeros-breakout-range-builder` worktree. The implementation must start from a new isolated worktree and receive only the allowlisted current-source snapshot.

## Verification

- Isolated focused suite: `swift test --filter LiveDecisionFreshnessTests` passed 4/4; isolated `git diff --check` passed.
- Integrated root focused suite: `swift test --filter LiveDecisionFreshnessTests` passed 4/4.
- Integrated root full suite: `swift test` passed 509/509 across 12 suites.
- Integrated release target: `swift build -c release --target BlazerOSMac` passed.
- Root `git diff --check` passed.
- Independent QA: first review found a missed stale decision for successful-but-unselected scanned instruments; follow-up fix and test were reviewed PASS.
- Runtime OANDA refresh behavior, macOS notification delivery, and relaunch UI were not exercised in this slice. Those remain product acceptance work; this task establishes code/test behavior only.
