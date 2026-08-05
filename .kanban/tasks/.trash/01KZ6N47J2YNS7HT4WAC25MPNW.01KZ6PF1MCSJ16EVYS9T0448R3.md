---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: 8c80
title: '[Router] Propagation probe (gated): does the task local survive respond()?'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"Phases" phase 1 (propagation probe) and §"The ambient context" effect 3.

## What
A gated test answering one question: when Apple's `LanguageModelSession.respond` calls a tool, does the `@TaskLocal ToolContext` bound around `respond()` arrive inside `call(arguments:)`, or is it `nil`?

- Add a probe tool that records `ToolContext.current != nil` (and the observed `completionToken`) from inside `call(arguments:)`.
- New gated suite in `Tests/FoundationModelsRouterIntegrationTests/` (gate: `FM_ROUTER_INTEGRATION_TESTS`, per-file constant + `.enabled(if:)` like the existing suites; acquire `GatedSuiteSerialGate.shared` in the test body). Bind the context around `respond()`, run one prompt that forces the probe tool call on the MLX path and one on the system model (follow `LanguageModelSessionBackendTests` fixtures / `RealModels.swift`).
- Record the answer in eventplan.md (replace the two-branch text with the observed result) and in the probe test's doc comment. Both outcomes are acceptable; the probe gates a file deletion, never the phase:
  - Propagates → native tools get ambient context free; create a follow-up kanban task to delete `EventEmittingTool`/`connecting(_:)` and the conformance-cast wiring this phase.
  - Does not propagate → the protocol stays as the native-path fallback, and the composition-time wiring must carry the full context (sink AND mailbox — elevation on the native path reads the mailbox from the ambient context). If this branch lands, verify `ElevatingTool`'s own per-call binding covers the mailbox need (it should, since the wrapper binds around the inner call) and record that in the test doc.
- Code mode is unaffected either way — `ToolInvoker` binds the context itself with no Apple code in the path.

Run it per the gated-run discipline: one `FM_ROUTER_INTEGRATION_TESTS=1 swift test --filter PropagationProbe` invocation at a time, nothing chained.

## Acceptance Criteria
- [ ] Gated probe test exists, builds ungated, runs on both model paths when gated, and asserts a definite boolean per path (no skip-as-pass when the gate is on)
- [ ] The observed result is recorded in eventplan.md and the branch decision is executed: either the deletion follow-up task exists on this board, or the keep-decision (with full-context wiring note) is documented
- [ ] Ungated `swift test` in Router remains green (probe builds but does not fire)

## Tests
- [ ] The probe IS the test: `cd ../FoundationModelsRouter && FM_ROUTER_INTEGRATION_TESTS=1 swift test --filter PropagationProbe` passes with a recorded verdict on MLX and system-model paths
- [ ] `cd ../FoundationModelsRouter && swift test` (ungated) green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first