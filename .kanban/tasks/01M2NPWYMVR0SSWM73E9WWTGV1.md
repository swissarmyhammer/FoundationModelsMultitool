---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: TypedMockDryRun rejects a snippet that iterates a `.json` result
---
## What

`TypedMockDryRun` mocks a `.json` result as a plain `{}` with no `Proxy` (`__mockValue`, kind `json`). Every verb of an `OperationTool` declares `Promise<object>`, and `listNote` answers a JSON array. A snippet that reads that array in the natural way fails the dry run:

- `for (const note of notes)` throws `TypeError: notes is not iterable`.
- `notes.filter(...)` throws `notes.filter is not a function. (In 'notes.filter(...)', 'notes.filter' is undefined)`.

Measured on card ^ezhh2bq with `ReadmeOperationSectionTests`: the README snippet reads the list through `Object.values(notes)` for that reason. A sample snippet the model writes for `searchTools` over a list verb takes the natural form, so the gate rejects a correct snippet and the generator then "repairs" correct code. That is the false-failure mode the `TypedMockDryRun` doc comment names as worse than no check.

Decide how a `.json` value mocks so that both an object read (`n.id`) and an array read (`for...of`, `.filter`, `.length`) pass clean. One shape: a mock that is an array of two empty objects wrapped so that a plain property read on it also answers `undefined`. Record the decision in the doc comment of `TypedMockDryRun`.

## Acceptance Criteria

- [ ] `TypedMockDryRun.apiUsageFailure(in:against:using:)` reports no failure for `const notes = await tools.notes.listNote({}); return notes.filter((n) => n.id).length;` over the verb entries of `NotesOperationTool`.
- [ ] The same call reports no failure for `for (const note of notes) { await tools.notes.tagNote({ id: note.id, tag: "due" }); }`.
- [ ] `const n = await tools.notes.addNote({ title: "x" }); return n.id;` still reports no failure.
- [ ] The README snippet in `## Operation tools` can then read the list without `Object.values`, and `ReadmeOperationSectionTests` still passes.

## Tests

- [ ] New cases in `Tests/FoundationModelsMultitoolTests/TypedMockDryRunTests.swift` for the two array reads over a `.json` entry.
- [ ] Run `swift test --filter "TypedMockDryRunTests|ReadmeOperationSectionTests"`; expect all pass.

#operation-tools