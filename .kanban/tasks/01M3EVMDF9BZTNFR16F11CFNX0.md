---
assignees:
- claude-code
depends_on:
- 01M3EVKX9JFDWDQR297Q4JRND0
position_column: todo
position_ordinal: 8a80
title: Remove the sandbox wait() global that holds an in-band runCode body
---
## What
User decision (2026-09-26): remove `wait`, and use mail. This includes the sandbox `wait()` hold. The sandbox global `wait(token, seconds)` (`Sources/FoundationModelsMultitool/MultiTool+SandboxGlobals.swift`, 25 uses of `wait`, and its JS surface in `Interpreter/JSCInterpreter.swift`) lets a `runCode` snippet block until a background run settles. When `runCode` runs in-band, which includes the `inlineSettleGrace` window, that block holds the model for every session on it (`../FoundationModelsRouter/generation-queue.md` §5.5).

- [ ] Remove the `wait` sandbox global and its rendering in the tool API surface (`Surface/ToolAPIRenderer.swift`, and the goldens under `Tests/FoundationModelsMultitoolTests/Goldens` that list it).
- [ ] A snippet that calls `wait(...)` now gets a repairable error that says: return the completion token, end the answer, and the result comes as mail.
- [ ] Remove or rewrite the tests that depend on it: `SandboxGlobalsTests.swift` (24 uses), `Fixtures/SandboxGlobalsFixtures.swift`, `InlineSettleGraceTests.swift`, `MultiToolExecutionTests.swift`, `ShellExecuteTests.swift`, and the support types `Support/Rendezvous.swift` and `Support/ReleaseGate.swift` if nothing else uses them.
- [ ] Update `Tests/Support/ScenarioGrading` rules that expect a sandbox `wait(`.

## Acceptance Criteria
- [ ] The rendered tool API surface has no `wait` global (the golden files are updated).
- [ ] A snippet that calls `wait("t", 1)` gets the repairable error text above, not a JS `ReferenceError` with no guidance.
- [ ] `swift test` passes.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SandboxGlobalsTests.swift`: a test that a call to `wait(...)` gives the repairable error.
- [ ] `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests` (the golden suite): the goldens do not contain `wait(`.
- [ ] Run `swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.