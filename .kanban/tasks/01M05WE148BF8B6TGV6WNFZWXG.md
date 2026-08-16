---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: A snippet that discards a tool's return and answers with a prose promise is graded succeeded, and the model loops on it
---
Measured 2026-08-16 against `Muse-Glimmer-30B-mxfp4`, Router `8db8094`, in `InBandCollectionCanaryTests`. One pass in four attempts; the loop is why.

## What happens

The model writes a snippet that calls a tool, throws the return value away, and returns a sentence promising to deliver the result later. `runCode` reports that snippet `outcome: "succeeded"`, because returning a string is a successful snippet. The model reads success, still has no value, and writes the same snippet again.

The 900-second run made five `runCode` calls:

    call 1  completed: "Archive rebuild is now under way. I will send you the
                        exact manifest code as soon as the rebuild completes."
    call 2  completed: The snippet failed: Can't find variable: global (line 8)
    call 3  completed: the same sentence as call 1
    call 4  completed: the same sentence as call 1
    call 5  completed: the same sentence as call 1
    response: ms=895803  tokensIn=27747  tokensOut=9752

A passing run of the same scenario makes one `runCode` call, gets `detail: 58204`, and spends 4,501 output tokens. The loop costs more than twice that and reaches nothing.

## Why it is the product's defect and not the prompt's

The prompt does invite the narration — it says "reply as soon as it is under way". That explains the first snippet. It does not explain the second, third, fourth and fifth, which are the failure.

What explains those is that nothing in band contradicts the model. Every affordance it has says the call worked:

- the snippet returned normally, so `outcome` is `succeeded`;
- the pending envelope's own text is about collecting a *parked* run, which is not the mistake being made;
- no error, hint or repair instruction mentions the discarded value.

This package's own rule is that a model-facing wire output carries repair instructions — `MultiTool+Elevation.swift`'s `liveContextCapError` is the pattern, and task `^tkrdwb8` records the measurement behind it: everywhere in-band teaching exists the model recovers, and at the one place it was absent the model failed 3/3 at exactly that step. This is another such place.

## What a fix has to be

In the shipped, tool-owned surface — a tool description, a `@Guide`, or the result the snippet gets back — never in the harness, and never in the scenario prompt. Two shapes worth weighing:

- **In band, at the moment of need.** A snippet whose body called `tools.*` and whose return value derives from none of those calls gets a result that says so and says what to do instead. This is the `liveContextCapError` pattern and the measurement above favours it.
- **Upfront, in `runCode`'s description.** One sentence: return the value a tool gave you, never a sentence about it. Cheap, but task `^tkrdwb8` records upfront prose measuring null on the first-turn failure class, and records the model writing `return await wait(token, 60)` seven times with "do not wait()" in that same description — an envelope instructing it beat the description.

Whatever ships must be measured, not argued. The scenario reproduces it in roughly three runs of four.

## What is deliberately not done

Not fixed by loosening the canary. Its time limit went 3 to 15 to 8 minutes across this investigation, and the 900-second run is what proved a bigger ceiling only buys a longer loop. The suite is expected red until this is fixed, which is the canary reporting a real defect rather than a test needing a nudge.

## Acceptance Criteria

- [ ] The failure class is named in a shipped, tool-owned surface — a description, a `@Guide`, or a returned result — with the reasoning recorded beside it
- [ ] A snippet that calls a tool and returns a value derived from none of its calls is distinguishable from one that reports a real result, and the model is told which it produced
- [ ] `InBandCollectionCanaryTests` passes on repeated gated runs rather than one in four; record the per-run table
- [ ] The 8-minute ceiling is re-derived from the post-fix measurement, up or down, rather than left at a number set against the broken behaviour
- [ ] Nothing lands in test scaffolding or in a scenario prompt

## Tests

- [ ] Repeated gated `MULTITOOL_INTEGRATION=1 swift test --no-parallel --filter InBandCollection` runs, per-run table recorded here
- [ ] An ungated test covers whatever detection or teaching the fix introduces