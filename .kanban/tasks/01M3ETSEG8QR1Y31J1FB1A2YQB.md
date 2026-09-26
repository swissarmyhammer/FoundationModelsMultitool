---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3femrh3xf45w5whe6sa1z3c
  text: |-
    ### implement — changed
    Compile errors that `swift build` reported against Router `c208add`:
    1. `MultiTool+TurnBoundary.swift:25` — cannot find type `TurnBoundaryTool`. Fix: rename the file to `MultiTool+SubmissionBoundary.swift` and conform to `SubmissionBoundaryTool` / `submissionWillBegin()`.
    2. `CLIRunner.swift:1034` — switch must be exhaustive: `.turnStarted` / `.turnEnded` are gone, and `.mailDeliveryPaused(_)` is a new case. Fix: put `submissionQueued`, `submissionStarted`, `submissionEnded`, `answered`, `answerFailed` and `mailDeliveryPaused` in the no-op arm. `repetitionStopped` already has its own arm, so it is not in the no-op arm (the compiler gave "case is already handled").
    No other compile error.

    Comment sites changed: SurfaceRefresher.swift, RegistryHolder.swift, MultiTool.swift (2 hook names, 3 "turn boundary", 1 file name), MultiTool+Forking.swift, MultiToolConfiguration.swift (no `ToolMount.defaultTimeoutSeconds`), SearchToolsTool.swift (2 "turn boundary"). Quotes from eventplan.md stay as they are.

    Discovery: `SearchToolsTool.swift:336-356` and `CLIRunner.swift:464` name `turnLock` and `generationGate`, which Router `c208add` does not have. These comments are about the same-model deadlock; card ^zhmqvxb owns that subject, so this task does not change them.

    Evidence: `swift build` → "Build complete!", exit 0. The only warning is the mlx `missing creator for mutated node` warning, which was there before this change. `rg -w 'TurnBoundaryTool|turnWillBegin|turnStarted|turnEnded|defaultTimeoutSeconds' Sources` → no match.
  timestamp: 2026-09-26T18:11:37.635868+00:00
position_column: doing
position_ordinal: '80'
title: Make the library targets build against the work-queue Router (c208add)
---
## What
FoundationModelsRouter replaced turns with a per-session message queue and one generation queue for each model (design `../FoundationModelsRouter/generation-queue.md` §5.5, §5.6, §5.10). Router `main` is pushed (`c208add`, which contains `9df76c4`). The local `Package.resolved` already resolves Router `c208add` and mlx-swift-lm `stable` `a1f77ad`. `Package.resolved` is in `.gitignore`, so there is nothing to commit for the pin. If a clean checkout resolves an older Router, run `swift package update FoundationModelsRouter mlx-swift-lm`.

Upstream commit `2f4707f` already did these items: `MultiToolConfiguration.defaultExecutionTimeLimit`, `innerCallMount`'s explicit timeout, `.synchronousUnbounded` → `.synchronous`, `wait(seconds: Double?)`, and `SessionEvent.generationCall`.

This task makes `swift build` pass (library targets only). The test target is the next task.
- [x] `Sources/FoundationModelsMultitool/MultiTool+TurnBoundary.swift`: rename the file to `MultiTool+SubmissionBoundary.swift`. Change `TurnBoundaryTool` / `turnWillBegin()` to `SubmissionBoundaryTool` / `submissionWillBegin()`. The doc comment must say that the Router calls the hook before each submission, and a continuation of the same answer is a submission too.
- [x] Update the comment sites that name the old hook or old Router names: `Capabilities/MCP/SurfaceRefresher.swift`, `RegistryHolder.swift`, `MultiTool.swift` (2), `MultiTool+Forking.swift`, and `MultiToolConfiguration.swift` (`ToolMount.defaultTimeoutSeconds` in the `executionTimeLimit` doc).
- [x] `Sources/MultitoolCLI/CLIRunner.swift`: make the `SessionEvent` switch compile. Change `.turnStarted` / `.turnEnded` to the new cases (`submissionQueued`, `submissionStarted`, `submissionEnded`, `answered`, `answerFailed`, `repetitionStopped`), and put them in the current no-op arm for now. The CLI answer task makes them correct.
- [x] Fix each other compile error that `swift build` reports against Router `c208add`. Record the list in a task comment.

## Acceptance Criteria
- [x] `swift build` passes with no errors and no new warnings.
- [x] `rg -w 'TurnBoundaryTool|turnWillBegin|turnStarted|turnEnded|defaultTimeoutSeconds' Sources` returns no match.

## Tests
- [x] Run `swift build`. Expected result: exit 0. The next task compiles and runs the tests.

## Workflow
- Use `/tdd` where a test target can compile. Otherwise make the smallest change that compiles.