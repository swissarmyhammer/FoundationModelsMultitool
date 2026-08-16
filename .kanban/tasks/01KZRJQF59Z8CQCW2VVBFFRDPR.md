---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m001cqs0m4y0ga3dyf8snajk
  text: |-
    ### The landed-but-unverified conformance is now verified, and covered

    `SearchToolsTool: DetachmentParameterProviding` returning both clocks at `unlimitedSeconds` compiles and runs. It had never been either. Two unit tests now hold it in place — ungated suite green at 329 tests in 27 suites, and 49 in 8.

    **`unlimitedSeconds` stopped being a literal.** It was `86_400` with a comment saying it was the same figure as Router's ceiling. It now *names* that ceiling — `ToolContext.waitSecondsCeiling`, public since Router's `^k0mecjp` — so the two cannot drift apart. `WaitTool.unboundedSeconds` took the same treatment.

    ### The two tests, and why they are shaped this way

    **"a slow discovery call returns its catalog inline, even mounted to detach immediately."** The card asks for this to be asserted against a deliberately slow searcher rather than by timing a real one. It goes one better: the slow searcher (a selection root that sleeps 300ms in `fork()`, so the call genuinely suspends) is mounted with `DetachConfiguration(mode: .detaching, waitSeconds: 0)` — the harshest mount there is, the very configuration under which `runCode` now always parks. A per-call answer overrides the wrap-time configuration, so discovery still blocks and the catalog comes back inline. "However long it takes" is a property of the clocks, not of a stopwatch, and this tests the property.

    **"a searcher that fails surfaces its own error, never a timeout and never a token."** A selection root that throws, mounted the same way. The searcher's own `SelectionSearchFailure` reaches the caller. The two shapes that must never appear are a `DetachingToolError.timedOut` blaming the clock for a search that failed on its merits, and a completion token for a search that is already over. `MetadataSearcher` is on this card's side here: its `.selection` path throws rather than degrading silently.

    ### Acceptance criteria

    - [x] A discovery call never returns a pending envelope, however long it takes — asserted against a deliberately slow searcher, not by timing a real one
    - [x] A searcher that throws surfaces as an error the model can read, and is not converted into a timeout or a pending token
    - [ ] A gated run shows `searchTools` returning a catalog inline, with the model's next call naming a real `tools.*` path from it
    - [ ] Whatever wall-clock discovery actually costs is **recorded** here

    The last two need real hardware and a real model, so they belong to the same run as the capstone `^0q2je6m`. This card stays in review until that run reports them; nothing about it is "done pending a gate" that a unit test could have proved instead.

    ### The model pin changed, and this card must know

    This card says the selection tier stays on `mlx-community/Qwen3.6-27B-mxfp4`, and names the reason: the small old Qwen failed `discoveryUnderDistractors`, and a catalog that omits the tool a request needs is unrecoverable.

    Under `^ev0zca7` both generation slots moved to `mlx-community/Muse-Glimmer-30B-4bit`, so the selection tier moved with them. **This is not the reversal the card warns about** — it is not a drop to a small fast model, and it was not made to improve the clock. It is a 30B agentic model taken for a prompt-cache reason: Qwen3.5/3.6 give their linear layers a non-trimmable `MambaCache`, and one non-trimmable entry stops prefix reuse for the whole cache list, which cost this suite its prompt caching entirely.

    The card's rule still binds, and it binds to the new pin: **the gated run owes a passing `discoveryUnderDistractors`.** If Muse Glimmer cannot do distractor discovery, the pin is wrong whatever it does for caching, and that finding belongs here.
  timestamp: 2026-08-14T11:44:21.280216+00:00
- actor: claude-code
  id: 01m02xxpf4qspnj5xcx1dt43k9
  text: |-
    ### Gated criteria met on real hardware. Muse Glimmer + GLM-4-9B.

    Both remaining criteria are now answered by real runs.

    **`searchTools` returns a catalog inline, and the model calls a real path from it.** From `singleCallWeather`'s trace:

    ```
    CALL [1] searchTools args={"task": "Get current temperature for Austin, Texas"}
    DONE searchTools out=... // tools.getWeather ... declare function getWeather(args: { city: string }): Promise<{ tempC: number; summary: string }>
    CALL [2] runCode args={"code": "const weather = await tools.getWeather({ city: \"Austin\" });..."}
    ```

    Inline — no pending envelope, on a surface where `runCode` two lines later gets one. That is the rule holding under the only condition that could disprove it.

    **Wall-clock cost, recorded rather than tuned**, as this card demands. Whole-scenario elapsed, discovery included:

    | scenario | elapsed |
    |---|---|
    | `singleCallWeather` | 83.2s |
    | `composeChain` | 83.1s |
    | `discoveryUnderDistractors` | 71.7s |
    | `repairFromTripProneTool` | 40.8s |

    And the sharpest measurement, from `PrefixReuseTests` — two consecutive selection-tier searches in one session:

    ```
    RESULT [prefixReuse] first=2.659s second=1.077s
    ```

    **The second search costs 41% of the first.** The fork inherits the prefix instead of re-prefilling. That is discovery's real marginal cost once a session is warm, and it is the property the whole Muse Glimmer move was made for.

    ### The distractor gate, on the new pin

    This card's standing rule: anyone changing the selection pin owes a passing `discoveryUnderDistractors`. The pin changed twice since the card was written — first to Muse Glimmer with `^ev0zca7`, then to `GLM-4-9B-0414-4bit` under `4c51abc` when sharing one model across both slots turned out to hang.

    The debt is paid:

    ```
    ✔ discovery scenario still names the warmest trip city among the distractor tools (79.4s)
    RESULT groundedIn=["getTrip", "getWeather"] searchToolsFirst=true
    MODES inventedPath=0 invented=[] overRefusal=0 answeredWithoutCalling=0 thrash=0
    ```

    `invented=[]` is the one that matters: among the distractor tools it named no path that does not exist.

    ### Acceptance criteria

    - [x] A discovery call never returns a pending envelope, however long it takes
    - [x] A searcher that throws surfaces as an error, not a timeout or a token
    - [x] A gated run shows `searchTools` returning a catalog inline, with the model's next call naming a real `tools.*` path from it
    - [x] The wall-clock cost is recorded here

    Done.
  timestamp: 2026-08-15T14:41:25.988372+00:00
- actor: claude-code
  id: 01m05b634gv2f5g4d6e1fs3j1n
  text: |-
    ### Reopening a correction: this card's implementation does not do what the card says

    `FoundationModelsRouter` found this while we were diagnosing a deadlock, and verified it in their source. Recording it here because this card is closed and its implementation is wrong.

    **What we shipped.** `SearchToolsTool.detachmentClocks` answers `(unlimitedSeconds, unlimitedSeconds)` — 86,400 for both — intending this card's rule: *"blocks until done. No wait clock, no work clock, no limit. Only a real error reaches the model."*

    **What that actually does.** `waitSeconds >= timeout` is not implemented as "never detach" anywhere. The two clocks are independent timers started concurrently that never consult each other. `DetachConfiguration.init` takes both with no validation and no relational check, and the stock design assumes the *opposite* relation — its own documentation says the 120s timeout is "deliberately much longer than" the 5s wait "so at stock settings the soft deadline always wins". We inverted that, and no code defends the inversion.

    So the call blocks in band for a full 24 hours, and then the two clocks race:

    - `waitSeconds` arms with fewer scheduling hops, so it usually fires first — the call detaches, and the timeout watcher immediately kills the run it just parked, handing the model a pending token for a **dead run**;
    - if the race lands the other way, `DetachingToolError.timedOut` is thrown in band.

    Both are reachable and which one you get is timing. Neither is what this card asked for.

    **Why it has never bitten.** No discovery call runs for 24 hours, so the race is unreachable in practice. The values achieve the intent by accident, not by construction — and there is no test anywhere for `waitSeconds == timeout` or `waitSeconds > timeout`; the only clamp coverage is the lower end.

    **Why the right fix is not available yet.** This card already recorded it: what the tool needs to declare is `DetachConfiguration.Mode.runToCompletion`, and `mode` is read from the wrap-time configuration while `DetachmentParameterProviding` exposes only the two clocks — so no tool can declare its own mode. Router is filing that as a genuine run-to-completion mode for a tool that must not park.

    And there is no better pair of numbers to pick meanwhile. `timeout < waitSeconds` makes the timeout fire first, which produces exactly the failure this card forbids — "error out on a real error, not timeout in searching tools." Neither ordering expresses the intent. The mode is genuinely required.

    **Action taken now:** the doc comment on `unlimitedSeconds` is corrected to state what the values really do, rather than implying a guarantee the mechanism does not provide. The values themselves stay, because they are the closest reachable approximation and changing them would trade an unreachable race for a reachable defect.

    **Not done, and deliberately:** no test is added for the 24-hour race. A test that waits a day is not a test, and simulating it would assert the behaviour we are trying to get rid of rather than the behaviour we want. When Router's run-to-completion mode lands, the test that belongs here is "a discovery call never detaches, whatever the mount configures" — and that one is cheap and real.
  timestamp: 2026-08-16T13:11:41.456719+00:00
depends_on:
- 01KZRJPJRK8SP9329DREV0ZCA7
position_column: done
position_ordinal: c280
title: searchTools blocks until done — no wait clock, no work clock, no limit
---
Depends on `^ev0zca7` (get building), because it cannot be measured otherwise.

## The three rules this belongs to

| tool | rule |
|---|---|
| `searchTools` | blocks until done. No wait clock, no work clock, no limit. Only a real error reaches the model |
| `runCode` | always backgrounds, always hands back a token. Waiting is not an option it has |
| `wait` | blocks until that token finishes, or until a timeout **the caller passed** |

The only duration anywhere is the one the model passes to `wait`. Nothing races a clock to decide anything, so a turn has the same shape on a fast machine and a loaded one.

**The gated tests must drive streaming.** On `respond(to:)` none of this exists — it drains, so a backgrounded `runCode` is collected before the caller sees it, a `wait` has nothing left to wait for, and a blocking `searchTools` is indistinguishable from a detaching one. A suite on `respond` would pass while testing none of the three rules.


> but FOR REAL -- searchTools needs to block till done

## Why blocking, not backgrounding

`searchTools` is a **synchronous prerequisite**. A model cannot write a snippet without knowing which `tools.*` paths exist, so nothing can be done while a discovery call is in flight — there is no concurrent work for a detached one to overlap with. Parking it converts a blocking dependency into one the model has to go and collect, which is strictly worse than waiting.

## Why no timeout either

> we'll worry about performance tuning once you have this working

> error out on a real error, not timeout in searching tools

A timeout and a detach answer different questions, and for a prerequisite read both answers are "never":

- `waitSeconds` — when should this become asynchronous? Never.
- `timeout` — how long may this run before being cancelled and reported failed? No limit, because **slow is not broken**. A timeout reports failure for a search that is still working, and the model then acts on a false statement about its own tools.

Only a real error — the searcher throwing, the selection model failing — should reach the model, and those already do, as errors.

## The bug that made blocking look impossible

`detachmentClocks` returned `timeout: nil`, and `nil` means *fall back to the wrap-time configuration* — the mount's 120 seconds. So a long wait was requested while the work clock was handed straight back to the value that kills the call:

```
DetachingToolError.timedOut(tool: "searchTools", timeoutSeconds: 120.0)
```

Twice — 134s, then 326s with `sample: nil`. **Both clocks must be answered explicitly; answering one is answering neither.** That is the lesson, and it generalises to every future `DetachmentParameterProviding` conformance.

## Landed but unverified

`SearchToolsTool: DetachmentParameterProviding` returning both clocks at `unlimitedSeconds` (86,400 — the ceiling `SessionMailbox.waitSecondsCeiling` already treats as unbounded). Written while the build was broken, so **never compiled or run**. Verify under `^ev0zca7` first.

## This is a workaround, and the card should say so

What this tool needs to declare is `DetachConfiguration.Mode.runToCompletion` — the mode Router already mounts for inner `tools.*` calls. `mode` is read from the wrap-time configuration (`DetachingTool.swift:384`) and `DetachmentParameterProviding` exposes only the two clocks, so **no tool can declare its own mode today**. Two large numbers express the intent; a per-tool mode would state it. Filed on Router's `^w8dzvee`.

Same gap applies to `wait` itself, which is mounted `.detaching` and can therefore park — see `^ddgjps6`.

## Acceptance Criteria

- [ ] A discovery call never returns a pending envelope, however long it takes — asserted against a deliberately slow searcher, not by timing a real one
- [ ] A searcher that throws surfaces as an error the model can read, and is not converted into a timeout or a pending token
- [ ] A gated run shows `searchTools` returning a catalog inline, with the model's next call naming a real `tools.*` path from it
- [ ] Whatever wall-clock discovery actually costs on the 27B is **recorded** here, not tuned. It is the input to a later performance decision, and that decision is explicitly not this card's

## Do not "optimise" the selection model back down

The selection tier stays on `mlx-community/Qwen3.6-27B-mxfp4`. This is a correctness requirement, not a preference:

> the reason i want to stick with qwen for serach - we always kept failing tool search with distractors, the small old qwen model was too stupid

The small model failed `discoveryUnderDistractors` — the scenario that mounts unrelated tools alongside the ones the question needs. Discovery is the one place where being wrong is unrecoverable: a catalog that omits the tool the request needs leaves the model with nothing to call, and no amount of downstream repair fixes it.

So the ordering of concerns here is deliberate and settled: **discovery must be right, then it must block, and only then may anyone care what it costs.** A future reader looking at a slow gated suite will be tempted to drop selection to a small fast model, because it makes the clock look better immediately. That trade was already made, in the other direction, on evidence. Anyone reversing it owes a distractor run that passes. #eventplan