---
assignees:
- claude-code
depends_on:
- 01KZ6N0G06Q27NNK51PZFF76MX
position_column: todo
position_ordinal: 8b80
title: '[MultiTool] Route tools.* through ElevatingTool with RunBinding'
---
CROSS-BOARD PREREQUISITE: the Router-side foundation (vocabulary move → SessionMailbox → ToolContext → ElevatingTool engine, tasks tagged `router-first` on ../FoundationModelsRouter's own kanban board) must be done and pushed to Router `main` before this task can build. Verify `ElevatingTool` and `ToolContext` exist on Router `main` (`swift package update` here resolves them) before starting.

Repo: this repo. Basis: eventplan.md §"Async JavaScript" (session affinity across the seam), §"Elevation" (the code-mode mount: elevation off), §"The constraint boundary" (inner calls never elevate).

## What
- `Invocation/ToolInvoker.swift` + the tools.* host-function glue in `MultiTool.swift`: send each inner `tools.*` call through the shared `ElevatingTool` engine with elevation off. Inner calls run until they complete, bounded by `timeout`; only the outer `runCode` elevates. The engine still owns correlation, events, and outcomes for inner calls.
- New `RunBinding` (one per `runCode` invocation), captured when the ambient context is bound: holds the `ToolContext` (session identity, mailbox reference, sink), the outer `completionToken`, and the interpreter's serial executor. Each promise carries the binding.
- The JS thread is not a Swift task — a JSC callback lands outside every task tree, so nothing may rely on task-local inheritance across the seam. Each inner call's `Task` closure re-binds `ToolContext.$current` explicitly from the binding and mints its own per-call `completionToken` from the captured context. Parallel `Promise.all` calls therefore correlate independently and post to the same session's mailbox.
- Settlement resolves the promise on the binding's executor, keyed by promise id. Two sessions sharing one registry can never cross-route because each invocation captured its own binding.
- Validation layering unchanged: `ToolInvoker`'s two layers still run, and their repairable errors reject the promise with identical message text.

## Acceptance Criteria
- [ ] An inner call slower than the configured `waitSeconds` still returns its real value to the snippet (never a pending envelope) — elevation is off on this path
- [ ] Two parallel inner calls under `Promise.all` carry distinct `completionToken`s and both post to the same session's mailbox/sink
- [ ] With two MultiTool instances over one registry, events from a run on instance A never reach instance B's sink (binding capture, not inheritance)
- [ ] A detached `Task` inside a tool that re-reads `ToolContext.current` gets `nil` (capture-at-start enforced)
- [ ] Full `swift test` green in this repo

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/RunBindingTests.swift`: slow-inner-call-no-elevation; parallel distinct correlation; cross-instance isolation; explicit re-bind (fixture tool records `ToolContext.current?.completionToken`)
- [ ] `swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1