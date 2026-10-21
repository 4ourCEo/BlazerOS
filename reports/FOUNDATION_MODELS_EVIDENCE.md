# Foundation Models evidence

## What is integrated

- `DeskAssistant` (BlazerCore) is the only model entry point. It checks `SystemLanguageModel`
  availability, serializes requests, applies per-feature timeouts, supports cancellation, and
  returns a deterministic fallback labelled `Basic explanation`.
- Guided generation schemas: scan explanation, coach answer, journal draft, session debrief,
  comparison, research suggestions.
- Read-only tools: fetch saved scan, compare saved scans, confirmed entries, deterministic
  performance, observation gaps, journal search. None can write, confirm, trade, or read
  credentials.
- Semantic validation rejects contradictory decision/score, non-recorded evidence, invented
  numbers/percentages, unknown citations, unsupported performance claims, and research that
  proposes live activation.
- Diagnostics are local and bounded (`model_diagnostics.jsonl`): request ID, feature, origin,
  availability/failure, latency, schema/prompt version, record IDs, validation issues. No
  prompt, response, or credential is retained.

## Real on-device generation executed on this Mac

Command:

```bash
swift test --filter "realAppleOnDevice"
```

Observed at HEAD:

```text
FM_RAW availability=ready decision=WAIT score=44 summary=The sealed decision was recorded as WAIT because the engine flagged a tight range.
FM_SERVICE availability=ready origin=appleOnDevice decision=WAIT score=44 latencyMs=20713.61 issues=[]
```

This is Apple’s on-device system model, not a mock or network model. It proves the API,
guided generation, semantic validation, and fallback boundary work. It is **not** proof of
generation on the physical iPhone; see the device gap below.

The model can occasionally include the configured timing (“8-second”) in prose. Validation
allows only the sealed score, expiry, and timing constants as digits; other numbers are
rejected. If a live output is rejected, the service returns the deterministic fallback with
the same sealed decision and score.

## Availability and failure coverage

`swift test` covers:

- available engine → `appleOnDevice` origin
- contradictory score → rejected, fallback
- unsupported percentage claim → rejected, fallback
- unavailable model → labelled fallback
- timeout → fallback
- cancellation → fallback
- guardrail/refusal error → fallback
- concurrent requests → serialized (max in-flight = 1)
- deterministic comparison differences
- confirmed-only context accounting

## Physical iPhone finding: context-window overflow

The first physical-device Coach run showed:

```text
generation failed: Provided 7,750 tokens, but the maximum allowed is 4,096.
```

The model was available; the context was not bounded. The fix now has two layers:

1. **Feature slices** — one scan for explanations, 4 scans / 8 entries / 8 gaps / 3 notes
   for chat, smaller debrief/research slices, with truncated evidence and notes.
2. **Central request budget** — `SystemLanguageModel.contextSize` is read at runtime
   (4,096 on this runtime), and Apple’s `tokenCount(for:)` API is used when available
   (iOS/macOS 26.4+). The count includes system instructions, user prompt, tool definitions,
   and the guided-output schema. Output reserve and a 256-token safety margin are subtracted.
   If the exact tokenizer is unavailable, a conservative character estimate is used and
   labelled `estimated`.

Exact measurement on this Mac:

```text
FM_BUDGET inputTokens=941 contextSize=4096 outputReserve=420 safetyMargin=640 method=exact
```

An oversized request retries **once** with a compact context, preserving the selected record
identity; a second overflow returns `Context too large` and the deterministic fallback. No
retry loops. The fallback label no longer says the model is unavailable.

Chat runs without tool definitions to avoid multi-turn tool latency; tools remain active for
scan fetch, comparison, debrief, and research. A real oversized-context test compacted and
completed in ~10.4s (`state=completed retry=0 tokens=1316`); an earlier full-context attempt compacted after a context error and completed in ~47s.

A device re-test of the bounded request is pending the phone being unlocked. Earlier, before
the budget fix, the physical iPhone did generate successfully twice:

```text
PHONE_FM_AVAIL ready
PHONE_FM_RESULT origin=appleOnDevice decision=WAIT score=44 latencyMs=5210.10 issues=[]
```

Those calls used the small self-test context, not the oversized Coach context that produced
the 7,750-token error.

## Request states versus capability

`AssistantAvailability` reports capability only (`ready` / reason). `AssistantRequestState`
reports the request outcome (`completed`, `contextTooLarge`, `cancelled`, `timedOut`,
`refusedOrFailed`, `invalidOutput`, `unavailable`, `basicFallback`). The Coach panel shows both.

## Physical iPhone status

- Real on-device generation succeeded on the phone (Apple A18 / iOS 27) with the self-test
  context.
- The Coach screen reproduced the 7,750-token overflow; the budget fix is committed.
- The bounded Coach request passed on the physical iPhone (A18 / iOS 27) on 2026-10-21:
  `PHONE_COACH_RESULT origin=appleOnDevice state=completed latencyMs=7835.7 tokens=1617
  limit=4096 method=exact retries=0 omitted=0 issues=[] failure=none`, citing both supplied
  scan IDs. The same harness on the Mac completed in 11.6 s with the same 1,617/4,096 token
  count. The harness is DEBUG-only: `BLAZER_FM_COACH_SELFTEST=1`.
- The app now defaults to FX/OANDA for Pocket Option handoff; crypto remains selectable.
- Extension app-group provisioning is fixed: the widget and Live Activity profiles were
  refreshed with `group.com.blazer.os`, and the signed archive/IPA carry it on the app and both
  extensions. Device test builds no longer blank extension entitlements.
- The measured OANDA → Pocket Option → return/confirm handoff remains pending because it
  requires the unlocked phone and the manual broker step.

## Physical iPhone verification gap

The iPhone simulator does not prove Apple Intelligence availability or generation. On the
device, open **Coach** and confirm:

1. The status chip reads `Apple on-device model ready`.
2. “Explain latest” returns `APPLE ON-DEVICE`, not `BASIC FALLBACK`.
3. The response cites the same record ID shown on the explanation card.
4. Airplane mode does not change model availability (the model is local).
5. Turning Apple Intelligence off in Settings changes the status to the honest unavailable
   reason and keeps deterministic explanations available.
6. Cancel/background during generation leaves scanning, quotes, countdowns, and entry
   untouched.

No raw conversation or credential appears in `model_diagnostics.jsonl`.
