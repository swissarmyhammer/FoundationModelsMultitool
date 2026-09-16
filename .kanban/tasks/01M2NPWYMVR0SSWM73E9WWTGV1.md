---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2nr4kk9vdj97ap3048g9bwh
  text: |-
    Research and decision.

    The `.json` mock was a plain `{}`. A `for...of` and a `.filter` on it throw. The interpreter converts the snippet result with `JSON.stringify` and gives `.null` for a value it cannot represent, so a `Proxy` result cannot fail the run.

    Dead end, measured before the code: an array of two empty objects, with a plain property read that answers `undefined`. It passes AC1 (`notes.filter((n) => n.id).length`) and AC3 (`n.id`), but it fails AC2. `note.id` is `undefined`, and `tagNote({ id: note.id, tag: "due" })` then fails with `must be string, but received undefined`. A value that passes a `string` check and an `object` check cannot be a primitive, so the elements must be tagged mocks.

    Decision: one `Proxy` over a function, `__mockJSON`, marked with the hidden key `__mockJSON`. The function target makes a field read callable (`note.body.includes("Friday")`). The trap answers `Symbol.iterator`, `length`, an index key and each `Array.prototype` method with two lazily built child mocks of the same kind; `then`/`catch`/`finally` with `undefined`, so `await` passes the value through; `toJSON` with `{}`; primitive coercion with `''` or `0`; every other string key with another such mock. A call gives another such mock, and an assignment is a no-op. `__mockCheck` accepts a marked value for every declared shape. The doc comment of `TypedMockDryRun` and of `runtime` record this.

    TDD: three new cases in `TypedMockDryRunTests` (AC1, AC2, and a string method on a field of an element, which the README snippet needs) failed first, then passed after the change. The README snippet now reads the list as an array, without `Object.values`. `ReadmeOperationSectionTests` reads the notes fixture entries through the new shared helper `TypedMockDryRunTests.notesEntries()`.
  timestamp: 2026-09-16T18:37:18.825007+00:00
- actor: claude-code
  id: 01m2nr5mds2s7c1rdqg58vcvhs
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Discovery/TypedMockDryRun.swift (`__mockJSON`, `__mockIsJSON`, `.json` routed to it, `__mockCheck` accepts a marked value, doc comments of `TypedMockDryRun` and `runtime` record the decision), Tests/FoundationModelsMultitoolTests/TypedMockDryRunTests.swift (helper `notesEntries()`, three new cases, one retitled case), Tests/FoundationModelsMultitoolTests/ReadmeOperationSectionTests.swift (reads the fixture entries through the shared helper), README.md (the `## Operation tools` snippet reads the list without `Object.values`, and the prose says why). `swift test --filter "TypedMockDryRunTests|ReadmeOperationSectionTests|SampleSnippetTests"`: 42 tests in 3 suites passed (the three new cases failed first, then passed). `swift test`: 1508 tests in 121 suites passed, 0 failures. The only `warning:` line is the build system's note about the `mlx-swift` dependency bundle under `.build/out`, not a diagnostic from the changed sources. All four acceptance boxes and both test boxes are ticked. Not committed.
    - next: `/review`. The card stays in `doing`.
  timestamp: 2026-09-16T18:37:52.441256+00:00
position_column: doing
position_ordinal: '80'
title: TypedMockDryRun rejects a snippet that iterates a `.json` result
---
## What

`TypedMockDryRun` mocks a `.json` result as a plain `{}` with no `Proxy` (`__mockValue`, kind `json`). Every verb of an `OperationTool` declares `Promise<object>`, and `listNote` answers a JSON array. A snippet that reads that array in the natural way fails the dry run:

- `for (const note of notes)` throws `TypeError: notes is not iterable`.
- `notes.filter(...)` throws `notes.filter is not a function. (In 'notes.filter(...)', 'notes.filter' is undefined)`.

Measured on card ^ezhh2bq with `ReadmeOperationSectionTests`: the README snippet reads the list through `Object.values(notes)` for that reason. A sample snippet the model writes for `searchTools` over a list verb takes the natural form, so the gate rejects a correct snippet and the generator then "repairs" correct code. That is the false-failure mode the `TypedMockDryRun` doc comment names as worse than no check.

Decide how a `.json` value mocks so that both an object read (`n.id`) and an array read (`for...of`, `.filter`, `.length`) pass clean. One shape: a mock that is an array of two empty objects wrapped so that a plain property read on it also answers `undefined`. Record the decision in the doc comment of `TypedMockDryRun`.

## Acceptance Criteria

- [x] `TypedMockDryRun.apiUsageFailure(in:against:using:)` reports no failure for `const notes = await tools.notes.listNote({}); return notes.filter((n) => n.id).length;` over the verb entries of `NotesOperationTool`.
- [x] The same call reports no failure for `for (const note of notes) { await tools.notes.tagNote({ id: note.id, tag: "due" }); }`.
- [x] `const n = await tools.notes.addNote({ title: "x" }); return n.id;` still reports no failure.
- [x] The README snippet in `## Operation tools` can then read the list without `Object.values`, and `ReadmeOperationSectionTests` still passes.

## Tests

- [x] New cases in `Tests/FoundationModelsMultitoolTests/TypedMockDryRunTests.swift` for the two array reads over a `.json` entry.
- [x] Run `swift test --filter "TypedMockDryRunTests|ReadmeOperationSectionTests"`; expect all pass.

#operation-tools