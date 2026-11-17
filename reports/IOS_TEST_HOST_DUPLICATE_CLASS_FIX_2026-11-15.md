# Remove duplicate package classes from hosted iOS tests

**Task:** `IOS-TEST-HOST-NO-STATIC-DUPLICATES`  
**Status:** Integrated and verified in an isolated snapshot; runtime package duplicate-class diagnostics removed from hosted unit tests.  
**Scope:** Remove runtime duplicate Swift class definitions from the iOS unit-test process without changing production package linkage.

## Debate

Two independent source/log reviews confirmed that `BlazerTests` links the static SwiftPM products `BlazerCore` and `LightningDesk` while using `BlazerOS.app/BlazerOS` as `TEST_HOST`. The app separately links those same products. Runtime diagnostics therefore find duplicate class implementations in `BlazerOS.debug.dylib` and `BlazerTests.xctest/BlazerTests`. `DISABLE_DIAMOND_PROBLEM_DIAGNOSTIC=YES` suppresses only Xcode's build-time graph diagnostic; it does not remove the runtime duplicates.

Counterpoint and failure case: unhosting the current test bundle directly is unsafe. `DeskLayoutTests` now creates `UIWindow(windowScene:)` from `UIApplication.shared.connectedScenes`, and other tests may rely on host identity, app-group entitlements, or application support. Changing production package products from static to dynamic would change app linkage and packaging broadly.

## Plan

**Goal:** host `BlazerTests` in a minimal scene-capable iOS test host that does not link `BlazerCore`, `LightningDesk`, or `BlazerCrypto`. Keep the test bundle as the only owner of those statically linked package implementations in the XCTest process. Keep the shipping `BlazerOS` app and `BlazerUITests` path unchanged.

**Ranked scope:**

1. Add a minimal `BlazerTestHost` application target with one SwiftUI/UIKit scene and a distinct bundle identifier.
2. Point `BlazerTests` `TEST_HOST`/`BUNDLE_LOADER` and target dependency at that host; remove direct app host dependency while retaining package modules linked to the test bundle.
3. Preserve required test entitlements and app-group behavior only if existing focused tests demonstrate they are required. Do not copy production secrets, credentials, or signing settings.
4. Verify the runtime process no longer emits duplicate class diagnostics while tests still resolve production types from the test bundle.

**Exclusions:** no package library type changes; no shipping app target changes beyond any shared project bookkeeping needed for the new test host; no warning suppression/linker hacks; no test semantics changes unrelated to host compatibility.

## Design contract

- The host has a real `UIWindowScene`, no app trading/service code, no network or Keychain setup, no Live Activity/intents, and no broker authority.
- `BlazerTests` remains the sole target linking the SwiftPM static products in its test process; `BlazerTestHost` must not link those products.
- The host uses a distinct bundle ID, an explicit empty UI, and only the test entitlements needed for tests. `BlazerUITests` continues to launch `com.blazer.os` directly.
- Do not grant `group.com.blazer.os` to the test host as a shortcut. Existing execution/OTC tests access the pending-Siri flag through that suite; verify these tests still pass without changing production app-group data. If they fail, stop and design a test-only defaults injection before adding any entitlement.
- Audit `Bundle.main.bundleIdentifier` and app-group assumptions in the complete test suite; run unit tests under the new distinct host identity.
- The test host must not be installed or distributed as a production app.
- If a test fails because it assumed the production host's identity or entitlement, record that as a bounded compatibility finding; do not grant unrelated capabilities to force it green.

## Acceptance evidence

- Project graph inspection confirms no Swift package product link from `BlazerTestHost` and exactly one copy in the XCTest process.
- Focused layout, execution, and `PhoneTargetTests` pass under the new host; full iPhone unit suite and UI suite pass.
- Simulator runtime output contains no `Class ... is implemented in both ... BlazerOS ... BlazerTests` diagnostics.
- Existing package/full Swift tests, release Mac target, shipping iPhone app build, and `git diff --check` pass.
- Independent review approves the exact project/host diff. Production target linkage and the active UI-test launch path remain unchanged.

## Checklist

| Task ID | Owner | Isolated worktree | Allowed files | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| `IOS-TEST-HOST-DEBATE` | Strategy QA + independent QA | Read-only | Project/test logs | None | Linkage cause, counterpoint, safe options, failure cases | Independent audits | DONE |
| `IOS-TEST-HOST-DESIGN` | Supervisor + independent QA | Read-only review | This report | Debate complete | Host contract, bundle identity, app-group data isolation, target isolation | Independent design challenge | ACCEPTED — PASS |
| `IOS-TEST-HOST-IMPL` | iOS build owner | `/private/tmp/blazeros-ios-test-host` (new source snapshot after V3 Review integration) | `iPhone/BlazerOS.xcodeproj/project.pbxproj`, new `iPhone/TestHost/**`, `iPhone/Tests/ExecutionFlowTests.swift` stale expected-message assertion only | Design challenge PASS; stale expectation confirmed against model output and primary checkout | Minimal host is separate, package classes link once, tests pass under distinct bundle ID without production app-group entitlement/data changes, no app/test package duplicate diagnostics | Focused historical test; full iOS unit/UI; app-group tests; source identity and diff checks; existing package/Mac verification for unchanged Swift products | INTEGRATED — VERIFIED |

## Preservation boundary

The primary checkout and multiple registered worktrees contain user-owned dirty changes. Preserve all of them. Do not alter package linkage or existing app/test source outside the exact approved scope. Main supervisor owns integration; no commits or publication are included.

## Results

Independent design challenge: **PASS**. The reviewer accepts a minimal host without production package links, requires a distinct bundle ID, prohibits production app-group entitlement/data access, and requires execution/OTC tests to pass under the helper. If test isolation fails, stop and design test-only defaults injection before changing entitlements.

The isolated implementation adds a scene-capable `BlazerTestHost` with bundle ID `com.blazer.os.testhost`, no SwiftPM product links, and no production app-group entitlement. `BlazerTests` now loads its package-linked test bundle in that host. The stale historical-entry test message was updated to match the model string; `XCTAssertNil(model.activeTrade)` is retained.


## Verification — 2026-11-15

- Focused historical-entry test: **1/1 passed**.
- Full iPhone 17e simulator suite: unit tests **22/22**, UI tests **4/4**. App-group/OTC tests passed **2/2** under the helper host without granting it the production entitlement.
- Runtime log contains no `BlazerOS`/`BlazerTests` duplicate Swift package class diagnostic. UI automation does emit a separate iOS Simulator runtime warning that `UIAccessibilityLoaderWebShared` exists in both system WebKit and WebCore; it is outside this app target.
- The full test log still reports an AVAudioSession main-thread hang-risk warning from `VoiceSession.swift:249`, plus simulator-only voice service diagnostics. Audio-session lifecycle is a separate open warning and needs its own serialized/availability-aware design.
- Build-time App Intents metadata notices are unchanged; the app has no App Intents code or framework dependency.
- `git diff --check` passed. The integrated project, host, and test files match the isolated verified snapshot byte-for-byte.
