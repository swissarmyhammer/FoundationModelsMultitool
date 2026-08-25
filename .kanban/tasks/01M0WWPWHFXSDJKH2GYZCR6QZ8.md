---
assignees:
- claude-code
depends_on:
- 01M0WWNQJYKW346Z0HVE601E9N
- 01M0WWP84DQAHJXYF04DRTZX60
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8580'
title: Port FileContext, FileChangeJournal, and FileWalker together, without diagnostics
---
## What
Port `FileContext`, `FileChangeJournal`, and `FileWalker` from the FileTool package into this package, in one task. The three types are one reference cycle: `FileContext` holds a `FileChangeJournal`; `FileChangeJournal` calls `FileWalker.canonicalDirectory` (source line 64); `FileWalker.boundDirectory(_:in:)` takes a `FileContext` (source lines 229 and 248). No smaller split builds. Also port the corrective vocabulary in the same task.

- Sources, all in `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/`: `FileContext.swift`, `FileChangeJournal.swift`, `FileWalker.swift`, `CorrectiveResult.swift`, `CorrectiveEncodable.swift`, `EnumParameter.swift`
- Targets: the same file names in `Sources/FoundationModelsMultitool/Capabilities/Files/`

Changes to `FileContext` in the port:
- Remove the `diagnostics` property, the `DiagnosticsBridge` initializer parameter, and the `eagerWarmup` parameter. Decision 2026-08-11 in eventplan.md: the capability does not get `DiagnosticsBridge` or `FileDiagnostics`, and it does not add the FoundationModelsCodeContext dependency.
- Remove `stop()` if nothing needs teardown after the bridge is gone. Confirm `FileChangeJournal` needs no teardown.
- Keep `root`, `pathGuard`, `readOnly`, and `changes` as constructor dependencies. eventplan.md § "We remove OperationTool": "Typed per-capability contexts (`ShellContext`, `FileContext`) stay as usual constructor dependencies."
- Do NOT port `DiagnosticsBridge.swift`, `FileDiagnostics.swift`, or `NullEmbedder.swift`.

## Acceptance Criteria
- [ ] `FileContext` holds `root`, `pathGuard`, `readOnly`, and `changes` only.
- [ ] No file under `Sources/FoundationModelsMultitool/Capabilities/Files/` names `DiagnosticsBridge`, `FileDiagnostics`, or `FoundationModelsCodeContext`.
- [ ] The corrective vocabulary renders the same messages as the source (`EnumParameter.nameList`, `unknownValueMessage`).
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `FileContextTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`. Remove the cases that test the diagnostics seam. Keep the cases for the guard, the read-only flag, and the journal wiring.
- [ ] Port the two `FileContext` cases from `PathGuardTests.swift` (source lines 510 and 518) into the ported `FileContextTests.swift`.
- [ ] `swift test --filter FileContextTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan