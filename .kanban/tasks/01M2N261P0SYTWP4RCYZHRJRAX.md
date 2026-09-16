---
assignees:
- claude-code
depends_on:
- 01M2N24ZEPMS79PQH5B58FF2SF
- 01M2N25MG8RCX1Z4BJGSZA6ZJA
position_column: todo
position_ordinal: '8580'
title: Search and hints treat each operation verb as its own entry
---
## What

Pin that discovery works per verb, and add one hint for the raw call form.

Part 1, search. Each verb is its own `APISurface.Entry`, so `SearchableMetadata.id` is the verb path and the indexed block is the verb block. Prove it over the five-verb fixture:

- A `MetadataSearcher` built by `SearchToolsTool.makeSearcher(over:selection:embedder:)` in `.auto` retrieval mode ranks `notes.tagNote` first for the task `attach a label to a note`, and `notes.listNote` first for `show every note`.
- `SearchToolsTool.format(task:matches:)` for one verb match gives the verb block followed by `Example: await tools.notes.tagNote({ id: "id", tags: ["tags"] });`.
- `Entry.renderSummaryBlock()` for a verb holds the banner `// tools.notes.tagNote` and the verb description, not the parent tool description.
- The `UnknownToolHint` for a snippet that names `tools.notes.tagNotes` (a near miss) proposes `tools.notes.tagNote`.

Part 2, the raw call form. A model that knows the fused Tool form may write `tools.notes({ op: "tag note", ... })`. In JavaScript `tools.notes` is an object, so the call fails with a `TypeError`. Extend `Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift`: when the failure text says a `tools.<group>` path is not a function and the registry has entries under that group, the hint lists the verbs of the group, at most the first eight, as `tools.<group>.<verb>`. Reuse `referencedToolPaths(in:)` to find the path. Keep the hint format that `UnknownToolHintTests` pins for the existing cases.

## Acceptance Criteria

- [ ] The two ranking cases, the format case, the summary-block case and the near-miss case pass.
- [ ] A failure text for `tools.notes(...)` produces a hint that names `tools.notes.addNote` and `tools.notes.tagNote`.
- [ ] A failure text for `tools.nothing(...)` with no such group produces the hint the code gives today, unchanged.
- [ ] `swift test` passes in full, including `UnknownToolHintTests` and `SearchToolsToolTests` with no change to their existing expectations.

## Tests

- [ ] `Tests/FoundationModelsMultitoolTests/OperationSearchTests.swift` for Part 1.
- [ ] New cases in `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift` for Part 2, with the exact `TypeError` text recorded by the `OperationRunCodeTests` card as the input.
- [ ] Run `swift test --filter "OperationSearchTests|UnknownToolHintTests"`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools