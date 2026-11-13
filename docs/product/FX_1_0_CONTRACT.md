# BlazerOS FX 1.0 Product Contract

**Status:** owner-directed working contract; runtime acceptance remains open.
**Baseline commit:** `f76f9751a3d0d9ad895e24c040599452ea4abf01` (current `main` as of 2026-11-13).
**Purpose:** the single product-direction source for FX 1.0. The older Pocket Option and fixed-expiry documents describe legacy behavior or research unless explicitly linked below; they do not silently redefine this product.

## Product goal

BlazerOS FX 1.0 is a **Mac-first hybrid forex trading-intelligence product**. It gathers authentic market observations, applies a supported and explicitly identified strategy, and presents a concise, traceable decision and risk plan for a person to review and execute manually. It helps a trader make a decision; it does not promise an edge or trade autonomously.

- **Primary workstation:** native macOS app; one authoritative local decision/runtime owner for v1.
- **Companion:** iPhone surfaces authoritative Mac-produced decisions, plans, status and history. It must not silently compete by presenting an independent scan as the Mac decision.
- **Market:** spot forex. Initial instruments: EUR/USD and GBP/JPY.
- **Initial data/broker boundary:** OANDA Practice for market data and later read-only account reconciliation. Broker orders remain manually submitted by the user.
- **Proving strategy:** ORB is a vertical-slice candidate, not a permanent selection and not a proven strategy. The live strategy is not accepted until a versioned spot-FX strategy produces the plan shown to the user.
- **Research:** offline/prospective evidence is separate from live decisions. Research cannot silently tune or promote production rules. Options, TradingView, tastyfx, public/live-capital claims and autonomous execution are outside FX 1.0.

## Required user journey

1. Launch the Mac app without OpenCode; see accurate connection, session, source and freshness state.
2. During an owner-configured forex monitoring window, observe eligible markets; the SCAN action performs a new, attributable assessment rather than replaying cached state.
3. See a supported lifecycle (`FORMING`, `ACTIONABLE`, `REJECTED`, `EXPIRED`, or `UNAVAILABLE`) and one clear `BUY`, `SELL`, `WAIT`, or `NO TRADE` presentation. A directional opinion alone is not an actionable trade.
4. For an actionable plan, review instrument, direction, entry trigger/condition, current bid/ask and source time, spread, stop, target, invalidation, sizing inputs/assumptions, and evidence/strategy status.
5. Place any order manually in an approved broker interface. Keep proposed plan, user intent, broker order, broker fill and position as distinct records.
6. Where authorized read-only broker access exists, reconcile broker-confirmed trades and outcomes. Otherwise label user-reported execution/outcomes accurately. Preserve unknown or ambiguous states.
7. Persist decision and lifecycle provenance durably. The iPhone receives the same authoritative decision identity and reports delivery/freshness honestly.

## Runtime and session contract

- Forex trading hours are not the NYSE cash-equity session. A New York-focused monitoring window is an **app policy**, not a declaration that forex opens at 9:30 AM ET.
- A candidate schedule is weekdays 9:30 AM–4:00 PM `America/New_York` (06:30–13:00 Pacific, with DST handled by the named zone). It is **not accepted yet**. The owner must decide whether this or an overlap-focused window is intended, and whether holidays/early closes affect scanning.
- An authenticated, fresh-data scan is on demand in the initial vertical slice. Automatic recurring scans, app-closed-but-Mac-awake monitoring, sleep/reboot recovery, and alerts are distinct requirements and must be demonstrated before they are claimed.
- No cloud relay is presumed. If alerts must arrive while Mac is off/asleep or when the iPhone is disconnected from the Mac, that is a separate availability/service requirement and needs an explicit owner decision.
- Stale, incomplete, wrong-instrument, future-dated or invalidly ordered data cannot yield an actionable decision. Reconnect and relaunch must not resurrect stale plans.

## Decision and execution boundaries

- BUY/SELL require a versioned strategy lifecycle and complete valid spot-FX plan; `WAIT`/`NO TRADE` are first-class results with specific reasons.
- Market context, signal, trade plan, manual execution, broker-confirmed execution and outcome are separate layers with stable identities and source/time provenance.
- Stops/targets use instrument-correct price units. Pip size, spread and sizing must be explicitly normalized and tested; do not alter historical/production thresholds without owner authorization.
- OANDA Practice quote/candle data does not prove executable fills. No fabricated fills, inferred broker outcomes, automatic orders, strategy promotion, or profitability claims.
- An experimental or Practice signal is visibly labeled experimental/Practice-only until a distinct evidence gate qualifies it.

## Authority and change control

This contract supersedes contradictory descriptions of the **FX 1.0 target**, not legacy implementations or historical evidence. Preserve legacy binaries/options work as quarantined or research-only until consumers and migration are audited. Contract changes require an explicit owner decision recorded here; implementation agents cannot redefine product scope by merging a branch.

The linked [acceptance checklist](FX_1_0_ACCEPTANCE.md) is the only FX 1.0 completion ledger. Tests, PR count, research volume and simulator screenshots are not installed end-to-end acceptance by themselves.
