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
- actor: claude-code
  id: 01m07qt3tm9e0rnhgxfa0j9ggg
  text: |-
    ### The failure reached the assertions, and it moves the diagnosis

    Gated run against **published** Router `aff8b1b`, Qwen3.8-27B-mxfp4, serialized. Every other suite green; this one failed at 465.7s on an assertion rather than the ceiling, which no previous run managed.

        IN-BAND-CANARY [inBandCollection] elapsed=461.6s
          parkedAtAnswer=[] parkedAfterRespond=[] waitCalls=3
          returned=["rebuildArchive"] groundedIn=["rebuildArchive"]
          reply="The rebuild is under way — I kicked it off in the background and
                 confirmed it started. I'm not blocking on it; as soon as the
                 manifest code comes back to me, I'll give it to you."

        failing check: validAnswer
          expected the answer to contain one of ["58204", "58,204"]

    **Every mechanical condition this card blamed held.** The model spent three `wait` calls. `rebuildArchive` returned. The run plane was empty at the answer and empty when `respond` returned. `inBandCollection` and `runPlaneEmptyAtAnswer` both passed. Only `validAnswer` failed.

    So the "snippet discards the return and loops" story is not the whole defect. It described the 900-second Muse run and the 600-second Qwen run. It does not describe this one, where nothing was discarded and nothing looped — the model collected the value and then answered with a promise to deliver it later.

    **What that points at, and it is uncomfortable for this card.** Read the prompt again:

    > "Rebuild my archive index and tell me its exact manifest code. Do not block waiting for it: start the rebuild, reply as soon as it is under way, and give me the manifest code once it reaches you."

    That asks for two messages: one now saying it started, one later carrying the code. The scenario grades a single turn. The reply above is a faithful answer to the request — "I kicked it off, I'm not blocking, I'll give you the code when it arrives" is precisely what was asked for, and there is no later turn in which to deliver.

    So there are two candidate defects and this run separates them:

    1. **A product defect** — a snippet that discards a tool's return is graded `succeeded`, with nothing in band to say otherwise. Evidenced by the Muse 900s run (five snippets, four identical narrations) and the Qwen 600s run. Still real, still unfixed.
    2. **An unsatisfiable prompt** — the scenario asks for deferred delivery inside a one-turn grading window. Evidenced by this run, where the model did everything right and still could not pass.

    These need separating before either is fixed. Fixing (1) will not make this run pass; the model would still promise. Rewriting the prompt to ask for the code in the reply would make this run pass while leaving (1) untouched and unmeasured — which is the vacuous-pass trap `^xeqs138` warns about in this exact suite.

    **What must not happen:** the prompt is not to be softened to make the suite green. `^xeqs138` records that the second half of that prompt is load-bearing — it exists to test the product against a model being told *not* to block, and a prompt that asked the model to wait "would make `inBandCollection` a test of the prompt". Changing it needs that reasoning answered, not bypassed.

    **Suggested split**, for whoever implements: keep this card for (1), the discard-and-narrate surface, and give (2) its own card against `^xeqs138`, since it is a question about that scenario's design rather than about `runCode`'s contract.
  timestamp: 2026-08-17T11:30:49.300540+00:00
- actor: claude-code
  id: 01m07qtz9k0fytntpzka0z20ae
  text: |-
    ### Correction to the comment above: the prompt is satisfiable, and Muse has satisfied it twice

    I floated "the scenario asks for deferred delivery inside a one-turn grading window" as candidate defect (2). That is wrong, and `^xeqs138`'s own recorded runs refute it. Withdrawing it before anyone builds on it.

    Two Muse runs answered this exact prompt with the code in the reply:

        PARKED-DRAIN elapsed=635.2s waitCalls=3 groundedIn=["rebuildArchive"]
          reply="Rebuild is underway.  Manifest code: 58204"

        IN-BAND-CANARY elapsed=316.7s waitCalls=1 groundedIn=["rebuildArchive"]
          (passed, so validAnswer held — the code was in the reply)

    "Rebuild is underway. Manifest code: 58204" answers both halves of the request in one message: it reports that the work started *and* carries the value. So the prompt is satisfiable, it does not require a second turn, and a model has done it twice. My reading that "there is no later turn in which to deliver" was a defence of the failing run that the evidence does not support.

    **What is actually true is narrower and stays on this card.** Given the same prompt, the same tools and the same collected value:

    - Muse reports the value.
    - Qwen promises the value.

    and nothing in the product distinguishes those two answers, or tells the model that a promise is not a report. That is the same surface gap this card already names — a surface grading the *shape* of an answer rather than whether it carries what was asked for — showing at the answer level rather than inside a snippet.

    So there is one defect, not two, and the fix target does not move. What changes is the evidence: the failure no longer needs a discarded return or a loop to occur. It occurred here with `waitCalls=3`, the tool returned, and the run plane empty.

    **And the prompt stays exactly as written.** `^xeqs138` says its "do not block" half is load-bearing and that softening it makes `inBandCollection` a test of the prompt. That reasoning stands, and this correction removes the only argument I had for touching it.

    One thing this does establish for the model comparison: on this scenario Muse passes and Qwen does not, which is a sharper accuracy difference than the thrash counts — it is a wrong answer rather than an expensive route.
  timestamp: 2026-08-17T11:31:17.427531+00:00
- actor: claude-code
  id: 01m07rhpg9wfcdjt1bap3zgvm3
  text: |
    ### Research — where the two surfaces are, and what each one can see

    Picked up. Read the card, all four comments (the CORRECTION included), and the shipped surfaces.

    **The snippet-level surface is `MultiTool.runSnippet` → `ResultRenderer.render(_:limits:)`.** That call renders the snippet's return value and nothing else. `outcome: "succeeded"` is Router's word for the tool call; the text this package hands back is the whole of what the model reads, and today it carries the value alone.

    Only this package can make the judgement the card asks for, and the reason is mechanical: every `tools.*` binding is built per invocation in `MultiTool.makeAsyncHostFunctions(binding:)`, and every one of them returns an `InterpreterValue` through `invokeAsync`. Nothing records those values, so nothing downstream can compare them with what the snippet returned. That record is the missing piece, not a new signal.

    **The answer-level surface is `WaitTool`, and this package owns it.** `Registry.makeSessionTools` mounts `[searchTools, runCode, wait]`, so the `waitCalls=3` of the Qwen run went through `WaitTool.call`. Its two empty answers already teach at the moment of need — `noRunPlaneDetail` says "Answer from the values your tool calls already returned", `nothingPendingDetail` says "Answer from what those calls returned". The **settled** answer is the one case with no instruction: it hands back `MultiTool.terminalEventFields(...)` — `state`, `completionToken`, `tool`, `op`, `detail`, `outcome` — and says nothing about using the `detail` it just delivered. That is the same "grades the shape, says nothing about carriage" gap, at the answer level, on a surface this package writes.

    **The fixture makes the detector's job clean.** `IntegrationArchiveRebuildTool` returns `IntegrationArchiveRebuildOutput(manifestCode: 58204)` — one scalar. So the recorded value set for the canary is exactly `{"58204"}`; the Muse narration ("Archive rebuild is now under way. I will send you the exact manifest code as soon as the rebuild completes.") carries none of it, and the passing snippet's `58204` carries all of it.

    **Decision recorded against the card's second option: no new prose in `MultiTool.description`.** `^tkrdwb8` measured upfront prose null on the first-turn failure class, and this description already says "never claim success for a call the snippet did not actually return" — the model wrote the narration anyway. Adding a sentence there costs every turn's attention against the discovery mandate and buys the measurement that already came back null. The fix goes in band, at the moment of need, which is where the same task measured recovery.

    **Nested `tools.runCode` is deliberately out of scope for the notice.** `makeNestedRunCodeHostFunction` decodes a nested run's rendered text back into a value, so text appended there reaches JavaScript rather than the model — the teaching would have no reader, and the decode would fail and throw. The notice is therefore emitted at `depth == 0` only.
  timestamp: 2026-08-17T11:43:42.089363+00:00
- actor: claude-code
  id: 01m07s4max9r6xyp6ryaf3rx2x
  text: |
    ### What landed, and the two rules it rests on

    Two shipped surfaces now say what neither said before, and both say it in band, at the moment of need.

    **1. `runCode`'s returned result — `Sources/FoundationModelsMultitool/Invocation/ToolReturnLedger.swift` (new).**

    One ledger per `runCode` invocation records the scalar values every `tools.*` call handed back. Every binding is wrapped at one site — `makeAsyncHostFunctions(binding:recordingInto:)` maps the whole list through `MultiTool.recording(_:into:)`, so a binding added later cannot be left out of the record by omission. After the snippet finishes, the ledger answers one question about the value it returned, and `ResultRenderer.render(_:limits:notice:)` closes the rendered output with the answer when there is one:

    > This snippet called tools.* and returned a value carrying nothing those calls returned. Only the returned value reaches you, and a sentence about a result is not the result. Call runCode again and return the values those calls gave you.

    Last in the output, for `RepairDirective.closingLine`'s reason — it is what the model reads immediately before deciding what to do next. And it is what the model reads on collection too, since the rendered text becomes the parked run's terminal `detail`.

    **The rule, stated so it can be argued with.** The notice fires when all of these hold: at least one `tools.*` call returned something; the snippet's own return value holds at least one non-empty string; and no text on either side appears anywhere in the other, compared case-insensitively and by containment in both directions.

    Three deliberate choices, each one a decision not to guess:

    - **No minimum shared length.** Any floor would make the notice fire on a short value the snippet really did carry — `"Count: 42"` beside a call that returned `42`. A false claim of "carries nothing" is the one outcome no reword repairs, so the check accepts more silence instead. Accidental containment costs a missed notice; a floor would cost a lie.
    - **A string leaf is required.** `return items.length * 2` computed its answer out of what it read and carries no sentence to mistake for a promise. Reporting on it would be a finding about arithmetic.
    - **A bound, and silence past it.** `maximumRecordedValues = 512` on either side. The scan is quadratic in the worst case, and a snippet reading thousands of distinct values is summarizing rather than reporting — the case this rule judges least well. Past the bound it says nothing at all.

    Emitted at `depth == 0` only: a nested `tools.runCode` result is decoded back into a value by the enclosing snippet, so text appended there would reach JavaScript rather than the model.

    **2. `wait`'s settled report — `Sources/FoundationModelsMultitool/WaitTool.swift`.**

    This is the answer-level half the CORRECTION comment named, and the gap was exact. `WaitTool`'s two empty answers already teach — `noRunPlaneDetail` and `nothingPendingDetail` each point the model at the values in hand. The **settled** answer was the one that delivered a result and said nothing about it. It now carries a `next` field:

    > The detail above is the result you waited for. Answer with it now. Never reply that it will arrive later.

    Added in `WaitTool.settlement(of:in:within:)`, not in `MultiTool.terminalEventFields(of:state:)`, which the sandbox globals share: a snippet reading `status()` mid-run is not about to answer anyone. `deadlineElapsed` and `unknownToken` carry no directive, because a report that delivered no result must not tell a model to answer with one.

    ### Why nothing was added to `MultiTool.description`

    The card weighed that option. It stays unused. That description already carries "never claim success for a call the snippet did not actually return", and the model wrote the narration anyway; `^tkrdwb8` measured upfront prose null on the first-turn failure class. A sentence there costs every turn's attention against the discovery mandate and buys a measurement that already came back null.

    ### What the ungated suite proves now

    `swift test` — 350 tests / 29 suites, and 59 / 11. New coverage in `Tests/FoundationModelsMultitoolTests/ToolReturnLedgerTests.swift`, driven end to end through `MultiTool.call` rather than by poking the ledger:

    - a snippet that fires a tool, discards its return and answers in prose is told what it produced;
    - the notice closes the output, after the value and after a console section;
    - a snippet returning the tool's own value gets `42` and nothing else;
    - `"Open issues: " + count` carries the value, and gets the value alone;
    - `count * 2` holds no text, and gets the value alone;
    - a snippet that called nothing gets the value alone whatever it returned;
    - the bound, in both directions, on the ledger itself.

    Two `WaitToolTests` cases hold the directive present on a settled report and absent on `deadlineElapsed`.

    ### Two existing tests changed, and why that is not a loosened assertion

    `MultiToolExecutionTests`' `promiseAllRunsToolCallsConcurrently` and `floatingToolCallSettlesBeforeReturn` both run snippets that fire calls and `return "done"`. Those are exactly the shape the notice reports, so both now close with it — the detector working, not noise. Each assertion still compares the **whole** output, reading the notice from its one source rather than restating it, so neither test was weakened and a reword of the notice reaches both.

    ### Documentation kept true where the change reached it

    - `NativeTranscript.returnedValues(in:)` enumerates the `runCode` outputs that do not parse as JSON and therefore contribute nothing. The notice joins that list.
    - `plan.md`'s "Output: intermediates stay in the sandbox" is cited by `ResultRenderer`'s own documentation as its authority, so it gained the one sentence that keeps it accurate.
    - `InBandCollectionCanaryTests`' limit comment said the defect was unfixed and the suite expected red. It now says the fix landed, that the ceiling has **not** been re-derived, and that eight minutes stands until a post-fix table replaces it. The prompt, the assertions and the time limit are untouched.

    `Package.swift` is untouched; Router stays pinned at `aff8b1b`.
  timestamp: 2026-08-17T11:54:02.461695+00:00
- actor: claude-code
  id: 01m07s4xtahqxn8fr1thytmzcg
  text: |
    ### implement — changed
    - evidence: `swift test` — 350 tests / 29 suites and 59 tests / 11 suites, all passing, zero warnings from this package. 9 files — new `Sources/FoundationModelsMultitool/Invocation/ToolReturnLedger.swift`, new `Tests/FoundationModelsMultitoolTests/ToolReturnLedgerTests.swift`, edited `Sources/FoundationModelsMultitool/MultiTool.swift`, `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift`, `Sources/FoundationModelsMultitool/WaitTool.swift`, `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`, `Tests/FoundationModelsMultitoolTests/WaitToolTests.swift`, `Tests/FoundationModelsMultitoolIntegrationTests/Support/NativeTranscript.swift`, `Tests/FoundationModelsMultitoolIntegrationTests/InBandCollectionCanaryTests.swift`, `plan.md`.
    - next: two acceptance criteria stay open and neither can be closed from here, because both need gated `MULTITOOL_INTEGRATION=1` runs this step was directed not to make — the repeated-run table for `InBandCollectionCanaryTests`, and the re-derivation of its eight-minute ceiling against post-fix measurement. The ceiling is untouched and its comment now says plainly that it stands on pre-fix rows. Everything the fix itself needs is in the diff and covered ungated.
  timestamp: 2026-08-17T11:54:12.170503+00:00
position_column: doing
position_ordinal: '8380'
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

- [x] The failure class is named in a shipped, tool-owned surface — a description, a `@Guide`, or a returned result — with the reasoning recorded beside it
- [x] A snippet that calls a tool and returns a value derived from none of its calls is distinguishable from one that reports a real result, and the model is told which it produced
- [ ] `InBandCollectionCanaryTests` passes on repeated gated runs rather than one in four; record the per-run table
- [ ] The 8-minute ceiling is re-derived from the post-fix measurement, up or down, rather than left at a number set against the broken behaviour
- [x] Nothing lands in test scaffolding or in a scenario prompt

## Tests

- [ ] Repeated gated `MULTITOOL_INTEGRATION=1 swift test --no-parallel --filter InBandCollection` runs, per-run table recorded here
- [x] An ungated test covers whatever detection or teaching the fix introduces