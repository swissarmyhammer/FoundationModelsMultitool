---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m05y8zqeegaacjh63ph46pym
  text: |-
    ### The class, named from the other side — and why no clock will catch it

    From the `FoundationModelsRouter` session, reviewing this card against their own `^466d38p`. Recorded because it sharpens what a fix has to do, and rules out two approaches before anyone tries them.

    **The class.** A tool-owned surface that grades the **shape** of a result rather than whether the result was used. "Returned a string" is a successful snippet and an empty answer at the same time. Our `outcome: "succeeded"` is truthful about the shape and silent about the substance, and the model has nothing else to read.

    **The third state.** A run can be still working, stuck, or busy achieving nothing. Router's `^z6xcmnh` shipped a stall *report* rather than a timeout precisely because a signal separates the first from the second — but neither one separates either from the third. Our loop is the third state. From outside it is indistinguishable from a hang, which is exactly what it looked like here for four runs.

    **So the stall detector will not help, and neither will a clock.** Their `SessionEvent.generationStalled` carries a `GenerationProgressVisibility` stating what claim it can make, and on a `respond` turn the strongest claim available is "this model call has run N seconds" — it cannot say whether a token moved. A model looping productively-looking work is generating the whole time. No deadline distinguishes it from a model thinking hard.

    Their conclusion, and it matches where this card already puts the fix: the signal has to come from **the tool surface that knows a return value was discarded**. Nothing upstream of that surface has the information.

    That rules out two things a later reader might reach for:

    - raising or adding a timeout — already refuted here by measurement (180s, 600s, 900s all cut off, 317s passed), and refuted again in principle by the above;
    - waiting for Router to detect it — they have said plainly that they cannot, and why.

    It also confirms the acceptance criterion as written: a snippet that calls a tool and returns a value derived from none of its calls has to be *distinguishable*, and the model has to be told which it produced. That is a judgement only this package can make, because only this package sees both the `tools.*` calls a snippet made and the value it returned.
  timestamp: 2026-08-16T18:45:19.214682+00:00
- actor: claude-code
  id: 01m06105ff7gv3ah89hst3dmdr
  text: |-
    ### Reproduced on a second model — same trigger, different flailing

    Ran the whole gated suite again on `Qwen3.8-27B-mxfp4` (pin swap on `1344a51`), same Router `8db8094`, serialized. Every other suite passed. This one failed at its 480-second ceiling, and the transcript shows the same entry into the failure:

        runCode 1 completed: "archive index rebuild started in the background"
        runCode 2 completed: "// globals /** The ambient globals every snippet
                              already has, beyond `tools.*` ... "
        runCode 3 completed: [{"completionToken":"01M05Z8EQ1575RWBM8E5DQMY5F",
                               "op":"runCode","state":"parked","tool":"runCode"}]
        response ms=476530  tokensIn=18089  tokensOut=8222

    **The first snippet is the defect, unchanged.** It fires `rebuildArchive`, discards the return, and answers with a narration string. `outcome` is `succeeded`, because returning a string is a successful snippet.

    **What follows differs by model, which is the useful part.** Muse repeated the same snippet verbatim four more times. Qwen does not repeat — it goes looking: snippet 2 reads the ambient-globals documentation, snippet 3 calls the run-status listing and gets back its own parked run. Two different recovery strategies, both spent on a problem neither model has been told it has, and neither one collects the manifest code.

    So the loop shape is a model behaviour and the **trigger is ours**. A fix aimed at the loop would have to anticipate every model's flailing strategy; a fix aimed at the trigger — telling a snippet that returned a value derived from none of its `tools.*` calls exactly that — covers both, and any third.

    That also settles the question this card left open about whether the prompt is to blame. Two models with different training, given the same prompt and the same surface, both take the same first wrong step and then diverge. The prompt invites the narration; the surface fails to contradict it.

    **Cost comparison, same scenario, same fixture:**

        model                     ceiling   tokensOut   ms        outcome
        Muse-Glimmer-30B-mxfp4      900s      9,752     895,803   cut off, looped
        Muse-Glimmer-30B-mxfp4     1200s     ~4,000     316,700   PASSED, waitCalls=1
        Qwen3.8-27B-mxfp4           480s      8,222     476,530   cut off, flailed

    Muse has passed this scenario once in four attempts. Qwen has not passed it in one. Neither number is a reliability claim yet, and neither should be quoted as one — but the defect is now cross-model and that is no longer a single-model observation.
  timestamp: 2026-08-16T19:32:55.919984+00:00
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