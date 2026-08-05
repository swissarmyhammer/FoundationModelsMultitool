---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: '[Router] Move event vocabulary into Hosting/'
---
Repo: ../FoundationModelsRouter (changes there; this board tracks the cross-repo phase). Basis: eventplan.md §"The vocabulary and the host substrate are in Router" and §"Phases" phase 1.

## What
Mechanical move of the event vocabulary from `../FoundationModelsOperationTool/Sources/Operations/` into a new `Sources/FoundationModelsRouter/Hosting/` folder. The Router target uses `path: "Sources/FoundationModelsRouter"` with no `sources:` list, so no manifest target change is needed. Move these files verbatim, doc comments intact:
- `OperationEvent.swift` — `OperationEventKind {progress, completed}` plus `OperationEvent`; the terminal-event scope contract doc (lines 1–13) moves without change.
- `OperationOutcome.swift` — including the unknown-preserving `.other(String)` decoder.
- `OperationEventSink.swift`
- `EventEmittingTool.swift` (imports FoundationModels)
- `ForkableTool.swift` (Router's fork composition at RoutedSession.swift:1905 calls `forked()`, so it must move for Router to drop the import)

Then remove `import Operations` from the 5 Router source files that have it (`Session/SessionOutbox.swift`, `Session/OperationEventSegment.swift`, `Session/RoutedSession.swift`, `RoutedLLM.swift`, `Recording/SessionTreeRestoration.swift`) and from the 7 test files (`SessionOutboxToolWiringTests`, `SessionTreeRestorationToolWiringTests`, `SessionOutboxTests`, `PendingEventInjectionTests`, `PromptQueueTests`, `TurnCancellationTests`, `ToolOutputCappingTests`). Delete `operationsProduct` and the `FoundationModelsOperationTool` package dependency from Router's `Package.swift`.

Port the vocabulary unit tests into `Tests/FoundationModelsRouterTests/`: `OperationOutcomeTests.swift` and the codable/connecting tests from `EventEmittingToolTests.swift` (drop `OperationTool`-specific fixtures; those stay behind).

Do NOT move `EventEmittingContext.swift` or `ForkableContext.swift` — Router does not use them; they stay in Operations and will compile against the shim typealiases (next task).

Commit and push to Router `main` when green — the shim task and MultiTool tasks resolve Router by git branch `main`.

## Acceptance Criteria
- [ ] `grep -r "import Operations"` over ../FoundationModelsRouter/Sources and /Tests returns nothing
- [ ] Router `Package.swift` has no FoundationModelsOperationTool dependency
- [ ] `Hosting/` contains the five files with unchanged public symbol names and doc comments (terminal-event contract text preserved verbatim)
- [ ] `cd ../FoundationModelsRouter && swift build && swift test` green

## Tests
- [ ] Ported `OperationOutcomeTests` in Tests/FoundationModelsRouterTests (raw-value round trips, unknown string → `.other` without throwing, bare-JSON-string encoding) pass
- [ ] Ported `OperationEvent` codable tests (outcome `decodeIfPresent` back-compat case included) pass
- [ ] `cd ../FoundationModelsRouter && swift test` — all suites green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first