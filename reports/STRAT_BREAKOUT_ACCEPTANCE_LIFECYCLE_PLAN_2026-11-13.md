# Breakout Acceptance lifecycle — execution checklist

**Task:** `STRAT-BREAKOUT-ACCEPTANCE-LIFECYCLE`  
**Owner:** Strategy engine (implementation worker); root supervisor owns integration  
**Phase:** Integrated and accepted after independent review and root verification  
**Scope:** Research-only durable lifecycle for the existing Breakout Acceptance evaluator.

## Debate and decision

- Keep `BreakoutAcceptanceV1.evaluate` pure. A separate adapter will project its evidence into the existing `ResearchStore` setup lifecycle stream.
- The existing lifecycle stream is append-only and already survives reload, but its event lacks a durable evaluator evidence link. Add optional Codable fields for configuration/input digests, engine version, source bar IDs, quote sequence, and structured reason codes. Optional fields preserve decoding of older events.
- Setup identity is a SHA-256 digest over strategy/version, config digest, engine version, instrument/provider/environment/timeframe, frozen structure identity, and configured direction. It deliberately excludes the changing quote and breakout bar so one frozen setup keeps one lifecycle identity.
- Each distinct evaluator input produces one idempotent event; exact replay is a no-op. Persist same-state observations so a relaunch has the latest source-time/sequence cutoff. Reject older source time, decreasing sequence, and same source time with conflicting/non-increasing sequence. Terminal setups cannot resume; a new frozen structure/config/build has a different setup identity.
- Map `WATCHING` to WATCHING, `AWAITING_ACCEPTANCE` to APPROACHING, and `RESEARCH_SIGNAL` to CONFIRMED. For `.REJECTED`, only explicit structural failure reason codes may invalidate; only explicit setup/session/bar-window expiry codes expire. Quote/spread/data/config/regime/cost/ambiguity/cluster rejects remain nonterminal (STALE where lifecycle supports it) and retain their reason codes.
- A monitor may first observe a setup after it has advanced. Permit an initial state beyond WATCHING only when the event carries complete typed evaluator provenance. Do not fabricate earlier event times or backfill stages absent from evidence. Allow a fresh watcher to progress directly to APPROACHING when the initial-break stage was already passed before monitoring began. Repeated timestamps are ordered by durable `recordedAt`; one append per observation avoids synthetic intermediate timestamps.
- No selector, production scan, Mac/iOS UI, notifications, broker orders, risk values, strategy thresholds, or promotion changes are part of this task.

## Independent design challenge

`book_hypothesis_inventory` found missing evidence/config/structure provenance and stale-observation guards in the old event contract. `strategy_pipeline_audit` additionally found that first observation can already be a signal, intermediate timestamps are unavailable, and equal `recordedAt` transitions are rejected. The accepted design addresses these by recording a single fully evidenced observed state (no fabricated backfill), optional typed event provenance, and a deterministic per-input idempotency key with monotonic source guards. The adapter only changes lifecycle transition state after evaluator status/reason classification.

## Checklist

| ID | Owner | Worktree | Allowed files | Prerequisites | Acceptance evidence | Status |
|---|---|---|---|---|---|---|
| `STRAT-BREAKOUT-ACCEPTANCE-LIFECYCLE-IMPL` | Strategy engine worker | `/private/tmp/blazeros-breakout-range-builder` (isolated disposable worktree; preserve its current dirty state) | `Sources/BlazerCore/V3DomainContracts.swift`; new `Sources/BlazerCore/Research/BreakoutAcceptanceLifecycleV1.swift`; new `Tests/BlazerCoreTests/BreakoutAcceptanceLifecycleV1Tests.swift` | This plan and accepted independent challenge | Adapter and schema landed in root; legacy decoding, initial advanced state, state mapping, transient/terminal reasons, dedupe/relaunch, monotonic source ordering, terminal re-arm, environment/config/structure identity and duplicate tamper tests pass | ACCEPTED |
| `STRAT-BREAKOUT-ACCEPTANCE-LIFECYCLE-REVIEW` | Independent QA | Read-only review of exact worker diff | Same implementation files | Worker completion | Independent review PASS after resolving sequence, duplicate identity, rejection classification, expiry and initial advanced state findings | ACCEPTED |
| `STRAT-BREAKOUT-ACCEPTANCE-LIFECYCLE-INTEGRATE` | Root supervisor | Root checkout | Worker-approved files plus lifecycle plan, contract, register, ledger | Independent review PASS | Root focused V3/lifecycle tests 30/30, full Swift suite 505/505, release `BlazerOSMac` build passes, `git diff --check` passes; no selector/order call sites | DONE |

## Worktree preservation note

The selected temporary worktree already contains the copied source snapshot and unrelated local edits from earlier verified work. Only reviewed lifecycle files were copied into root. No unrelated worktree state was staged, reset, cleaned, or pruned.
