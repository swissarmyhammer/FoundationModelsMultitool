---
assignees:
- claude-code
depends_on:
- 01M2N24ZEPMS79PQH5B58FF2SF
position_column: todo
position_ordinal: '8780'
title: Document operation tools in the README and ExamplesTests
---
## What

Write the shipped contract for operation tools where the package states its contracts.

`README.md`: add a section `## Operation tools` after `## Capabilities`. State, in ASD-STE100 Simplified Technical English:

- An `OperationTool` from the Extras `Operations` module mounts with `addTool`, `addGroup(named:_:)` or inside a `Capability`, with no new builder method.
- The Multitool expands it into one verb per operation at `tools.<toolName>.<verbNoun>`; the op string `tag note` becomes `tagNote`. Show the five rendered `notes` declarations from the golden `Goldens/OperationSurface.ts.txt`.
- Each verb shows only its own fields with true required marks. The `op` field does not appear, and the fused form `tools.notes({op})` is not mounted.
- A result is a parsed JSON value, declared `Promise<object>`. The surface does not know the fields of the result, so a snippet reads them as it does any JSON. A refusal is a thrown error the snippet can catch.
- Inside a group or capability the verbs flatten into that noun; a shared op string is a build error.
- Show one snippet: the list, filter, tag loop from the design discussion. This snippet must be one that `TypedMockDryRun` accepts over the verb entries (the renderer card proves the `.json` mock), so a sample snippet the model gets from `searchTools` can look like it.

Do not change the `### Injected globals` list; `HardeningTests` parses it, and this feature adds no global.

`Tests/FoundationModelsMultitoolTests/ExamplesTests.swift`: add one self-contained example test that mounts the hand-conformed fixture from `Fixtures/OperationToolFixtures.swift`, builds the registry, and asserts the five verb paths and one rendered declaration. Keep it copy-pasteable in the style of the other examples there.

`plan.md` status note: add one line that names this feature and points to the README section, in the same style as the other status lines at the top.

## Acceptance Criteria

- [ ] `README.md` has the `## Operation tools` section with the rendered declarations, the snippet, and the six statements above.
- [ ] `HardeningTests` still passes, so the globals list is unchanged.
- [ ] `ExamplesTests` has the new example and it passes.
- [ ] The rendered declarations in the README equal the lines in `Goldens/OperationSurface.ts.txt` for the same verbs.
- [ ] The README snippet passes `TypedMockDryRun.apiUsageFailure(in:against:using:)` over the fixture surface with no failure.

## Tests

- [ ] The new example in `ExamplesTests.swift`.
- [ ] A new `Tests/FoundationModelsMultitoolTests/ReadmeOperationSectionTests.swift` that reads `README.md` through `RepositoryFile`, checks that every `declare function` line in the `## Operation tools` section also appears in `Goldens/OperationSurface.ts.txt`, and runs the fenced `js` snippet of that section through `TypedMockDryRun` over the fixture surface. The README then cannot drift from the renderer or the dry run.
- [ ] Run `swift test --filter "ExamplesTests|HardeningTests|ReadmeOperationSectionTests"`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools