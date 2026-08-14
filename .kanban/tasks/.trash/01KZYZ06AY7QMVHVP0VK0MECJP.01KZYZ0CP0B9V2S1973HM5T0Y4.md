---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: ToolContext gets the run-plane capabilities a tool host needs
---
## Why

`^j0pp9yp` moved the run plane inside the module. `Hosting/SessionMailbox.swift` now says:

> The run-plane machinery (park, wait, cancel, status, sweep) is internal wiring the detachment engine and the session own.

That audit counted two audiences: the engine and the session. There is a third. `FoundationModelsMultitool` is a **host that shows the run plane to a model**. Its `runCode` sandbox has the `status(completionToken)`, `wait(completionToken, seconds)` and `cancel(completionToken)` builtins, and it mounts a `wait` tool. Those builtins are the product, not internal wiring (`../FoundationModelsMultitool/eventplan.md`, "Elevation" and "The sandbox globals").

The consumer therefore cannot build. It reached the plane through `ToolContext.mailbox`, which is now internal, at 13 sites in `MultiTool+SandboxGlobals.swift`, `WaitTool.swift` and `Invocation/RunBinding.swift`.

**Do not make `SessionMailbox` public again.** The actor is a god object, and a host must never hold one. Add typed capabilities on `ToolContext`, beside the `elicit(_:)` and `progress(_:)` that are already there. The mailbox stays internal, and the host names three operations instead of an actor.

That set is small, and it gets smaller. `FoundationModelsMultitool` is moving to "every mounted call detaches and hands back a `completionToken`". After that move, these three are the **only** reason a host touches the plane: its tests stage a parked run by calling a real tool, not by parking one by hand.

## What to add

Three capabilities on `ToolContext`:

```swift
public func parkedRuns() async -> [ParkedRun]
public func wait(completionToken: String, seconds: Double) async -> WaitOutcome
public func cancel(completionToken: String) async -> CancelOutcome
```

Each forwards to the session mailbox the context already holds. Each carries public vocabulary, because a host renders it:

- `ParkedRun`: `completionToken`, `tool`, `op`, `kind`, `latestProgressDetail` — the five fields the JSON row carries
- `WaitOutcome`: `settled(OperationEvent)`, `deadlineElapsed`, `unknownToken`
- `CancelOutcome`: `reported(OperationOutcome)`, `alreadySettled(OperationEvent)`, `unknownToken`
- `waitSecondsCeiling`, which a host clamps a model-supplied deadline against, and `terminalDetailTailLimit`, which a host asserts its rendered output tail against

Keep the existing internal `RunStatus`/`WaitResult`/`CancelResult` as the internal shape, or rename them into the public vocabulary. Do not publish two names for one thing.

## Also in this change

`ToolDetachment.wrapping(tool:sessionID:mailbox:sink:configuration:)` is public but demands a `SessionMailbox`, which no caller outside this package can obtain. A public function whose arguments nobody can supply is unusable. An out-of-package binder wraps its own inner calls with it (`RunBinding.invoke`, elevation off).

An additive overload and one test are **already in this working tree**, written while diagnosing the break:

```swift
public static func wrapping(
    tool: any Tool,
    inheriting context: ToolContext,
    sink: any OperationEventSink,
    configuration: DetachConfiguration
) -> any Tool
```

Review it, keep it or replace it, and commit it with the rest. It obeys the same rule as the three capabilities above: a host names a context, never a mailbox.

## Acceptance Criteria

- [ ] `ToolContext` carries the three capabilities, and every run-plane member of `SessionMailbox` stays internal
- [ ] The public vocabulary is one set of names, not two
- [ ] `ToolDetachment.wrapping(tool:inheriting:sink:configuration:)` is reviewed and covered by a test
- [ ] Unit tests drive each capability with no live model
- [ ] The "Audience" paragraph in `Hosting/SessionMailbox.swift` names the host run-plane capability, so the next audit does not close this door again
- [ ] `swift build` clean and `swift test` green

#eventplan