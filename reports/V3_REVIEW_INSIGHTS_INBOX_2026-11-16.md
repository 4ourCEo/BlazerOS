# V3 Review Insights inbox — 2026-11-16

## Status

Plan, design challenge, implementation, independent QA, and primary integration are complete. Review close-completeness Insights are verified; the broader Coach V3-context requirement remains partial. Overall STRIKE V3 remains **PARTIAL**.

## Debate

Two independent read-only audits compared the current Review and Coach surfaces with PRD §4.4 (`reports/source/BlazerOS_STRIKE_V3_REBUILT_PRD.md:139-141`). They agree that:

- Review loads V3 plans, lifecycle, entry evidence, positions, user-reported closes, and outcomes, and distinguishes loading, empty, populated, and unavailable archives.
- Review has no bounded Insights inbox. Coach citations are validated against legacy journal/ledger context and do not include records displayed in the V3 archive.
- A small mechanical evidence-gap projection is actionable; it should link to exact source records, use archive state to preserve unavailable-vs-empty semantics, and avoid speculative ranking or performance claims.
- Existing Coach behavior is bounded/read-only with deterministic fallback and citation checks. Broad Coach/assistant redesign or notification delivery is outside this slice.

Counterargument: Review already has detailed timelines, so insights could duplicate the same data. Mitigation: project only a high-value completeness gap (missing user-reported close time and/or price), cite the exact close and opening IDs, include the existing timeline rows on expansion, and cap the number of cards.

## Plan

**Objective:** Add a bounded, deterministic Insights section to Review that surfaces only linked user-reported close records whose effective close time or exit price is unavailable.

**Ranked scope:**

1. Derive insights only from a successfully loaded `V3ReviewArchiveSnapshot` and only for close events linked to their plan and opening record.
2. Keep the latest close correction in each close chain; do not duplicate superseded reports.
3. Emit stable identity, exact plan/close/opening references, explicit missing fields, source archive, manual/unverified/not-broker-confirmed status, and deterministic sort/cap behavior.
4. Add Review loading, unavailable, empty, populated, and no-matching-insights states. Expanding a card shows its exact cited timeline rows.
5. Add projection and interaction regressions; preserve archive separation, existing timelines, assistant context, and manual-only execution safeguards.

**Explicit exclusions:** no broker integration, position/lifecycle mutation, market or performance inference, notification delivery, Coach prompt/context redesign, order path, or cross-archive joins. V3 Coach citation access remains open after this slice.

**Preservation boundaries:** keep all existing dirty work intact; do not reset, clean, stash, overwrite, delete simulator data, read credentials, call broker endpoints, or publish. Restrict edits to the files named in the checklist.

**Completion conditions:** valid linked incomplete close produces one bounded insight with exact citations and explicit missing fields; complete close produces none; superseded correction is not duplicated; malformed/unlinked archive evidence does not become an insight; archive failure differs from empty; stable ordering/cap are tested; UI exposes manual/unverified provenance and exact linked rows; all focused/full checks pass; `git diff --check` is clean.

## Design

- Derivation is a pure projection over the already atomically validated snapshot. It does not query current quotes, mutate records, or call the assistant.
- Candidate close must occur in `snapshot.detail(planID).timeline` as a linked close, and its referenced immutable opening record must be present in the same source snapshot. Integrity conflicts and orphans produce no insight.
- Select only the unsuperseded terminal close correction per position/close chain. Insight ID is stable from archive source plus close record ID. Cites are the plan ID, close ID, and opening record ID; only close/opening timeline rows are shown as evidence citations.
- Missing values remain explicitly unavailable. The card says the record is a user report, unverified, and not broker-confirmed; no actual execution or performance claim is implied.
- Sort by report receipt time descending, then stable insight ID ascending; cap at six insights per archive. `empty`/`unavailable` archive states are rendered distinctly from a populated archive with zero matching insights.
- Accessibility labels expose status, missing fields, and cited record IDs. No VoiceOver-only or color-only status.

## Design challenge

Independent challenge: **PASS**. The existing store validates one root, predecessor existence, no branches, and a connected close chain (`ResearchStore.swift:1018-1073`). Selecting the unsuperseded leaf is therefore safe for a successfully loaded snapshot; do not use timestamp fallback. `V3ReviewPlanDetail` marks a close with a missing opening revision as integrity evidence (`ReviewScreen.swift:120-130`). Preserve the exact cited opening revision and any “later superseded” label. Use non-urgent copy because unknown values may be intentional; accessibility must announce archive, manual/unverified/not-broker-confirmed status, missing fields, and exact IDs. Required regressions include complete/incomplete leaf, complete correction superseding incomplete close, chains per position, orphan/mismatched opening, superseded opening, deterministic cap/sort and stable IDs, archive unavailable vs empty/zero matches, and linked-row expansion. No edits or tests were made in the challenge.

## Checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `V3-REVIEW-INSIGHTS-PLAN` | Supervisor | Primary (report only) | This report | Two independent read-only audits | Scope, exclusions, preservation, completion conditions | Report review | DONE |
| `V3-REVIEW-INSIGHTS-DESIGN` | Supervisor + independent challenger | Read-only | This report, `ReviewScreen.swift`, `V3ReviewArchiveStateTests.swift`, `BlazerUITests.swift` | Plan recorded | Pure source-bound projection, close-chain/link validation, unavailable semantics, accessibility, deterministic cap | Independent challenge **PASS**, including corrections recorded above | DONE — PASS |
| `V3-REVIEW-INSIGHTS-IMPL` | Assigned worker | `/private/tmp/blazer-v3-review-insights` | `Sources/LightningDesk/Screens/ReviewScreen.swift`, `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`, `iPhone/UITests/BlazerUITests.swift`, this report | Design challenge PASS | Bounded linked-close gap projection, citations, state semantics, accessible content, regressions | Focused 4/4; full Swift 675/675; iPhone 17e 33/33; `git diff --check` | IMPLEMENTED — PASS |
| `V3-REVIEW-INSIGHTS-QA` | Independent QA | Read-only | Exact implementation allowlist and logs | Implementation complete | Link validity, stale/superseded/orphan handling, state semantics, accessibility, no mutation | Initial CHANGES REQUIRED corrected with visible plan citation; exact-diff re-review | DONE — PASS |
| `V3-REVIEW-INSIGHTS-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed allowlist | QA PASS | Hash-equal integration and primary verification | Four hashes match; focused 4/4; full Swift 675/675; iPhone 17e 33/33; `git diff --check` | DONE — PASS |

## Evidence and result

### Implementation

Changed only the assigned allowlist:

- `Sources/LightningDesk/Screens/ReviewScreen.swift`
- `Tests/BlazerCoreTests/V3ReviewArchiveStateTests.swift`
- `iPhone/UITests/BlazerUITests.swift`
- `reports/V3_REVIEW_INSIGHTS_INBOX_2026-11-16.md`

The pure projection uses only the selected archive snapshot. It validates close and opening correction chains, requires exact linked plan/close/opening timeline rows, emits only incomplete unsuperseded manual close leaves, preserves a later-superseded opening label, sorts by `recordedAt` descending then stable ID, and caps each archive at six. The view distinguishes loading, unavailable, empty, and populated-with-no-matches. Expanded cards expose the selected archive, missing values, manual/unverified/not-broker-confirmed status, exact IDs, and the exact close/opening rows.

### Verification

- `swift test --filter reviewInsights` — **PASS**, 4 tests.
- The first snapshot `swift test` attempt completed 675 tests with two unrelated staged-packaging test failures because the isolated snapshot omitted `scripts/package-mac-app-staged.sh`. The existing script was then copied into the isolated snapshot as a test dependency only (commit `98ee79e`, not part of the product-task delta); rerun passed **675/675 across 17 suites**. The primary checkout and script were not changed for this task.
- First full iPhone test plan run: app tests **27/27 passed** and five UI tests passed; the existing close-correction UI test saw the confirmation switch off and the plan exited 65. The close-correction test then passed **1/1** in isolation. A full iPhone 17e rerun passed **33/33** (27 app + 6 UI) with zero failures: `/tmp/blazer-review-insights-full.xcresult`.
- `git diff --check` — **PASS**; no whitespace errors.

### Independent review and correction

- Independent exact-diff review first returned **CHANGES REQUIRED** because sighted users could not see the plan ID. Added a visible `Plan <planID> · close record <closeID> · opening record <openingRecordID>` line inside the expanded insight and asserted its exact string in the projection test.
- Independent exact-diff re-review: **PASS**. The projection remains source-bound, rejects invalid/orphan links, selects the unsuperseded close leaf, preserves superseded-opening status, keeps archive states distinct, and does not mutate position/risk/broker state.
- After the visible-citation correction, `swift test --filter reviewInsights` passed **4/4**; focused Review UI test passed; targeted close-correction UI passed **1/1**; and the isolated full iPhone 17e test plan passed **33/33**. Independent exact-diff re-review: **PASS**.
- Primary implementation hashes exactly match the reviewed snapshot:
  - `ReviewScreen.swift`: `3b41b9ab934ef2c3a5432be859af5814fb5efe6945943c562bdbc78bc7ba5827`
  - `V3ReviewArchiveStateTests.swift`: `d1a206060a5d8082b4f144956577d965c11f3444f76ea9fef453d35f91e9bd35`
  - `BlazerUITests.swift`: `fc2ef924a526ebdc8bd126207e5e245f3a0c6385e07a11f445dda4cf46a5f2b7`
- Primary focused Insights tests **4/4**; full Swift suite **675/675 across 17 suites**; full iPhone 17e plan **33/33** (27 app + 6 UI); `git diff --check` **PASS**. Primary result bundle: `/tmp/v3-primary-review-insights-full.xcresult`.

The Xcode run emitted simulator/test-host diagnostics (duplicate WebKit accessibility class, unresolved debugger-version lookup, voice metadata fallback, app-group entitlement notices, pointer service port notice, concurrency/appearance warnings, and an IOSurface notification failure). The tests continued; these were not compiler warnings from the Insights changes.

The focused UI check uses the existing stable demo route rather than seeding a close record. Exact citation content and expansion row identity are covered by snapshot projection tests to avoid brittle simulator archive state. Independent QA, primary integration, and primary verification are complete.

### QA correction: visible plan citation

Independent QA found that the plan ID appeared in the insight's accessibility label but was not visibly rendered. The expanded insight now displays a citation line containing `Plan <planID>`, the close record ID, and the immutable opening record ID. The projection test asserts the exact visible citation string; the UI binds that same string to a visible `Text` row with a stable accessibility identifier.

Correction verification:

- `swift test --filter reviewInsights` — **PASS**, 4 tests.
- `xcodebuild -quiet -project iPhone/BlazerOS.xcodeproj -scheme BlazerOS -destination 'platform=iOS Simulator,name=iPhone 17e' -derivedDataPath /tmp/blazer-review-insights-derived -only-testing:BlazerUITests/BlazerUITests/testPrimaryDestinationsAreTradeMarketsReview test` — **PASS**, exit 0. This stable UI route verifies the Review Insights section/status. The app fixture has no incomplete close record, so exact plan/close/opening text is asserted by the projection test instead of depending on simulator persistence state.
- `git diff --check` — **PASS**.

The visible citation correction is committed separately after original implementation commit `ea2e367896ab4f1b2984940b6cce37e0d5001248`. Correction commit: `c5163b3466595d5560fddb1b3b2c6207e3bffcce`. No other acceptance scope changed.

## Status and next gap

This bounded Review Insights inbox slice is **VERIFIED** in primary. The overall STRIKE V3 goal remains **PARTIAL**. Next Coach requirement is to expose validated V3 archive context and direct individual-record citations while preserving archive separation and explicit unavailable responses. Broker-confirmed close production remains specifically **BLOCKED** pending authorized Practice account activity access, verified schema, account binding, and transaction reconciliation contract; physical-device evidence, owner-signed strategy promotion, exact-SHA CI, and signed distribution also remain open.
