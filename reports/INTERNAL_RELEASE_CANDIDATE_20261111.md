# BlazerOS Internal Release Candidate

Status: **INTERNAL BUILD VERIFIED**  
Generated: 2026-11-11  
Source HEAD: `2aa339958c906ca48647cd638cd1ae07996e01e5`  
Dirty-tree status SHA-256: `52a3a899daf66728d62a2e24ba685fa0dbb4e6298d7f7d648490696ebb97dee7`

## Artifacts

- Archive: `iPhone/build/InternalRC-20261111/BlazerOS.xcarchive`
- IPA: `iPhone/build/InternalRC-20261111/Export/BlazerOS.ipa`
- IPA SHA-256: `6f80ef0195daf94044f4e3c998545391c438aa5a9aa27f1cb77edb5c38a465ed`
- Bundle: `com.blazer.os`
- Version/build: `2.0.0 (1)`
- In-app build identity: `rc-20261111-2aa3399-dirty`
- Team: `8GZ3352QQB`
- Signing identity: Apple Development certificate `A2N63PR6N6`
- Production engine pin: verified by the Swift regression suite

## Reproduction

```sh
xcodebuild archive \
  -project iPhone/BlazerOS.xcodeproj \
  -scheme BlazerOS \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath iPhone/build/InternalRC-20261111/BlazerOS.xcarchive \
  -allowProvisioningUpdates \
  MARKETING_VERSION=2.0.0 \
  CURRENT_PROJECT_VERSION=1 \
  BLAZER_BUILD_ID=rc-20261111-2aa3399-dirty

xcodebuild -exportArchive \
  -archivePath iPhone/build/InternalRC-20261111/BlazerOS.xcarchive \
-exportOptionsPlist iPhone/exportOptions.plist \
-exportOptionsPlist iPhone/exportOptions-internal.plist \
  -exportPath iPhone/build/InternalRC-20261111/Export \
  -allowProvisioningUpdates
```

The internal export options are versioned at
`iPhone/exportOptions-internal.plist`; no production or App Store export was
attempted.

## Signing verification

The app, Widget extension, and Live Activity extension all passed
`codesign --verify --deep --strict`. Each has an embedded provisioning profile,
team `8GZ3352QQB`, its expected bundle identifier, and
`group.com.blazer.os`. The candidate was not installed on the personal iPhone.

## Acceptance evidence

- Swift regression: **427 tests passed in 5 suites**.
- Simulator UI: **3 tests passed, 0 failures**.
- Adaptive snapshot evaluation: **11 focused tests passed**.
- Final simulator acceptance after CLI/signing work: **4 tests passed, 0
  failures**.
- Screenshot: `reports/simulator-acceptance-20261111/readiness-4/2D8134E2-EC16-4D17-A32A-609454130C90.png`.

## OANDA execution-context finding

The native app stores OANDA values under the existing Keychain service
`com.blazer.os.oanda`. Metadata lookup finds the token/account entries, but
noninteractive secret retrieval blocks on Keychain authorization. The CLI now
refuses to touch that access-controlled secret path and reports
`CLI_CREDENTIAL_CONTEXT_MISSING`; bounded CLI runs require approved
`OANDA_API_TOKEN`, `OANDA_ACCOUNT_ID`, and optional `OANDA_ENV=practice`
environment injection. No token was printed, persisted, or sent by this run.

Authentic Practice observation and latency remain **OWNER ACTION REQUIRED**:
provide the approved secure environment to the bounded CLI or authorize an
interactive native-app scan, then run the read-only adaptive diagnostic.

Environment isolation was verified without a broker request: an explicitly
configured `OANDA_ENV=live` diagnostic terminates as `LIVE_REJECTED` before
`AdaptiveMarketRehearsal.runBounded` is called.

## Protection and rollback

- Existing installed `com.blazer.os` application and App Group data were not
  uninstalled, replaced, or modified.
- Rollback is to retain the existing installed app and discard this separate
  archive/IPA; no migration was applied.
