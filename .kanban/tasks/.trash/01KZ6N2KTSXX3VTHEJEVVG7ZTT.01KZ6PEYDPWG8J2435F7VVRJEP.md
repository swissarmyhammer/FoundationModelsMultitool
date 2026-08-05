---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8980'
title: '[Router] ElevatingTool engine with the two-clocks model'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"Elevation: waitSeconds and the completion token", §"MultiTool is a host and an emitter" (synthesized events), §"Consolidation of the siblings" (two clocks; promotion of MCP's `CallWait` and Shelltool's `RunSupervisor` race — reference designs at ../FoundationModelsMCP/Sources/FoundationModelsMCP/{CallWait,CallDeadline,MCPServer}.swift and ../FoundationModelsShelltool/Sources/ShellTool/ShellRunner.swift).

## What
New `Sources/FoundationModelsRouter/Hosting/ElevatingTool.swift`: a wrapper over `any Tool` at the `FoundationModels.Tool` protocol level. Follow the forwarding precedent of `Session/ToolOutputCapping.swift`'s `TokenCappingTool` (forward `name`/`description`/`parameters`/`includesSchemaInInstructions`, decorate only `call(arguments:)`). The wrapper's `Output` is the rendered value — a typed wrapped `Output` never represents the pending case; the model reads text on the wire either way.

Behavior of `call(arguments:)` with elevation on:
1. Mint a `completionToken` (ULID; it IS the run's event `correlationID`), bind `ToolContext` around the inner call via `ToolContext.$current.withValue`.
2. Race the inner call against a `waitSeconds` timer (default 5 s; `0` detaches immediately). Use a continuation-based race, not a task group — a group cannot exit with a suspended child (both reference designs agree; MCP's `raceThroughGate` is the cleaner primitive).
3. Completes in the window → return the rendered output inline. Nothing resets `waitSeconds`.
4. Window elapses → park the still-running call in the session's `SessionMailbox` (kind: `swiftTask`, cooperative canceler) and return the pending envelope as rendered output: `{ "pending": true, "completionToken": "01…" }`. At elevation, post one synthesized `progress` event iff the run has posted no events of its own yet.
5. Terminal synthesis is terminal-scoped, enforced at a single posting funnel (precedent: `MCPServer.postOperationCompletedEvent`): at settlement, the engine posts `.completed` — rendered output in `detail`, `completionToken` as `correlationID`, correct `OperationOutcome` (`succeeded`/`failed`/`timedOut`/`cancelled`) — iff no terminal event for that `correlationID` already passed the funnel. A tool that posted only `progress` still gets its `.completed` synthesized; a tool that posted its own terminal event gets no duplicate. Exactly one `.completed` per elevated run, emitter or not. Terminal events always go upstream, even if a snippet already collected the result via `wait()` — the journal must stay complete.
6. Two clocks: `waitSeconds` limits the block of the call and nothing resets it; a per-call `timeout` limits the work itself and progress resets it (port MCP's `CallDeadline.resetForProgress` loop; timeout suspends while an elicitation is pending, per `isElicitationPending`).
7. Elevation off (the mode `ToolInvoker` will mount for inner `tools.*` calls): the call runs to completion bounded only by `timeout`; same engine owns correlation, events, and outcomes.

Per-call clock sourcing — the mechanism is defined HERE, in this task (the MultiTool envelope task consumes it): a public protocol in `Hosting/`, e.g. `ElevationParameterProviding { func elevationClocks(from arguments: GeneratedContent) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) }`. If the wrapped tool conforms, the engine extracts per-call clocks from the opaque `GeneratedContent` via this hook; otherwise the wrap-time configuration applies (Router's mount default: 5 s). `nil` fields fall back to configuration.

## Acceptance Criteria
- [ ] A fast fake tool returns its rendered output inline; a tool that completes in-window and posts no events of its own produces no events at all
- [ ] A slow fake tool elevates: pending envelope rendered with `pending: true` and a ULID `completionToken`; mailbox holds the run; one synthesized `progress` at elevation; on settle exactly one `.completed` with output in `detail` and matching `correlationID`
- [ ] A tool that posts only its own `progress` events still yields exactly one synthesized `.completed`; a tool that posts its own terminal event gets no duplicate
- [ ] `waitSeconds: 0` detaches immediately; a per-call `waitSeconds` supplied through `ElevationParameterProviding` overrides the wrap-time default; progress resets `timeout` but never extends `waitSeconds`; `timeout` expiry cancels the work and yields outcome `timedOut`
- [ ] Elevation-off mode never parks and never returns a pending envelope
- [ ] Exactly one `.completed` in every path (inline, elevated, tool-throws, cancel, timeout)
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] New `Tests/FoundationModelsRouterTests/ElevatingToolTests.swift` with fake-clock/short-interval fixtures: inline fast path; elevation slow path (envelope shape, mailbox entry, event sequence); zero-wait detach; `ElevationParameterProviding` override; two-clocks matrix (progress resets timeout, not wait); terminal-scoped synthesis matrix (no events / progress-only / own-terminal); exactly-one-completed including tool-throws, cancel, and timeout paths; elevation-off mode
- [ ] `cd ../FoundationModelsRouter && swift test --filter ElevatingTool` green; full suite green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first