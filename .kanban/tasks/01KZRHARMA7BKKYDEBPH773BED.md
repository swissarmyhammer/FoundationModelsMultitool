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