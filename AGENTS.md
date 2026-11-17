# BlazerOS multi-agent delivery rule

This rule applies to any substantial BlazerOS change that spans multiple files, targets, or agents; adds a third-party dependency; changes trading decisions, credentials, persistence, or app lifecycle; or needs independent review.

## Required sequence

The supervisor must run these phases in order and record the outcome in the task's durable report before moving to the next phase:

1. **Debate** — Assign bounded, read-only reviews to the relevant roles. Ask for evidence, tradeoffs, counterarguments, and failure cases. No code or dependency changes during this phase.
2. **Plan** — The main agent resolves the debate into one goal, ranked scope, explicit exclusions, dependencies, preservation boundaries, and measurable completion conditions. Record unresolved questions as blockers instead of silently guessing.
3. **Design** — Define the data/API contract, target/platform ownership, user-visible behavior, error and recovery paths, security boundaries, accessibility, and performance expectations. Have an independent role challenge the design before implementation.
4. **Checklist** — The main agent creates the durable task checklist. Every task must have a unique ID, one owner, one isolated worktree, allowed files, prerequisites, acceptance evidence, verification steps, and a status. The main agent assigns tasks from this checklist; workers must not create competing implementations or claim unassigned scope.
5. **Delegate and execute** — The supervisor assigns ready tasks to workers in their isolated worktrees. Workers report changed files, verification output, commit SHA, and blockers. A worker may continue only to the next task explicitly assigned by the supervisor.
6. **Review and integrate** — The independent reviewer checks the evidence and diff. The main agent alone owns integration, conflict resolution, and final acceptance. Never merge or replace code merely because a worker reports completion.
7. **Loop** — After integration, update the durable queue and ledger, then return to Debate for any materially new scope. Repeat Plan → Design → Checklist before starting that scope.

## Ownership and safety

- Keep the primary checkout's pre-existing dirty files, staged state, credentials, and user work intact. Do not reset, clean, stash, overwrite, or prune worktrees as a shortcut.
- Keep macOS and iOS application entry points, UI, packaging, and platform-only behavior separate. Shared code may change only when the task explicitly names both consumers and acceptance covers both.
- Keep OANDA credentials in the user's existing Keychain flow. Never print, copy, commit, or include credentials, account identifiers, authorization headers, or credential-bearing URLs in agent prompts, examples, logs, or test fixtures.
- Keep all manual-execution and Practice-only safeguards. Research or visualization work cannot create broker orders or imply that a displayed plan is an executed trade.
- External packages must be reviewed from primary sources for exact revision, license, platform/toolchain support, maintenance, transitive dependencies, and security impact before they enter an application target. Prefer a disposable spike over modifying a shared target.
- Stop and report a blocker if a task needs access, risk limits, destructive cleanup, external publication, or an unresolved product decision. Do not work around the blocker by broadening permissions or inventing requirements.
- Tests and checks must be tied to checklist acceptance. Report what ran and what did not; never claim verification without output or other direct evidence.
