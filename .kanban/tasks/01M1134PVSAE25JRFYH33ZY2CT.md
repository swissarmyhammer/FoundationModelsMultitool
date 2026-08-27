---
assignees:
- claude-code
position_column: todo
position_ordinal: '9480'
title: 'Pin the plain-Tool contract: files verbs on a bare LanguageModelSession'
---
## What
The six files verbs (`Read`, `Write`, `Edit`, `Patch`, `Glob`, `Grep`) take a `FileContext` at construction and never read `ToolContext.current`. Thus they already work on a bare `LanguageModelSession` with no Router. No test pins that. Add the pin, so a later change that reads the ambient context in a files verb fails a test instead of breaking bare-session hosts in silence.

- Add `Tests/FoundationModelsMultitoolTests/PlainToolContractTests.swift`: for each of the six verbs, construct it through `FilesCapability(root:)`, call `call(arguments:)` directly with no bound `ToolContext`, and assert the in-band result (a read returns content; a write creates the file; a path outside the root returns the corrective text, and it does not throw).
- Add one reflective case: no file under `Sources/FoundationModelsMultitool/Capabilities/Files/` contains the string `ToolContext.current`. Read the folder with `#filePath`, the way the golden tests do. This is the cheap guard; the doc comment states why it exists.
- Add a gated case in `IntegrationTests/`: mount `FilesCapability(root:).tools` on `LanguageModelSession(model: .default, tools:)` with no Router, prompt the model to read a seeded file, and assert the answer carries its content.
- No production change is expected. If a verb turns out to read the context, that is a finding: record it as a comment on this task and correct it here only if the correction is one line; otherwise make a new task.

## Acceptance Criteria
- [ ] Each of the six verbs answers correctly with no `ToolContext` bound.
- [ ] The reflective case passes: no `ToolContext.current` in `Capabilities/Files/`.
- [ ] The gated bare-session case passes on hardware.
- [ ] `swift build` succeeds.

## Tests
- [ ] `swift test --filter PlainToolContractTests` passes.
- [ ] Full `swift test` passes.

## Workflow
- Use `/tdd` — the tests are the deliverable; write them, run them, and record the result. #eventplan #phase-4