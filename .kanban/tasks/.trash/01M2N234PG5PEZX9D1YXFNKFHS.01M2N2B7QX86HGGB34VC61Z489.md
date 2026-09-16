---
assignees:
- claude-code
depends_on:
- 01M2N22DCHSHQEWZT1Z28C4ZXY
position_column: todo
position_ordinal: '8180'
title: 'Extras: conform OperationTool to OperationDescribing with a throwing perform'
---
## Repository

This work is in the sibling checkout `../FoundationModelsExtras`, not in this repository. Make the change there and commit there.

## What

Make `OperationTool<Context>` in `Sources/Operations/OperationTool.swift` conform to `OperationDescribing` for every `Context`.

- `operationDescriptors` maps each `AnyOperation<Context>` in `operations` to an `OperationDescriptor`, in registration order. Map `ParamMeta` to `OperationParameterDescriptor` field by field, and `ParamType` to `OperationParameterType` case by case. Drop `ParamMeta.short`; it is a CLI affordance.
- `perform(_ arguments: GeneratedContent) async throws -> String` runs the same pipeline as `call(arguments:)`: `resolver.extractedOpString(from:)`, `resolver.matchOpString(_:against:)`, `resolver.resolveParameters(_:matching:)`, then `operation.run`. The difference: it throws `OperationError.unknownOperation`, `.missingRequired` and `.decodingFailed` instead of returning their text, and it does not read or change the `RetryState` actor. Factor the shared resolve step out of `call` so the two paths cannot drift. `call(arguments:)` keeps its behavior exactly.

Also give `Sources/OperationsCLI/AnyOperationTool.swift` no change; it keeps its own erasure.

Update `docs/OPERATIONS_DESIGN_NOTES.md` with a short section that records why `perform` exists: a host such as Multitool runs a tool inside a code sandbox where a throw is a promise rejection the model sees, so the return-not-throw rule of `call` does not apply there.

## Acceptance Criteria

- [ ] `NotesTool.make()` from `Examples/NotesTool` casts to `any OperationDescribing` and gives five descriptors with op strings `add note`, `get note`, `list note`, `delete note`, `tag note`.
- [ ] The `AddNote` descriptor marks `title` required and `body` and `tags` optional; the `TagNote` descriptor marks `tags` required.
- [ ] `perform` with `{"op": "tag note", "id": "note-1", "tags": ["a"]}` gives the same JSON text as `call` gives for the same payload.
- [ ] `perform` with an unknown op throws `OperationError.unknownOperation`; `call` still returns the corrective text for the same payload.
- [ ] `perform` with a missing required field throws `OperationError.missingRequired`, and a later `call` is not affected by the retry cap.
- [ ] `swift test` in `../FoundationModelsExtras` passes in full, including `DocCoverageTests`.

## Tests

- [ ] `Tests/OperationsTests/OperationDescribingConformanceTests.swift`: the descriptor mapping for the `CoreTypesTests` fixture operations, each `ParamType` case, and the five `perform` cases above.
- [ ] `Examples/NotesTool/Tests/NotesToolTests/NotesIntegrationTests.swift`: one test that lists the five descriptors of the real notes tool.
- [ ] Run `swift test` in `../FoundationModelsExtras`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools #extras