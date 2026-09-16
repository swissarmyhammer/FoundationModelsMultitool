---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2n2by7n1kkw5qgx3n34qq5x
  text: The precondition cards on the FoundationModelsExtras board are ^rmmv6qv (Add the OperationDescribing protocol and its descriptor types) and ^3jpfqa3 (Conform OperationTool to OperationDescribing with a throwing perform). Extras `main` was at 8ec26d4 when these were made; the two cards land as later commits on `main`. Bump `Package.resolved` to a revision at or after them.
  timestamp: 2026-09-16T12:16:50.421312+00:00
depends_on:
- 01M2N2KZKERE5EHE5NJ5BWY82D
position_column: todo
position_ordinal: '8280'
title: 'Add OperationVerbTool: one Tool per operation with a per-operation schema'
---
## Precondition, in another repository

This card needs the `OperationDescribing` protocol from the FoundationModelsExtras package. Two cards on the Extras board, `^rmmv6qv` and `^3jpfqa3` (tag `multitool-ask`), add it: the protocol and its descriptor types in the core `FoundationModelsExtras` module, and the `OperationTool` conformance with a throwing `perform(_:)`. Before you start, check that `origin/main` of `git@github.com:swissarmyhammer/FoundationModelsExtras.git` carries `Sources/FoundationModelsExtras/OperationEvents/OperationDescribing.swift`. If it does not, stop and report; do not implement the protocol here. A local commit in the sibling checkout is not enough, because `Package.swift` takes Extras by URL and branch.

The protocol, as agreed:

- `public protocol OperationDescribing: Tool` with `var operationDescriptors: [OperationDescriptor] { get }` and `func perform(_ arguments: GeneratedContent) async throws -> String`. `perform` takes the same payload as a model call (`op` plus one operation's fields) and throws `OperationError` for a refusal instead of returning text.
- `OperationDescriptor`: `verb`, `noun`, `opString`, `description`, `parameters: [OperationParameterDescriptor]`.
- `OperationParameterDescriptor`: `name`, `type: OperationParameterType`, `required`, `description`, `aliases`, `allowedValues: [String]?`.
- `OperationParameterType`: `string`, `integer`, `number`, `boolean`, `array(of:)`.

## What

Add the internal wrapper that presents one operation of an `OperationDescribing` tool as an ordinary `Tool`. This is the unit the registry mounts, `ToolInvoker` validates, and `searchTools` indexes. It follows `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPTool.swift`: one Swift type, `Arguments = GeneratedContent`, schema given at run time.

First, move `Package.resolved` to the Extras revision that carries `OperationDescribing` (`swift package update FoundationModelsExtras`). The library target already links the `FoundationModelsExtras` product, so `Package.swift` needs no new product. Do not add the `Operations` product to the library target, and do not import `MCP` in `Surface/`.

Create `Sources/FoundationModelsMultitool/Surface/OperationVerbTool.swift`:

- `struct OperationVerbTool: Tool, Sendable` with `Arguments = GeneratedContent`, `Output = GeneratedContent`. It holds `parent: any OperationDescribing` and `descriptor: OperationDescriptor`.
- `init(parent: any OperationDescribing, descriptor: OperationDescriptor) throws`.
- `name`: the op string as a camelCase identifier. Split `opString` on spaces, `_` and `-`; lowercase the first word; capitalize the first letter of each other word; join. `get symbol` gives `getSymbol`; `get type_definition` gives `getTypeDefinition`. Put this in `static func verbName(for opString: String) -> String`.
- `description`: `descriptor.description`.
- `includesSchemaInInstructions = true`, declared as `MCPTool` declares it. The verb's own schema is the one the model needs.
- `parameters`: a `GenerationSchema` built with `DynamicGenerationSchema` from `descriptor.parameters` only. No `op` property. `isOptional` is the inverse of each parameter's `required`. `allowedValues` becomes the `anyOf: [String]` string form. Map `string`, `integer`, `number`, `boolean`, `array(of:)` to `String`, `Int`, `Double`, `Bool`, and `arrayOf`. This schema serves `ToolInvoker.validate` and the `Tool` conformance only; it does not drive the rendered surface.
- `func render() throws -> ToolDescriptor`: maps `descriptor.parameters` to `[ToolAPIRenderer.RenderedParameter]` in descriptor order (`allowedValues` becomes `.string(choices:)`, `array(of:)` becomes `.array(element:)`) and calls `ToolAPIRenderer.render(name:description:arguments:returns: .json)` from the renderer card. The rendered order and choices come from the descriptor, so they do not depend on how the schema encodes.
- `call(arguments:)`: build a new `GeneratedContent` from `arguments` plus `("op", descriptor.opString)`; the `op` key wins over any `op` the caller sent. Call `parent.perform(_:)`. If the result text is valid JSON (check with `JSONSerialization` first), return `GeneratedContent(json:)` of it, so the snippet gets a parsed object or array. If it is not valid JSON, return `GeneratedContent(text)`, so the snippet gets the string.

## Acceptance Criteria

- [ ] `verbName(for:)` gives `addNote`, `listNote`, `getTypeDefinition`, `getCallgraph` for `add note`, `list note`, `get type_definition`, `get callgraph`.
- [ ] `render()` for a descriptor with `title` required and `body`, `tags` optional, in that order, gives `declare function addNote(args: { title: string; body?: string; tags?: string[] }): Promise<object>;` and the `@example` names only `title`.
- [ ] `render()` for a descriptor with `allowedValues: ["c", "f"]` gives `"c" | "f"`.
- [ ] `includesSchemaInInstructions` is `true`.
- [ ] `ToolInvoker.validate` against `parameters` rejects a payload with `title` missing, and the error names `title`. Record in a test what it does with a value outside `allowedValues`; either outcome is accepted, because the parent checks allowed values at dispatch.
- [ ] `call` sends `{"op": "add note", "title": "x"}` to the parent, in that shape, and returns a parsed object when the parent answers JSON text.
- [ ] `call` returns a string when the parent answers text that is not JSON.
- [ ] An error thrown by `perform` propagates out of `call` unchanged.

## Tests

- [ ] `Tests/FoundationModelsMultitoolTests/Fixtures/OperationToolFixtures.swift`: a hand-conformed `OperationDescribing` fixture with five notes-like operations (`add note`, `get note`, `list note`, `delete note`, `tag note`) over an in-memory store. Inside `perform(_:)` it records every payload it receives and the value of `ToolContext.current?.op` beside it, and it throws for a bad op or a missing id. Import `FoundationModelsExtras` and `FoundationModelsRouter` only; do not use the `Operations` macros here.
- [ ] `Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift`: the eight criteria above.
- [ ] Run `swift test --filter OperationVerbToolTests`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools