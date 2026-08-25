---
assignees:
- claude-code
depends_on:
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8880'
title: Port GlobEngine, and make the tools.files.glob verb
---
## What
Port `GlobEngine`, and make the first Files verb. `FileWalker` is NOT in this task: it is one reference cycle with `FileContext` and `FileChangeJournal`, so the FileContext task ports it.

- Sources: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/GlobEngine.swift` and `.../Operations/GlobFiles.swift`
- Targets: `Sources/FoundationModelsMultitool/Capabilities/Files/GlobEngine.swift` and `.../Glob.swift`

`GlobEngine` is a behavioral port over the already-ported `FileWalker`. `Glob.swift` is a rewrite of the `@Operation` struct `GlobFiles` as a plain `FoundationModels.Tool` conformer, in the pattern of `Capabilities/Shell/GetLines.swift`:
- `struct Glob: Tool` with `name = "glob"`. The capability supplies the noun, so the path renders as `tools.files.glob`.
- A `@Generable` arguments struct with a `@Guide` on each parameter: `pattern`, `path`, `caseSensitive`, `respectGitIgnore`.
- The `@OperationParam` aliases (`file_path`, `absolute_path`) do not port. Plain `@Generable` arguments keep only the canonical names.
- A flat `@Generable` result with a `correction` field, in the Shell pattern: the matches and the correction are exclusive.
- The verb holds its `FileContext` as a constructor dependency, as the Shell verbs hold `ShellState`.
- The doc comment carries the full behavioral contract and one example snippet, per eventplan.md § "Registration of capabilities: noun/verb".

## Acceptance Criteria
- [ ] The glob results agree with the source: newest first, capped, git-aware when `respectGitIgnore` is on, bounded through `PathGuard`.
- [ ] A bad pattern, a broad pattern with no path, a bad path, and a missing directory each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `GlobFilesTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesGlobTests.swift`, adapted to the `Tool` call shape.
- [ ] `swift test --filter FilesGlobTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan