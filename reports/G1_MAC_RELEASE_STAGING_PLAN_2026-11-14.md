# G1 Mac Release Staging Helper

**Task:** `G1-MAC-PACKAGE-STAGING`

**Owner:** Mac product; supervisor integrates

**Status:** Helper has independent source review PASS. Owner selected/pinned the BlazerOS Local Development fingerprint. A fresh current-source staged package now passes strict signature and identity verification. Prior closed-market recovery restored 120 persisted candles. FX is open, but the latest SCAN attempt timed out at the UI bridge before results could be observed; open-market data acceptance remains inconclusive.

**Debate:** The initial read-only release audit found the source build newer than installed/dist bundles, no valid signing identities at that time, differing bundle identifiers, and a destructive existing bundler. A new audit on 2026-11-14 found two valid identities; owner selected `F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`.
**Independent design challenge:** PASS — require exact identity, preserve `com.blazer.BlazerOS`, stage uniquely, verify before declaring ready; packaging does not prove runtime acceptance.

## Scope

Add a new non-destructive helper; do not edit the existing user-modified `scripts/bundle-mac-app.sh`. The helper builds the native `BlazerOSMac` target, requires an exact SHA-1 fingerprint for one identity returned by `security find-identity -v -p codesigning`, preserves bundle ID `com.blazer.BlazerOS`, and writes a uniquely named bundle to `dist/` without removing or replacing prior apps. It verifies the Info.plist, executable identity, and deep strict code signature.

The helper must fail before building or touching `dist/` when no exact valid identity is supplied. It must never ad-hoc sign, install, launch, remove old bundles, read credentials, or request Live broker access. A successful staged package is not runtime acceptance and may need a one-time Keychain trust approval before launch.

## Acceptance checklist

1. Add one script only: `scripts/package-mac-app-staged.sh`.
2. `bash -n` passes. Missing identity fails closed before build or directory creation. Existing bundle artifacts remain untouched. Reject a symlinked/non-directory `dist/` and existing/dangling stage/final paths.
3. The configured SHA-1 fingerprint must match exactly one valid codesigning identity; no common-name substring selection or ad-hoc fallback.
4. The script validates the release executable exists, copies app/resources into a unique same-volume temporary stage, writes fixed bundle ID `com.blazer.BlazerOS`, runs `plutil -lint`, signs and verifies `--deep --strict`, verifies the executable UUID matches the release product, and publishes with Darwin `renameatx_np(RENAME_EXCL)` so a concurrent destination cannot be overwritten or treated as a directory container. It verifies final bundle ID and UUID after publication.
5. Failures after staging preserve the stage for inspection; success prints the exact staged path. No installation or launch.
6. Independent review PASS. Smoke checks confirm an existing destination refuses atomically without mutation (errno 17), absent destination succeeds, Bash syntax/whitespace pass, and missing identity refuses before build. Runtime Keychain, fresh-process recovery, and open-market SCAN remain separate gates.

## G1 signed runtime acceptance cycle (2026-11-14)

### Debate — complete, read-only

- Mac product review and independent QA agree current G1 is not accepted. Source has prior open-market scan evidence, but it predates later UI/feed edits; current installed and `dist` bundles are stale. `dist/BlazerOS-Mac-20261113.app` uses `com.blazer.BlazerOS.mac20261113`; installed `/Applications/BlazerOS.app` uses `com.blazer.BlazerOS`.
- `security find-identity -v -p codesigning` currently returns two valid identities. `Sources/BlazerOSMac/OwnerSignerPin.swift` is empty, and the staged package script fails closed without that owner pin. No credential or Keychain item was accessed.
- Counterpoint: scan implementation and tests already exist, and an older open-market runtime scan worked. This narrows the present blocker to exercising the current product build, not redesigning SCAN.
- Failure case: bypassing the signer pin or launching a stale/differently identified bundle cannot establish trusted strategy manifest, Keychain continuity, or current UI behavior.

### Plan

- **Goal:** create and verify one uniquely staged native Mac build from current source using the owner's explicitly selected signer, then establish current-process and fresh-process G1 evidence.
- **Ranked scope:** (1) compile-time pin the exact owner-selected signer; (2) run the fail-closed staged packager and verify bundle ID, executable identity, and signature; (3) launch that staged build and verify credentials are read through the existing Keychain flow, perform read-only OANDA Live SCAN, confirm current quote/completed candles/decision/visible notification, quit/relaunch and verify recovery.
- **Exclusions:** no credential extraction or embedding, no broker order submission, no risk-setting change, no replacing/deleting existing app bundles, no modifying the existing bundler, and no strategy promotion based only on this runtime test.
- **Dependency:** owner selected `BlazerOS Local Development`, SHA-1 `F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`. Approval covers pinning this certificate and using it for the non-destructive staged package.
- **Preservation:** primary checkout had 128 dirty/untracked entries at task start and is not a scratch area. Preserve all user files, existing bundles, and every worktree. The verified staged app below was built from the primary checkout after the reviewed strategy changes were integrated.
- **Completion conditions (split by market availability):** Immediate staging gate: staged app bundle ID is `com.blazer.BlazerOS`; embedded signer matches the approved fingerprint; strict signature verifies; app launches; UI/notification surfaces and safe persistence restoration are inspected; targeted and full relevant tests pass; independent review accepts the evidence. Open-market gate: on a market-open session, explicit SCAN shows current source quote, completed candles, actual engine decision and visible notice; quit/relaunch restores durable history and requires fresh Live validation; independent review accepts the runtime evidence. The repository's `FxSession.isOpen` rejects Saturday, and `scan()` exits before Keychain access while FX is closed, so the open-market gate cannot be claimed today.

### Design

- The existing staged package helper is the package API. It builds `BlazerOSMac`, writes a unique bundle beside existing artifacts, and verifies the signer; it does not install or launch. The owner pin is the compile-time trust root consumed by `StrategyPromotionRuntime`.
- Runtime follows the existing Keychain resolver. The closed-market startup/status check showed no prompt but did not exercise credential authorization or establish a prompt count. Display distinguishes Live data, stale/cache bars, and errors. A setup notification is display-only; manual execution and Practice/Live safeguards remain intact.
- If signing, launch, Keychain access, network, closed market, or data validation fails, preserve the staged app and report the exact failure. No repeated-prompt loop; no fallback to ad-hoc signing or historical data.
- Runtime acceptance records scan latency and candle count; it does not infer strategy quality.
- Independent design challenge is required before editing the signer pin or running the packager.

### Checklist

| ID | Owner | Isolated worktree | Allowed files/actions | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| G1-SIGNED-RUNTIME | Supervisor | `/Users/thagreat/Desktop/Blazer/BlazerOS` | `Sources/BlazerOSMac/OwnerSignerPin.swift`, `scripts/package-mac-app-staged.sh`, uniquely staged bundle under primary `dist/`, this report | Independent design challenge CONDITIONAL PASS; owner approved exact F807… identity; metadata preflight fix QA PASS | Primary-source signed app and recovery display; no existing bundle replaced | Verify bundle/signature; inspect launched UI; retain process chronology; QA review | PARTIAL — prior closed-market recovery PASS; fresh Nov 16/17 signed package verified; open-market scan acceptance inconclusive because CUA timed out |
| G1-OPEN-MARKET-SCAN | Supervisor + independent QA | `/Users/thagreat/Desktop/Blazer/BlazerOS` (read-only scan actions only) | Primary staged app; runtime evidence log in this report | FX is open; fresh current-source signed artifact verified | Live quote, fresh completed candles, actual strategy decision, visible scan notice, latency/candle count, quit/relaunch recovery and fresh revalidation | Explicit scan; verify no order submitted; independent QA | IN PROGRESS — SCAN click attempted, but UI bridge timed out before results could be read; retry through healthy Mac UI session |
| G1-SIGNED-RUNTIME-QA | Independent QA | `/Users/thagreat/.codex/worktrees/blazer-independent-qa/BlazerOS` | Read-only review of task diff, logs, staged bundle metadata, and runtime evidence | G1-SIGNED-RUNTIME implementation evidence | PASS/PARTIAL/BLOCKED finding with exact evidence and remaining gates | Independently verify scope, signature identity, bundle ID, scan/notification/recovery claims, and no order path invoked | PASS for bounded signed-artifact identity and closed-market cold-launch recovery; not G1 overall. Open-market scan and Keychain prompt count remain unverified. |

### Design challenge — conditional PASS, read-only

The reviewer accepted the exact owner-selected pin and unique staged package path. Required correction was made above: separate the immediate signed build/launch/UI checks from the open-market SCAN and credential authorization gate. On Saturday the app's scan exits before Keychain access; the open-market gate is therefore deferred until Sunday at 17:00 America/New_York. No credentials were accessed during design review.

### Execution and review evidence (2026-11-15)

- The first package attempt signed the app but exited 141 because the `codesign -dv | awk ... exit` pipeline triggered SIGPIPE under `pipefail`. The staged artifact was retained and verified independently; the root cause was reproduced from the Bash trace. The helper now reads the full `codesign` stream before returning the exact Identifier.
- Independent QA source review of that correction: **PASS**. It confirmed exact owner pin matching, one valid identity, strict signature check, signer certificate SHA-1, bundle ID, executable UUID, and atomic no-replace publication. QA did not change files.
- `bash -n scripts/package-mac-app-staged.sh`: PASS. `git diff --check` for task files: PASS.
- `swift test` in `/private/tmp/blazeros-mac-package-staging` after the causal M15/TTL changes: **610/610 tests, 16 suites PASS**. The prior run's five issues were stale strategy-source/configuration digest goldens; updating the expected SHA-256 values restored all 11 registry tests and the full suite.
- Successful helper output: `/private/tmp/blazeros-mac-package-staging/dist/BlazerOS-Mac-staged-20261115T080419Z-56458.app`. Verified `CFBundleIdentifier=com.blazer.BlazerOS`, `BLAZER_OWNER_SIGNER_SHA1=F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`, `Authority=BlazerOS Local Development`, `codesign --verify --deep --strict` exit 0, release/staged UUID both `CC2DF75D-73B1-3DE5-92E8-BDE7CA07BD82`.
- Primary-source package output: `/Users/thagreat/Desktop/Blazer/BlazerOS/dist/BlazerOS-Mac-staged-20261115T082908Z-58913.app`. Verified `CFBundleIdentifier=com.blazer.BlazerOS`, `BLAZER_OWNER_SIGNER_SHA1=F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`, `Authority=BlazerOS Local Development`, `codesign --verify --deep --strict` exit 0, and release/staged UUID both `2973EE34-2260-3C96-8A42-6498891CDAA4`. The staged package helper revalidated the exact primary-checkout source/build-input manifest before signing.
- The primary checkout full Swift suite passed **610/610 tests across 16 suites** after reviewed strategy integration; `git diff --check` passed. This is source/test evidence, not live-broker acceptance.
- Independent final QA **PASS** for staged artifact identity/signature and closed-market cold-launch recovery. QA confirmed the exact staged executable, strict signature, owner signer pin, bundle identity, and retained before/after process chronology; it observed restored 120 stale OANDA candles, FX-closed WAIT/feed notices, and no broker orders. This is bounded recovery acceptance only, not G1 acceptance. Keychain authorization prompt count and open-market SCAN remain outstanding.
- Cold-process UI inspection shows the light Mac Trade workspace, large candle chart, Live label, and visible strategy/feed notices. Startup first shows the closed-market empty state; within six seconds it restores “Saved OANDA candles · stale · 120 bars.” It correctly shows `FX closed — SKIP`, `WAIT / NO TRADE`, and no order path.
- The Credentials sheet showed “OANDA Live credentials are saved in this device’s Keychain” and “credential is saved, but the quote feed is disconnected.” The app did not expose a token or account ID, and no macOS authorization dialog appeared during startup or this status view. This confirms Keychain-saved state, not broker authentication. No SCAN was requested and no order was submitted.
- Root process was confirmed absent before launch and restarted from the primary staged path (PID 65183, Sun Nov 15 01:26:04 PST) after graceful quit of PID 59724. The app restored its 120 saved OANDA candles and closed-market WAIT/notice state. Existing `/Applications/BlazerOS.app` and dated `dist` bundle were not replaced. Two failed hidden stages in the sidecar `dist` remain for inspection, per the helper's failure-retention contract.
- **Still unproven:** Live broker authentication, current quote freshness, live candles, multi-strategy decision on an open market, notification after a real scan, the count for any scan-triggered Keychain prompt, and post-scan open-market revalidation. FX opens Sunday at 17:00 America/New_York (14:00 Pacific); do not mark G1 complete before that acceptance run and independent QA.
- **Still unproven:** live Keychain authorization/prompt count, quote freshness, live candles, multi-strategy decision on an open market, notification after real scan, and open-market relaunch revalidation. FX opens Sunday at 17:00 America/New_York (14:00 Pacific); do not mark G1 complete before that acceptance run and independent QA.

| Updated task | Status | Evidence/next action |
|---|---|---|
| G1-SIGNED-RUNTIME (bounded staging/recovery acceptance) | PASS | Primary-checkout staged app signature, bundle ID/pin/UUID verified. Retained process chronology and before/after screenshots show 120 stale saved candles and closed-market WAIT restored. Independent QA PASS for this bounded scope. Keychain prompt count and open-market behavior are outside this pass. |
| G1-SIGNED-RUNTIME (overall G1) | PARTIAL | Live quote, current candles, multi-strategy decision, notification, Keychain prompt count, and open-market relaunch revalidation remain unverified. |
| G1-OPEN-MARKET-SCAN | INCONCLUSIVE — UI BRIDGE TIMEOUT | Re-establish a healthy Mac UI observation session, explicitly scan via the fresh staged app, verify current quote, completed candles, engine decision and visible notice; record Keychain prompt count; quit/relaunch and verify fresh Live revalidation; submit no order. |

### Current-source staged Mac verification (2026-11-16 Pacific)

- The updated staging helper and shared `.swiftpm` metadata policy allow only a direct regular, non-symlink `.DS_Store`; nested `.DS_Store` files and unsafe variants remain rejected. Independent QA PASS; focused tests 10/10 PASS.
- Fresh package: `dist/BlazerOS-Mac-staged-20261117T031404Z-76595.app`; bundle ID `com.blazer.BlazerOS`; signer `BlazerOS Local Development`; pinned SHA-1 `F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`; arm64 executable UUID `453CF523-2F5C-3E2F-B470-5C08F79CB9FA`; strict signature PASS. Existing staged bundles were preserved.
- Initial fresh UI state: Live/connecting, quote unavailable, no candles loaded, scan pending. The documented read-only SCAN action was attempted, but CUA timed out during the click and subsequent state/screenshot queries. No scan output is available; open-market data/decision/notice acceptance remains inconclusive. No order action was invoked.
- Follow-up process sampling showed the staged process alive and idle after the scan window. During the scan, worker stacks showed `OandaClient.fetchBundle`, OANDA URLSession requests, and candle JSON decoding; the main thread remained in AppKit/SwiftUI event handling. This gives no evidence of a main-thread deadlock, but the UI state is still unobserved. No code-level defect has yet been isolated for the CUA timeout.
- Next step: recover a healthy Mac UI observation session, inspect the existing staged app without opening credentials or exposing account details, and repeat the explicitly authorized read-only SCAN only when the UI can be observed. Then record results and perform fresh-process recovery. Never submit orders.
