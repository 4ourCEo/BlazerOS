# Scan research implementation

Implemented following the October 2 design debate. The original analysis remains a historical audit of the previous engine and recorded data.

## Shipped engineering changes

- Preserved the original engine resource with its original SHA-1 as an explicit research control. Updated the shared current-engine pin.
- Separated signed direction score, symmetric conviction, and directional strength. Neither conviction nor strength is presented as a winning probability. Desk and telemetry no longer invert an already symmetric LOW conviction.
- Made freshness an eligibility gate before ranking; comparable fresh signals rank by conviction rather than tiny timestamp differences. Corrected flat RSI and ambiguous two-sided sweep handling, gold units, and malformed-input failures.
- Added optional continuation, range-reversal and regime-router policies in the single JavaScript engine. They use separate M1/M5 ATR, slope, directional efficiency, spread/ATR, wick/reclaim quality, trigger age, chase distance, and pre-trigger levels. Thresholds are registered in the versioned engine artifact; they have not been optimized against the existing ledger.
- Added one shared mechanical entry-quality contract for desk and research. The frozen scan strike remains unchanged; the accepted trade records the current verified entry price separately. Failed refreshes, stale setups, wide spreads, and excessive displacement block entry.
- Bounded OANDA expiry observation timing. Missing, old or delayed prints remain unresolved; equality is TIE in research. The desk offers manual reconciliation for unresolved/tied expiry and retains state after failed saves. It blocks new scans and pair changes while a trade/outcome is pending, and blocks entry if the scan was not archived.
- Retained legacy ledger CSV compatibility while adding label source, actual horizon, entry time, observed expiry timestamp, and durable arm ID. CloudKit preserves those outcome metadata fields without transporting research observations or quote feeds. Unsupported $10 stake fabrication was removed.
- Replaced the forward tester's mixed simulation/execution-ledger workflow with a local research runner. Candidate inputs and vetoes are persisted before accepted research entries. A separate quote-observation task records all three horizons; relaunch restores pending events and explicitly marks missed observation windows unresolved. Capture, observer and archive errors are surfaced.
- Added offline replay and deterministic synthetic exercise modes with correct M5 aggregation. No credential failure triggers an implicit simulation. Statistics group by source, engine hash and policy version and disclose assumed payout and independence limits.
- Removed unsupported fixed peak-hour win-rate claims from coaching, prime-window cards, telemetry and notification content. Local unknown/proxy outcomes cannot produce a PROVEN EDGE badge. Corrected the displayed morning schedule to 05:00–10:00 PT and removed fixed UTC equivalences.

## Research isolation

Default roots:

```
~/Library/Application Support/BlazerOS/Research/oanda-proxy
~/Library/Application Support/BlazerOS/Research/synthetic
```

Each candidate has an independent UUID, full SHA-256 input digest, both completed-bar timeframes, policy/engine versions, observed quote time, and entry acceptance/veto. Separate outcomes are keyed by event ID and horizon. Millisecond timestamps survive relaunch. Research documents are not a CloudKit record type and are never read by `LedgerStatsEngine`.

The research expiry label is the first observed OANDA midpoint print at or after target expiry, within two seconds, received within five seconds. This explicitly bounded proxy is not the venue's exact settlement. The regular broker rate limiter can still cause unresolved observations, which are retained and counted rather than converted to losses. The runner places no trades.

## Rollout

The repaired baseline is the desk default. Use `ForwardTest --all-policies --prime-only --continuous` to collect prospective control/baseline/challenger comparisons. Start and monitor this study explicitly; development verification did not start a live study, install a daemon or read Keychain credentials.

The archived control is research-only; it is not a selectable live desk strategy. Contract repairs intentionally alter LOW score semantics and selection, and gold and ambiguous-sweep behavior. The original golden fixture still produces WAIT, conviction 68, and the same fingerprint/evidence.

Rebuild both shipping clients against the updated package and bundled script. A separately bundled old Mac script/pin must be updated before deployment; no external client or running service was changed by this workspace edit.

## Remaining research work

These are deliberately not promoted without data: probability calibration; an integrated currency-specific news calendar; session-specific trained thresholds; exact venue outcome reconciliation; and walk-forward/day-block statistical promotion tooling. The research archive provides the required inputs for that work. No prospective win-rate improvement has yet been established.

The phone's unresolved outcome survives as in-memory retry state while the app is running; a durable phone active-trade recovery mechanism is not introduced. The research runner's pending events and horizon outcomes do survive relaunch. Archived historical phone journals still use legacy display fingerprints and cannot be fully reconstructed into the new research schema.
