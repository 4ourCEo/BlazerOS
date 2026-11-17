# Signed Mac Runtime Recovery Evidence

Date: 2026-11-15 (America/Los_Angeles)  
Market state: FX closed; no SCAN or order was submitted.

## Artifact identity

- App: `dist/BlazerOS-Mac-staged-20261115T082908Z-58913.app`
- Bundle ID: `com.blazer.BlazerOS`
- Owner signer pin: `F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819`
- `codesign --verify --deep --strict`: PASS

## Fresh-process recovery

1. Before relaunch, the signed staged app was running as PID 59724. The captured screen showed the native light Trade workspace, `OANDA LIVE · DISCONNECTED`, 120 candles labeled `Saved OANDA candles · stale`, a closed-market WAIT/withdrawal notice, and no broker orders.
2. The staged app was asked to quit by its exact bundle path. PID 59724 was confirmed absent.
3. The same staged bundle was reopened with `open -a`. It started as PID 65183 at 2026-11-15 01:26:04 PST. The process command path resolves inside the exact staged bundle.
4. Accessibility inspection of that path-bound app after launch again showed 120 saved stale candles, `WAIT / NO TRADE`, `FX closed — SKIP`, `risk_missing · units withheld`, and `No broker orders`. The post-relaunch screenshot independently shows the same restored candle window and closed-market notice.

At 2026-11-15 01:33 PST, a follow-up accessibility inspection of the same running staged bundle showed `OANDA LIVE · DISCONNECTED`, `Quote unavailable`, `WAIT / NO TRADE`, `FX closed — SKIP`, and the saved 120 candles still labeled stale. No scan was triggered and no credential prompt was opened; this is a closed-market status check only.

Screenshots:

- Before relaunch: `staged-app-closed-market.png`
- After relaunch: `staged-app-post-relaunch-closed-market.png`

## Limits

This verifies persistence display after a fresh process for saved candles and the closed-market decision/notice projection. It does not verify a fresh Live quote, open-market SCAN, scan notification behavior, Keychain authorization prompt count, or post-scan revalidation. The credentials sheet was not opened during this check; no secret was read. There was no broker order path invoked.

During app selection, an older `/Applications/BlazerOS.app` process was briefly opened for comparison; it was gracefully quit without changing its bundle or data. The signed staged app remained the acceptance target.
