---
assignees:
- claude-code
depends_on:
- 01M5F20JBW6YSTD6GM1X8VTYWZ
position_column: todo
position_ordinal: '8280'
title: 'SnapshotsGraph: changes(after:) subscription and cursor query (MT-13)'
---
## What
**Blocked outside this repo:** HOOKS-1 (change stream of `SnapshotStore`, FoundationModelsHooks, status agreed, not built) and EXTRAS-10 (`ChangeLog` + `RESYNC_REQUIRED` in the Extras toolkit, status proposed). Neither has an owning session yet. Do not start until both have landed on `main` and `swift package update` picks them up.

Following EXTRAS-9 rule 9 (TestudoApp `features/packages/foundationmodels-extras.md`, D115):
- `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraph.swift`: subscription `changes(after: String, sessionId: ID): SnapshotChange!`, where `SnapshotChange { cursor: String!, at: DateTime!, sessionId: ID!, added: [ID!]!, changed: [ID!]!, removed: [ID!]! }` (a new checkpoint is `added`). The client re-queries `checkpoint`. Root query `cursor: String!`.
- Event ids in `added`/`changed`/`removed` use the `<sessionId>:<index>` format of `Checkpoint.id`.
- Feed: one `ChangeLog<SnapshotChange>` per `SnapshotStore` (not per capability value, EXTRAS-9 rule 1), filled from the HOOKS-1 store stream; use `changes(after:where:)` for the `sessionId` filter and the viewer filter. A too-old, other-epoch or future cursor → `RESYNC_REQUIRED`.
- Alias table: `snapshotChanges` → `changes` (the MT-13 name).
- Viewer: an `external` viewer gets only the events of sessions it owns.

## Acceptance Criteria
- [ ] A `take` or rollback on the store gives one `SnapshotChange` with a newer cursor; its `added` id matches `checkpoint(...).id` (`<sessionId>:<index>`)
- [ ] `changes(after: cursor)` gives only later events; a too-old, other-epoch or future cursor gives `RESYNC_REQUIRED`
- [ ] `snapshotChanges` works through the alias
- [ ] An external viewer does not get events of sessions it does not own
- [ ] Two `SnapshotsCapability` values over one store give the same cursor

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphChangesTests.swift` against a real `SnapshotStore` in a temp dir, including: `added` matches `checkpoint(...).id`, and two `SnapshotsCapability` values over one store give the same cursor
- [ ] Update the SDL golden; conformance is empty with no rule-9 exception left
- [ ] `swift test --filter Snapshots` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.