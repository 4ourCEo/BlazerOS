# BlazerOS Worktree Reconciliation

Date: 2026-11-15  
Status: Debate complete; inventory recorded; no worktree mutations performed.

## Debate — read-only findings

Two independent read-only audits reviewed the original 13 registered worktrees. The primary checkout now contains 137 dirty or untracked entries (reviewed changes and the accepted archive validator/report are preserved). Seven original `/private/tmp/blazeros-*` worktrees are detached at primary HEAD `2aa3399` and contain large, mostly duplicated dirty snapshots; they are not safe bulk-merge sources. Three Codex worktrees are clean at `e9908dc` (not an ancestor of primary), while the strategy-engine worktree is at `0b51869` with uncommitted strategy files. No pre-existing worktree was cleaned, reset, pruned, or overwritten.

Unique or divergent deliverables identified:

- London retest source and tests in `/private/tmp/blazeros-london-break-retest` match primary byte-for-byte.
- Trend-pullback strategy/campaign files are already present in primary byte-for-byte.
- London registry files exist in primary but differ from `/private/tmp/blazeros-london-registry`; compare behavior before deciding whether any delta is useful.
- Breakout Acceptance files in `/Users/thagreat/.codex/worktrees/blazer-strategy-engine/BlazerOS` are uncommitted. Its range builder/tests match primary; evaluator/tests differ. Primary includes added provider/instrument binding and rearm safeguards. Do not overwrite primary with the sidecar version.
- `/private/tmp/blazeros-breakout-range-builder` and `/private/tmp/blazeros-trend-pullback` contain other range-builder versions; avoid mixing snapshot variants.
- `/Users/thagreat/.codex/worktrees/blazer-mac-runtime-scan/BlazerOS/Tools/` contains the ChartSpike app/build artifacts. Owner direction is to keep chart work in the existing BlazerOS Mac app; keep this isolated and do not integrate or relaunch it.
- `/Users/thagreat/.codex/worktrees/mac-ios-motion/BlazerOS` contains unique `MacCandleChart.swift` and chart-separation notes, plus changed Mac/iOS/project files that differ from primary. Review as targeted diffs only.
- `/private/tmp/blazeros-mac-package-staging` contains a separate snapshot and 226 paths absent from primary, including a duplicated `Sources/Sources` tree. The primary-checkout signed staged app is authoritative.

Counterpoint: some sidecars carry useful source or tests. Their shared dirty history and competing versions make targeted comparison safer than merging a complete branch snapshot.

## Plan

- Goal: preserve all worktree/user state and make each distinct outstanding deliverable discoverable and reviewable.
- Ranked scope: (1) label byte-identical work as already integrated; (2) isolate divergent strategy/chart changes for targeted review; (3) integrate only accepted, assigned diffs into primary; (4) retain tooling-only or owner-rejected artifacts without launching them.
- Exclusions: no reset, clean, stash, prune, bulk copy, wholesale merge, or deletion; no ChartSpike integration; no changing app/product behavior in this inventory task.
- Completion: every unique delta has a named location and disposition; no user data is discarded; subsequent code integration has a separate owner/worktree, allowed files, review, and verification evidence.

## Design and safety boundaries

- Primary checkout remains the integration authority; sidecars are evidence/source only until an individually reviewed change is assigned.
- The owner’s existing macOS/iOS boundary remains intact. `MacCandleChart.swift` is Mac-only unless an explicit shared target change is later designed.
- Strategy files remain research-only unless their exact source contract and evidence pass their promotion gates. No worktree audit creates order authority.
- Preserve all 13 pre-existing worktrees and their dirty content. A new 14th detached worktree, `/private/tmp/blazeros-oanda-archive-validator`, was created at `2aa3399` for the assigned archive validator slice; its reviewed files were integrated into primary, and the worktree remains available and unchanged. Do not infer that a duplicate-looking whole snapshot is disposable.

## Checklist

| ID | Owner | Isolated worktree | Allowed scope | Prerequisite | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| WT-INV-001 | Supervisor | Primary checkout (read-only) | This report and `git worktree list/status` reads | Independent debate complete | Unique work and duplicate snapshots listed with disposition | Compare paths/status in each registered worktree; no mutations | DONE |
| WT-STRAT-ACCEPTANCE-DIFF | Strategy owner + independent QA | Strategy-engine worktree and primary read-only comparison | Breakout Acceptance evaluator/tests only | Review primary contract and source provenance | Explicit behavior delta and recommendation; no authority promotion | Focused code/test review before any integration | DONE — retain primary |
| WT-LONDON-REGISTRY-DIFF | Strategy owner + independent QA | London-registry worktree and primary read-only comparison | Registry/test delta only | Inventory above | Explain each semantic difference; identify source-backed value | Focused review; no blind copy | DONE — retain primary |
| WT-MAC-CHART-DIFF | Mac product owner + independent QA | mac-ios-motion worktree and primary read-only comparison | `MacCandleChart.swift`, chart notes, directly related Mac diffs | Existing Mac chart source and platform boundary | Concrete usability/performance value; no iOS regression | Focused code review; Mac/iOS build and visual acceptance before integration | REVIEW — chart renderer is promising; fixes and verification needed |

### Focused reviews

**Breakout Acceptance:** Independent read-only review recommends retaining the primary implementation and not copying the strategy-engine worktree evaluator/tests over it. The sidecar has no verified provenance and removes instrument/provider binding checks and their rejection tests. It also changes breakout selection from the first qualifying displacement to the first close beyond the level (then rejects weak displacement), removing a test that permits a later qualifying break. It changes event identity on refreshed input and drops a test asserting stable identity. These are material behavior/regression risks. No files changed and no tests ran during review.

**London registry:** Independent direct no-index comparison recommends retaining primary. The sidecar removes most registry behavior/tests, including effective configuration/source digests, candidate identity/version resolution, promotion validation and safety tests. Its `family(for:)` maps unknown IDs to Legacy V1; primary returns nil and requires exactly one accepted identity. London source references are already registered in primary with the exact identity; no unique actionable London change was found. No files changed and no tests ran.

**Mac chart:** Independent read-only review found `MacCandleChart.swift` is a native macOS-only renderer with price/time axes, candle selection and OHLC, zoom/browse gestures, and accessibility labels. The primary chart already has price/time axes, scrub OHLC, zoom and horizontal browse, so no proven feature gap from this renderer was established. The chart worktree's broader workspace is behind primary and removes current multi-strategy WAIT explanations; do not replace primary with it. The renderer does not validate `bodyOpen` for finiteness and has no chart-specific tests or runtime performance evidence. Shared `MiniCandleChart.swift` edits stay out of any Mac-only task.

## Current G1 status

The approved signer pin and staged app are in the primary checkout. The staged app’s signature, identity, UUID, and current UI passed independent review. Full Swift suite: 610/610 tests across 16 suites. Overall G1 remains partial: open-market scan, live quote/candle evidence, scan notification behavior, Keychain authorization prompt count, and open-market relaunch validation have not been demonstrated. No app was installed over an existing bundle, no secret was read, and no broker order was submitted.
