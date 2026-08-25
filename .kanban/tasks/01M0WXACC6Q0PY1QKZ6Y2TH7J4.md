---
assignees:
- claude-code
position_column: todo
position_ordinal: '9180'
title: Port TestSupport and PathContainmentTests into the test target
---
## What
Port the shared test support into the test target. Ten of the ported test files use it, so this task comes first.

- Sources: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/TestSupport.swift` and `.../PathContainmentTests.swift`
- Targets: the same file names in `Tests/FoundationModelsMultitoolTests/`

`PathContainmentTests` tests `TestSupport.path(candidate:isContainedBy:)`, not `PathGuard`. Thus it belongs to this task, not to the PathGuard task.

Keep `makeTemporaryDirectory` and the path-containment helper. Remove the helpers that serve only the excluded suites (DocC coverage, README snippets, the fused-tool dispatch) when no ported test needs them.

## Acceptance Criteria
- [ ] The test target compiles with the ported `TestSupport`.
- [ ] The ported file references none of the excluded types (`DiagnosticsBridge`, `FileDiagnostics`, the fused `FileTool`).

## Tests
- [ ] `swift test --filter PathContainmentTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the support to make them pass. #phase-3 #eventplan