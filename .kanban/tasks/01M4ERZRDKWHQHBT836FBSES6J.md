---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Declare an optional result field as `T | null` in the rendered `@returns` type
---
## What
Task ^efqdpfn changed `ArgumentMarshaler.renderOutput(_:)`: a `nil` optional field of a `@Generable` result now reaches a `runCode` snippet as `null`. The rendered result type of `ToolAPIRenderer` (`declaredType(ofObject:)` in `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift`) still writes such a field as `name?: T`. That type says "missing or `T`", not "`null` or `T`".

The same renderer writes the `args` object type. For an argument, `name?: T` is correct, because a snippet omits an optional argument.

Decide if the result type must show `null` (for example `name?: T | null`, or `name: T | null`) and change only the result side.

## Acceptance Criteria
- [ ] The rendered result type of a tool with a `@Generable` `Output` agrees with what a snippet reads for a `nil` optional field.
- [ ] The rendered `args` type does not change.

## Tests
- [ ] A unit test in `ToolAPIRendererTests` for a result with an optional field.
- [ ] Run `swift test` — all tests pass. #environment