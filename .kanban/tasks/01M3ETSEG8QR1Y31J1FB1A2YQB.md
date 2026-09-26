---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Make the library targets build against the work-queue Router (c208add)
---
## What
FoundationModelsRouter replaced turns with a per-session message queue and one generation queue for each model (design `../FoundationModelsRouter/generation-queue.md` §5.5, §5.6, §5.10). Router `main` is pushed (`c208add`, which contains `9df76c4`). The local `Package.resolved` already resolves Router `c208add` and mlx-swift-lm `stable` `a1f77ad`. `Package.resolved` is in `.gitignore`, so there is nothing to commit for the pin. If a clean checkout resolves an older Router, run `swift package update FoundationModelsRouter mlx-swift-lm`.

Upstream commit `2f4707f` already did these items: `MultiToolConfiguration.defaultExecutionTimeLimit`, `innerCallMount`'s explicit timeout, `.synchronousUnbounded` → `.synchronous`, `wait(seconds: Double?)`, and `SessionEvent.generationCall`.

This task makes `swift build` pass (library targets only). The test target is the next task.
- [ ] `Sources/FoundationModelsMultitool/MultiTool+TurnBoundary.swift`: rename the file to `MultiTool+SubmissionBoundary.swift`. Change `TurnBoundaryTool` / `turnWillBegin()` to `SubmissionBoundaryTool` / `submissionWillBegin()`. The doc comment must say that the Router calls the hook before each submission, and a continuation of the same answer is a submission too.
- [ ] Update the comment sites that name the old hook or old Router names: `Capabilities/MCP/SurfaceRefresher.swift`, `RegistryHolder.swift`, `MultiTool.swift` (2), `MultiTool+Forking.swift`, and `MultiToolConfiguration.swift` (`ToolMount.defaultTimeoutSeconds` in the `executionTimeLimit` doc).
- [ ] `Sources/MultitoolCLI/CLIRunner.swift`: make the `SessionEvent` switch compile. Change `.turnStarted` / `.turnEnded` to the new cases (`submissionQueued`, `submissionStarted`, `submissionEnded`, `answered`, `answerFailed`, `repetitionStopped`), and put them in the current no-op arm for now. The CLI answer task makes them correct.
- [ ] Fix each other compile error that `swift build` reports against Router `c208add`. Record the list in a task comment.

## Acceptance Criteria
- [ ] `swift build` passes with no errors and no new warnings.
- [ ] `rg -w 'TurnBoundaryTool|turnWillBegin|turnStarted|turnEnded|defaultTimeoutSeconds' Sources` returns no match.

## Tests
- [ ] Run `swift build`. Expected result: exit 0. The next task compiles and runs the tests.

## Workflow
- Use `/tdd` where a test target can compile. Otherwise make the smallest change that compiles.