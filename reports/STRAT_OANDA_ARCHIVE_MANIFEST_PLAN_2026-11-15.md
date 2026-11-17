# OANDA Practice Historical Archive Validation

**Task:** `STRAT-OANDA-ARCHIVE-MANIFEST`  
**Status:** Debate complete; plan and design drafted; independent design challenge pending.  
**Scope:** Research data integrity only. No candidate thresholds, trading decisions, app UI, broker orders, or strategy promotion.

## Debate — read-only findings

Two independent reviewers confirmed that the existing `ForwardTest` authentic replay reads only Legacy V1 policies plus ORB; it does not run the researched candidate lifecycles. The local archive is present at `~/Library/Application Support/BlazerOS/Research/oanda-proxy/historical-bid-ask`, containing 20 Practice-labeled OANDA JSON batches across EUR/USD and GBP/JPY M1/M5. It has roughly 11.6k unique M1 and 2.3k unique M5 timestamps per pair after exact-overlap removal, spanning approximately Nov 1–12, 2026. Batch metadata reports successful transport/HTTP 200; a local inspection found no malformed bid/ask OHLC rows and no conflicting duplicate timestamp payloads. This is limited history, not statistical edge evidence.

The archive also includes 42 additional bounded Practice batches and four short multiframe smoke batches under separate directories. Do not combine these scopes without explicit dataset selection. Existing overlapping requests contain many exact duplicate rows; M1 timelines contain gaps. Gaps must be reported, not automatically treated as corrupt, because FX weekends and session breaks exist. Exact grid completeness requires a versioned calendar/session contract. The current files use Foundation Codable `Date` encoding (seconds from the 2001 reference date); a validator must use Swift decoding or correctly apply that encoding, not interpret values as Unix timestamps.

**Counterpoint:** the replay already deduplicates some historical batches and can produce useful summaries. However it does not emit a complete, reusable integrity manifest; uniqueness alone cannot detect conflicting overlaps, batch identity issues, or missing completion/provenance fields. The bounded prerequisite is a read-only validator, not a new campaign evaluator.

## Plan

- **Goal:** establish deterministic, inspectable quality/provenance facts for one explicitly selected immutable archive before any research campaign consumes it.
- **Ranked scope:** (1) validate each batch envelope and candle row; (2) group by instrument/granularity; (3) identify identical duplicates, conflicting duplicate timestamps, ordering, and time gaps; (4) hash every source file and the canonical summary; (5) report coverage and limitations without inferring fills or performance.
- **Exclusions:** no repair, rewrite, deduplication-in-place, archive merging, OANDA network access, strategy evaluation, threshold selection, cost assumptions, or promotional claims. Do not silently treat missing timestamps as market closures.
- **Data selection:** default only the `oanda-proxy/historical-bid-ask` directory. Other Practice folders require a separate explicit run and remain separate datasets.
- **Completion:** the tool produces stable machine-readable JSON and a human-readable summary; fixture tests cover valid batches, malformed/incomplete rows, exact and conflicting duplicates, out-of-order candles, wrong instrument/granularity, failed transport, and gaps; actual local archive inventory is recorded as a read-only report. No source archive file is modified.

## Design

- The validator consumes already-decoded `OandaHistoricalBidAskBatch`-compatible JSON using a standard-library tool with no external package dependency.
- Output fields: schema/tool version, selected relative root, per-file SHA-256, source label inferred from path/name (the batch schema has no authenticated provider/environment field), request interval, transport/HTTP status, instrument/granularity, raw/unique/exact-duplicate/conflicting counts, candle-completion and bid/ask OHLC validation, chronology/grid alignment, first/last timestamp, and gap intervals.
- Duplicate timestamps are collapsible only in the *reported view* when all candle fields match exactly. Conflicting payloads invalidate the dataset. Source files remain untouched.
- Gaps are listed with elapsed time and missing expected grid count. They are informational until a strategy-specific versioned FX session calendar classifies them; no weekend or holiday inference is made by this task.
- Batch envelope is eligible only when its transport decodes as `ok`, HTTP status equals 200, `practiceOnlyRejected` is false, `requestedFrom` and `requestedTo` decode and are ordered, and every candle matches the batch instrument/granularity. For the selected M1/M5 series, times must be on the OANDA UTC grid and candle starts must lie between the grid floor of `requestedFrom` and the grid floor of `requestedTo`, inclusive. This allows the candle covering a fractional `from` time because the archived client explicitly sends `includeFirst=true`; this endpoint behavior is documented by OANDA. A candle outside those aligned endpoint bounds invalidates the batch. Filename text is reported as a label and is not trusted to override batch fields.
- Strict JSON parsing rejects `NaN`/infinity tokens, duplicate object keys, malformed date values, and trailing garbage. Foundation Codable `Date` numbers are Cocoa reference-date seconds (2001-01-01 UTC). Hash the exact file bytes once, then parse those same in-memory bytes; do not reread the file between validation and hashing. Reject symlinks that resolve outside the selected root.
- Invalid envelope, bad price ordering, crossed bid/ask, incomplete candle, malformed time, unexpected identity, or failed transport marks that batch invalid. The report still includes all discovered issues and hashes, but its dataset eligibility is false.
- Enumerate a sorted snapshot of regular `.json` paths at start; reject symlinks. Read each file once and compute its digest and validation from the same byte buffer. Files added after enumeration are outside that manifest. Hash the selected relative-path set separately. A manifest describes those exact read bytes, not a promise that the directory cannot change afterward.
- Output is sorted deterministically and contains no run-time creation timestamp. The canonical manifest digest is SHA-256 over UTF-8 JSON using sorted keys, compact separators, ASCII escaping, and no non-finite numbers; the digest field itself is omitted. Output values use integers, booleans, and normalized UTC timestamp strings (not binary floats) to keep canonicalization stable. Standard output is the default. Optional file output must refuse to overwrite an existing path.
- No account IDs, tokens, authorization headers, or credential sources are read or emitted.

## Independent design challenge

**Independent design challenge: PASS.** Two review rounds required strict envelope/JSON handling, same-bytes hashing, symlink containment, digest definition, correction of the provisional gap count from 53 to **55**, and handling the valid `includeFirst=true` candle that covers a fractional request boundary. The current contract includes these. OANDA's official instrument-candles endpoint defines `includeFirst` as including the candle covering the `from` time: https://developer.oanda.com/rest-live-v20/pricing-ep/ . Filename/path `oanda-practice` is only a local label because the batch has no provider/environment field. Final reviewer requested fixtures verify both request boundaries against the selected archive and pin path-set digest serialization.

## Checklist

| ID | Owner | Isolated worktree | Allowed files/actions | Prerequisites | Acceptance evidence | Verification | Status |
|---|---|---|---|---|---|---|---|
| STRAT-OANDA-ARCHIVE-DEBATE | Research + independent QA | Read-only | Source/report/archive metadata inspection | None | Debate, counterpoint, and limits recorded | Independent audit; no archive mutations | DONE |
| STRAT-OANDA-ARCHIVE-DESIGN | Supervisor + independent QA | Primary checkout | This report only | Debate complete; OANDA boundary behavior checked against official endpoint documentation | Typed deterministic input/output contract and safety boundaries | Independent design challenge accepted | ACCEPTED — independent PASS; verify from/to boundary fixtures and pin path-set digest serialization during implementation |
| STRAT-OANDA-ARCHIVE-VALIDATOR | Research owner + independent QA | `/private/tmp/blazeros-oanda-archive-validator` then primary integration | `scripts/validate_oanda_archive.py`, `scripts/tests/test_validate_oanda_archive.py` only | Independent design challenge PASS | Deterministic report; fail-closed invalidity; archive untouched | 14 fixture tests PASS; selected archive validation; `git diff --check`; independent final QA PASS | ACCEPTED / INTEGRATED |
| STRAT-OANDA-ARCHIVE-ROOT-REPORT | Supervisor | Primary checkout | `reports/research-data/oanda-proxy-historical-bid-ask-2026-11-15.json`, this plan, execution ledger | Validator accepted | Local selected archive inventory recorded with scope and limitations | Review manifest digest and generated counts; archive remains read-only | DONE |

## Provisional local archive observations

Read-only file inventory found 66 batch files across three separate directories. In the selected `oanda-proxy` scope: 20 files, each reports successful transport and HTTP 200; 26,296 raw M1 and 5,291 raw M5 rows across both instruments; exact deduplicated totals are 23,293 M1 and 4,682 M5 rows. No conflicting timestamps or malformed bid/ask OHLC rows were found by the provisional audit. It found **55** inter-candle gaps across the four instrument/timeframe series, which are not yet calendar-classified. Date range is 2026-11-01 through 2026-11-12 UTC. These provisional counts must be reproduced by the accepted validator before use in a campaign. `oanda-proxy` is the local directory label, not cryptographic provider attestation.

## Implementation review — 2026-11-15

Initial implementation review found `Decimal.normalize()` could round distinct numeric prices beyond 28 significant digits into the same value. This was fixed using exact sign/coefficient/exponent canonicalization without context rounding, with a 32-significant-digit duplicate-conflict regression and signed-zero coverage. Independent QA re-review: **PASS**. Primary `python3 -m unittest discover -s scripts/tests -p 'test_validate_oanda_archive.py' -v`: **14/14 passed**; `git diff --check`: PASS.

Selected archive report is stored at `reports/research-data/oanda-proxy-historical-bid-ask-2026-11-15.json`; SHA-256: `81db0a0f0433dd255cbcf6ba3b2277247a5661c72429f655298599e0c686a7cc`. It reports 20/20 structurally valid batches, 23,293 unique rows, 3,612 exact duplicate rows, zero conflicting duplicate timestamps, and 55 unclassified grid gaps across EUR/USD and GBP/JPY M1/M5 from Nov 1–12 UTC. Archive bytes were not modified. `archiveIntegrityValid=true` is structural validation only; campaign readiness remains `NOT_ASSESSED_BY_ARCHIVE_VALIDATOR`.
