---
assignees:
- claude-code
depends_on:
- 01M2N24ZEPMS79PQH5B58FF2SF
position_column: todo
position_ordinal: '8680'
title: 'Live integration: a real @Operation tool is found and called through runCode'
---
## What

Prove the feature with a real Extras operation tool and a real model, in the nested integration package. The unit tests use a hand-conformed fixture; this card uses the macros and `OperationTool` itself.

In `IntegrationTests/Package.swift`, add the `FoundationModelsExtras` package dependency (`git@github.com:swissarmyhammer/FoundationModelsExtras.git`, branch `main`, the same form the root manifest uses) and link its `Operations` product in the test target. The root package does not change.

Add `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/IntegrationNotesOperationTool.swift`: five `@Generable @Operation` structs (`add note`, `get note`, `list note`, `delete note`, `tag note`) over an in-memory actor store, fused with `OperationTool(name: "notes", ...)`. Model it on `../FoundationModelsExtras/Examples/NotesTool/Sources/NotesToolCore`, but keep it local; do not depend on the example target.

Add `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OperationToolLiveTests.swift` with two tests, gated and paced like `SearchThenCallTests.swift` and `HeldOutSurfaceDiscoveryTests.swift`:

1. Discovery. Mount the notes tool beside the `FilesAndShellSurface` distractors. Grade `GradedDiscoveryQuery` literals such as `add a note titled Groceries` (correct: `notes.addNote`), `put the tag urgent on note-2` (correct: `notes.tagNote`), `how many notes are there` (correct: `notes.listNote`). Use `gradeDiscoveryRounds` and `expectEveryQueryFindsACorrectPath`.
2. Search then call. Prompt: `Add a note titled Groceries with the body milk and eggs, then tag it shopping, and tell me its id.` Assert through the scenario call log that the model called `searchTools` then one `runCode`, that the store holds one note with title `Groceries` and tag `shopping`, and that the answer names the id.

## Acceptance Criteria

- [ ] `swift build --package-path IntegrationTests` passes with the new dependency.
- [ ] The discovery test finds a correct verb path for every query in every round.
- [ ] The search-then-call test leaves the store with the one expected note and returns its id.
- [ ] The unit package `swift test` is unchanged and still passes.

## Tests

- [ ] The two tests above.
- [ ] Run `swift test --package-path IntegrationTests --no-parallel --filter OperationToolLiveTests`; expect all pass on a machine with the live model.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools