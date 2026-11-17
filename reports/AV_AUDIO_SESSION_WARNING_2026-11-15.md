# AVAudioSession warning and lifecycle follow-up

**Task:** `VOICE-AUDIO-SESSION-LIFECYCLE`
**Status:** Integrated and verified in primary; iOS 26 runtime evidence unavailable.
**Evidence:** iPhone 17e simulator suite reported `AVAudioSession_iOS.mm:978` from `VoiceSession.swift:249` during `testExpiryRecordsReferenceWithoutTouchingConfirmedStats`.

## Debate

Two read-only lifecycle audits agree that synchronous activation/deactivation on the main thread causes the hang-risk warning. The installed SDK exposes async activation/deactivation starting at iOS 27; the app minimum remains iOS 26. A direct unconditional API change is therefore unavailable. On iOS 26, preserve a synchronous API path but execute it on a dedicated serial queue and await its completion without blocking MainActor. On iOS 27+, await the native async APIs.

Existing lifecycle issues that must be handled with the warning:

- Permission work is untracked; cancel during a permission request can be followed by a late listening start.
- Recognition and speech callbacks can arrive after cancel or a newer session starts.
- A stale activation/deactivation may race with another audio mode. Actor isolation alone is insufficient because actors are reentrant across `await`, and queued operations must retain order through continuation completion.
- Speech delegate callbacks currently deactivate audio synchronously off MainActor and set `.idle` without utterance identity checks.
- Setup failures after activation must stop partial IO and release only the matching session's ownership.

## Plan

**Goal:** eliminate main-thread synchronous AVAudioSession activation/deactivation on supported iOS runtimes and make listening/speaking transitions safe under cancellation, failure, and delayed callbacks.

**Ranked scope:**

1. Introduce one serialized audio-session coordinator/controller with explicit owner tokens for listen and speech modes.
2. On iOS 27+, use and await the async AVAudioSession activation/deactivation APIs. On iOS 26, run synchronous configuration/activation/deactivation on one dedicated serial queue and resume callers only after each operation completes.
3. Ensure an operation's queue/transition remains serialized through its completion; releasing an obsolete owner must not deactivate a session now owned by a newer mode.
4. Track a VoiceSession generation and permission task. Cancellation invalidates the generation immediately. Late permissions, activation completions, recognition callbacks, and speech callbacks must not start work or change state for a newer generation.
5. Keep engine/synth IO ordering explicit: await successful activation before starting; stop IO before releasing ownership; clean partial setup on every failure; do not report listening/speaking as active if activation fails.
6. Preserve on-device speech recognition policy, sealed evidence boundaries, manual-only trading safeguards, and current public call sites.

**Exclusions:** no trading behavior, credentials, persistence, networking, new package dependencies, or unrelated Coach/UI redesign. Do not raise the minimum OS solely to remove a warning.

## Design contract — proposed for challenge

- Audio ownership is represented by a unique token. The coordinator performs category changes, activation, and release serially. `release(token)` is a no-op unless that token still owns the active session.
- A serial transition chain spans each complete awaited native operation (including continuation return), not just the initial queue submission. No actor-reentrancy assumption may allow overlapping transitions. Ownership check/release is atomic relative to the next acquire; stale work may release only its own active lease. Category change, activate, and deactivate all use the same serialized controller.
- Listening and speech use separate modes/categories. Category changes happen only after prior mode IO has stopped and prior ownership has been released.
- `VoiceSession` owns a monotonically changing generation. Permission tasks, recognition handlers, pending activation, and utterances capture the generation. State updates and IO actions verify it is still current.
- A speech finish/cancel callback carries an immutable utterance identity to MainActor; only the currently owned utterance may set idle or release its audio token.
- The iOS 26 fallback uses a dedicated serial dispatch queue, never blocks MainActor, and still reports activation/deactivation failures. The iOS 27 path awaits system async APIs and propagates errors.
- Activation errors are visible in the existing `.error` state and never start the engine/synthesizer. Cleanup is idempotent and owner-scoped.
- Public `VoiceSession` methods and existing Coach behavior remain source-compatible.

## Design challenge result

Independent challenge: **PASS**. The iOS 26 serial queue is an appropriate app-side serialization path; callers must await without blocking MainActor. One required condition is explicit: ownership check/release must be atomic relative to the next acquire, the transition remains serialized through iOS 27 async completion, and all category/activation/deactivation operations use that same controller.

## Acceptance checklist

| ID | Owner | Isolated worktree | Allowed files | Prerequisite | Acceptance | Status |
|---|---|---|---|---|---|---|
| `VOICE-AUDIO-DEBATE` | Research + independent QA | Read-only | `VoiceSession.swift`, SDK header, logs | Existing warning evidence | Tradeoffs, OS availability, races, failure cases recorded | DONE |
| `VOICE-AUDIO-DESIGN` | Supervisor + independent challenger | Read-only | This report | Debate complete | Ownership/serialization/callback contract challenged; no unresolved race in accepted design | DONE — PASS with atomic lease condition |
| `VOICE-AUDIO-IMPL` | iOS lifecycle worker | `/private/tmp/blazeros-ios-test-host` isolated snapshot | `Sources/BlazerCore/VoiceCoach/VoiceSession.swift`; focused iPhone lifecycle test file; this report | Design PASS | Async iOS 27 path and non-main iOS 26 path; stale owner/callback guards; errors clean up safely; manual-only/on-device boundaries retained | DONE — focused 5/5; iOS 26 target build PASS |
| `VOICE-AUDIO-REVIEW` | Independent iOS QA | Read-only | Exact implementation diff and test logs | Implementation complete | Race and platform API audit; no unowned deactivation or stale state update | DONE — PASS after uncertain-owner recovery correction |
| `VOICE-AUDIO-INTEGRATE` | Supervisor | Primary checkout | `Sources/BlazerCore/VoiceCoach/VoiceSession.swift`, `iPhone/Tests/VoiceAudioSessionLifecycleTests.swift`, this report | Independent review PASS | Exact bytes, focused/full tests, iOS 26 target build, iOS 27 warning check, diff check | DONE — PASS; iOS 26 runtime not available |

## Independent implementation review — 2026-11-15

The first exact-diff review found one required correction: `releaseSerial` cleared ownership when deactivation failed, even though the system session could remain active, and VoiceSession cleanup surfaced an error but still allowed a later acquisition. The worker is updating the coordinator to preserve uncertain ownership and perform an explicit serialized deactivation recovery before accepting a later lease. Add an injected deactivation-failure regression before review can pass.

## Required tests

- iOS 27: activation awaited before engine/synth starts; IO stopped before deactivation; no main-thread AVAudioSession warning.
- iOS 26: synchronous operations execute on the dedicated queue; MainActor remains responsive; activation/category failure and deactivation failure are handled.
- Cancel while permissions are pending, then complete permission: no activation and no stale state change.
- Cancel while activation is pending and start another mode: stale completion cannot start IO or release the new mode's token.
- Recognition result/error and speech finish/cancel from an old generation/utterance cannot mutate or stop the current session.
- Engine start/recognition setup failure after activation releases the owned session; repeated cancel is safe; listening↔speech transitions preserve ordering.

## Preservation and safety

The primary checkout has extensive pre-existing dirty work. No reset, clean, stash, or broad copy is permitted. The implementation worker must work in the isolated snapshot above. Main supervisor owns exact-file integration after independent review. No commits or publication are included.

## Current status

- Prior actor-isolation and deprecated-window compile warnings are fixed.
- Hosted unit tests use `BlazerTestHost`; app/test package duplicate diagnostics are removed.
- The AVAudioSession main-thread hang-risk warning is fixed; see the integrated verification below.
- Remaining compiler/tool/runtime messages are listed with source and context below; app-group container notices come from tests under the intentionally unentitled helper host.


## Integration and verification — 2026-11-15

- Integrated the exact independently reviewed source/test bytes. SHA256: `VoiceSession.swift` `b71f0a933075e4ea3bf6bc01fe4788ab4d5793b3d0955f585d600be3763e28d9`; `VoiceAudioSessionLifecycleTests.swift` `40c3481910bfe56ee0145f03b2815747992ffa043a0ae39c07a64cbdf4fc01bf`.
- Independent exact-diff review initially caught deactivation failure clearing lease ownership. The corrected `.uncertain` state retries deactivation before any new lease; failed recovery keeps acquisition fail-closed. Independent re-review: **PASS**.
- Focused audio coordinator tests **5/5**, and the original expiry test passed on iOS 27.0. Combined focused run **6/6**; no `AVAudioSession Hang Risk` warning. The simulator still logs `SupportsInterruptionEndedAfterActivationError` as an unsupported property.
- iOS 26 deployment-target build using the iOS 27.2 SDK: **PASS**. No iOS 26 simulator runtime is installed, so iOS 26 runtime behavior is not verified.
- Primary full iPhone 17e run: unit tests **27/27**, UI tests **4/4**. Primary full Swift suite **620/620 across 16 suites**. Release Mac product build **PASS**. `git diff --check` **PASS**.
- Replaced deprecated `Text + Text` in `MiniCandleChart.ohlcField` with styled `HStack` and combined accessibility children; primary iOS build no longer emits that iOS 26 deprecation.
- Remaining messages: App Intents metadata extraction notices because the app has no App Intents dependency; simulator-only unsupported audio property; simulator system WebKit/WebCore duplicate-class diagnostic during UI automation; helper-host app-group container lookup notices (the helper intentionally has no production app-group entitlement; relevant tests pass); simulator VoiceDB fallback diagnostics. No app/test duplicate package classes or AVAudioSession hang-risk warning appear in the primary full run.

## Follow-up simulator verification — 2026-11-16

- After integrating the ORB lifecycle writer, the current primary tree passed the iPhone 17e V3 test plan: **27 unit + 4 UI tests**, result bundle reports **31 passed, 0 failed, 0 skipped**, with no runtime warnings (`/private/tmp/v3-primary-iphone-derived/Logs/Test/Test-BlazerOS-2026.11.16_11-01-45--0800.xcresult`).
- The build still emits only the known App Intents metadata extraction notice because the target has no `AppIntents.framework` dependency. The runtime warning list in the result bundle is empty.


## V3 user-report verification — 2026-11-16

- Final focused/full Swift logs contained no Swift compiler warnings. The Release simulator build and UI build emitted only Xcode’s App Intents metadata extraction skip because the app has no `AppIntents.framework` dependency.
- The UI simulator process printed the existing system `UIAccessibilityLoaderWebShared` duplicate-class diagnostic from WebKit/WebCore. This is a simulator runtime message; it is not an app source warning.
- The previously fixed actor-isolation, deprecated UIKit/Text composition, app/test package duplicate-class, and AVAudioSession hang-risk warnings did not regress. The exact run evidence is in `reports/V3_USER_REPORTED_POSITION_2026-11-16.md`.


## V3 entry-observation verification — 2026-11-16

- Integrated primary full Swift run: **653/653 across 17 suites**, with no Swift compiler warnings. Device-specific iPhone 17e simulator build succeeded. Its only `warning:` line is Xcode App Intents metadata extraction skipped because the app target has no `AppIntents.framework` dependency. No App Intents dependency was added solely to suppress this tool message.
- A generic simulator destination also emitted a simulator-placeholder missing OS-version diagnostic; using the installed iPhone 17e destination avoided that diagnostic. The targeted UI-test run exited 75 while saving its result log and reports zero tests, so there is no new runtime warning evidence from that attempt.
- The entry-observation changes introduced no AVAudioSession, deprecated API, duplicate package-class, or Swift compiler warning regression. Source warning cleanup remains verified; the remaining App Intents diagnostic is a build-tool notice for an unused feature.


## V3 shadow-outcome verification — 2026-11-16

- Primary full Swift **663/663 across 17 suites** and focused structural-outcome **18/18** produced no compiler warnings. iPhone 17e simulator build passed; its only `warning:` is Xcode App Intents metadata extraction skipped because `AppIntents.framework` is not linked. The app does not use App Intents, so no dependency was added solely to silence the processor.
- The focused Review UI test passed **1/1**. Xcode emitted its nil debugger-version lookup diagnostic during UI testing but the test completed successfully. The earlier result-log save failure did not recur. Generic simulator builds may still emit a placeholder missing-OS-metadata diagnostic; the device-specific destination avoids it.
- Existing actor-isolation, deprecated API/Text, package duplicate-class, and AVAudioSession hang-risk source warnings remain fixed.


## V3 user-reported position-close verification — 2026-11-16

- Primary focused close **6/6**, V3 domain **15/15**, and full Swift **671/671 across 17 suites** passed without Swift compiler warnings. Device-specific iPhone 17e simulator build succeeded.
- Earlier close-correction failures came from a simulator fixture that wrote its entry correction before its earlier close, causing the store to correctly reject the close. A new fixture revision writes the close against the original opening first; the correction UI flow now passes in the full test plan.
- Full iPhone 17e test plan: **33/33** (27 unit + 6 UI), including close correction; targeted close-correction UI **1/1**. Full Swift suite **671/671**, no compiler warnings. Xcode emits `Metadata extraction skipped, no AppIntents.framework dependency found` for `BlazerUITests`, which contains no App Intents implementation; `BlazerIntents` remains the app’s separate functional target. No unused framework was added. UI process logs still show the system WebKit/WebCore duplicate-class warning and an Xcode debugger-version lookup diagnostic; the test result bundle reports zero runtime warnings. Helper-host app-group lookup and VoiceDB fallback messages remain simulator/test-host diagnostics.
- Earlier actor-isolation, deprecated Text composition, package duplicate-class, and AVAudioSession hang-risk source warnings remain fixed.

## App Intents metadata warning probe — 2026-11-16

- Fresh, non-quiet iPhone 17e `build-for-testing` succeeded using a new derived-data directory and `ENABLE_APP_INTENTS_METADATA_GENERATION=NO` (`/tmp/v3-warning-optout-probe.log`). Xcode still ran `appintentsmetadataprocessor` and emitted `Metadata extraction skipped, no AppIntents.framework dependency found` for `BlazerActivity`, `BlazerTestHost`, `BlazerTests`, `BlazerOS`, and `BlazerUITests`. The setting did not suppress the task; it is not added to the project.
- The warning is emitted by Xcode’s metadata processor for targets without App Intents. No unused `AppIntents.framework` is linked just to silence it. Swift compiler warnings remain absent in the latest full Swift suite; simulator WebKit/WebCore and debugger messages are runtime/tool diagnostics, with zero xcresult runtime warnings in the full suite.

## 2026-11-16 focused Coach UI verification

- Primary focused Swift route/answer tests emitted no Swift compiler warnings. The accepted iPhone 17e simulator xcresult reported `runtimeWarnings: []` for the selected-insight/intent workflow.
- Xcode console still emitted its simulator debugger-version lookup diagnostic. Earlier simulator UI runs also printed the system WebKit/WebCore duplicate-class message. These runtime/tool diagnostics are distinct from source compiler warnings. The App Intents metadata extraction notice remains documented above; no dummy framework dependency was added.
