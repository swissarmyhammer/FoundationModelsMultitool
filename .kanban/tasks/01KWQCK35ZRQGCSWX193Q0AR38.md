---
depends_on:
- 01KWQC004XSC6ZS9PW10WF5GAD
position_column: todo
position_ordinal: '8880'
title: Add id-enum selection grammar helper
---
## What
Standalone, GPU-free groundwork for the selection-tier rewire: the xgrammar id-enum grammar that will constrain every `findAPIs` selection session to the catalog's exact entry paths.

- New `Sources/FoundationModelsMultitool/Agent/SelectionGrammar.swift`: internal `func idEnumGrammar(ids: [String]) throws -> Grammar` building the `{"type":"object","properties":{"ids":{"type":"array","items":{"type":"string","enum": ids},"uniqueItems":true}},"required":["ids"]}` JSON Schema by hand via `JSONSerialization` and wrapping it in `Grammar.jsonSchema(_:)`.
- This is the registry's documented integrator path — copy the shape from `../FoundationModelsMetadataRegistry/Examples/LiveRouterSupport/LiveRouterSupport.swift` (`idEnumGrammar(ids:)`, lines ~85–99). The registry keeps its own `SelectionTier.idEnumGrammar` internal on purpose, and `MetadataSearcher` independently verifies every returned id (`.unknownSelectedId`), so this hand-built schema only keeps the model honest about response *shape*.

## Acceptance Criteria
- [ ] `idEnumGrammar(ids:)` exists, is `throws`, returns a `Grammar`, and its serialized schema contains the given ids as an `enum`, `uniqueItems: true`, and `required: ["ids"]`.
- [ ] `swift build` and full `swift test` green (nothing else changes in this task).

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SelectionGrammarTests.swift`: decode the schema JSON out of the built grammar (or build the schema string via a testable seam) and assert enum ids, `uniqueItems`, and `required` are present; empty-ids input produces a well-formed schema with an empty enum.
- [ ] `swift test` — full suite green.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.