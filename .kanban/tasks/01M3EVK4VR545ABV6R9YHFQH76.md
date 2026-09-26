---
assignees:
- claude-code
depends_on:
- 01M3ETSEG8QR1Y31J1FB1A2YQB
position_column: todo
position_ordinal: '8780'
title: Make the unit test target build and pass against the work-queue Router
---
## What
After the library task, `swift build --build-tests` can still fail in `Tests/FoundationModelsMultitoolTests` against Router `c208add`. Upstream commit `2f4707f` already gave the stub container a `TokenCounter` (`StubWordTokenCounter`) and the stub metadata `max_position_embeddings`, and it already changed the timeout and mount names in the tests.
- [ ] In `RegistrySwapTests.swift` (9 uses) and `SurfaceRefresherTests.swift` (10 uses), replace `turnWillBegin()` with `submissionWillBegin()`. In `MCPSessionSweepTests.swift`, change the `cancelCurrentTurn()` reference to `cancel()`.
- [ ] `submissionWillBegin()` now also runs between continuation submissions of one answer (compaction yield, rejected tool call, repetition recovery). So a staged registry can be applied in the middle of an answer. Add a test for this.
- [ ] Fix each other compile error or test failure that `swift build --build-tests && swift test` reports against Router `c208add`. Record the list in a task comment.

## Acceptance Criteria
- [ ] `swift build --build-tests` passes with no errors and no new warnings.
- [ ] `swift test` passes.
- [ ] `rg -w 'turnWillBegin|TurnBoundaryTool|cancelCurrentTurn' Tests` returns no match.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/RegistrySwapTests.swift`: stage a registry that removes a verb, call `submissionWillBegin()` between two calls of one answer, and check that a later `runCode` call to the removed verb gives a repairable tool error (the unknown-verb hint), not a crash.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.