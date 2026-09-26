---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fj6nm4wp97376e8h9gmvz1
  text: |-
    Research and design (implement, iteration 1):
    - The sandbox `wait()` was an `AsyncHostFunction` in `MultiTool+SandboxGlobals.swift` (`awaitSettlement`) that called Router `ToolContext.wait(completionToken:seconds:)`. It is removed, with its docs block, `CallResult.timeout`, and `SandboxGlobalError.missingWaitDeadline`.
    - The name `wait` keeps a SYNCHRONOUS `HostFunction` (`MultiTool.makeRemovedGlobalHostFunctions`, name `MultiTool.removedWaitGlobalName`) that throws `SandboxGlobalError.waitRemoved` at once: "wait() does not exist. Do not wait for a run inside a snippet. Return the completion token and end your answer. When the run finishes, its result comes back to you as mail, in a new message." A synchronous throw stops the snippet at the call, awaited or not; a rejected promise that a snippet does not await would pass silently. The function reads no session, thus the text is the same in and outside a session.
    - Because `wait` is still an injected name, the README and docs/SECURITY.md "Injected globals" lists keep `- \`wait\`` (HardeningTests parses the README list and compares it with the runtime set) and now say that `wait` only gives the repair text.
    - `status()` still uses a zero-second `context.wait` as its lifecycle probe. That never suspends, thus it holds nothing.
    - The goldens under `Tests/FoundationModelsMultitoolTests/Goldens` did not contain `wait(`; the globals page is not in the goldens. A new test in `ToolAPIRendererTests` pins that no golden names `wait(`.
    - `liveContextCapError` named `wait(completionToken, seconds)`; it now says: end your answer, results come back as a new message; status() lists tokens; cancel() stops one.
    - `MultiToolExecutionTests.runCollectedBySandboxWaitIsAlsoMail` (the double-delivery finding of ^q4jrnd0) is replaced by `sandboxWaitIsRemovedAndTheRunComesBackAsOneMail`: the collector snippet gets the repair text with no result, and exactly one later prompt carries the result (mail).
    - `RouterSessionMountTests.runCodeEnvelopeTellsTheModelToEndItsAnswer` used `wait(token, 60)` only to keep a snippet pending; it now uses `GatedCodeTool` with `inlineSettleGrace: 0`.
    - `Support/Rendezvous.swift` and `Support/ReleaseGate.swift` stay: `FileChangeRunCodeTests`, `GatedConnectTransport`, `GatedTransportFactory`, `GatedDisconnectTransport` and `MailProbeFixtures` use them. `InlineSettleGraceTests` and `ShellExecuteTests` use the Router host API `context.wait`, not the sandbox global; no change. `Tests/Support/ScenarioGrading` has no rule that expects a sandbox `wait(`; one doc comment in `ScenarioTools.swift` changed.
    - IntegrationTests files that name the sandbox `wait()` (task ^ER9Z owns them; not changed here): `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift:279` (doc comment: "live background-run globals (`status()`, `wait()`, `cancel()`)"). The other `wait(` hits there are `generationGate.wait()` / `AsyncSemaphore.wait()` and Router `wait(completionToken:)` comments in `ShellRunContextProbe.swift:10`, `ShellBackgroundRunner.swift:35`, `NestedGenerationProbeTests.swift:22,24`, `IntegrationNestedGenerationTool.swift:56`, `ScenarioRunner.swift:1228,1231,1259` — not the sandbox global.

    ### implement — changed
    - evidence: Sources: MultiTool+SandboxGlobals.swift, MultiTool.swift, MultiTool+Background.swift, MultiToolConfiguration.swift, Interpreter/JSCInterpreter.swift, multitool-cli/main.swift; Tests: SandboxGlobalsTests.swift, MultiToolExecutionTests.swift, RouterSessionMountTests.swift, ToolAPIRendererTests.swift, Fixtures/SandboxGlobalsFixtures.swift, Support/ScenarioGrading/ScenarioTools.swift; Docs: README.md, docs/SECURITY.md. `swift build --build-tests` complete.
    - next: test
  timestamp: 2026-09-26T19:13:50.212385+00:00
- actor: claude-code
  id: 01m3fj7v0cq76tg3jczg6j77c2
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` complete, no compiler warning (only the SwiftPM build-system note "missing creator for mutated node" for the mlx-swift_Cmlx bundle, which is not a compiler diagnostic and was present before); `swift test` — 1786 tests in 144 suites passed, 0 failed, 0 skipped. `ResilienceTests.freshOperationWaitsForInFlightDisconnectStragglerBoundedByDisconnectGracePeriod` passed in this run. The new tests ran and passed (filtered rerun: 114 tests in 5 suites passed).
    - next: commit
  timestamp: 2026-09-26T19:14:28.492711+00:00
- actor: claude-code
  id: 01m3fjk1wwfrhg9f7mznhh57dn
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — sandbox `wait()` removed; the name `wait` keeps a synchronous function that throws `SandboxGlobalError.waitRemoved` (return the completion token, end the answer, the result comes as mail); docs page, live-context cap error, README and docs/SECURITY.md updated; `runCollectedBySandboxWaitIsAlsoMail` replaced by `sandboxWaitIsRemovedAndTheRunComesBackAsOneMail`; golden test added.
    - test: green — `swift build --build-tests` complete, no compiler warning; `swift test` 1786 tests in 144 suites passed, 0 failed, 0 skipped (the ResilienceTests disconnect-grace test passed in this run).
    - commit: changed — ec75ad2 feat(sandbox)!: remove the sandbox wait() global; a call to wait() gives a repair text
    - review: clean — review sha HEAD~1..HEAD: 0 findings (14 attempted, 0 failed; README.md and docs/SECURITY.md have no validator; .kanban excluded). No prior findings. Subtasks checked. Task moved to done.
  timestamp: 2026-09-26T19:20:35.996406+00:00
depends_on:
- 01M3EVKX9JFDWDQR297Q4JRND0
position_column: done
position_ordinal: ffef80
title: Remove the sandbox wait() global that holds an in-band runCode body
---
## What
User decision (2026-09-26): remove `wait`, and use mail. This includes the sandbox `wait()` hold. The sandbox global `wait(token, seconds)` (`Sources/FoundationModelsMultitool/MultiTool+SandboxGlobals.swift`, 25 uses of `wait`, and its JS surface in `Interpreter/JSCInterpreter.swift`) lets a `runCode` snippet block until a background run settles. When `runCode` runs in-band, which includes the `inlineSettleGrace` window, that block holds the model for every session on it (`../FoundationModelsRouter/generation-queue.md` §5.5).

- [x] Remove the `wait` sandbox global and its rendering in the tool API surface (`Surface/ToolAPIRenderer.swift`, and the goldens under `Tests/FoundationModelsMultitoolTests/Goldens` that list it).
- [x] A snippet that calls `wait(...)` now gets a repairable error that says: return the completion token, end the answer, and the result comes as mail.
- [x] Remove or rewrite the tests that depend on it: `SandboxGlobalsTests.swift` (24 uses), `Fixtures/SandboxGlobalsFixtures.swift`, `InlineSettleGraceTests.swift`, `MultiToolExecutionTests.swift`, `ShellExecuteTests.swift`, and the support types `Support/Rendezvous.swift` and `Support/ReleaseGate.swift` if nothing else uses them.
- [x] Update `Tests/Support/ScenarioGrading` rules that expect a sandbox `wait(`.

## Acceptance Criteria
- [x] The rendered tool API surface has no `wait` global (the golden files are updated).
- [x] A snippet that calls `wait("t", 1)` gets the repairable error text above, not a JS `ReferenceError` with no guidance.
- [x] `swift test` passes.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/SandboxGlobalsTests.swift`: a test that a call to `wait(...)` gives the repairable error.
- [x] `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests` (the golden suite): the goldens do not contain `wait(`.
- [x] Run `swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.