---
assignees:
- claude-code
depends_on:
- 01KZRJPJRK8SP9329DREV0ZCA7
position_column: todo
position_ordinal: '8380'
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