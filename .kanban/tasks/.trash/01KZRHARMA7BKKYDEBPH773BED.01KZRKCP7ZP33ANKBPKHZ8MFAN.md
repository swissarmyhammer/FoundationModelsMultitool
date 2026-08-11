---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'Move waiting out of runCode and into a wait tool: streaming never blocks, respond drains'
---
## The contract, as ruled

> so streaming waiting -- wait tool calls. respond block drains

- **streaming** — no tool holds the turn. Slow work backgrounds, events flow, the transcript accumulates, results arrive.
- **`respond(to:)`** — blocks and drains. FoundationModels semantics, one value, unchanged. A caller who wants blocking calls this.
- **`wait(timeout)` as a mounted tool** — the model's explicit, deliberate join, when it genuinely cannot proceed without a result.
- **no waiting inside a snippet, ever.** Not `wait()`, not a `waitSeconds` argument, not a hint.

## Why a wait *tool* is legitimate where `wait()` in a snippet never was

They are not the same mechanism wearing different clothes:

| | `wait()` in a snippet | `wait(timeout)` as a tool |
|---|---|---|
| what the model supplies | a predicted duration | an intent to block |
| `timeout`'s role | how long the work will take — a guess | a safety bound so nothing hangs |
| visibility | buried in snippet source | a tool call, in the transcript and the UI |
| who loops | the model, across turns | the host, correctly |

A timeout as a **bound** is honest. A timeout as a **prediction** never was: every value the model can write is wrong, because the duration belongs to someone else's work. Measured evidence that the prediction form fails: with `do not wait()` in its description, a gated model still wrote `return await wait(token, 60)` seven times, because a pending envelope told it to (`^2w9vbkm`).

## Transcript is not model context

Established while reading Router `a3c2e4c`, and it constrains what we ask for:

> as events come in from running tools - these really do need to be 'in' the transcript to drive UI -- but may not need to be in the model context -- really only outputs - not just status needs to be told to the model

Router now journals **every** posted `OperationEvent` — "each progress update, each elicitation, the one terminal" (`RoutedSessionActorRunJournal.swift:63-67`) — as a `Transcript.Entry.toolOutput`. That is the right record and the wrong channel: `.toolOutput` is what feeds the model's context on replay, so every "3 of 8 cities" becomes context noise.

Not our fix, but our requirement, and filed on `^w8dzvee`: journal everything, and **project** only outputs into the model's context. `SessionProjection` is the natural home. A router-only entry kind is the wrong answer — Router's own doc explains that the mapper rejects the two that exist, so a third would journal but never rebuild.

## This is all ours to build

`ToolContext.current` is an ambient task-local (`Invocation/RunBinding.swift:81`), so **any** mounted tool's `call(arguments:)` can reach the session mailbox. A `wait` tool needs no Router change, and `SessionMailbox.wait(completionToken:seconds:)` already implements the mechanism the sandbox global was calling.

## The integration tests must drive streaming. Not negotiable.

> we also need to be very clear in the plan that our integration tests need to work with the streaming mode

**On `respond(to:)` none of this design exists.** `respond` blocks and drains, so a backgrounded `runCode` is drained before the caller sees it, a `wait` call has nothing left to wait for, and a blocking `searchTools` is indistinguishable from a detaching one. A gated suite on `respond` would pass while testing none of the three rules — it cannot observe the feature at all.

So every gated scenario drives `RoutedSession.streamEvents(to:)` and drains it to completion. `respond` keeps exactly one job in this suite: proving the final answer matches what a drained stream accumulates. Answer parity, nothing else.

This has bitten before and the scar is worth keeping: while the runner used `respond`, **four of the seven failure modes were unobservable**, and the `MODES` line printed `0` for each — reading as "clean" when it meant "not measured". That is why `routeObservable` exists and why the runner streams (`ScenarioRunner.swift`).

Two further consequences for the suite:

- **A client's view is part of the contract.** `.toolCall` → `.running*` → `.completed`, keyed to one call id, is what a UI draws. The runner records `.running` events and prints `progress=N`; it silently discarded them until task `h773bed`, so no run before that is evidence about whether progress flows.
- **The deliberate parker must survive.** If `searchTools` blocks and every snippet is fast, nothing detaches and the backgrounded path stops being exercised — exactly how `^w8dzvee` D5 hid for weeks behind green tests. `ElevationTests` keeps a fixture that sleeps 8s. A green suite bought by never reaching the hard case is the failure mode to guard against here.

## The three rules, as finally ruled. No threshold anywhere.

> but FOR REAL -- searchTools needs to block till done
> wait needs to block till the runCode token finishes or we hit a passed timeout
> runCode should always return a token in this setup
> more than 'waitseconds 0' get rid of waiting being an option for runCode -- runCode should always background. the model can decide to wait, or just let it run to completion

| tool | rule |
|---|---|
| `searchTools` | blocks until done. No wait clock, no work clock, no limit of any kind. Only a real error — the searcher throwing, the selection model failing — reaches the model |
| `runCode` | always backgrounds, always hands back a token. Waiting is not an option it has; the concept is removed from its schema, not set to zero |
| `wait` | blocks until that token finishes, or until a timeout **the caller passed**. Those are the only two ways it returns |

The only duration anywhere in the system is the one the model explicitly passes to `wait`. Nothing races a clock to decide anything, so the shape of a turn is identical on a fast machine and a loaded one.

**A timeout is not backgrounding.** `waitSeconds` asks "when should this become asynchronous"; `timeout` asks "how long may this run before it is cancelled and reported failed". For a prerequisite read both answers are "never", because *slow is not broken* — a timeout there reports a failure for work that is merely still running, and the model then acts on a lie.

### Landed so far

- `searchTools` blocks: `detachmentClocks` returns both clocks at `unlimitedSeconds` (86,400 — the ceiling `SessionMailbox.waitSecondsCeiling` already treats as unbounded).
- `wait` honours a passed timeout exactly, and waits for the run when none is passed. The host-side 120s cap is gone: it would have been a third way out, reporting `deadlineElapsed` for a run still going.
- The harness stopped wiring a `sampleGenerator`, matching `CLIRunner.swift:390`. It was testing a configuration the product does not ship, at the cost of a second nested 27B generation (×3 attempts) per discovery call.

### The bug that made blocking look impossible

`detachmentClocks` returned `timeout: nil`, and `nil` means **fall back to the wrap-time configuration** — the mount's 120 seconds. So a long wait was requested and the work clock was handed straight back to the value that kills the call:

```
DetachingToolError.timedOut(tool: "searchTools", timeoutSeconds: 120.0)
```

Twice, with `sample: nil` the second time, at 134s and 326s. Both clocks must be answered explicitly; answering one is answering neither.

## Still to do: remove waiting from runCode, and the blast radius it has

Removing `waitSeconds` (and `timeout`) from `RunCodeArguments` and always detaching breaks five existing tests. They are **contract changes, not regressions**, but two of them are behavioural and need reasoning rather than re-assertion:

- [ ] `RouterSessionMountTests.swift:60` — "runCode returns the same value through Router's session mount as it does direct". This can **never** hold again: through the mount `runCode` always returns a token, so byte-transparency is superseded by design. The test needs to become "the mount returns a token where direct returns the value", which is a stronger statement than the one it replaces
- [ ] `SuspendedContextTests.swift:66` — "waitSeconds crosses the envelope untouched, including the immediate-detach zero". Encodes the removed contract; delete it with the property
- [ ] `SuspendedContextTests.swift:43` — asserts the stock wait clock is `nil`. Becomes: `runCode` always detaches, so there is no stock wait clock to inherit
- [ ] `SuspendedContextTests.swift:108` — "a snippet that elevates while its inner call is in flight settles into exactly one terminal event". **Behavioural.** Its harness gate did not start when every call detaches immediately; understand why before touching the assertion
- [ ] `SuspendedContextTests.swift:179` — "cancel(completionToken) on a suspended snippet tears its context down within the time limit". **Behavioural**, same caution

## Blocked on Router, twice over

- **Per-tool mode.** What `searchTools` and `wait` need to say is `DetachConfiguration.Mode.runToCompletion` — the mode Router already mounts for inner `tools.*` calls. `mode` is read from the wrap-time configuration (`DetachingTool.swift:384`) and `DetachmentParameterProviding` exposes only the two clocks, so no tool can declare it. Two large numbers express the intent; a per-tool mode would state it.
- **`wait` can park itself.** Mounted `.detaching` like everything else, a `wait` call that blocks past 5s parks — the same regress as D5, inside the tool built to replace it. It is only accidentally safe today, and needs `.runToCompletion` for real.
- **Router's tree does not currently build**: `RoutedSessionActorRunJournal.swift:85: cannot find 'journaledTerminalCorrelationIDs' in scope`, mid-edit by their agent. Nothing here can be measured until that clears.

## Steps

- [ ] **Add the `wait` tool**, mounted beside `searchTools` and `runCode`. Reads `ToolContext.current` for the mailbox. Blocks until the named runs settle — or every pending run, when the model names none — bounded by `timeout`. Reuse `SessionMailbox.wait`, and the reporting shapes `terminalEventFields`/`tokenOnlyFields` already produce, so a settled run reads the same however it was collected
- [ ] **Remove `wait()` from the sandbox globals**: the `AsyncHostFunction` (`MultiTool+SandboxGlobals.swift:285`) and its `SandboxGlobalDoc` block (`:195`, whose `@example` teaches `await wait(token, 30)`). `status()` and `cancel()` stay — a query and a command. `elicit()` stays: it parks for a person, not a clock
- [ ] **Remove `waitSeconds` and `timeout` from `RunCodeArguments`** and from the `@Guide` text. The host keeps its own work ceiling through `MultiToolConfiguration.executionTimeLimit`, which is where a limit belongs. `MultiTool+Detachment.swift`'s `detachmentClocks` has nothing left to read from arguments — decide there whether MultiTool still conforms to `DetachmentParameterProviding` at all, and record why
- [ ] **`searchTools` declares it does not detach.** A prerequisite read: the model cannot write a snippet without the catalog, so there is nothing to background *for*, and parking it turns a blocking dependency into an unsatisfiable one. Available today through `DetachmentParameterProviding`, which is public and which the engine reads off any wrapped tool (`DetachingTool.swift:422`)
- [ ] Ungated suite green, and the sandbox-globals page, help docs, and sample snippets carry no `wait(` anywhere

## Acceptance Criteria

- [ ] No `wait(` appears in any model-facing description, sandbox preamble, docs page, or sample snippet in `Sources/` — asserted off the **rendered** preamble, not the doc array, so a re-binding cannot pass it
- [ ] A snippet calling `wait(...)` gets the standard unknown-identifier repairable error, pinned by a test: the model is corrected in band, never handed a global that silently vanished
- [ ] The `wait` tool blocks until a parked run settles and returns its terminal detail, proven without live inference against a scripted mailbox
- [ ] The `wait` tool's `timeout` is a bound, not a duration: a test proves a run that settles early returns early, and one that never settles returns at the bound rather than hanging
- [ ] `RunCodeArguments` exposes `code` alone; a test asserts the rendered schema carries no `waitSeconds` and no `timeout`
- [ ] The host work ceiling still bounds a runaway snippet with no model-facing clock present — the existing watchdog coverage still passes
- [ ] **A gated run reaches a grounded answer with no wall-clock wait anywhere in it.** Either the tool result arrived without asking, or the model called `wait` deliberately. This is the criterion the others cannot substitute for: every previous description-level fix passed its unit tests and changed nothing about the turn

## Known risk to hold onto

If discovery stops parking and nothing else is slow, **nothing detaches**, and the parked path stops being exercised — which is exactly how D5 hid for weeks behind green tests. `ElevationTests` must stay the deliberate parker (its fixture sleeps 8s). A green suite bought by never reaching the hard case is the failure mode here. #eventplan