# V3 Review archive state

**Task:** `V3-REVIEW-ARCHIVE-STATE`  
**Status:** Implemented, independently reviewed, and integrated into the primary checkout.  
**Parent goal:** `reports/V3_AUTONOMOUS_CONTINUATION_LOOP.md`  
**Scope:** Make the Review destination accurately report selected V3 research archives without conflating Live, proxy, synthetic, or legacy journal evidence.

## Debate

- `ResearchStore` already persists plans, setup lifecycle events, entry evidence, position events, executable spot outcomes, and structural outcomes with validation and immutable/idempotent writes.
- `ReviewScreen` currently shows only four aggregate counts. It omits lifecycle and entry-evidence event counts and silently retains zero defaults if any read fails.
- The current source selection is wrong for some visible records: Live strategy plans are written under `Research/live-oanda` through `LightningDeskModel.liveDecisionStore`, while Review reads `Research/oanda-proxy`. Reading one source under a general V3 label can falsely present an empty archive.
- No active LightningDesk path currently creates a `V3PositionRecord`; adding manual position entry would require a separate provenance-sensitive product design and is excluded here.
- The selector and promotion boundary remains fail closed, and `productionPromotionRecords` is empty. The signed promotion manifest still needs an owner-pinned identity before positive runtime acceptance; do not promote a profile in this task.

**Counterpoint:** the existing summary is intentionally read-only and keeps the legacy Journal on its existing path. A complete event timeline or manual position workflow is too large for this bounded correction. This slice improves archive truthfulness and evidence coverage without changing trade decisions or position authority.

## Plan

**Goal:** show a complete, clearly sourced summary for the Live OANDA decision archive and the OANDA proxy research archive, with distinct loading, empty, populated, and unavailable states.

**Ranked scope:**

1. Load each explicitly selected archive independently; never merge Live, proxy, or synthetic data.
2. Include V3 plan, setup-lifecycle-event, plan-entry-evidence-event, position-event, spot-outcome, and structural-outcome counts.
3. Surface a single unavailable status for a source if any required read/validation fails. Never show partial counts or default zero on failure. An absent selected archive is empty.
4. Keep the legacy Journal/Research sections and persistence untouched.
5. Add deterministic tests using injected roots for empty, populated, and malformed archives.

**Exclusions:** no position creation/editing, no strategy changes or promotion, no trade/entry authority, no synthetic archive display, no archive repair/deletion, and no change to legacy Journal records/statistics.

**Data contract:** a source enum maps only to a fixed archive label and a caller-injected root. One async load returns either a complete immutable count snapshot, `.empty` when all selected record directories are absent/empty, or `.unavailable` after any decode/validation/read error. It never exposes filesystem paths or raw errors. Each archive receives its own state and UI group.

**User behavior and accessibility:** show `Loading`, `No V3 records`, `N V3 records`, or `Archive unavailable` for each source. Label all six values as event/record counts. Give each metric a distinct accessible label/value and expose the source status as readable text. Keep Journal content visually and semantically separate.

**Performance and recovery:** reads run in the existing async view task and use `ResearchStore`'s read-only methods. Failure is retryable on the next view task; no files are rewritten. No new dependencies or shared platform behavior.

## Independent design challenge

First challenge: **PARTIAL**. Reviewer found Live OANDA plans live under `Research/live-oanda`, while Review currently reads `Research/oanda-proxy`; using one source could falsely show empty history. Reviewer also required whole-source failure semantics, root injection, accurate event-count labels, and independently accessible statuses/metrics. These amendments are incorporated above.

Second challenge: **PARTIAL, amended and closed**. The existing `ResearchStore.v3PlanEntryEvidence()` decodes without record validation or filename-to-ID verification. The design now requires safe ID/planID, observation validation at its recorded receipt time, and file-name consistency checks before returning evidence, plus malformed-but-decodable and filename-mismatch persistence fixtures. Because ForwardTest uses the accessor, full Swift and release Mac verification are required. Independent final re-review: **PASS**.

## Checklist

| Task ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-REVIEW-ARCHIVE-STATE-DESIGN` | Supervisor + independent QA | Read-only review | This report | Debate complete | Exact archive roots, data contract, failures, accessibility and exclusions agreed | Independent design challenge | ACCEPTED — PASS |
| `V3-REVIEW-ARCHIVE-STATE-IMPL` | LightningDesk owner | `/private/tmp/blazeros-v3-review-state` (new isolated source snapshot; preserve all existing worktrees) | `Sources/BlazerCore/Research/ResearchStore.swift`, `Sources/LightningDesk/Screens/ReviewScreen.swift`, `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`, `Tests/BlazerCoreTests/V3PersistenceTests.swift` | Design challenge PASS | Two archives remain separate; six validated counts; empty/populated/unavailable are distinct; no partial counts; entry evidence validates fields and filename; legacy Review path and order authority unchanged | Focused tests 16/16; full `swift test` 620/620; release `BlazerOSMac` build PASS; iPhone 17e layout 3/3 and UI 4/4; `git diff --check` PASS | DONE — independent QA PASS |
| `V3-REVIEW-ARCHIVE-STATE-INTEGRATE` | Main supervisor | Primary checkout | Reviewed allowlisted files and this report only | Implementation and independent QA PASS | Reviewed source/test bytes match isolated snapshot; integration regression evidence recorded | Primary focused tests 16/16; full `swift test` 620/620; iPhone 17e layout 3/3 and UI 4/4; primary `git diff --check` PASS | DONE |

## Preservation boundary

The primary checkout contains extensive user-owned modifications and untracked files. Do not reset, clean, stash, overwrite unrelated work, or prune existing worktrees. Use a new isolated worktree and copy only the allowlisted source snapshot into it. Main supervisor owns integration. No secrets, credentials, network access, broker orders, or external publication are needed.

## Results

Implementation complete in the isolated source snapshot. Four allowed files only: `ResearchStore.swift`, `ReviewScreen.swift`, `V3ReviewArchiveStateTests.swift`, and `V3PersistenceTests.swift`. Combined ordered-file source identity: `04100f2926ad1cb2249730177b0268611bbb95191106dedad178ec00c083888b`. No commit was created.

Verification: focused persistence/Review tests **16/16 passed**; full Swift package **620/620 passed across 16 suites**; release `BlazerOSMac` build passed; iPhone 17e simulator `DeskLayoutTests` **3/3** and `BlazerUITests` **4/4** passed; `git diff --check` passed. Xcode compiler output contained only App Intents metadata extraction notices. The previously identified runtime duplicate-class warning is outside this change and has its own accepted plan.

Independent exact-diff review: **PASS**; no reproducible defects. The four allowlisted files were copied from the reviewed isolated snapshot. Primary checkout file-by-file comparisons passed. Primary focused tests passed 16/16; primary full Swift suite passed 620/620 across 16 suites; primary iPhone 17e simulator tests passed DeskLayout 3/3 and UI 4/4; primary `git diff --check` passed. Release Mac target passed in the same isolated source snapshot. No commit created.

Remaining V3 Review gap: detailed plan/position timelines, costs, and unresolved-outcome inspection remain future scope. The current slice reports evidence category counts and availability only; it does not create positions or imply execution.
