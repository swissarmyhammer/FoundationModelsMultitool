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
position_column: doing
position_ordinal: '80'
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