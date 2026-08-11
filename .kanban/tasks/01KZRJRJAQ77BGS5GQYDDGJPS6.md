---
assignees:
- claude-code
depends_on:
- 01KZRJNSJRB1RGKQDEBCV98VFF
position_column: todo
position_ordinal: '8480'
title: wait blocks on a backgrounded runCode token, until it finishes or the caller's timeout
---
Depends on `^cv98vff`: there is nothing to wait *on* until `runCode` always hands back a token.

## The three rules this belongs to

| tool | rule |
|---|---|
| `searchTools` | blocks until done. No wait clock, no work clock, no limit. Only a real error reaches the model |
| `runCode` | always backgrounds, always hands back a token. Waiting is not an option it has |
| `wait` | blocks until that token finishes, or until a timeout **the caller passed** |

The only duration anywhere is the one the model passes to `wait`. Nothing races a clock to decide anything, so a turn has the same shape on a fast machine and a loaded one.

**The gated tests must drive streaming.** On `respond(to:)` none of this exists — it drains, so a backgrounded `runCode` is collected before the caller sees it, a `wait` has nothing left to wait for, and a blocking `searchTools` is indistinguishable from a detaching one. A suite on `respond` would pass while testing none of the three rules.


> wait needs to block till the runCode token finishes or we hit a passed timeout

Two ways to return, and **no third**. A host-side cap would be a third — the tool giving up on its own schedule and reporting `deadlineElapsed` for work still running, sending the model back around a loop it had already decided to stop for.

## Why a wait *tool* works where `wait()` in a snippet did not

Not the same mechanism in different clothes:

| | `wait()` in a snippet | the `wait` tool |
|---|---|---|
| what the model supplies | a predicted duration | an intent to block |
| the number's role | how long the work will take — a guess | a bound the caller chose |
| visibility | buried in snippet source | a tool call, in the transcript and the UI |
| who loops | the model, across turns | the host, correctly |

Code can wait until settled; a model can only guess and re-ask. Measured: with `do not wait()` in its own description, the model still wrote `return await wait(token, 60)` **seven times**, because a pending envelope instructed it to (`^2w9vbkm`).

## Landed but unverified

`WaitTool` exists, is mounted last (`searchTools`, `runCode`, `wait`) including in direct mode, and has 8 unit tests. The passed-timeout-honoured change and its assertions were written while the build was broken and have **never compiled or run** — verify under `^ev0zca7`.

What is *not* covered: the settlement path itself. Every existing test exercises the no-session and bound-arithmetic paths, because a real one needs a `SessionMailbox` with a parked run.

## Acceptance Criteria

- [ ] Blocks until a parked run settles and returns its terminal `detail`, proven against a scripted mailbox with no live inference
- [ ] A run that settles early returns early — the bound is not a floor
- [ ] A caller's timeout is honoured as passed, and a run still going at that bound reports `deadlineElapsed` rather than hanging or claiming failure
- [ ] With no timeout passed, waits for the run rather than returning on a host schedule
- [ ] Waiting with no token waits for **every** pending run, and a session with none says so in a way that points at the answer rather than inviting another wait
- [ ] **A gated run where the model backgrounds work, calls `wait`, and answers from what came back** — no wall-clock guess anywhere in the turn. This is the criterion the unit tests cannot substitute for: every description-level fix so far passed its unit tests and changed nothing about the turn

## Blocked on Router for real safety

`wait` is mounted `.detaching` like every other tool, so a `wait` call that blocks past 5s **parks itself** — the same regress as `^w8dzvee` D5, inside the tool built to replace it. It is only accidentally safe today. It needs `DetachConfiguration.Mode.runToCompletion`, which `DetachmentParameterProviding` cannot express (`DetachingTool.swift:384`). Filed on `^w8dzvee`. #eventplan