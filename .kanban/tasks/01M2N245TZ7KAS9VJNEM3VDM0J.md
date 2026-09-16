---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2n2by7n1kkw5qgx3n34qq5x
  text: The precondition cards on the FoundationModelsExtras board are ^rmmv6qv (Add the OperationDescribing protocol and its descriptor types) and ^3jpfqa3 (Conform OperationTool to OperationDescribing with a throwing perform). Extras `main` was at 8ec26d4 when these were made; the two cards land as later commits on `main`. Bump `Package.resolved` to a revision at or after them.
  timestamp: 2026-09-16T12:16:50.421312+00:00
- actor: claude-code
  id: 01m2nc3ttsfrhgzfpkk7r1h0vc
  text: |-
    Picked up. Research notes:

    - `swift package update FoundationModelsExtras` resolved Extras at `c98ae6b` (c98ae6ba956f82e0d75bcb7583b28e5c88304d23). The checkout carries `Sources/FoundationModelsExtras/OperationEvents/OperationDescribing.swift` with `OperationDescribing`, `OperationDescriptor`, `OperationParameterDescriptor`, `OperationParameterType` in the core module. The precondition is met.
    - `Package.resolved` is in `.gitignore` (line 18). The new pin is on disk only. A commit cannot carry it. `Package.swift` takes Extras from `main`, so a new clone resolves the same revision.
    - `ToolInvoker.validate` is `private static`. A test reaches it through `ToolInvoker.invoke(_:content:)`, the same way `ToolInvokerTests` does. A missing required field gives `ToolInvokerError` with kind `.missingRequiredField` and `field` set.
    - `ToolAPIRenderer.render(name:description:arguments:returns:onWiden:)` is the typed path. `RenderedParameter(name:shape:isRequired:description:)` with `constraints` and `exampleValue` at their defaults. `ToolValueShape.string(choices: [InterpreterValue])`, `.number`, `.boolean`, `.array(element:)`. The renderer test `addNoteDescriptor()` in `ToolAPIRendererTests` gives the exact declaration text the card expects.
    - `MCPTool` is the model for the type: internal `struct`, `Arguments = GeneratedContent`, `let includesSchemaInInstructions = true`.
    - `SchemaConverter.dynamicSchema(for:)` shows the `DynamicGenerationSchema` forms: `DynamicGenerationSchema(type: String.self)`, `(arrayOf:)`, `(name:description:anyOf:)`, and `DynamicGenerationSchema.Property(name:description:schema:isOptional:)`.
    - `ToolContext.current` is a `@TaskLocal` in Router; its `init` is internal to Router, so a unit test here cannot bind a context. The fixture reads `ToolContext.current?.op` and records `nil` outside a session.
    - A `GeneratedContent` object is built with `GeneratedContent(kind: .structure(properties:orderedKeys:))`, as `ArgumentMarshaler.content(from:)` does.
  timestamp: 2026-09-16T15:07:10.553919+00:00
- actor: claude-code
  id: 01m2nct0hkhytsnftagb0yk921
  text: |-
    Implementation landed, with `/tdd`.

    RED: `Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift` (12 cases) and `Tests/FoundationModelsMultitoolTests/Fixtures/OperationToolFixtures.swift` were written first. `swift build --build-tests` failed on `cannot find 'OperationVerbTool' in scope` and on nothing else; the fixture compiled.

    GREEN: `Sources/FoundationModelsMultitool/Surface/OperationVerbTool.swift`. `swift test --filter OperationVerbToolTests` passes 12 tests in 1 suite. The whole unit suite passes: 1477 tests in 117 suites, exit 0.

    REFACTOR: `payload(from:op:)` and `output(from:)` became `private static`; no caller outside the type.

    Discoveries:
    - The `anyOf` of string constants that `DynamicGenerationSchema(name:description:anyOf:)` builds encodes as an `enum`, so `ToolInvoker.validate` rejects a value outside `allowedValues` with `.guideViolation` and the field name, before the parent sees the payload. The test `invokerRejectsAValueOutsideAllowedValues` records that outcome.
    - The fixture defines `NotesOperationError` for its refusals. `OperationError` lives in the `Operations` module of Extras, not in the core module the card allows.
    - The fixture records `ToolContext.current?.op`; it is `nil` in these unit tests because `ToolContext.init` is internal to Router, so no unit test here can bind a context. The `callSendsTheOpAndParsesAJSONAnswer` case asserts that `nil`.
    - `Package.resolved` is gitignored, so the Extras pin `c98ae6b` is on disk only.
    - Two behaviors beyond the eight criteria have tests: the `op` key of the verb wins over an `op` the caller sent, and `name`/`description` come from the descriptor.

    Not committed. The card stays in `doing` for `/review`.
  timestamp: 2026-09-16T15:19:17.299512+00:00
- actor: claude-code
  id: 01m2nct424g3hdz0tm5w12brty
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Surface/OperationVerbTool.swift, Tests/FoundationModelsMultitoolTests/Fixtures/OperationToolFixtures.swift, Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift; `swift test --filter OperationVerbToolTests` → 12 tests in 1 suite passed; `swift test` → 1477 tests in 117 suites passed, exit 0; Package.resolved (gitignored) pins FoundationModelsExtras at c98ae6ba956f82e0d75bcb7583b28e5c88304d23
    - next: `/review`
  timestamp: 2026-09-16T15:19:20.900998+00:00
- actor: claude-code
  id: 01m2ndm45602tytk0qsqetch06
  text: |-
    ### review — findings
    - scope: `review sha HEAD~2..HEAD`, local backend, iteration 1
    - evidence: 1 finding — Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift:21 (`completeness/case-sensitivity-coverage`)
    - next: add one test case with uppercase or mixed-case input to `verbNameCases`, make `verbName(for:)` give correct camelCase for that input, then run `/review` again. The card stays in `review`.
  timestamp: 2026-09-16T15:33:32.966210+00:00
- actor: claude-code
  id: 01m2ndn1grw9e286z84dnv5tbs
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 files (Surface/OperationVerbTool.swift, Fixtures/OperationToolFixtures.swift, OperationVerbToolTests.swift); Package.resolved (on disk, gitignored) pins Extras at c98ae6b
    - test: green — swift test, 1477 tests in 117 suites passed, 0 failed, 0 skipped, 0 warnings
    - commit: 41b811c (code), 5e20381 (kanban)
    - review: findings — Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift:21 (completeness/case-sensitivity-coverage: `verbName(for:)` does not normalize a mixed-case op string)
  timestamp: 2026-09-16T15:34:03.032826+00:00
- actor: claude-code
  id: 01m2ndytby447bw9s9x5zg4jbr
  text: |-
    Review finding worked, with `/tdd`.

    RED: two cases added to `verbNameCases` in `Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift`: `("GET Type_Definition", "getTypeDefinition")` and `("Delete NOTE", "deleteNote")`. `swift test --filter OperationVerbToolTests` failed on one case: `Delete NOTE` gave `deleteNOTE`. The `GET Type_Definition` case passed before the fix, because each word after the first already had a capital first letter and lowercase rest; only `Delete NOTE` shows the fault.

    GREEN: `verbName(for:)` in `Sources/FoundationModelsMultitool/Surface/OperationVerbTool.swift` now lowercases every word before it capitalizes the first letter of each word after the first. The doc comment states that the case of the input does not reach the identifier. `swift test --filter OperationVerbToolTests` passes 12 tests in 1 suite (6 `verbName` cases). `swift test` passes 1477 tests in 117 suites, exit 0, 0 failed, 0 skipped.

    Rules check: the validator rules file (11,727 lines) was read whole. `case-sensitivity-coverage` asks for one regression test for the non-canonical spelling; the two new cases give it. `invariant-propagation` and `reuse`: `verbName(for:)` is the one site in `Sources/` that turns an op string into an identifier, and no other helper does that work, so no sibling site needs the same treatment.

    Discovery: `swift test` prints one build-system line, `warning: missing creator for mutated node: (.../.build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS)`. It comes from the build system about a prebuilt bundle in `.build`, not from a compiler diagnostic in the package sources, and it stands before and after this change.

    The finding item is checked `- [x]`. Not committed. `Package.swift` and `Package.resolved` are not touched. The card stays in `doing` for `/review`.
  timestamp: 2026-09-16T15:39:23.390970+00:00
- actor: claude-code
  id: 01m2ndywvxst5zjjp3cyq0fred
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Surface/OperationVerbTool.swift, Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift; `swift test --filter OperationVerbToolTests` → 12 tests in 1 suite passed (6 `verbName` cases); `swift test` → 1477 tests in 117 suites passed, 0 failed, 0 skipped, exit 0; the one open `## Review Findings` item is checked
    - next: `/review`
  timestamp: 2026-09-16T15:39:25.949573+00:00
depends_on:
- 01M2N2KZKERE5EHE5NJ5BWY82D
position_column: doing
position_ordinal: '80'
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

- [x] `verbName(for:)` gives `addNote`, `listNote`, `getTypeDefinition`, `getCallgraph` for `add note`, `list note`, `get type_definition`, `get callgraph`.
- [x] `render()` for a descriptor with `title` required and `body`, `tags` optional, in that order, gives `declare function addNote(args: { title: string; body?: string; tags?: string[] }): Promise<object>;` and the `@example` names only `title`.
- [x] `render()` for a descriptor with `allowedValues: ["c", "f"]` gives `"c" | "f"`.
- [x] `includesSchemaInInstructions` is `true`.
- [x] `ToolInvoker.validate` against `parameters` rejects a payload with `title` missing, and the error names `title`. Record in a test what it does with a value outside `allowedValues`; either outcome is accepted, because the parent checks allowed values at dispatch.
- [x] `call` sends `{"op": "add note", "title": "x"}` to the parent, in that shape, and returns a parsed object when the parent answers JSON text.
- [x] `call` returns a string when the parent answers text that is not JSON.
- [x] An error thrown by `perform` propagates out of `call` unchanged.

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/OperationToolFixtures.swift`: a hand-conformed `OperationDescribing` fixture with five notes-like operations (`add note`, `get note`, `list note`, `delete note`, `tag note`) over an in-memory store. Inside `perform(_:)` it records every payload it receives and the value of `ToolContext.current?.op` beside it, and it throws for a bad op or a missing id. Import `FoundationModelsExtras` and `FoundationModelsRouter` only; do not use the `Operations` macros here.
- [x] `Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift`: the eight criteria above.
- [x] Run `swift test --filter OperationVerbToolTests`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools

## Review Findings (2026-09-16 10:22)

> Scope: `review sha HEAD~2..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/OperationVerbToolTests.swift:21` `completeness/case-sensitivity-coverage` — The `verbName(for:)` test cases cover only lowercase op strings. The function should normalize mixed-case or uppercase input to proper camelCase, but this behavior is untested. For example, `verbName(for: "GET Type_Definition")` should produce `"getTypeDefinition"`, but the current implementation may produce `"getTYPEDEFINITION"` because it preserves the case of non-first characters. Add one test case with uppercase or mixed-case input to verify the contract. Add one test case to verbNameCases like ("GET Type_Definition", "getTypeDefinition") to document the expected behavior for non-lowercase input and verify proper camelCase normalization.
