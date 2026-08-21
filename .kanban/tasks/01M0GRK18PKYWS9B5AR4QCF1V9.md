---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'wait() inside runCode live-locks: each round mints a new token, so the model chases the chain'
---
CI run `32392350928`, job `96504690907`: the elevation suite passed at `1785.670 seconds` against its 1800-second `.timeLimit` — a margin of 14.33 seconds. The transcript shows the cause, and it is a live-lock in the product, not a slow machine.

## The live-lock

```
CALL [2]  runCode  {"code": "const r = await tools.runDeepScan({});\nreturn r;"}
DONE      runCode  {"pending":true,"completionToken":"01M0G1M9M7C4XBMD8PCBB243Y4", ...}
CALL [3]  runCode  {"code": "return await wait(\"01M0G1M9M7C4XBMD8PCBB243Y4\", 60);"}
DONE      runCode  {"pending":true,"completionToken":"01M0G1NH3KBK0RGPVRK268MA8W", ...}
CALL [4]  runCode  {"code": "return await wait(\"01M0G1NH3KBK0RGPVRK268MA8W\", 60);"}
DONE      runCode  {"pending":true,"completionToken":"01M0G1PT7F4YV8SJ6MZQ2VRBCY", ...}
... calls 5 through 22, each waiting on the token the call before it minted ...
CALL [23] wait     {"completionToken": "01M0G1M9M7C4XBMD8PCBB243Y4", "timeout": 120}
DONE      wait     {"detail":"{\"reportCode\":41739}", ...}
```

A `wait` inside `runCode` suspends, so that `runCode` call elevates in its own turn and returns a pending envelope whose `completionToken` names **that `runCode` call**, not the run being waited for. The model reads the newest token and waits on it. The next round does the same. Each round costs 60 seconds of wait plus one generation on a 27B model.

Call 23 broke the chain only because the model used the top-level `wait` **tool** with the **original** token from call 2, and that returned the answer at once.

The fixture's own delay is 8 seconds (`integrationDeepScanDuration`, `IntegrationTests/.../Fixtures/ScenarioTools.swift:503`). About 1700 of the 1777 seconds bought nothing.

## This explains the run-time spread

| Where | Time | Tool calls | Card |
|---|---|---|---|
| Dev box | 51.79s | not recorded | `^dwzkfzx` |
| Dev box | 643.687s | 24 | `^hht0009` |
| CI | 1785.670s | 23 | this card |

These are not three machine speeds. They are three different counts of chain iterations before the model escaped. A 12-times spread on one machine has no other explanation.

## What

1. **Break the regress in the product, in the tool's own contract.** A pending envelope returned by a `runCode` call that is itself blocked in `wait` must lead the model back to the run it is waiting for, not to a fresh handle for the wrapper. Candidates, to be judged against the shipped tool descriptions and the envelope's own `next` text: return the original `completionToken` on an envelope that wraps only a `wait`; or make the envelope's `next` name the token to wait on. The teaching belongs in the shipped tool description and the envelope text, never in test scaffolding.
2. **Add an ungated regression test that holds the fix**, with no model. The seams exist: `Tests/FoundationModelsMultitoolTests/RouterSessionMountTests.swift:104-112` composes the identical `.nativeSessionMount`, and `Fixtures/SandboxGlobalsFixtures.swift:218-261` (`startScriptedRun`) builds a background run with `waitSeconds: 0`. A test that calls `wait` inside `runCode` on a pending token and asserts the envelope leads back to the original run runs in milliseconds.
3. **Re-derive the `.timeLimit` by the method of `^nhxj8hx`** once the live-lock is gone, from real measurements with a stated margin. Do not raise the limit before step 1 — a raised limit hides the live-lock.

## Acceptance Criteria

- [ ] The regress is broken in the product, and the change is in a shipped tool description, envelope text, or mount behavior — not in test scaffolding.
- [ ] An ungated, model-free regression test holds the fix and fails without it.
- [ ] The elevation scenario completes in a bounded number of tool rounds; the count before and after is recorded here.
- [ ] The suite `.timeLimit` is re-derived from measurements, with the margin stated. No retry loop.
- [ ] A CI run shows the suite green with the derived margin; run id recorded here.

## Tests

- [ ] Root `swift test` green.
- [ ] One CI integration run with the suite green, run id and suite time recorded here.

## Related

- `^hht0009` — the run that failed at 1793.2s. Its "zero-activity hang" reading rested on the `STALL withoutProgress=` lines, and that reading is refuted: in the passing run above the same value climbs to 1765.7s with no reset while 23 tool calls succeed, because it measures time since the last streamed **text** fragment and a tool-calling turn streams no text. Whether that run was this same live-lock without an escape is open; `toolCalls=0` on its `RESULT` line is the only remaining evidence.
- `^9gkbbvq` — made CI keep the recordings, which is how a future run gets a transcript like the one above.
- `^nhxj8hx` — holds the ceiling-derivation method.