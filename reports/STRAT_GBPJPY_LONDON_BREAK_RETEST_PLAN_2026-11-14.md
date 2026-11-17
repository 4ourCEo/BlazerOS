# GBP/JPY London Breakout + Retest Candidate A

**Task:** `STRAT-GBPJPY-LONDON-BREAK-RETEST`  
**Owner:** Strategy evaluator worker; supervisor integrates  
**Status:** DONE — integrated after independent implementation review  
**Authority:** `reports/GBPJPY_STRATEGY_VALIDATION_PRD_2026-11-10.md`, section 4, Candidate A  
**Independent challenge:** `/root/london_break_retest_challenge`, PASS with required configuration and research-only boundary

## Debate outcome

The PRD establishes the family mechanics: build a configured London opening range from completed M1 bars; require a completed close outside the range; require a retest within a bounded number of bars; enter only when that retest holds in the breakout direction; place the structural stop beyond the range boundary with a configured volatility buffer; set a configured fixed-R target. It does not supply validated threshold values or define one volatility estimator. The evaluator must require all such values and must not inherit New York ORB defaults.

The independent reviewer challenged causal timing, DST/session identity, missing and duplicate bars, quote authority, M3/M5 aggregation, and the difference between a research plan and an executed trade. This slice is M1-only; derived decision bars, sizing, broker execution, notifications, and Live selector integration are excluded.

## Design contract

- Add an independent `GBPJPYLondonBreakRetestV1` evaluator with its own versioned required configuration, typed result state/reason codes, source bar IDs, quote source/time, and canonical configuration/input digests.
- Accept completed M1 OHLC bars, an explicit London session interval resolved to absolute instants, a versioned calendar digest, a fresh bid/ask quote, provenance, and `asOf`.
- Require configured range duration, min/max range width, minimum breakout distance, retest tolerance, maximum retest bars, ATR period and buffer multiple, reward multiple, spread/quote-age/setup-age caps, and re-arm/cooldown policy. Reject incomplete or invalid configuration; provide no production default profile.
- Freeze the volatility algorithm explicitly as a required, versioned configuration value. Candidate A does not choose between ATR smoothing methods; the selected implementation method must be named and unsupported values rejected.
- Require unique, ordered, contiguous, complete M1 source bars on the configured grid. A breakout is a completed close beyond the sealed range plus the configured distance. A valid retest must occur within the configured number of bars, touch the boundary tolerance, and close on the breakout side. No extra confirmation candle is added.
- Require the quote to be valid, within configured freshness/spread limits, and strictly newer than the retest-bar close. Preserve bid/ask direction in the entry reference. Derive stop/target from the configured boundary/ATR/fixed-R rules; never calculate units or imply a fill.
- Keep the implementation research-only and disconnected from Live selection, notifications, and broker orders. Do not claim edge or profitability.

## Acceptance checklist

1. Worker changes only `Sources/BlazerCore/Research/GBPJPYLondonBreakRetestV1.swift` and `Tests/BlazerCoreTests/GBPJPYLondonBreakRetestV1Tests.swift` in an isolated worktree; no package/dependency or UI edits.
2. Tests cover long/short success, range not sealed, narrow/wide range, breakout distance, retest touch/close direction including over-tolerance wick with failed reclaim, retest timeout, exclusive session-close expiry, London timezone/DST absolute interval handling, non-contiguous/duplicate/malformed/future bars, quote stale/spread/ordering/provenance rejection, required-config rejection, explicit volatility-method selection, stop/target ordering, deterministic replay/digests, and distinct digests for invalid non-finite values.
3. Independent review verifies no lookahead, no implicit threshold defaults, correct quote side and cost units, and no Live/order call sites.
4. Integrate only after focused tests and independent review pass; run full `swift test`, release Mac target build, and whitespace checks. Update the execution ledger with exact evidence.

## Explicit unresolved evidence

This evaluator does not choose parameter values or claim a validated edge. Candidate profile selection, matched cost-adjusted chronological replay, holdout analysis, and any strategy promotion are later tasks. The missing STRIKE master PRD remains a separate blocker for the distinct Breakout Acceptance family.

## Independent implementation review correction

The first implementation review's two integrity findings were corrected: ATR method is now required/versioned and non-finite input values produce distinct canonical digests. The second review confirmed those fixes and found two lifecycle issues: session close must be exclusive, and a close back inside the range must terminally fail a retest even when the wick exceeds touch tolerance. Both were corrected and covered by regression tests. Final independent review passed. Root verification: focused suite 12/12, full suite 555/555 across 15 suites, release `BlazerOSMac` target build successful. The candidate remains research-only with no validated profile or edge claim.
