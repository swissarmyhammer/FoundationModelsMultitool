---
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
position_column: todo
position_ordinal: 8f80
title: 'M4c: Guided turn format — @Generable union via respond(to:generating:)'
---
## What
The second of the two turn formats from plan.md "Router integration" (split out of M4b, which ships the loop + tolerant parse):
- `Sources/FoundationModelsMultitool/Agent/AgentTurn.swift` — a `@Generable` union type `{ findAPIs(task) | runCode(code) | final(text) }` (discriminated by a `kind` enum field, since Generable has no sum types) that Router guided generation can constrain to.
- Wire it as the selectable `guided` turn strategy in `MultiToolAgent`: each turn goes through the `AgentSession` seam's guided path (backed by Router `respond(to:generating:)` / `.jsonSchema` grammar), so every step is parseable by construction — no repair turn needed for format errors (tool-arg errors still repair via ResultRenderer).
- Strategy selection: `MultiToolAgent(turnFormat: .guided | .tolerantParse)`; default stays `.tolerantParse` until M6.5 settles the empirical winner.

## Acceptance Criteria
- [ ] With a scripted fake guided session, a full findAPIs → runCode → final scenario runs under `.guided` with zero repair turns
- [ ] The derived JSON schema for `AgentTurn` stays within Router's xgrammar subset (no `$ref`/`allOf`/`format`) — asserted via `Grammar.jsonSchema` validation logic or a fixture check
- [ ] Switching `turnFormat` changes only the turn strategy; loop semantics (dispatch, max-turns, error feedback) are shared code with M4b

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/GuidedTurnFormatTests.swift` — guided scenario end-to-end on the fake seam, schema-subset assertion, strategy-switch equivalence
- [ ] `swift test --filter GuidedTurnFormatTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.