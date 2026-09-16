---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'Extras: add the OperationDescribing protocol and its descriptor types'
---
## Repository

This work is in the sibling checkout `../FoundationModelsExtras`, not in this repository. Make the change there and commit there. This card tracks it because the Multitool cards depend on it.

## What

Add a cast-friendly protocol that lets a host that holds `any Tool` enumerate the operations of an operation tool. Follow the pattern of `Sources/FoundationModelsExtras/OperationEvents/ForkableTool.swift`: no associated types, so `tool as? any OperationDescribing` succeeds on an `any Tool` existential.

Create `Sources/FoundationModelsExtras/OperationEvents/OperationDescribing.swift` in the core `FoundationModelsExtras` module (the module Multitool already links), with:

- `public protocol OperationDescribing: Tool` with
  - `var operationDescriptors: [OperationDescriptor] { get }`
  - `func perform(_ arguments: GeneratedContent) async throws -> String`. This is the throwing dispatch. The payload has the same shape as a model call: an `op` key plus the fields of one operation. A refusal (unknown op, missing required field, decode failure) is thrown, not returned as text. The document comment must state this difference from `Tool.call`.
- `public struct OperationDescriptor: Sendable, Equatable` with `verb`, `noun`, `opString`, `description`, `parameters: [OperationParameterDescriptor]`, and a public memberwise `init`.
- `public struct OperationParameterDescriptor: Sendable, Equatable` with `name`, `type: OperationParameterType`, `required: Bool`, `description`, `aliases: [String]`, `allowedValues: [String]?`, and a public memberwise `init`.
- `public indirect enum OperationParameterType: Sendable, Equatable` with cases `string`, `integer`, `number`, `boolean`, `array(of: OperationParameterType)`.

These are new erased value types. Do not move `ParamMeta` or `ParamType` out of the `Operations` module. Every public declaration needs a document comment; `Tests/OperationsTests/DocCoverageTests.swift` checks the `Operations` sources, and the core module follows the same rule by convention.

## Acceptance Criteria

- [ ] `swift build` in `../FoundationModelsExtras` passes.
- [ ] A test type that conforms to `OperationDescribing` and to nothing else in `Operations` compiles with `import FoundationModelsExtras` alone.
- [ ] `(tool as any Tool) as? any OperationDescribing` returns the tool for a conforming type and `nil` for a plain `Tool`.
- [ ] The doc comment of `perform(_:)` states that a refusal is thrown and that `call(arguments:)` keeps its return-not-throw rule.

## Tests

- [ ] `Tests/FoundationModelsExtrasTests/OperationDescribingTests.swift`: a hand-conformed fixture tool; the cast test above; `OperationDescriptor` and `OperationParameterDescriptor` equality; `perform` on the fixture throws for a bad `op`.
- [ ] Run `swift test --filter OperationDescribingTests` in `../FoundationModelsExtras`; expect all pass.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools #extras