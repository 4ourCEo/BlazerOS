# Reliability release — local iPhone execution desk

Scope: one dependable iPhone app. OANDA (FX) and Binance/Kraken (crypto) data are fetched
directly by the phone; the pinned scan engine runs on-device; history is local. No Mac,
server, CloudKit, or broker automation is required. Broker execution remains manual.

## What changed

### Execution state

- `DeskEntryGate` is the single entry gate. It refuses stale signals, stale quotes,
  cross-pair quotes, historical scans, vetoed commits, and a second concurrent position.
- `pickedSignal` no longer falls back to `bag[0]`. If the JavaScript picker declines every
  candidate, the desk stays `WAIT`.
- An active manual entry owns its pair. Quote refresh uses the entry's own pair, not the
  browsing pair, and keeps updating while the user browses or switches screens.
- The entry's recovery record is written **before** the desk treats it as tracked.
- Market switching is disabled while an entry or settlement is in flight.
- `DeskFrame.isActionable` (not a positive timer) drives the TAP state. A stale feed or a
  veto shows `WAIT` with no rail.

### Scan identity and measurement

- `ScanInputSnapshot` is the storage identity: pair, M1, M5, bid/ask/spread, expiry,
  engine identity, and policy. The 4-byte hash remains a display label only.
- Snapshots persist M5 bars and quote/spread inputs, so a saved decision is reproducible.
- The journal records the full identity; the ledger writes the engine actually used
  (including the crypto engine identity, not the pinned FX SHA).
- Synthetic research remains under `Application Support/BlazerOS/Research/synthetic`;
  OANDA proxy research stays under `.../oanda-proxy`. Neither writes the desk ledger.
- Confirmed performance counts only `venue-confirmed` rows. Reference observations and
  synthetic runs are reported separately and cannot promote a pair. The Journal header now
  reads confirmed-only counts; `OutcomeStats.tally` remains available for full-history audits.
- Engine score is documented as side-neutral conviction (`max(directionScore, 100-directionScore)`),
  not a win probability. Crypto conviction is passed as 0…100, never as a 0…1 fraction.

### Crypto execution

- `CryptoDeskSignal` populates `asOfMs`, ATR features, quote/spread, and a 0…100 score.
- The documented crypto ceilings are now enforced: `CTAssets.minConviction`,
  `maxSpreadPips`, and `maxATRPips`.
- A Kraken fallback with a synthetic spread is labelled `kraken-synthetic-spread`, cannot
  arm, and does not paint LIVE.
- Crypto feed health uses `CryptoFeedHealth`; a failed poll can no longer leave a stale
  LIVE badge on screen.

### Recovery and persistence

- One canonical ledger (`LedgerStore`); the legacy `LedgerFile` duplicate implementation is
  removed.
- Pre-v3 ledgers are backed up once (`scan_ledger.csv.pre-v3.bak`) before header upgrade.
- A legacy 9-column row's `theirPrice` is read as an entry price, never as a payout.
- Malformed ledger lines are counted and surfaced; the original file is not rewritten.
- Pending settlements with corrupt lines are quarantined to
  `pending_settlements.corrupt.jsonl`; valid records still reconcile.
- Journal read-modify-write operations are serialized inside `PersistenceCoordinator`, so an
  interleaved settlement cannot save a stale journal array.
- An unreadable strike-position store is moved aside (`strike_positions.json.corrupt-*`)
  rather than silently overwritten. Position creation and its opening event are one write.
- Restored entries expire correctly and keep their original arm ID, full identity, and
  complete scan input.

### iPhone surfaces

- Widgets render a saved TAP only inside the 8-second beam; afterwards the row reads
  `HISTORICAL`. The timeline refreshes at beam close.
- Live Activities use `context.isStale` and the expiry time; expired activities show
  `EXPIRED · CONFIRM THE VENUE RESULT` and never actionable TAP wording.
- Live Activity recovery scans `Activity.activities`, so a force-quit cannot orphan an
  activity that only existed in memory.
- Siri's pending-scan flag is consumed on foreground activation even when the Keychain
  session is already loaded, and is ignored while an entry or settlement is active.
- The Explore Demo desk suppresses the missing-credential cover without pretending a
  Keychain session exists.

## Verification performed

- `swift build`
- `swift test` — 122 tests
- `swift run -c release Parity` — 43 checks
- `swift run Persist` — 59 checks
- `xcodebuild ... -scheme BlazerOS test` on iPhone 16 simulator — passed, including
  `ExecutionFlowTests` (armed entry, pair-switch refusal, stale/historical refusal, and
  relaunch restore) and the all-tabs canvas test
- Widget, Live Activity, and Intents schemes build

## Remaining gate (physical device)

These are simulator-independent and require the actual phone:

1. OANDA credentials present; scan FX and confirm a fresh TAP HIGH and TAP LOW.
2. Switch pairs and markets while an entry is active; the entry's price and countdown must
   not change identity or pair.
3. Open Pocket Option (app switch), return after 60s/3m/5m, confirm one venue result.
4. Force quit after entry, relaunch, and confirm the position and its expiry state restore.
5. Enable Airplane Mode during an armed beam; entry must be refused and TAP must disappear.
6. Deny notification/Live Activity permission and confirm the desk still functions.
7. Confirm the widget shows `HISTORICAL` after the beam, and the Live Activity shows
   `EXPIRED` after the horizon without a foreground update.
8. Repeat Siri "Scan with Blazer" while the app is already open.
