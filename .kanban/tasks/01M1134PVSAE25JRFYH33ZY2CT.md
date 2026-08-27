---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11w7av39j2epn3n0jqwag4f
  text: |-
    ### research
    - The six files verbs (`Read`, `Write`, `Edit`, `Patch`, `Glob`, `Grep`) hold a `FileContext` and read no `ToolContext.current`. A grep of `Sources/FoundationModelsMultitool/Capabilities/Files/` for `ToolContext.current` finds no line. The ambient context is read only in `Capabilities/Shell/Execute.swift`, `Invocation/RunBinding.swift`, `MultiTool.swift` and `WaitTool.swift`.
    - `FilesCapability(root:)` makes one `FileContext` and puts the six verbs in `tools: [any Tool]`. A test finds each verb in that array by its concrete type and calls `call(arguments:)` on it.
    - `RepositoryFile.swiftFiles(inRelativeDirectory:)` walks a directory of the repository through `#filePath`; the reflective case reads the Files folder through it.
    - `ShellPermissionRemovalTests` holds a private line scan of the same shape the reflective case needs. The scan moves into `RepositoryFile` as a shared helper; the new case calls it.
    - The gated case follows `IntegrationTests/.../ShellBareSessionTests.swift`. The shared part (model guard, session, respond, assert) moves into `Support/BareSessionScenario.swift`, and both bare-session suites call it.
    - No production change is expected.
  timestamp: 2026-08-27T15:08:12.003805+00:00
- actor: claude-code
  id: 01m11wfp7xew5qnjj3k9859qc5
  text: |-
    ### implement — changed
    - evidence: 6 files — Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift (new, 13 cases: two per verb and one reflective guard), Tests/FoundationModelsMultitoolTests/RepositoryFile.swift (shared `sightings(of:inRelativeDirectory:excluding:)`, `sightings(of:inRelativeFile:)`, `relativePath(of:)`), Tests/FoundationModelsMultitoolTests/ShellPermissionRemovalTests.swift (calls the shared scan), IntegrationTests/.../Support/BareSessionScenario.swift (new, `runBareSessionScenario` and `bareSessionTimeLimitMinutes`), IntegrationTests/.../FilesBareSessionTests.swift (new gated case), IntegrationTests/.../ShellBareSessionTests.swift (calls the shared scenario).
    - `swift test --filter PlainToolContractTests`: 13 tests in 1 suite passed. Full `swift test`: 1216 tests in 88 suites passed. `swift build --package-path IntegrationTests --build-tests`: build complete. On this machine the gated cases also ran: `FilesBareSessionTests` passed in 4.9 s (reply `1:b9|pelican`), `ShellBareSessionTests` passed in 4.0 s.
    - No production change. No verb reads the ambient context; the reflective case found no sighting.
    - next: /test, /commit, /review
  timestamp: 2026-08-27T15:12:45.821170+00:00
- actor: claude-code
  id: 01m11x17ty85462s4b3ec4jv4w
  text: |-
    ### review — findings
    - evidence: 4 findings — Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift:77, :94, :102, :111 (review sha HEAD~1..HEAD; counts findings 4, confirmed 4, refuted 4)
    - next: /implement corrects the four findings, then /test, /commit, /review
  timestamp: 2026-08-27T15:22:20.894343+00:00
- actor: claude-code
  id: 01m11x1ak5026kgfv5je9vnaz9
  text: |-
    ### finish iteration 1 — review found 4 findings
    - implement: changed — 6 files (PlainToolContractTests.swift, RepositoryFile.swift, ShellPermissionRemovalTests.swift, Support/BareSessionScenario.swift, FilesBareSessionTests.swift, ShellBareSessionTests.swift)
    - test: green — swift test 1216 passed, 0 failed, 0 skipped; IntegrationTests package builds; both gated bare-session cases passed on this machine
    - commit: d9a765b
    - review: findings — PlainToolContractTests.swift:77 swift/fluent-usage, :94 swift/fluent-usage, :102 swift/fluent-usage, :111 reuse/reuse
  timestamp: 2026-08-27T15:22:23.717052+00:00
- actor: claude-code
  id: 01m11xb49evqgcmt06th8fgfrc
  text: |-
    ### implement — changed
    - evidence: 4 files — Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift (`seed(in:)`, `verb(of:in:)`, `expectOutsideRoot(correction:)`; the private `text(at:)` is gone), Tests/FoundationModelsMultitoolTests/TestSupport.swift (shared `readBytes(at:)` and `text(at:)`), Tests/FoundationModelsMultitoolTests/FilesEditTests.swift and FilesWriteTests.swift (the private `readBytes(_:)` copies are gone; each call goes to `TestSupport.readBytes(at:)`).
    - Each of the four review findings of 2026-08-27 10:14 is corrected: the three unlabeled first parameters carry labels, and the file-reading logic stands in `TestSupport` one time.
    - `swift build --build-tests`: no compiler warning. `swift test`: 1216 tests in 88 suites passed.
    - next: /test, /commit, /review
  timestamp: 2026-08-27T15:27:44.942582+00:00
- actor: claude-code
  id: 01m11xgn1jqnn7qj7bghc9zced
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (3b530d8) — counts findings 0, confirmed 0, refuted 0; 4 files reviewed. The four findings of 2026-08-27 10:14 are corrected in 3b530d8 and checked.
    - next: task moves to done
  timestamp: 2026-08-27T15:30:45.938054+00:00
- actor: claude-code
  id: 01m11xgph3cn7ykpdxhsa9w8x5
  text: |-
    ### finish iteration 2 — review clean
    - implement: changed — 4 files (PlainToolContractTests.swift, TestSupport.swift, FilesEditTests.swift, FilesWriteTests.swift); the four findings of iteration 1 corrected
    - test: green — swift test 1216 passed, 0 failed, 0 skipped; swift build --build-tests no compiler warning
    - commit: 3b530d8
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-08-27T15:30:47.459367+00:00
position_column: done
position_ordinal: ff9380
title: 'Pin the plain-Tool contract: files verbs on a bare LanguageModelSession'
---
## What
The six files verbs (`Read`, `Write`, `Edit`, `Patch`, `Glob`, `Grep`) take a `FileContext` at construction and never read `ToolContext.current`. Thus they already work on a bare `LanguageModelSession` with no Router. No test pins that. Add the pin, so a later change that reads the ambient context in a files verb fails a test instead of breaking bare-session hosts in silence.

- Add `Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift`: for each of the six verbs, construct it through `FilesCapability(root:)`, call `call(arguments:)` directly with no bound `ToolContext`, and assert the in-band result (a read returns content; a write creates the file; a path outside the root returns the corrective text, and it does not throw).
- Add one reflective case: no file under `Sources/FoundationModelsMultitool/Capabilities/Files/` contains the string `ToolContext.current`. Read the folder with `#filePath`, the way the golden tests do. This is the cheap guard; the doc comment states why it exists.
- Add a gated case in `IntegrationTests/`: mount `FilesCapability(root:).tools` on `LanguageModelSession(model: .default, tools:)` with no Router, prompt the model to read a seeded file, and assert the answer carries its content.
- No production change is expected. If a verb turns out to read the context, that is a finding: record it as a comment on this task and correct it here only if the correction is one line; otherwise make a new task.

## Acceptance Criteria
- [x] Each of the six verbs answers correctly with no `ToolContext` bound.
- [x] The reflective case passes: no `ToolContext.current` in `Capabilities/Files/`.
- [x] The gated bare-session case passes on hardware.
- [x] `swift build` succeeds.

## Tests
- [x] `swift test --filter PlainToolContractTests` passes.
- [x] Full `swift test` passes.

## Workflow
- Use `/tdd` — the tests are the deliverable; write them, run them, and record the result. #eventplan #phase-4

## Review Findings (2026-08-27 10:14)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift:77` `swift/fluent-usage` — The first parameter of `seed(_:)` is unlabeled, but this is not a value-preserving conversion. The parameter should be labeled to form a clear phrase at the call site. Change `seed(_ directory: URL)` to `seed(directory: URL)` or `seed(in directory: URL)` to make calls like `Self.seed(directory: root)` read more fluently.
- [x] `Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift:94` `swift/fluent-usage` — The first parameter of `verb<Verb:Tool>(_:root:)` is unlabeled, but this is not a value-preserving conversion. The parameter should be labeled to form a clear phrase at the call site. Change `verb<Verb: Tool>(_ type: Verb.Type, root: URL)` to `verb<Verb: Tool>(of type: Verb.Type, in root: URL)` or similar to make calls read: `Self.verb(of: Read.self, in: root)`.
- [x] `Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift:102` `swift/fluent-usage` — The first parameter of `expectOutsideRoot(_:)` is unlabeled, but this is not a value-preserving conversion. The parameter should be labeled to form a clear phrase at the call site. Change `expectOutsideRoot(_ correction: String?)` to `expectOutsideRoot(correction: String?)` to make calls read: `Self.expectOutsideRoot(correction: result.correction)`.
- [x] `Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift:111` `reuse/reuse` — The `text` function implements generic file-reading logic (load bytes, decode as UTF-8) that is already duplicated across multiple test files. FilesEditTests and FilesWriteTests both define `readBytes()` with identical semantics (0.89 similarity). This utility belongs in TestSupport, not scattered across test classes. Move this function to TestSupport as a shared utility (e.g., `TestSupport.text(at path:)` or `TestSupport.readFileAsText(at:)`). Update all test classes (FilesEditTests, FilesWriteTests, and PlainToolContractTests) to call this single version rather than maintaining parallel copies.

## Review Findings (2026-08-27 10:27)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)