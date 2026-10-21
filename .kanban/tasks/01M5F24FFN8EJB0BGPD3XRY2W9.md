---
assignees:
- claude-code
depends_on:
- 01M5F23YY9X0YEG7M1D9C0FP9M
- 01M5F249SHTG5BWEM0HAF25EM5
position_column: todo
position_ordinal: '8980'
title: SessionsGraph changes(after:) subscription and cursor (MT-10)
---
## What
**Blocked outside this repo:** EXTRAS-10 (`ChangeLog`, `RESYNC_REQUIRED`) in FoundationModelsExtras. Also depends on 01M5F249SHTG5BWEM0HAF25EM5, which changes the same file and SDL golden.

In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraph.swift`, under EXTRAS-9 rule 9:
- `changes(after: String): SessionChange!` with `cursor: String!`, `at`, `added`, `changed`, `removed` (session ids), fed by `directory.events()` wrapped in one `ChangeLog<SessionChange>` per directory. Root query `cursor: String!`.
- A new root session shows up on this subscription as `added` (section 11.5).
- Alias: `sessionChanges` → `changes`.
- Viewer filtering through `changes(after:where:)`: an external viewer gets only the events of sessions it can see.
- The `ChangeLog` is built once per directory, not per `SessionsTool` copy. The tool is a value type that gets copied, so every copy must give the same cursor (EXTRAS-9 rule 1).

## Acceptance Criteria
- [ ] start/tag/send/archive each give one `SessionChange` with a newer cursor
- [ ] `changes(after:)` with a too-old, other-epoch or future cursor gives `RESYNC_REQUIRED`
- [ ] `sessionChanges` works through the alias
- [ ] Two copies of `SessionsTool` give endpoints with the same `cursor`
- [ ] An external viewer receives no event for a session it cannot see

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SessionsGraphChangesTests.swift`, including a case where an external viewer receives no event for a session it cannot see
- [ ] `swift test --filter SessionsGraph` passes; conformance has no rule-9 exception left

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.