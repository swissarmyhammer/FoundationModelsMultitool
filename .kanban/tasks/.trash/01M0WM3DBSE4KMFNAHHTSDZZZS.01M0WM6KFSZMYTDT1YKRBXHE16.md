---
assignees:
- claude-code
position_column: todo
position_ordinal: '9080'
title: 'Router: the natural terminal of a killed process run reports .succeeded'
---
## What

Found while proving the session-end sweep for ^1hq8xny. This is a **Router**
defect, not a Multitool one, so it needs a change in
`FoundationModelsRouter` and cannot be closed from this repository.

`DetachingTool.settle(...)` builds the run's terminal event from
`terminalFacts(for: result)`, where `result` is the `Result<String, Error>` of
the wrapped tool's own call:

```swift
let terminal = OperationEvent(..., kind: .completed, detail: facts.detail, outcome: facts.outcome)
await funnel.settleRun(with: terminal)
return RunSettlement(result: result, terminal: terminal)
```

`SessionMailbox.park(settling:)` takes `Task { await workTask.value.terminal }`,
so THAT event — the engine's — is what `markSettled` retains and what
`wait(completionToken:)` and a sweep hand back.

A `RunKind.process` run is stopped by its own supplied canceler, which sends
`killpg(SIGKILL)` and does NOT cancel `workTask`. `Execute.call` therefore
returns normally, with a report that reads `status: killed`. So
`terminalFacts` sees `.success` and the retained terminal event reports
`OperationOutcome.succeeded` for a run a `SIGKILL` ended.

`Execute` posts its OWN terminal event through `RunEventFunnel`, and that one
carries the honest `.stopped` (it reads `CommandStatus.killed` out of the
store). The funnel forwards it upstream and then drops the engine's, so a
SINK sees `.stopped`. Only the value the MAILBOX retains is wrong.

## Where it shows

- `ToolContext.wait(completionToken:)` on a run that a cancel already stopped
  reports `.succeeded`.
- `SessionMailbox.sweep()` uses the natural terminal when a run settles inside
  the window of its own canceler await. That window is narrow — the canceler
  is two actor hops and the run body needs the reap, the drain and a file read
  — so the sweep almost always synthesizes with the canceler's `.stopped`
  instead. It is a race, not a certainty, and the record it can write is a
  manufactured `.succeeded`.

## Why it is not fixed here

`FoundationModelsMultitool` cannot reach it. The outcome comes from the
engine's reading of the wrapped tool's return value, and no declaration a
capability makes changes that reading. A capability that threw instead would
report `.failed`, which is a second wrong word rather than a fix.

## Acceptance Criteria

- [ ] The terminal event a `RunKind.process` run settles with reports the
      outcome its own canceler reported, and never `.succeeded`, when a cancel
      stopped it.
- [ ] `wait(completionToken:)` on a stopped process run reports `.stopped`.
- [ ] The fix lands in `FoundationModelsRouter`, and this repository moves to
      the version that carries it.

## Tests

- [ ] A Router test parks a `.process` run, cancels it, lets the body settle,
      and asserts the retained terminal event reports `.stopped`.
- [ ] `swift test` in this repository passes on the updated Router.

#eventplan #phase-2