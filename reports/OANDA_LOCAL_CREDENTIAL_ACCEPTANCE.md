# OANDA Practice local credential acceptance

## Contract

The native macOS client and the explicitly authorized `run-forwardtest-practice.sh`
collector resolve Practice credentials from
`~/Library/Application Support/BlazerOS/credentials/practice.json`. The JSON
contract is exactly `{"OANDA_API_TOKEN":"…","OANDA_ACCOUNT_ID":"…","OANDA_ENV":"practice"}`.
Keep the containing directories owner-only (`0700`) and the regular file owner-only
(`0600`). The credential must never be copied into the repository, shell environment,
build settings, test fixtures, logs, or screenshots. `OANDA_ENV` may only be
`practice` for the research launcher. The client remains read-only; no order
operation is part of this credential path.

## Durable acceptance test (run on the owner’s Mac)

1. Check only presence/type/owner/modes (never `cat`, `jq`, or print the JSON):
   `stat -f '%HT %Sp uid=%u links=%l' "$HOME/Library/Application Support/BlazerOS/credentials/practice.json"`
2. Build BlazerOS with the normal local app build. Do not inject credentials into
   the build process.
3. Launch the installed app. Confirm Practice account identity and a successful
   read-only candle request in the UI/diagnostic; confirm no order request occurred.
4. Quit and relaunch the app. Confirm it reconnects without a Keychain prompt or
   credential entry. Repeat after a rebuild/reinstall and signing change.
5. Run the authorized collector through `scripts/run-forwardtest-practice.sh` and
   confirm its Practice-only diagnostic/candle result. Do not run it for unrelated
   research workers.

## Diagnostic procedure

If acceptance fails, record only the stage and sanitized HTTP status: file absent,
unsafe permissions/type/owner, malformed Practice config, unauthorized token,
account mismatch, environment mismatch, or unavailable candle data. Never include
the token/account file payload. Recheck Practice (not Live), owner UID, mode `0700`
on the BlazerOS and credentials directories, mode `0600` on the regular file, and
no symlinks/hardlinks. Rebuild and repeat launch/relaunch before changing credential
stores. Do not regenerate the token without evidence that the current token is
invalid. Reopen this issue only with new sanitized evidence showing the accepted
path fails.

## Verification status

The existing credential file was present as a regular owner-owned `0600` file with
one link. Its contents were not read (only its JSON key names/types were inspected
to match the existing schema). The BlazerOS parent directory was changed to
owner-only `0700` to satisfy the contract. A production ForwardTest build and the
authorized read-only adaptive Practice diagnostic completed successfully against
OANDA and returned fresh market data. Installed GUI app account identity/relaunch
acceptance remains to be performed on the owner’s Mac; this collector result does
not claim those GUI lifecycle checks passed.
