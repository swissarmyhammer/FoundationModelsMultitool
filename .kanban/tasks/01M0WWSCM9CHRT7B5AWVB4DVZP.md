---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0xn7zkx0jcp8cm6nnmxgpkr
  text: |-
    Research done. Findings:
    - Source op: PatchFiles.swift wraps PatchParser.parse + PatchEngine.apply. Both engines are already ported into Capabilities/Files (PatchParser.swift, PatchEngine.swift). PatchEngine.Failure has .corrective(String, committed:) and .unresolved(path:pair:resolution:); Failure.committedOutcomes must be recorded before a corrective returns.
    - Verb pattern from Edit.swift: @Generable arguments with @Guide, flat @Generable result with a `correction` field, wire outcomes ride as JSON strings with sorted keys, `struct Patch: Tool` with `name = "patch"` and `let context: FileContext` (synthesized memberwise initializer), read-only check up front, `Result.resolveAsync(corrective:)` from CorrectiveResult.swift binds ParseFailure.description (which carries the line number) into the correction.
    - Plan for the per-file outcomes: an internal Encodable `PatchFileResult` wire struct encoded into `files: [String]` JSON text, the same way Edit encodes EditOutcome into `outcomes: [String]`. To not copy Edit's private JSON encoder, a shared `EditOutcomeProjection.encodedText(_:)` helper will be added and Edit's private helper will forward to it.
    - changeKinds table ports as an internal `static let` on Patch (future reader: FileChangeSetTests port ^7r99xf5). It is live code (changeKind(for:) reads it), so no periphery marker is needed.
    - Tests port as Tests/FoundationModelsMultitoolTests/FilesPatchTests.swift. The fused-tool dispatch and op-inference tests of the sibling do not port (no FileTool in this package). Added per the card: outside-root corrective, read-only-context corrective, add-onto-existing corrective, and three journal tests. Committed content is read back through the Read verb; byte-identity claims read raw bytes, the FilesWriteTests pattern.
    - Validator rules dumped and read whole (55 rules). Key constraints: no magic numbers outside {0,1,-1,100} (named constants in tests), `- Parameter` keys use internal names, no redundant memberwise initializer, own `let` per binding in case patterns, no copied blocks.
  timestamp: 2026-08-25T23:49:15.517462+00:00
- actor: claude-code
  id: 01m0xnhan5q457s7h35ahhkt79
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Capabilities/Files/Patch.swift (new verb: PatchArguments, PatchResult, PatchFileResult wire type, changeKinds table, change recording, result projection, `struct Patch: Tool` with the format-teaching description), Tests/FoundationModelsMultitoolTests/FilesPatchTests.swift (new, 12 ported/adapted tests), Sources/FoundationModelsMultitool/Capabilities/Files/EditOutcomeProjection.swift (shared `encodedText(_:)` JSON encoder), Sources/FoundationModelsMultitool/Capabilities/Files/Edit.swift (private encoder now forwards to the shared one), Sources/FoundationModelsMultitool/Capabilities/Files/PatchEngine.swift (header note updated: the verb is now a caller). TDD followed: the suite was written first and failed with `cannot find 'Patch' in scope`, then the verb made it pass. `swift test --filter FilesPatchTests`: 12/12 passed. Full `swift test`: 978 tests in 70 suites, all passed, zero failures. `swift build --build-tests`: zero compiler warnings (the one "missing creator" line is pre-existing mlx bundle noise).
    - acceptance: applied patch reproduces the source op's tree state (add/update/delete/move verified through the Read verb and raw bytes); changeKinds table carried in Patch.swift (doc names the ^7r99xf5 reader); parse failure (with line number), add-onto-existing (engine's description), outside-root path, and read-only context each answer in-band, nothing throws; journal records on a recording context (kinds add/modify/delete/move, old/new content), records nothing when disabled or unresolved.
    - next: /review
    task: ^vb4dvzp
  timestamp: 2026-08-25T23:54:21.733570+00:00
- actor: claude-code
  id: 01m0xnkg8c6ef9rms7z7hs6327
  text: |-
    ### test — green
    - evidence: swift test — Test run with 978 tests in 70 suites passed after 4.291 seconds; 0 failures; 0 skipped; 1 known pre-existing warning: mlx-swift "missing creator for mutated node" (not chased, per instruction).
    - next: none
  timestamp: 2026-08-25T23:55:33.004445+00:00
depends_on:
- 01M0WWRKSCECWP5XSEZBHGTF8T
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: doing
position_ordinal: '80'
title: Make the tools.files.patch verb from PatchFiles
---
## What
Rewrite the `PatchFiles` operation as the plain `Tool` conformer `Patch`.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/Operations/PatchFiles.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/Patch.swift`

Shape:
- `struct Patch: Tool` with `name = "patch"`, so the path renders as `tools.files.patch`.
- A `@Generable` arguments struct with a `@Guide` on each parameter.
- A flat `@Generable` result with a `correction` field.
- Carry the `changeKinds` table from `PatchFiles` into `Patch.swift`. The later `FileChangeSetTests` port reads it.
- A patch that cannot parse, and a hunk that cannot apply, each give a corrective result in-band with the engine's description.
- A patch records into `FileContext.changes` when the journal records. A patch on a read-only context gives a corrective result in-band.
- The verb holds its `FileContext` as a constructor dependency.
- The doc comment carries the full behavioral contract and one example snippet.

## Acceptance Criteria
- [ ] An applied patch gives the same tree state as the source operation.
- [ ] `Patch.swift` carries the `changeKinds` table.
- [ ] A patch that cannot parse, a hunk that cannot apply, a path outside the root, and a read-only context each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `PatchFilesTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesPatchTests.swift`, adapted to the `Tool` call shape.
- [ ] `swift test --filter FilesPatchTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan