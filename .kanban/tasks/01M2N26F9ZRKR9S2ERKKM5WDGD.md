---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2nkxezmcpy98fgyaer7jj0t
  text: |-
    Picked up. Research:

    - The root package expands an `OperationDescribing` tool into one `OperationVerbTool` for each descriptor (`Sources/FoundationModelsMultitool/Surface/RegistrySource.swift`). A standalone `addTool(operationTool)` puts the verbs under the tool name, thus `OperationTool(name: "notes", ...)` gives `notes.addNote`, `notes.getNote`, `notes.listNote`, `notes.deleteNote`, `notes.tagNote`.
    - `OperationTool` conforms to `OperationDescribing` since Extras commit 1c703ee. The root `Package.resolved` pins Extras at c98ae6b. The nested `IntegrationTests/Package.resolved` (git-ignored) pins Extras at 8b4706d, which is before `OperationDescribing` exists. The nested package must resolve Extras again after the manifest change.
    - `makeFilesAndShellSurface(over:)` builds the nine-entry distractor surface. The discovery test needs the notes tool beside it, thus the helper gets a defaulted `adding tools:` parameter. Callers: `AgentSurfaceDiscoveryTests`, `HeldOutSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests`, `UnknownToolHintLiveTests`; a default keeps them unchanged.
    - `ScenarioCallLog` records fixture tool calls only. `searchTools` and `runCode` are session tools, and the runner records their calls in `StreamedTurn.calls`. The search-then-call assertion reads the route off `StreamedTurn.calls` with `NativeTranscript.searchToolsPrecedesRunCode(in:)` and a `runCode` count.
    - `makeScenarioSurface(over:on:)` and `ScenarioSurface` in `Support/ScenarioRunner.swift` are `private`. The search-then-call test mounts a registry the same way, thus the two become internal instead of a copy.
    - The `Operations` module re-exports `ArgumentParser`; the `@Operation` macro makes a `Command` for each struct. The example `NotesToolCore` shows the shape: `@Generable @Operation(verb:noun:description:)` struct, `execute(in:) -> Encodable`, an actor store, a `Sendable` context struct.
  timestamp: 2026-09-16T17:23:30.420950+00:00
- actor: claude-code
  id: 01m2nm6nzg0e664fam8txq9mt7
  text: 'Discovery: the nested package did not build before this card. `swift build --package-path IntegrationTests --build-tests` on a clean `.build` failed with `cannot find type ''OperationDescribing'' in scope` (and `OperationDescriptor`, `OperationParameterDescriptor`, `OperationParameterType`) in the root sources it compiles. Cause: the git-ignored `IntegrationTests/Package.resolved` pinned FoundationModelsExtras at 8b4706d, and the descriptor types arrive in 1a62f5f. Fix: `swift package --package-path IntegrationTests update FoundationModelsExtras`, which moves the nested pin to the head of `main` (c98ae6b or later). The root `Package.resolved` is not changed. A CI machine with no nested `Package.resolved` resolves the head of `main` and does not see this.'
  timestamp: 2026-09-16T17:28:32.496543+00:00
- actor: claude-code
  id: 01m2nnty7en5wskwhp65sdv9kv
  text: |-
    Implementation landed, with `/tdd`.

    RED: the manifest change, the two support edits and `OperationToolLiveTests.swift` went in first. `swift build --package-path IntegrationTests --build-tests` failed on the missing fixture types only (`cannot find 'IntegrationNotesTool'`, `IntegrationNotesStore`, `IntegrationNote`).

    GREEN: `Fixtures/IntegrationNotesOperationTool.swift` — five `@Generable @Operation` structs, an `actor` store, a `Sendable` context and the `IntegrationNotesTool.make(store:)` factory over `OperationTool(name: "notes", ...)`. The build completed with zero errors and zero new warnings (the one `missing creator for mutated node` warning is in the baseline build too).

    Files:
    - `IntegrationTests/Package.swift`: Extras dependency on `main`, `Operations` product linked. Only that product; no file names a symbol of the core `FoundationModelsExtras` module.
    - `IntegrationTests/Tests/.../Fixtures/IntegrationNotesOperationTool.swift` (new).
    - `IntegrationTests/Tests/.../OperationToolLiveTests.swift` (new): the discovery test and the search-then-call test.
    - `IntegrationTests/Tests/.../Support/FilesAndShellSurface.swift`: `makeFilesAndShellSurface(over:adding:)` gets a defaulted `adding tools:` parameter; the four callers are unchanged.
    - `IntegrationTests/Tests/.../Support/ScenarioRunner.swift`: `ScenarioSurface` and `makeScenarioSurface(over:on:direct:)` are internal, not private, so the search-then-call test mounts a registry the same way as every scenario and holds no copy.

    Design notes:
    - The discovery queries are the three the card names plus `attach a label to a note` (`notes.tagNote`) and `show every note` (`notes.listNote`).
    - The route assertion reads `StreamedTurn.calls`, the record `streamTurn` keeps of every session tool call. `ScenarioCallLog` holds fixture tool calls only; `searchTools` and `runCode` are session tools, so the turn stream is where they are recorded. The suite doc comment says so.
    - The reply is graded against the id the store really gave (`stored.map(\.id)`), never a literal.
    - Both tests resolve `multitoolTinyProfile`, the shipped profile, because both grade a capability claim.

    Live run (`swift test --package-path IntegrationTests --no-parallel --filter OperationToolLiveTests`): 2 tests in 1 suite passed after 156.9 s.
    - Discovery: 14 entries in the catalog; rounds 1, 2 and 3 each scored correctTotal=5 wrongTotal=0, one exact verb path for each of the five queries. Test passed after 111.7 s.
    - Search then call: calls=["searchTools", "runCode", "wait"]; one snippet `tools.notes.addNote({ title: "Groceries", body: "milk and eggs", tags: ["shopping"] })`; stored=["note-1 \"Groceries\" [\"shopping\"]"]; reply names `note-1`. SCENARIO result=PASS, all four checks pass. Test passed after 45.2 s. The model put the tag on the `addNote` call instead of a second `tagNote` call, which the card permits: one `runCode`, the store holds the note with the tag.

    Root unit package: `swift test` — 1502 tests in 120 suites passed after 12.0 s. No root file changed.
  timestamp: 2026-09-16T17:57:04.878488+00:00
- actor: claude-code
  id: 01m2nnv1ygyf960jpyc8fndvj1
  text: |-
    ### implement — changed
    - evidence: 5 files — IntegrationTests/Package.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/IntegrationNotesOperationTool.swift (new), IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OperationToolLiveTests.swift (new), IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/FilesAndShellSurface.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift. `swift build --package-path IntegrationTests --build-tests`: Build complete. `swift test --package-path IntegrationTests --no-parallel --filter OperationToolLiveTests`: 2 tests in 1 suite passed (156.9 s). Root `swift test`: 1502 tests in 120 suites passed.
    - next: `/review`. Not committed.
  timestamp: 2026-09-16T17:57:08.688223+00:00
depends_on:
- 01M2N24ZEPMS79PQH5B58FF2SF
position_column: doing
position_ordinal: '80'
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

- [x] `swift build --package-path IntegrationTests` passes with the new dependency.
- [x] The discovery test finds a correct verb path for every query in every round.
- [x] The search-then-call test leaves the store with the one expected note and returns its id.
- [x] The unit package `swift test` is unchanged and still passes.

## Tests

- [x] The two tests above.
- [x] Run `swift test --package-path IntegrationTests --no-parallel --filter OperationToolLiveTests`; expect all pass on a machine with the live model.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools