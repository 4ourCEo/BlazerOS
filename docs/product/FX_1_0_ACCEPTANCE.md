# BlazerOS FX 1.0 Acceptance Ledger

This checklist is the authoritative FX 1.0 progress record. It describes the reconciled source state at baseline commit `f76f9751a3d0d9ad895e24c040599452ea4abf01`; it does **not** assert installed-product acceptance. Update an item only with its test/runtime witness and exact commit/PR.

## Status vocabulary

- `NOT_STARTED` — no implementation/witness.
- `IN_PROGRESS` — work exists but acceptance is incomplete.
- `BLOCKED` — a named external, product, safety or dependency decision prevents progress.
- `VERIFIED` — stated test/runtime evidence exists for the exact recorded source; this alone is not owner acceptance.
- `ACCEPTED` — owner has accepted the requirement against its measurable criteria and recorded witness.

A test suite may verify a code property. Product/runtime requirements need the specified installed-app witness. A Gate is `ACCEPTED` only when all its required items are `ACCEPTED`.

## Gate G0 — Reconciled baseline

| ID | Status | Dependency / owner | Source and measurable acceptance | Witness / commit | Blocker |
|---|---|---|---|---|---|
| G0-01 Truthful vertical-slice audit | `VERIFIED` | none / GPT-6 High + read-only Luna audits | Trace source→context→strategy→plan→Mac→manual execution→reconciliation→journal→iPhone; distinguish code/tests from runtime evidence. | This baseline; source at `f76f975`; independent read-only audits 2026-11-13. | Owner review pending. |
| G0-02 One product contract | `IN_PROGRESS` | G0-01 / GPT-6 High; owner approves unresolved policies | `FX_1_0_CONTRACT.md` is authoritative; explicit boundaries for manual orders, experiment/live, time windows, Mac/iPhone authority. | This branch; owner approval not recorded. | Confirm scan schedule and app-closed behavior. |
| G0-03 PR/worktree reconciliation | `IN_PROGRESS` | G0-01 / GPT-6 High | Record current PR heads, check state, dependency and disposition; preserve dirty worktrees; do not merge feature branches without product-path reason. | GitHub snapshot 2026-11-13 and `git worktree list`; PR #29 merged at `f76f975`. | #24/#26/#27 checks green/open; #30/#31 checks running at snapshot; disposition/review still required. |

## Gate G1 — Live Mac decision workflow

| ID | Status | Dependency / owner | Source and measurable acceptance | Witness / commit | Blocker |
|---|---|---|---|---|---|
| G1-01 Installed Mac baseline | `VERIFIED` | G0 / GPT-6 High + owner device action | Signed/identified release app launches independently of OpenCode on the owner’s Mac; build identity is shown and captured. | Feature source `c437235` built Release; `scripts/bundle-mac-app.sh` created ad-hoc signed `dist/BlazerOS.app`; `codesign --verify --deep --strict` passed; `open -n` launched PID 30001 on this Mac, 2026-11-12. This is a local ad-hoc app launch, not a distribution-signed install or complete plan witness. | Owner acceptance and distribution signing/install evidence remain open. |
| G1-02 Authenticated fresh FX data | `IN_PROGRESS` | G1-01 / GPT-6 High; Luna review | EUR/USD and GBP/JPY Practice quotes and completed M1/M5 context reach the Mac model; source time, receipt time, age, spread, status and failure reason are visible; stale/invalid input fails closed. | OANDA client/source tests and PR #29 establish bounded authenticated research collection, not this app run. The lifecycle now consumes `MarketScanSnapshot` bid/ask and source time; absent timestamps fail closed. | No live app Practice scan witness; capture was outside the chosen user focus window. |
| G1-03 On-demand SCAN and scheduled monitoring | `IN_PROGRESS` | G1-02 / GPT-6 High | SCAN performs fresh requests/evaluation and is distinct from cached display. Demonstrate weekday 9:30 AM–4:00 PM `America/New_York`, configurable 30-minute warmup, app-window-closed monitoring while awake, duplicate suppression, stale handling, sleep/reconnect and relaunch recovery. | User selected this schedule/warmup and background continuation while Mac awake. On-demand SCAN source exists. No schedule/background monitor was added in this vertical slice; no runtime scan witness. | Scheduled/background monitor and runtime behavior remain unimplemented. |
| G1-04 Spot-FX strategy lifecycle | `IN_PROGRESS` | G1-02 / GPT-6 High; Luna strategy audit | A named/versioned spot strategy emits forming/actionable/rejected/expired/unavailable states; independent ORB plan cannot be silently substituted or promoted. | PR #33 source commit `c437235` wires the existing ORB decision from `performFXScan` into `SpotFXPracticeLifecycle`; five lifecycle tests and ORB tests pass. Legacy `ScanKernel`, HIGH/LOW and `DeskEntryGate` remain unchanged. Local app launch did not include a real scan. | Authenticated current Practice scan witness pending. |
| G1-05 Valid plan and risk | `BLOCKED` | G1-04 / GPT-6 High + owner risk-policy inputs | Actionable decision renders correct entry condition, side-specific bid/ask, stop, target, invalidation, instrument pip units, spread and approved sizing assumptions; reject malformed/over-risk plans. | PR #33 adds validation for strategy/plan identity, Practice environment, source/receipt freshness (5s), crossed quote, instrument pip scale, spread versus unchanged plan max, expiry, risk acceptance/units and hard cap. Tests include EUR/USD and GBP/JPY, boundaries, over-cap and expiry. Model intentionally passes no risk-sizing result; current lifecycle reports `risk_missing`, never ACTIONABLE. | Owner must define approved account balance/risk fraction, pip-value/conversion basis, margin/units constraints, and absolute USD hard cap. Do not invent inputs or present ORB's placeholder units as approved size. |
| G1-06 Native Mac state and alerts | `IN_PROGRESS` | G1-03–05 / GPT-6 High | Live UI displays current provenance/status and truthful reasons; alert only on valid lifecycle transition, suppress duplicate/stale alerts; foreground/background behavior is witnessed. | PR #33 adds distinct Practice plan panel with entry/stop/target, proposed units, state/reason, spread pips, not-order/fill warning and gated acknowledgment. Local Release app launches; no in-session quote-to-UI witness. No lifecycle-specific alerts added. | Need real Practice session scan and risk-policy resolution. |

## Gate G2 — Manual broker-assisted execution and records

| ID | Status | Dependency / owner | Source and measurable acceptance | Witness / commit | Blocker |
|---|---|---|---|---|---|
| G2-01 Manual execution handoff | `NOT_STARTED` | G1-05 / GPT-6 High + owner | User reviews and manually places an OANDA Practice order; UI documents that BlazerOS does not submit orders. Store plan separately from order/fill evidence. | Existing manual flow is fixed-expiry handoff, not spot FX; source audit only. | Spot-FX manual workflow absent. |
| G2-02 Read-only account reconciliation | `NOT_STARTED` | G2-01 / GPT-6 High + Luna broker audit | Authorized read-only OANDA access finds open/closed trades, correlates only with evidence, handles unmatched/ambiguous state, and cannot submit orders. | `OandaClient` at baseline covers market data; no account/trade/transaction reconciliation APIs. | Implement only after an acceptance-approved API/security boundary. |
| G2-03 Durable FX journal/recovery | `IN_PROGRESS` | G1-05 / GPT-6 High | Persist immutable plan identity, user action, broker IDs/fills when present, costs and outcomes; restart recovers state without inventing fills or final outcomes. | PR #33 appends immutable V3 plans and lifecycle events to `ResearchStore`; tests cover event roundtrip/idempotency/conflict/transition and model restores latest plan/event with historical quote explicitly marked refresh-required. Full app restart witness not captured. Manual acknowledgment is not execution evidence. | Capture persistence/relaunch in an in-session integrated runtime; broker IDs/fills remain unavailable. |

## Gate G3 — iPhone companion and release

| ID | Status | Dependency / owner | Source and measurable acceptance | Witness / commit | Blocker |
|---|---|---|---|---|---|
| G3-01 Authoritative Mac-to-iPhone state | `NOT_STARTED` | G1-06 / GPT-6 High + Luna iPhone audit | iPhone receives same decision ID/fingerprint, version, source time, freshness and lifecycle; stale/duplicate/tampered/out-of-order state is rejected; it does not present a competing local FX result as authoritative. | At baseline each device runs its own scan. Cloud sync is disabled in model and excludes live scans/quotes. | No Mac→iPhone transport/authority contract. |
| G3-02 Notification delivery | `NOT_STARTED` | G3-01 / GPT-6 High + owner device action | Demonstrate genuine transition notification with app foregrounded/backgrounded and document behavior when Mac sleeps/offline and iPhone is disconnected. | Local notification and Live Activity components exist; no remote Mac-decision delivery witness. | Delivery architecture and service policy unresolved. |
| G3-03 Installed iPhone companion recovery | `NOT_STARTED` | G3-01 / GPT-6 High + owner device action | Install exact companion build; verify state/history survives force quit/relaunch and unavailable transport is explicit. | Historical iPhone evidence concerns earlier legacy desk, not FX 1.0 authoritative companion. | Exact-build physical-device witness absent. |
| G3-04 Release declaration | `NOT_STARTED` | G1–G3 / GPT-6 High + owner | Exact signed artifacts, platform versions, source commit, known limitations and release approval recorded. | No FX 1.0 Mac/iPhone installed release bundle. | Prior product/release docs conflict; signing/deployment status must be reconfirmed. |

## First implementation slice

**G1-04 → G1-05 → G1-06:** introduce the smallest production spot-FX decision/plan seam that can consume already available Practice M1/M5 observations and display an explicitly experimental plan/rejection on Mac. Keep the current binary-options engine available only to its legacy paths; do not rewrite or promote it implicitly. Add one deterministic feed-to-plan-to-view acceptance test, then capture a real Mac Practice runtime witness. Do not prioritize M15/H1 collection, chart polish, cloud relay, or strategy expansion unless this chain demonstrates a specific need.

## Integration snapshot (2026-11-13)

| PR | State at snapshot | FX 1.0 disposition |
|---|---|---|
| #24 adapter role metadata | Open; both required CI checks SUCCESS; base current | Review whether it directly supports G1-04 strategy eligibility; integrate only with focused source review. |
| #25 structural replay | Merged | Preserve; development-only evidence. |
| #26 freshness/experiment attempts | Open; both required CI checks SUCCESS; base current | Integrate before relying on its freshness/attempt infrastructure; it does not close live freshness acceptance alone. |
| #27 bounded CI policy | Open; both required CI checks SUCCESS; base current | Governance support; review and integrate at the next safe integration boundary. |
| #28 entry-quote provenance | Merged | Preserve; better provenance, not fills. |
| #29 Practice runner | Merged at `f76f975` after isolated-build/archive hardening; required CI checks SUCCESS | Integrated acquisition capability; not a live Mac runtime witness. |
| #30 MTF collector | Open; CI IN_PROGRESS at snapshot; based on #29 | Defer for vertical slice unless strategy audit demonstrates timeframe dependency. Preserve branch/archive. |
| #31 Markets ORB research radar | Open; CI IN_PROGRESS at snapshot | Review for truthful research-only projection; not a replacement for the production decision-to-plan path. |
| #33 Practice plan lifecycle | Open; first CI run pending at snapshot; head `c437235` | Direct G1-04/05/06 and G2-03 implementation. Requires source review and live Practice/runtime witness; does not resolve owner risk configuration. |

PR check status is a point-in-time snapshot, not an ongoing watch. At the latest audit snapshot, #24/#26/#27 had new heads and checks queued/in progress after base advanced to `f76f975`; #30 was behind with its iPhone check still running; #31 was behind its base with its iPhone check still running. See GitHub before any merge; no loop is running.

The primary workspace at `/Users/thagreat/Desktop/Blazer/BlazerOS` is a highly modified and uncommitted `rc1/research-paper-trading` checkout at `2aa3399`. It contains relevant in-progress V3/ORB/adaptive source and simulator-acceptance artifacts, plus unrelated edits. No part of it was copied, reverted, reset or cleaned for this audit. Its internal-release report identifies a signed iPhone archive/IPA built from a dirty tree and simulator tests, explicitly says it was not installed on the owner’s iPhone, and is not a Mac runtime witness. Preserve and reconcile that worktree separately before selecting implementation commits.

## Vertical-slice update (2026-11-13)

PR #33 (`feature/fx-practice-plan-lifecycle-20261113`, commit `c437235`) is the first bounded implementation of the Practice lifecycle→Mac panel path. Verification on the isolated feature worktree: focused ORB/lifecycle tests 14 passed; full Swift suite 460 passed; Release `BlazerOS` build succeeded; ad-hoc app bundle signature verified and app launched on the Mac. System time at capture was Thursday 2026-11-12 5:14 PM Pacific, outside the owner's focus window, so no live scan was performed. No authenticated live quote/decision-to-view witness is claimed. The deterministic fixtures are labeled tests only.

The first production blocker is now explicit risk-policy input, not another strategy/replay feature: account balance, conversion/pip-value source, margin/units constraints and absolute USD cap have no owner-approved values. Until supplied and tested, the plan must stay `UNRESOLVED` (`risk_missing`); proposed ORB units are not an approved size. Broker verification remains blocked because no read-only trade/fill reconciliation API is integrated. Next acceptance action: owner supplies risk constraints (or explicitly authorizes a no-sizing, non-actionable Practice-only plan policy), then capture the in-session Practice scan through persisted Mac UI and relaunch. No background monitor, broker orders, iPhone sync or new alert infrastructure was added.
