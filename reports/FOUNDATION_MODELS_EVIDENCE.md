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
