---
assignees:
- claude-code
depends_on:
- 01M2N24ZEPMS79PQH5B58FF2SF
position_column: todo
position_ordinal: '8480'
title: Prove runCode calls an operation verb end to end
---
## What

Drive a `MultiTool` over the five-verb fixture with real snippets through the JavaScriptCore interpreter, and pin the whole call path: preamble binding, `ToolInvoker.validate` against the per-verb schema, `op` injection, `perform`, parsed result, and error propagation. Follow the shape of `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift` and `Fixtures/MultiToolExecutionFixtures.swift`. No production change is expected. If a test finds a defect in `OperationVerbTool` or in the registry expansion, fix it in the same card and record the fix in a comment.

Snippets to run, each as one `runCode` call:

1. `const n = await tools.notes.addNote({ title: "Plan", body: "deadline Friday" }); return n.id;` gives the id the store assigned. The fixture recorded exactly one payload `{"op": "add note", "title": "Plan", "body": "deadline Friday"}` and no `tags` key.
2. `const all = await tools.notes.listNote({}); return all.length;` gives a number, and `all` is an array in the snippet, not a string.
3. The loop from the design discussion: list, filter on `body`, `tagNote` each hit, return a count. Every `tagNote` payload holds `"op": "tag note"`.
4. `await tools.notes.tagNote({ id: "note-1" })` (no `tags`) rejects before the fixture sees a payload; the rejection text names `tags`. The fixture recorded nothing for this call.
5. `await tools.notes.getNote({ id: "missing" })` where the fixture throws from `perform`: the snippet catches the rejection with `try/catch` and returns `e.message`, which holds the fixture's error text.
6. A fixture verb that answers plain text (not JSON) gives a string in the snippet.
7. `await tools.notes({ op: "add note", title: "x" })` rejects; the snippet sees a JavaScript `TypeError` and does not reach the fixture. Record the exact message text in the test, and add it as a comment on this card, because the search-and-hints card uses it as its input.

Journal op. Under a `RunBinding` with a `ToolContext`, a `tagNote` call reaches the fixture with `ToolContext.current?.op == "tagNote notes"`. The fixture records that value beside each payload (see `Fixtures/OperationToolFixtures.swift`); read it back from the recording. The `AmbientRecordingTool` in `Fixtures/RunBindingFixtures.swift` cannot serve here, because the mounted tool is the verb wrapper, not the fixture.

## Acceptance Criteria

- [ ] The seven snippets above behave as stated.
- [ ] The recorded `op` for a verb call is `"<verb> <group>"`.
- [ ] The exact `TypeError` text of snippet 7 is a comment on this card.
- [ ] `swift test` passes in full.

## Tests

- [ ] `Tests/FoundationModelsMultitoolTests/OperationRunCodeTests.swift` with one test per snippet and one for the journal op.
- [ ] Run `swift test --filter OperationRunCodeTests`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools