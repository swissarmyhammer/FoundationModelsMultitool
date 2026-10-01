---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Put the bounds of the web verb integer arguments in their generation schemas
---
## What
Card ^tm4x2hp found this defect in `tools.files.read`: the verb refused `limit: 0` with a correction, but the generation schema of `ReadArguments` did not carry the bound. The on-device model wrote `limit: 0`, read the correction, and answered that a one-line file held no lines. The fix put `.range(...)` guides on `offset` and `limit`, from one shared range that the verb's `BoundParameter` also reads (`ReadArguments.offsetRange`, `ReadArguments.limitRange`).

The web verbs have the same shape. Each has a `BoundParameter` but no range guide in its arguments schema:
- `Sources/FoundationModelsMultitool/Capabilities/Web/Search.swift`: `countBound`.
- `Sources/FoundationModelsMultitool/Capabilities/Web/Fetch.swift`: `offsetBound`, `maxCharactersBound`, `timeoutBound`.

## Do
- For each bounded argument, add a `.range(...)` (or `.minimum(...)` when there is no upper end) guide that reads the same constant as its `BoundParameter`.
- Keep the in-band correction, because a snippet in `runCode` does not go through guided generation.

## Tests
- [ ] One unit test for each bounded argument: the rendered surface doc (`ToolAPIRenderer.render(tool).doc`) holds the `(range ...)` or `(minimum ...)` clause. See `FilesReadTests.generationSchemaBoundsLimit` for the pattern.
- [ ] `swift test` passes.