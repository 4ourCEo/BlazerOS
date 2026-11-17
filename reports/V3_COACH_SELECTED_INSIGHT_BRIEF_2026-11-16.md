# V3 Coach selected-insight brief — 2026-11-16

## Status

Plan recorded. Debate evidence supports a deterministic, read-only selected-insight handoff. Independent challenge of the exact UI implementation is pending. Overall STRIKE V3 remains **PARTIAL**.

## Debate

Two independent read-only audits inspected the validated Review insight and generic Coach paths. `V3ReviewInsight` contains source archive, exact plan/close/opening record IDs, missing fields, supersession state, and exact evidence rows. Review has no selected-insight handoff today. Generic Coach context and citation validation use legacy journal/ledger records; generic fallback answers from saved scan or performance context. Passing a selected V3 record through that path could answer from unrelated evidence or imply unsupported broker/performance facts.

Counterproposal: add a closed-schema V3 DTO to the Core assistant, require archive-qualified citations, constrain every answer, and handle stale/cancelled requests. Decision: defer model-backed Q&A. A dedicated deterministic brief fully covers this handoff without changing assistant context, prompts, citations, or fallbacks.

## Plan

**Objective:** Let a user open one validated Review close-completeness insight in Coach and read a deterministic brief about that exact evidence.

**Ranked scope:**

1. Offer an explicit “Explain in Coach” action on each populated insight.
2. The per-insight action identifies only source plus insight ID. Before presentation, reload and reproject that same archive; require the same source+ID and full projected payload/evidence equality. Never re-resolve from another archive or join archives.
3. On loading/read failure/empty archive/missing ID/changed leaf or invalid links, show a dedicated stale or unavailable state with a retry/return path and no old facts. Do not fall back to generic Coach.
4. For a valid current insight, render only a clearly labeled deterministic record brief: source archive; exact plan/close/opening IDs and evidence rows; missing values explicitly unavailable; user-reported/manual, unverified, not broker-confirmed provenance; and superseded-opening status when present.
5. Provide accessible per-insight action labels, visible wrapped citations, headings, stable identifiers, and return/focus behavior. Preserve existing generic Coach route and behavior.
6. Extract same-source/full-payload revalidation as a pure state projection and add focused regressions for valid live/proxy scope, same-ID payload changes, changed correction leaf, a new unrelated insight displacing the selected item beyond the six-card display cap, source mismatch, unavailable, empty, and loading states. Keep the end-to-end UI regression on the isolated Live route, including citations/provenance/return; preserve the existing generic Coach presentation regression.

**Explicit exclusions:** no Core assistant/LLM calls, legacy-context reuse, voice, market or performance analysis, broker claims, urgency/action recommendations, archive mutation, cross-archive joins, persistence changes, or external access.

**Preservation boundaries:** primary checkout contains extensive unrelated dirty and untracked work. Do not reset, clean, stash, overwrite, or prune. Implement in the existing isolated Review Insights worktree, copying only explicitly allowlisted baseline files if needed. Any simulator fixture must route through a process-static UUID temporary root under DEBUG+simulator, bypass app-group migration for this fixture only, and never write to the ordinary App Group archive. Integrate only exact reviewed file contents.

**Completion conditions:** selected source+ID is reloaded and the full projected payload/evidence is equal before any facts display; a pure state projection uses uncapped targeted lookup and is covered for valid, proxy-source, same-ID changed payload/correction leaf, unrelated-newer insight beyond cap, source mismatch, loading, unavailable, and empty states; stale/unavailable states expose no facts and never fall back; current brief shows exact source/citations, unavailable fields, supersession and provenance; generic Coach remains unchanged; focused state and isolated UI checks pass; independent exact-diff review passes; integration is byte-identical; `git diff --check` is clean.

## Design

- UI ownership: `ReviewScreen` owns pending handoff and brief state. The action carries source plus insight ID; it must not accept caller-built text or IDs. Reload the selected archive root, reproject, and require the same `(source, insightID)` plus equality of the full selected payload with the current projection (plan/close/opening IDs, missing fields, provenance/state, timestamps, superseded flag, and evidence-row identities) before presenting facts. Clear state on dismissal.
- Put the destination in a dedicated deterministic brief view, clearly titled “Insight explanation · deterministic record brief.” Do not route this selection through generic `CoachScreen`, `CoachAssistantPanel`, voice controls, legacy answer cards, or model state. Preserve the ordinary Coach sheet unchanged.
- Loading, read failure, empty/missing insight, invalid chain, or changed correction leaf yields an explicit no-facts stale/unavailable state with retry/return controls. Never show the previously selected facts, generic Coach, or another archive as fallback.
- Distinguish missing close time and exit price in clear copy (“not recorded / unavailable”). Show exact archive title, plan/close/opening IDs, exact evidence row content, manual/unverified/not broker-confirmed provenance, and superseded-opening label where applicable.
- Use native SwiftUI buttons and headings, visible wrapped text (not color-only or accessibility-only facts), action labels with source and close ID, stable UI identifiers, Dynamic Type, and a dismiss path returning focus to the originating action.
- Current archive loader reads categories sequentially. Reload/reprojection narrows stale selection but does not provide a transactional multi-file read version. Validation failure must suppress facts; concurrent correction during the sequential reload remains a documented residual risk unless the store provides atomic snapshot reads.
- The UI regression needs a linked incomplete close. A normal Live OANDA fixture risks contaminating persistent App Group storage. The simulator test route therefore uses a process-static UUID temporary root selected only by `--ui-testing-review-insight` in DEBUG+simulator builds; fixture initialization must skip App Group migration for this specific launch before any migration side effect. Normal launches and release/physical targets retain existing paths.

## Design challenge

Independent challenge first returned **CHANGES REQUIRED**, citing stale selection, generic Coach identity, source/error behavior, accessibility and sequential archive reads. The plan now requires same-source reload/reprojection by typed ID, suppression of stale facts, dedicated deterministic identity, source-qualified labels, retry/return, focus restoration, and documents the lack of a transactional multi-file archive read. Revised independent challenge: **PASS** with one acceptance refinement: matching only stable source+ID is insufficient; compare the entire selected projection payload/evidence identities and show only stale/retry/return on any difference. A subsequent fixture challenge found the normal App Group would be polluted and required isolated temporary storage. The isolated-root design first received **CHANGES REQUIRED** because model initialization called App Group migration before root selection. After adding the exact-flag migration bypass and selecting the temporary root before App Group lookup, final independent challenge: **PASS**. The source and Review use the same process-static root; normal and release/physical launches retain existing behavior.

## Checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-COACH-INSIGHT-DEBATE` | Supervisor + two read-only auditors | Read-only | This report, Coach/Review source | Existing validated Review inbox | Competing model-backed vs deterministic proposals and risks | Independent audit results recorded | DONE |
| `V3-COACH-INSIGHT-PLAN` | Supervisor | Primary report only | This report | Debate results | One objective, ranked scope, exclusions, preservation, acceptance | Report review | DONE |
| `V3-COACH-INSIGHT-DESIGN` | Supervisor + independent challenger | Read-only | This report and implementation allowlist | Plan recorded | Selection, closed evidence boundary, fallback, stale/dismissal, accessibility, platform, uncapped targeted revalidation | Independent challenge **PASS**, including uncapped lookup, source mismatch, and loading regressions | DONE — PASS |
| `V3-COACH-INSIGHT-IMPL` | Assigned worker | `/private/tmp/blazer-v3-review-insights` | `Sources/BlazerCore/Persistence/FileLocations.swift`, `Sources/LightningDesk/LightningDeskModel.swift`, `Sources/LightningDesk/Screens/ReviewScreen.swift`, `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`, `iPhone/UITests/BlazerUITests.swift` | Design challenge PASS; exact current baseline staged in isolated worktree | Dedicated deterministic brief route; pure source+ID/full-payload uncapped revalidation state and focused regressions; dedicated isolated simulator fixture; stale/error no-facts states; preserved generic Coach; targeted UI regression | `swift test --filter reviewInsight` 8/8; iPhone 17e UI 1/1; `swift build`; `git diff --check` | IMPLEMENTED — PASS |
| `V3-COACH-INSIGHT-QA` | Independent reviewer | Read-only isolated worktree | Exact implementation allowlist | Worker completion | No generic/legacy/model path; archive and citations exact; labels/accessibility complete; no stale/cap escape | Exact diff re-review **PASS**; independently ran focused 8/8, `swift build`, targeted UI 1/1, diff check | DONE — PASS |
| `V3-COACH-INSIGHT-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed allowlist and this report | QA PASS | Exact hash integration and primary verification | Five hashes match; primary focused Swift 8/8; iPhone 17e UI 1/1; diff check | DONE — PASS |

## Implementation and evidence

The isolated worker added the source+ID reload and full-payload equality gate, dedicated deterministic brief, process-specific temporary fixture root, simulator-only plan/opening/incomplete-close fixture, and an end-to-end Live UI route. The per-insight action is a sibling of the disclosure control so it remains independently reachable by accessibility and UI automation.

The first normal-form UI attempt failed and wrote its test opening and close into the simulator App Group before the action step; those records were preserved and not deleted or rewritten. This attempt is explicitly excluded from acceptance. The redesigned process-isolated fixture UI run passed **1/1** (37.7s), with `git diff --check` passing. This covers valid Live navigation, citations, unavailable missing fields, provenance, no generic Q&A panel, and return.

Independent QA returned **CHANGES REQUIRED for coverage/reporting**. It confirmed the main safety boundaries but requested focused revalidation regressions for changed payload/correction leaf and unavailable/empty/proxy cases; the report status also needed correction. The design challenger identified a further cap edge: an unrelated newer insight could displace a valid selection from the six-card list. Revalidation now uses uncapped targeted lookup and focused tests cover that case, source mismatch, and loading. Independent exact-diff QA re-review: **PASS**. It independently verified `swift test --filter reviewInsight` **8/8**, `swift build` **PASS**, isolated iPhone 17e handoff UI **1/1** with zero runtime warnings, and `git diff --check` **PASS**. Primary integration byte-matched all five allowlisted files. Primary verification: focused Swift **8/8**; iPhone 17e targeted UI **1/1**, zero xcresult runtime warnings; `git diff --check` **PASS**. The CLI emitted the known simulator WebKit duplicate-class and debugger-version diagnostics; no Swift compiler warning appeared in the focused Swift run. Known App Intents metadata skip remains documented in `reports/AV_AUDIO_SESSION_WARNING_2026-11-15.md`. No broker credentials or endpoints were accessed.

## Integrated file hashes

- `Sources/BlazerCore/Persistence/FileLocations.swift`: `0e08c6940760698ecd2d74a97630d913b1017a4deea0bd4b7f2b1dd001078c96`
- `Sources/LightningDesk/LightningDeskModel.swift`: `abedbb5198b5522ee99127701e4c1e8a026fd3afd460277ed8408214ea8222ae`
- `Sources/LightningDesk/Screens/ReviewScreen.swift`: `40c06a1418e7a8cbd3b2e1df263fd161f3da8480949a457452f9605fcef1b7da`
- `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`: `7b3332f6a8c54316ec572ae988e3a0455ad80793b4994fca10a7cdb6a7a52e67`
- `iPhone/UITests/BlazerUITests.swift`: `3ae6968ebe1456f1660dffa368fffde3832211b9066970a2d5516d6a5661d84d`

## Remaining V3 status

This task only adds a safe selected-insight display in Coach. General V3 Coach Q&A/citation support remains open. Position-close and outcome production, physical-device recovery/accessibility/performance, owner-signed strategy promotion, exact-SHA CI, and signed distribution remain open. Broker-confirmed close production remains blocked on the externally gated Practice activity source and reconciliation contract documented in `reports/RC1_IMPLEMENTATION_RECONCILIATION_2026-11-03.md`.
