---
comments:
- actor: wballard
  id: 01kwqgg17h9rpqy0eh0pvq3hae
  text: |-
    Implemented via TDD:
    - Added `Tests/FoundationModelsMultitoolTests/SelectionGrammarTests.swift` first (RED: confirmed "cannot find 'idEnumGrammar' in scope" build failure).
    - Added `Sources/FoundationModelsMultitool/Agent/SelectionGrammar.swift` with `func idEnumGrammar(ids: [String]) throws -> Grammar`, hand-built via `JSONSerialization` and wrapped in `Grammar.jsonSchema(_:)`, mirroring `FoundationModelsMetadataRegistry/Examples/LiveRouterSupport/LiveRouterSupport.swift`'s own `idEnumGrammar(ids:)` (lines ~85-99) exactly as the task calls for (copying the shape rather than reaching into the registry's package-internal `SelectionTier.idEnumGrammar`).
    - `swift build`: green.
    - `swift test`: 254 tests, only 1 failure — the pre-existing, already-tracked `HardeningTests.readmeInjectedGlobalsListMatchesRuntime` (task 1pn8764), unrelated to this change. New `SelectionGrammarTests` (3 tests: object/required shape, ids property enum+uniqueItems, empty-ids edge case) all pass.
    - Spawned double-check agent for adversarial review; awaiting verdict before final handoff.
  timestamp: 2026-07-04T21:28:02.545758+00:00
- actor: wballard
  id: 01kwqgkc2y7q20a8khk7atq2ct
  text: |-
    Adversarial double-check: PASS. Independently re-verified signature/location/access, schema shape (matches registry's LiveRouterSupport.swift pattern), test meaningfulness (real decoded-JSON assertions, not tautologies), build/test greenness, and no scope creep (only the two new Swift files touched, aside from kanban bookkeeping). Sole test failure remains the pre-existing, separately tracked HardeningTests.readmeInjectedGlobalsListMatchesRuntime (task 1pn8764).

    Work complete. Leaving in `doing` for /review per the implement skill's process — both acceptance-criteria checkboxes and both test checkboxes are satisfied.
  timestamp: 2026-07-04T21:29:51.966692+00:00
depends_on:
- 01KWQC004XSC6ZS9PW10WF5GAD
position_column: done
position_ordinal: '9880'
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