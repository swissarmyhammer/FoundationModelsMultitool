---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'runCode''s description forbids wait(): awaiting is the whole of how a snippet coordinates its work'
---
## Why

Human ruling on the design, made while reading a gated trace where the collect instruction parked itself:

> long 'waits' in the code should trigger the truly asynchornous mode. but also -- there is NO reason at all to allow a tool call run code to generate a wait() ... ever. waiting on time is just a terrible idea

`wait(completionToken, seconds)` asks the model to predict how long another party's work takes. Every value it can write is wrong: too short burns a turn, too long stalls it, and the right value is unknowable at the call site. A long wait is the signal to go asynchronous — it is not something to sit through.

Detaching on a wall clock is a sound **entry** condition and stays. This card removes the wall-clock **exit** condition.

## Scope — the description, not the binding. Human ruling.

> same on ^2w9vbkm -- in the description, just say 'do not wait()'

So this card is the one sentence, already landed: `runCode`'s description now reads "Awaiting a call is the whole of how a snippet coordinates its work: do not wait(), and never time a call or poll for one."

Forbidding it by name was a deliberate reversal of how this file usually works. Naming a thing to forbid it normally puts it back in the option set — the reason the description never names refusal. `wait()` is different: it is *already* in the option set from outside, because a detaching host mount hands the model an envelope instructing exactly that call. A prohibition has to name what it overrides.

Removing the binding stays possible and is written up below, but it is **not** required to close this card, and nothing should be removed before Router can deliver a settled run's result (see Sequencing).

## What this repo owns, if the binding is ever removed

- `Sources/FoundationModelsMultitool/MultiTool+SandboxGlobals.swift:195` — the model-facing `SandboxGlobalDoc` block, including `@example const settled = await wait(token, 30);`
- `Sources/FoundationModelsMultitool/MultiTool+SandboxGlobals.swift:285` — the `AsyncHostFunction(name: "wait")` binding itself

`status()` and `cancel()` stay: a query and a command, neither one a bet on a duration. `elicit()` stays too — it parks for a person, not for a clock.

Also review whether `RunCodeArguments.waitSeconds` should stay model-facing (`MultiTool.swift:199`, an `@Guide` field). The host needs a detach threshold; it does not follow that the model should name one. Decide it on this card rather than leaving it implied.

## Sequencing — read before starting

Collection today happens **only** through `wait`. Removing it before Router delivers a settled run's result would leave a parked run uncollectable by a second route.

That is not a regression in practice: a parked run is *already* uncollectable, which is the defect this came from. Router's `^w8dzvee` D5 carries the delivery half — a settled run injects its own terminal event into the session via `SessionMailbox`/`OperationEventSink`/`enqueue`, and the envelope promises delivery rather than prescribing a snippet. Land this with or after that, and say in the commit which Router commit it pairs with.

## Evidence this is real

Gated run, `--filter singleCallWeather`, Router `c7b9477`, 69s, 5 tool calls, 0 failed:

```
CALL [2] searchTools -> {"pending":true,"completionToken":"01KZRA6229...","next":"... return await wait(\"01KZRA6229...\", 60)"}
CALL [3] runCode     args={"code": "return await wait(\"01KZRA6229...\", 60)"}
DONE     runCode     -> {"pending":true,"completionToken":"01KZRA6ED1...","next":"... return await wait(\"01KZRA6ED1...\", 60)"}
```

The model did exactly what it was told and got a pending envelope for a **different** token. `typed=[] invoked=[] returned=[]` — no fixture tool ran — and the reply was "I don't have access to real-time weather data".

## Acceptance Criteria

- [x] `runCode`'s description says `do not wait()`, in the same sentence that states awaiting is the whole of how a snippet coordinates its work, and that nothing is ever timed or polled
- [x] The description contract test pins that clause, so it cannot be dropped in a later edit of the description
- [x] Ungated suite green: 320 tests / 26 suites, plus 49 / 8
- [ ] `MULTITOOL_INTEGRATION=1 swift test --filter singleCallWeather` is re-run and it is recorded whether the model still writes a `wait(...)` snippet when handed a pending envelope. **This can legitimately still fail**: the envelope is a live instruction arriving mid-turn, and a description clause may not outweigh it. Record what happens rather than assuming the clause wins

### Not required to close this card

Removing the `wait` binding, and the `waitSeconds` schema decision. Both stay written up above for whenever Router's delivery path lands; neither is in scope under the ruling. #eventplan