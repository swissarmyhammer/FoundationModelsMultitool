---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: HeldOutSurfaceDiscoveryTests still says it is red at 9 of 22, and it now scores 16 and passes
---
## What

`heldOutRoundCorrectLevel` in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/HeldOutSurfaceDiscoveryTests.swift` carries this paragraph:

> **This level is the standard the surface owes a host, and the model does not meet it today.** ... Measured on 2026-09-10, all three rounds scored 9 of the 22 declared paths and returned 8 undeclared ones, and six queries found no declared path at all in any round. The suite is therefore red on a real, repeating defect, recorded on card `^kn9ay20`, and the level is not lowered to the measurement to make it green.

That is no longer true. Measured on 2026-09-10 while card `^kvefc5z` ran the gated suites:

    RESULT [heldOutSurfaceDiscovery] round=1 queries=15 correctTotal=16 wrongTotal=2
    RESULT [heldOutSurfaceDiscovery] round=2 queries=15 correctTotal=16 wrongTotal=2
    RESULT [heldOutSurfaceDiscovery] round=3 queries=15 correctTotal=16 wrongTotal=2

All three rounds scored 16 of 22 declared paths, over the level of 15, with 2 undeclared paths, and the suite passed in 40.3 s. Every query found a declared path, so the six queries the paragraph names as finding nothing now find something.

The most likely cause is card `^p06rh7z`, which rewrote all nine tool descriptions so each one names the work a person brings. That is what both the selection prompt and the retrieval tier read.

A doc comment that says a green suite is red is worse than no comment: a reader who trusts it will not believe a real failure later.

## What to do

- Read the paragraph beside `heldOutRoundCorrectLevel` and state what the measurement now is, with the date and the cause.
- Decide whether the level of 15 stands or rises. Three rounds each scored 16. A level at 16 would sit at the measurement, which is what `agentSurfaceRoundCorrectLevel` does and what that constant's own paragraph argues for. Say which, and why.
- Check the suite-level doc comment of `HeldOutSurfaceDiscoveryTests` for the same claim.
- Do not lower any level.

## Acceptance Criteria

- [ ] No doc comment of the file says the suite is red.
- [ ] The paragraph carries the new measurement, its date, and the card that most likely moved it.
- [ ] The level decision is written down with its reason.

## Tests

- [ ] `swift test --package-path IntegrationTests --no-parallel --filter HeldOutSurfaceDiscoveryTests`: passes, with the counts recorded on the card.

#discovery #search-tools #documentation