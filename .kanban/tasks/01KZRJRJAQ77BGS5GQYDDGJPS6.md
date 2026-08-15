---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m001krkd9thabcq1ddxfnv7g
  text: |-
    ### The settlement path is covered now, and `wait` stopped being accidentally safe

    Ungated suite green at 335 tests in 27 suites, and 49 in 8, two consecutive runs.

    ### The gap this card named is closed

    > What is *not* covered: the settlement path itself. Every existing test exercises the no-session and bound-arithmetic paths, because a real one needs a `SessionMailbox` with a parked run.

    It needs one no longer as a special favour: `parkScriptedRun(in:)` parks a run through the real detachment engine (rewritten under `^ev0zca7`), so a unit test can hold a genuine parked run with no live inference. Six new tests use it.

    **Two of them had to be rebuilt to prove what they claimed.** Both first passed in 0.001s, which was the tell: the settlement had already happened before the wait was issued, so `wait` was reading a retained terminal event rather than blocking on anything. A wait that returned at once asserts identically. They now hold the run open for a known 300ms/200ms after the wait is issued, and the blocking test asserts `elapsed >= heldOpen` — with no timeout passed, nothing but the settlement could have ended that wait, and it cannot have ended before the settlement it reports. That is an ordering proof rather than a timing tolerance.

    ### `wait` no longer parks itself — the third way out is gone

    This card called it out and filed the real fix on Router:

    > `wait` is mounted `.detaching` like every other tool, so a `wait` call that blocks past 5s **parks itself** — the same regress as `^w8dzvee` D5, inside the tool built to replace it. It is only accidentally safe today.

    `WaitTool` now conforms to `DetachmentParameterProviding` and answers both clocks at `unboundedSeconds`, the same workaround `SearchToolsTool` uses, and for the same reason: a per-call answer overrides the wrap-time configuration. The wait clock asks when this call should become asynchronous — never, since blocking is the entire call. The work clock asks how long it may run before being cancelled as failed — no limit, because the caller's `timeout` is the only bound in this design, and a host clock firing under it would report `deadlineElapsed` on the host's schedule rather than the caller's.

    A test mounts `wait` with `waitSeconds: 0` — harsher than the five seconds that made it accidentally safe — lets the bound elapse, and asserts the report comes back inline and is never a pending envelope.

    **This is still a workaround, and the card should keep saying so.** What the tool needs to declare is `DetachConfiguration.Mode.runToCompletion`, which is read from the wrap-time configuration and which `DetachmentParameterProviding` cannot express. Two large numbers state an intent a per-tool mode would declare. Filed on Router's `^w8dzvee`; unchanged by this card.

    ### Acceptance criteria

    - [x] Blocks until a parked run settles and returns its terminal `detail`, proven against a scripted mailbox with no live inference
    - [x] A run that settles early returns early — the bound is not a floor (a 600-second bound, settled at once, returns at once)
    - [x] A caller's timeout is honoured as passed, and a run still going at that bound reports `deadlineElapsed` rather than hanging or claiming failure — and the run is still parked afterwards, because still going is not failure
    - [x] With no timeout passed, waits for the run rather than returning on a host schedule
    - [x] Waiting with no token waits for **every** pending run; a session whose runs have all finished reports `nothingPending` with the detail that points at the answer already in hand
    - [ ] **A gated run where the model backgrounds work, calls `wait`, and answers from what came back**

    The last one is the criterion this card says the unit tests cannot substitute for, and it is right. It belongs to the capstone run `^0q2je6m`. This card stays in review until then.
  timestamp: 2026-08-14T11:48:11.501275+00:00
- actor: claude-code
  id: 01m02xy8jprn6dtkwwcbxj7fwv
  text: |-
    ### The gated criterion is met, literally.

    This card's last open item was the one it said the unit tests could not substitute for:

    > **A gated run where the model backgrounds work, calls `wait`, and answers from what came back** — no wall-clock guess anywhere in the turn.

    From `singleCallWeather` on real hardware:

    ```
    CALL [2] runCode  args={"code": "const weather = await tools.getWeather({ city: \"Austin\" });\nreturn weather;\n"}
    DONE runCode      out={"pending":true,"completionToken":"01M00XZBHSJA96T8SJ0DKHRTFC","next":"..."}
    CALL [3] wait     args={"completionToken": "01M00XZBHSJA96T8SJ0DKHRTFC"}
    DONE wait         out={"completionToken":"01M00XZB...","detail":"{\"summary\":\"Sunny\",\"tempC\":31}","state":"settled","outcome":"succeeded"}
    reply: "It's currently 31°C (about 88°F) and sunny in Austin right now."
    ```

    Background, token, `wait`, settled, answer — and the answer carries the fixture's own 31, which reached the model **only** through the collected run's `detail`. `groundedIn=["getWeather"]` confirms it from the call log rather than from the prose.

    **And no wall-clock guess anywhere in the turn.** Look at call 3: the model passed a `completionToken` and no `timeout`. It did not predict a duration, which is precisely the failure this tool was built to end — the recorded `return await wait(token, 60)` written seven times without collecting anything (`^2w9vbkm`). Here it declared an intent to block and the host did the waiting.

    The same shape appears in `ElevationTests`, independently:

    ```
    CALL [3] wait  -> {"detail":"41739","state":"settled","outcome":"succeeded"}
    ```

    `41739` is the deep-scan fixture's report code, unguessable, arriving through the collected run.

    ### Where `wait` shows up that this card did not predict

    `RespondDrainTests` measured `waitCalls` of 1 and 2 on the **blocking** surface. That is not this card's business but it is worth recording next to it: `runCode` backgrounds on every surface, and the pending envelope instructs the model to collect, so `wait` is not streaming-only in practice. It cost `^n6kgckr` an assertion.

    ### Acceptance criteria

    Every one now met — five by unit test, the last by gated run:

    - [x] Blocks until a parked run settles and returns its terminal `detail`
    - [x] A run that settles early returns early
    - [x] A caller's timeout is honoured as passed; still-running reports `deadlineElapsed` and stays parked
    - [x] With no timeout passed, waits for the run rather than a host schedule
    - [x] No token waits for every pending run; nothing pending says so
    - [x] **A gated run where the model backgrounds work, calls `wait`, and answers from what came back**

    Done.
  timestamp: 2026-08-15T14:41:44.534688+00:00
depends_on:
- 01KZRJNSJRB1RGKQDEBCV98VFF
position_column: done
position_ordinal: c380
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