# Mac staged packager `.DS_Store` preflight — 2026-11-16

## Status

A current-source Release build of `BlazerOSMac` passed. The authorized staged packager then stopped at preflight with `Unknown repository-local .swiftpm entry.` Inspection found `.swiftpm/.DS_Store`, a regular file, alongside the approved empty `configuration` and Xcode workspace metadata. The helper did not build or touch `dist/` on this failure. The design challenge identified the shared `StrategySwiftPMMetadataPolicy` as a second gate; both gates are now changed and independent QA passed after catching and closing the nested-file case. Focused tests passed in both the isolated worktree and primary checkout. The fresh primary package was staged and verified. Initial UI load displayed Live/connecting with no quote/candles; the SCAN action was attempted under the documented read-only scope, but CUA timed out during and after the interaction, leaving runtime acceptance inconclusive.

## Debate

The stage helper intentionally rejects unknown SwiftPM metadata entries so local configuration cannot silently influence a signed release. The current primary checkout has Xcode's workspace metadata plus Finder's `.DS_Store`, which is non-build input and prevents the approved non-destructive stage path. Deleting or moving it would modify user data. Building a non-authoritative copy would risk packaging the wrong dirty source. The proposed correction is to allow only an exact top-level `.DS_Store` regular non-symlink file; continue rejecting a directory or symlink with that name and every other unknown entry. The file is only classified, never read as build input, copied, or removed.

Counterproposal: remove `.DS_Store` from the primary checkout before packaging. Rejected because it is user-owned filesystem metadata and cleanup is unnecessary.

## Plan

**Objective:** Allow the current Mac package helper to stage the exact primary source while keeping strict SwiftPM metadata validation and all existing bundles untouched.

**Scope:** accept an exact direct `.swiftpm/.DS_Store` only when it is a regular non-symlink file in both shell `validate_swiftpm_metadata` and shared `StrategySwiftPMMetadataPolicy`; add tests for both. Reject nested `.DS_Store` basenames anywhere in `.swiftpm`, including accepted Xcode user-data subtrees. Preserve fail-closed behavior for symlinks/directories/nonregular/unknown entries; `.swiftpm/configuration` must remain empty. Update earlier promotion-plan wording if it categorically rejects hidden entries.

**Exclusions:** no unrelated source/product/UI changes; no bundle replacement or deletion; no credential reads; no signer-pin change; no reading or modifying `.DS_Store` content. Runtime acceptance is restricted to the documented read-only SCAN after fresh package verification; never submit orders.

**Preservation:** implement in `/private/tmp/blazeros-mac-package-staging`, whose staged helper and signer pin baseline match primary. Integrate only the reviewed script delta. Keep the primary `.swiftpm/.DS_Store` untouched.

**Acceptance:** shell syntax passes; metadata preflight accepts an allowlisted `.DS_Store` regular file and rejects symlink, directory, and unknown file; primary current-source staged package succeeds under the already approved exact signer, passes manifest/identifier/UUID/strict signature verification, and creates a new unique path without changing existing bundles; independent QA and `git diff --check` pass.

## Design challenge

Initial independent challenge **CHANGES REQUIRED**: the shared `StrategySwiftPMMetadataPolicy` also rejects unknown direct `.swiftpm` children, and manifest generation invokes it before build. The revised contract allows only a direct regular non-symlink `.DS_Store` in both validators. Independent QA then found that accepted Xcode user-data subtrees could contain nested `.DS_Store` files; recursive policy enumeration and a shell `find` preflight now reject those, with fixtures for both validators. Final independent QA **PASS**: direct exception is exact, nested names and unsafe variants remain rejected, and existing configuration/Xcode controls are intact.

## Checklist

| ID | Owner | Isolated worktree | Allowed files/actions | Prerequisite | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `G1-MAC-PREFLIGHT-DEBATE` | Supervisor + independent reviewer | Read-only | This report, packaging script | Preflight failure reproduced | Cause, alternatives, preservation rationale | Read-only inspection | DONE |
| `G1-MAC-PREFLIGHT-PLAN` | Supervisor | Primary report only | This report | Debate recorded | Narrow plan/exclusions/acceptance | Report review | DONE |
| `G1-MAC-PREFLIGHT-DESIGN` | Supervisor + independent challenger | Read-only | This report and script | Plan recorded | Exact allowlist exception preserves type/symlink/unknown guards | Independent challenge | PASS |
| `G1-MAC-PREFLIGHT-FIX` | Supervisor | `/private/tmp/blazeros-mac-package-staging` | `scripts/package-mac-app-staged.sh`, `Sources/BlazerCore/Research/StrategyPromotionPackage.swift`, `Tests/BlazerCoreTests/StrategyPromotionPackageTests.swift`, this report | Design challenge PASS | Allowlist direct regular `.DS_Store` in both validators; reject nested and unsafe variants; keep config/workspace rules | `bash -n`; 10 focused tests; release build | PASS |
| `G1-MAC-PREFLIGHT-QA` | Independent QA | Read-only worktree | Exact script/shared-policy/test/report diff | Fix and focused tests | Exact acceptance/no collateral mutation | Two-pass independent review; final pass | PASS |
| `G1-MAC-PREFLIGHT-INTEGRATE` | Supervisor | Primary checkout | Exact reviewed script/shared-policy/test/report deltas, this report | QA PASS | Current source stages at unique path; prior artifacts untouched | Primary focused tests, signed staged output, identity/signature checks, diff check | PASS |

## Remaining Mac acceptance

The fresh staged app must still be launched and exercised through the open-market read-only scan path documented in `reports/G1_MAC_RELEASE_STAGING_PLAN_2026-11-14.md`. Do not submit orders. The prior Nov 15 staged app is not treated as current-source acceptance.

## Primary current-source staging evidence (2026-11-16 Pacific)

- Staged app: `dist/BlazerOS-Mac-staged-20261117T031404Z-76595.app` (unique path; prior bundles were not replaced).
- Bundle ID: `com.blazer.BlazerOS`; embedded owner pin `F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`; authority `BlazerOS Local Development`.
- Executable UUID: `453CF523-2F5C-3E2F-B470-5C08F79CB9FA` (arm64). The packager compared it with the release executable before signing and again after publication.
- `codesign --verify --deep --strict`: PASS; designated requirement satisfied.
- Primary `bash -n`, `git diff --check`, and focused `StrategyPromotionPackageTests`: PASS (10/10).
- Fresh staged app opened successfully. Initial accessibility state showed `OANDA LIVE · CONNECTING`, quote unavailable, no candle data, and scan pending.
- The explicit SCAN button was clicked under the documented read-only acceptance scope. The CUA call timed out; subsequent accessibility-state and screenshot calls also timed out. No scan output could be observed, so quote/candle/decision/notice acceptance is **inconclusive**. No order action was invoked. Do not treat the market-data gate as passed.
- Follow-up process sampling found the staged process still alive and idle (0% CPU); during the scan window, worker stacks included `OandaClient.fetchBundle`, `fetchCandlesResult`, OANDA `URLSession` requests, and candle JSON decoding. The main thread was servicing AppKit/SwiftUI event processing rather than waiting inside scan or network code. This confirms the SCAN path ran network work and gives no evidence that the Mac main thread deadlocked. It does not establish the final model/UI state because accessibility snapshots remained unavailable.
- No code-level cause has been proven for the post-click CUA timeout. Do not add an arbitrary retry, timeout, or view rewrite as a substitute for observing the current app state. Resume runtime acceptance with a healthy accessibility session or direct operator-visible screen capture, then make a code fix if that evidence identifies an app defect.
