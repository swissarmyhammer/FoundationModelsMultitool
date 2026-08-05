---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: 8a80
title: '[Router] Mount ElevatingTool for native sessions; bind ToolContext around respond'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"Elevation" (two mounts, one engine, two policies — this is the native mount) and §"The vocabulary and the host substrate" (Router binds the task local around native `respond()` also).

## What
- Insert `ElevatingTool` (elevation on, configured `waitSeconds` default 5 s) after `connecting(_:)` and inside whatever capping each site already applies. The three sites have deliberately different chains today — do NOT unify them; add only the elevation layer:
  1. `RoutedLLM.swift:204-208` (`RoutedModel.makeSession`): today `connect → cap`; becomes `connect → elevate → cap`.
  2. `RoutedSession.swift:1904-1909` (fork): today `fork → connect → cap`; becomes `fork → connect → elevate → cap`.
  3. `Recording/SessionTreeRestoration.swift:279-281` (restore): today `connect` only — no fork, no cap; becomes `connect → elevate`. Do not add fork or capping here.
  The pending envelope is tiny, so capping outside elevation is safe; document the per-site chains where the existing fork-then-connect rule is pinned.
- Bind the ambient context around native turns: `RoutedSessionActor`'s turn execution binds `ToolContext.$current.withValue(ctx)` around the backend `respond()`/stream calls, with the session's mailbox, upstream sink (the session's `SessionOutbox`), session identity, and cancellation. This is the host layer owning `window` — whether Apple's runtime propagates the task local into `Tool.call` is the propagation-probe task's question; the binding is correct either way, and `ElevatingTool` itself binds per-call around the inner call regardless.
- Native follow-up policy: no builtins on this path. A parked native call's completion arrives as a turn-riding event through the outbox at the next turn boundary — this already works via the existing drain/preamble machinery (`composedPrompt`, `appendingOperationEventSegments`) once the engine posts `.completed` to the connected sink; verify, don't rebuild.

## Acceptance Criteria
- [ ] All three composition sites produce elevated tools, each preserving its real existing chain (wiring tests assert the three distinct per-site orders listed above, in the style of `SessionOutboxToolWiringTests`)
- [ ] A slow fake tool invoked through a session's composed tool list returns the pending envelope to the model, and its later `.completed` event appears in the next turn's preamble and as a durable `OperationEventSegment`
- [ ] A fork's parked runs live in the fork's own mailbox; parent unaffected
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] Extend `Tests/FoundationModelsRouterTests/SessionOutboxToolWiringTests.swift` (and restoration wiring twin) for the new elevation layer with per-site order assertions
- [ ] New turn-riding-completion test with a scripted backend: elevate → pending envelope in rendered output → completed event drained into the following turn's composed prompt
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first