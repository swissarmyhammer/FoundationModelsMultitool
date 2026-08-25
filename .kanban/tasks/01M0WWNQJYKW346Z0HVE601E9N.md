---
assignees:
- claude-code
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '80'
title: Port PathGuard and PathCorrective into Capabilities/Files
---
## What
Port `PathGuard` and `PathCorrective` from the FileTool package into this package. This is a behavioral port: keep the logic the same, and write new header comments in the style of `Capabilities/Shell` (see `ShellCapability.swift` and `GetLines.swift`).

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/PathGuard.swift` and `.../PathCorrective.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift` and `.../PathCorrective.swift`

Refer to eventplan.md § "Consolidation of the siblings": the Files capability gets "`PathGuard` root bounds", and corrective results (a path outside the root) stay in-band, never thrown.

Note on the tests: `PathGuardTests.swift` lines 510 and 518 construct a `FileContext`, which this task does not have yet. Move those two cases to the FileContext task. Do not port them here.

## Acceptance Criteria
- [ ] `PathGuard` bounds each path to the root and to the additional roots, with the same rules as the source (symlink policy included).
- [ ] A path outside the root gives a corrective message in-band. It does not throw.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `PathGuardTests.swift` (without the two `FileContext` cases at source lines 510 and 518) and `PathCorrectiveTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter PathGuardTests` passes.
- [ ] `swift test --filter PathCorrectiveTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass.