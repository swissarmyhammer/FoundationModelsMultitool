---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: '[Router] Pending envelope must teach the collect step: render next-step instructions into PendingRunEnvelope'
---
HUMAN-DIRECTED ROOT-CAUSE FIX (2026-08-07). This card is Router-native; it edits only FoundationModelsRouter sources.

## Why (evidence, researched in source — not inferred)

`PendingRunEnvelope.rendered` (`Sources/FoundationModelsRouter/Hosting/ElevatingTool.swift:141`) is the ONLY model-facing wire output in the elevation system that carries no next-step instruction. Its exact bytes today:

```
{"pending":true,"completionToken":"<26-char ULID>"}
```

A model whose long tool call parks receives this and nothing else. To proceed it must recall one sentence buried at the tail of MultiTool's runCode description. Measured consequence (MultiTool card 01KZ6N5Z39W4ZBBE74JTKRDWB8, 2026-08-07): `elevationInCodeMode` red 3/3, every failure at the collect step with `pendingEnvelope=pass`; a control run hallucinated the report code outright — the signature of a model holding a token it does not understand while the user demands an answer.

The contrast is decisive and comes from the same day's measurements: every in-band text that DOES teach the next move succeeds — MultiTool's deliberately vague booking tool repairs 4/5 because the error text names the fix; `liveContextCapError` is "phrased as repair instructions, like every other error this package hands a model" (MultiTool's own stated house rule); the unknown-tool near-match hints produced 8/8 clean invocations. The parked envelope is the one violation of that rule, and it sits exactly where the suite fails.

## What

Make the rendered envelope self-describing while keeping recognition byte-exact:

- New wire form: fixed `prefix` + token + fixed `midfix` + token + fixed `suffix`, e.g.:
  `{"pending":true,"completionToken":"<T>","next":"Still running — do not answer yet and never invent the result. Call runCode again with a snippet that does: return await wait(\"<T>\", 60) — when its state is \"settled\" the result is in its detail field; if \"deadline_elapsed\", call wait again with the same token."}`
  Adjust wording freely; the facts that MUST be present, in this order: still running; do not answer / do not invent; the exact follow-up snippet with the real token spliced in; result is in `detail` when state is `settled`; on `deadline_elapsed` wait again. Splice state names from `RunPlaneState`-equivalent constants where they exist rather than retyping.
- `isRendered` stays an exact byte-shape check: fixed frame lengths, both token slots must be the SAME valid ULID.
- `TokenCappingTool` passthrough keeps recognizing it (it calls `isRendered`; verify with its existing test, updated).
- Total length stays far under any render cap.
- No change to WHEN the envelope is produced — only its wire text.

## Acceptance Criteria
- [ ] `rendered`/`isRendered` round-trip exact for random ULIDs; tampered variants (mismatched twin tokens, wrong lengths, edited prose) rejected
- [ ] `TokenCappingTool` passes the new envelope through untouched
- [ ] `swift test` green in FoundationModelsRouter (ungated)
- [ ] Committed on `main` and PUSHED — MultiTool consumes Router via `.package(url:branch:)`, so the fix is invisible to MultiTool's gated suite until it is on the remote branch (push 159aada with it, or as agreed with the human)

## Tests
- [ ] Unit tests for the new wire form incl. adversarial variants (same file's existing envelope tests extended)
- [ ] `swift test` in FoundationModelsRouter, 0 failures

## Workflow
- Use `/tdd` — write the failing recognition/rendering tests first.

#phase-1