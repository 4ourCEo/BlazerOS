# V3 Coach insight question intents — 2026-11-16

## Status

Debate, plan, design challenge, implementation, independent QA, and primary integration are complete for finite selected-insight intents. General natural-language V3 Coach Q&A remains open. Overall STRIKE V3 remains **PARTIAL**.

## Debate

Two independent read-only audits reviewed PRD §4.4 and the current Coach/Review paths. The integrated `Explain in Coach` route is a deterministic brief for one selected, revalidated close-completeness insight. Generic Coach still receives only legacy journal, ledger, observations, and performance context; it has no V3 records or archive-qualified citations, and its fallback can answer about an unrelated scan/performance record. Passing all V3 archives to generic freeform Coach would create source mixing, unvalidated citations, and false fallback answers. The selected brief's same-source revalidation, full-payload equality, and nonready/no-facts behavior provide a safe basis for a smaller next slice.

Counterproposal: keep the exact brief as a read-only display; the close insight has few facts, so extra Q&A interaction may duplicate content and imply model-backed reasoning. Decision: add only a small finite-intent layer that reveals fixed deterministic text for directly supported questions. It will remain clearly identified as deterministic and preserve the brief as authoritative. This does not claim to satisfy general natural-language V3 Coach Q&A.

## Plan

**Objective:** Let a user ask a small, explicit set of deterministic questions about the one selected, revalidated close-completeness insight, with answers and citations derived only from that insight.

**Ranked scope:**

1. Add a closed intent enum with fixed mappings for: missing close details; what the manual record establishes; whether it is broker-confirmed; which plan/close/opening records are linked; and whether the referenced opening was superseded.
2. Offer these intents only when the selected insight route is `.ready`. Keep source, exact IDs, missing values, and provenance visible in every answer or persistent surrounding brief.
3. Build response text from the selected immutable `V3ReviewInsight` only. Include archive-qualified visible record IDs; do not use `AssistantContext`, generic `CoachAnswer.fallback`, `AssistantSession`, Apple Foundation Models, market/account data, or another archive.
4. Unsupported intent has an explicit deterministic “not supported by this record” response; no freeform question field is added.
5. Add exhaustive enum/response tests for missing one/both, supersession true/false, exact supporting citations, and nonready reset; add a UI interaction regression. Preserve the existing generic Coach flow.

**Explicit exclusions:** no freeform/NLP or model-backed answers, whole-archive retrieval, cross-archive joins, citations outside this one insight, Legacy context, notifications, broker/market/account APIs, outcome or performance claims, order/risk/lifecycle mutation, and changes to general Coach prompts/fallbacks.

**Preservation boundaries:** use the current isolated Review Insights worktree; do not reset, clean, stash, prune, or overwrite user changes. Primary has existing user work and one documented simulator App Group fixture side effect from a prior failed UI attempt; preserve it. The accepted UI test uses the process-isolated DEBUG simulator root. Integrate only exact reviewed files.

**Completion conditions:** finite intents have exhaustive deterministic answers; text is sourced only from the selected insight and preserves missing/unverified/not-broker-confirmed semantics; exact citations remain visible; stale/nonready state exposes no intent controls or answers; unsupported intent does not fall through to generic Coach; generic Coach remains intact; focused unit/UI/build checks pass; independent exact-diff review and `git diff --check` pass.

## Design

- Put the intent/answer contract next to the deterministic insight brief in `ReviewScreen.swift` or a narrowly scoped new LightningDesk type. Inputs are the already validated value only; no store/model/network dependencies.
- The intent UI reads only the existing `V3ReviewInsightRouteValidation.ready` payload. A source-tagged citation list is constructed from `insight.source`, close ID, and exact opening ID. The plan ID is shown as a binding reference unless the plan row itself is included as evidence.
- Fixed safe answers:
  - “What is missing?” lists only `missingFields`, says values are not recorded and remain unavailable, and makes no estimate.
  - “What does this record establish?” says only that a manual close report was recorded; it does not establish an actual close, execution, or fill.
  - “Is this broker-confirmed?” says no, explicitly unverified/not broker-confirmed.
  - “Which records are linked?” lists the same archive plus exact plan, close, and opening IDs.
  - “Was the opening superseded?” states the supersession flag; if true, labels that opening as historical and not current. If false, says the selected evidence does not mark it superseded.
- Retain the deterministic brief and local-archive-snapshot identity, exact evidence rows, missing values, and provenance on screen. Announce intent and answer accessibly; keep long IDs wrapped under Dynamic Type. Use a small number of visible buttons; no text field.
- Intent interactions are synchronous and side-effect-free. Nonready route states do not present the question controls. Dismissing the sheet clears the selected route per existing behavior.

## Design challenge

Independent challenge: **PASS**. The reviewer confirmed all five intents are supported by insight fields/rows, and required that the “establishes” answer say only that a manual close report was recorded. Each answer must cite only supporting archive-qualified record IDs; label plan ID as a binding reference. Controls and prior answer stay hidden/cleared whenever the route is nonready or retrying. Keep the local snapshot caveat, deterministic identity, accessible question/answer and no model/fallback path. Challenge regressions include missing one/both values, supersession true/false, source mismatch, nonready/retry reset, existing generic Coach unchanged, and a selected intent UI interaction.

## Checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-COACH-INTENTS-DEBATE` | Supervisor + two read-only auditors | Read-only | This report and Coach/Review source | Selected-insight brief integrated | Narrow deterministic vs freeform options and failure risks | Two audit reports recorded | DONE |
| `V3-COACH-INTENTS-PLAN` | Supervisor | Primary report only | This report | Debate complete | Objective, scope, exclusions, preservation, measurable completion | Report review | DONE |
| `V3-COACH-INTENTS-DESIGN` | Supervisor + independent challenger | Read-only | This report and implementation allowlist | Plan recorded | Closed enum, source-only answers, stale behavior, accessibility, no model path | Independent design challenge **PASS**, with answer/citation/retry acceptance clarifications recorded | DONE — PASS |
| `V3-COACH-INTENTS-IMPL` | Assigned worker | `/private/tmp/blazer-v3-review-insights` | `Sources/LightningDesk/Screens/ReviewScreen.swift`, `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`, `iPhone/UITests/BlazerUITests.swift`, this report | Design challenge PASS | Deterministic finite intent UI, exhaustive mapping tests, selected-brief UI regression | Full focused 11/11; UI 1/1; package build pass; diff check | IMPLEMENTED — PASS |
| `V3-COACH-INTENTS-QA` | Independent reviewer | Read-only isolated worktree | Exact implementation allowlist | Worker completion | No source leaks, unsupported claims, generic/model fallback, or mutation | Exact-diff review **PASS**; independently verified focused 3/3 and 11/11, build, UI 1/1, zero runtime warnings, diff check | DONE — PASS |
| `V3-COACH-INTENTS-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed allowlist and this report | QA PASS | Hash-equal integration and primary verification | Three hashes match; primary focused 11/11; iPhone 17e UI 1/1; diff check | DONE — PASS |

## Implementation and evidence

Implemented in the isolated worktree across the three allowed product/test files. The ready-only deterministic answer mapper has five supported intents and a closed unsupported case. Each answer uses only the selected insight, source-qualified citations, and fixed language; the plan ID is called a binding reference. Nonready route states have no selected insight, so answer construction returns `nil`. The sheet retains its deterministic/local-snapshot label and hides the Q&A controls for nonready states. Generic Coach, AssistantSession, model prompts, and legacy fallback are untouched.

Focused verification:

- `swift test --filter reviewInsightQuestion` — **3/3 passed**.
- `swift test --filter reviewInsight` — **11/11 passed**.
- `swift build` — **PASS**.
- Isolated iPhone 17e UI `testReviewInsightOpensDeterministicCoachBrief` — **1/1 passed**; verifies missing-details and broker-confirmation intents, exact citations, no free-text Coach field, and return. Isolated result: `/tmp/blazer-v3-coach-insight-derived/Logs/Test/Test-BlazerOS-2026.11.16_17-45-50--0800.xcresult`; primary result: `/tmp/v3-primary-coach-insight-derived/Logs/Test/Test-BlazerOS-2026.11.16_17-50-54--0800.xcresult`. Both report zero runtime warnings.
- `git diff --check` — **PASS**.

The first intent UI attempt failed because a parent accessibility identifier replaced child question-button identifiers. Adding an accessibility container preserved each child identifier; the rerun passed. This attempt used only the process-isolated fixture root. No regular App Group data was accessed or changed.

Integrated file hashes:

- `Sources/LightningDesk/Screens/ReviewScreen.swift`: `f5580d1a4e94d8c203262d84d94edb6e7adfe6c89d47dff4f93a3f28264de22d`
- `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`: `783f64b9abd9fd59f9dcea07a8823f1794dcbbab1c9863ff64880a6aa5d37411`
- `iPhone/UITests/BlazerUITests.swift`: `7bbe199a4416ebda4ad11a21991270c880a2430532769970c5a55ec47cfb1fd3`

Independent exact-diff QA: **PASS**; reviewer independently reran focused answer tests 3/3 and combined insight tests 11/11, `swift build`, isolated iPhone 17e UI 1/1 with zero runtime warnings, and `git diff --check`. Primary integration byte-matched all three reviewed files. Primary focused Swift tests **11/11**; primary iPhone 17e UI **1/1** with zero xcresult runtime warnings; `git diff --check` **PASS**. Xcode command output contained the known debugger-version lookup diagnostic; no Swift compiler warning appeared in the focused Swift run. The prior failed normal-storage UI test side effect remains preserved and is outside this change; all new UI work continues to use the isolated process-specific test root. General natural-language V3 Coach Q&A remains open; broader V3 retrieval, physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open. Broker-confirmed close production remains blocked on authorized Practice activity access and a verified reconciliation contract.
