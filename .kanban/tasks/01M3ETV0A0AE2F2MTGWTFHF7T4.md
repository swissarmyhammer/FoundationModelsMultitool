---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fmtgggpm38n1rtn5fyym09
  text: |-
    Scope addition (2026-09-26): the IntegrationTests package must also compile against these changes:
    - The discovery API change (task 01M3FMSTTSP16K9AE7JKZAEFGZ): change each `makeSessionTools(librarian:embedder:...)` and `SearchToolsTool(registry:librarian:...)` call site to pass the registry seams through the public adapter in `MultitoolCLI`. The call sites are in `NoDescriptionSurfaceDiscoveryTests`, `OverBudgetSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests`, `SelectionForkPerCallTests`, `WebResearchScenarioTests`, `Support/FilesAndShellSurface.swift`, `Support/ScenarioRunner.swift` and `Support/ShellBackgroundRunner.swift`.
    - The removal of the `wait` tool and the sandbox `wait()` (tasks ^q4jrnd0 and ^11cfnx0): remove `WaitTool` and the old canary API from the package, only so that it compiles. Task 01M3ETVQGBG0R25ED1ER77ER9Z owns the behavior of the in-band canary and the drain tests.
  timestamp: 2026-09-26T19:59:37.488199+00:00
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
- 01M3FMSTTSP16K9AE7JKZAEFGZ
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
position_column: todo
position_ordinal: '8380'
title: Make the IntegrationTests package build against the work-queue Router events
---
## What
The nested package `IntegrationTests/Package.swift` lists Router directly (`:84`). Its `IntegrationTests/Package.resolved` is in `.gitignore`, so it is local only and it can pin an older Router than the root.

- [ ] Run `swift package update --package-path IntegrationTests FoundationModelsRouter mlx-swift-lm`, so the nested package resolves Router `c208add` or later and mlx-swift-lm `stable` `a1f77ad` or later. There is nothing to commit for this step.
- [ ] Move the fold of session events into a pure, model-free function in `Tests/Support/ScenarioGrading`, for example `SubmissionLog.fold(_ events: [SessionEvent]) -> [AnswerRecord]`. It must record each `submissionStarted` (`SubmissionStart.submissionId`, `messageIds`, `cause`), each `submissionEnded` (`usage`, `finishReason`), `answered` (`SessionAnswer.reply`), `answerFailed` and `repetitionStopped`.
- [ ] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift`: replace the `.turnStarted` / `.turnEnded` handling (8 uses) with that function. Rename `turnIdentity` to `submissionIdentity`. Where the old code meant "the end of the reply", use `answered`. Where it meant "the end of one SDK call", use `submissionEnded`. Write the decision in a comment. The respond path and the stream path must take the answer text from `answered.reply`.
- [ ] Fix each other compile error that `swift build --package-path IntegrationTests --build-tests` reports, for example in `InBandCollectionCanaryTests.swift`, `RespondDrainTests.swift`, `Support/BareSessionScenario.swift` and `Support/ShellBackgroundRunner.swift`. Keep each measurement's meaning. Behavior changes are in the live-suites task.

## Acceptance Criteria
- [ ] `swift build --package-path IntegrationTests --build-tests` passes with no errors.
- [ ] No file under `IntegrationTests/` names `turnStarted`, `turnEnded`, `turnId` or `TurnStart`.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ScenarioGradingTests.swift`: two `submissionStarted` / `submissionEnded` pairs and one `answered` fold to one answer with both submission ids. An `answerFailed` folds to a failed answer. A `repetitionStopped` is recorded.
- [ ] Run `swift test --filter ScenarioGradingTests` and `swift build --package-path IntegrationTests --build-tests`. Expected result: both pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.