---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g0jxbnttk64287vn2e408w
  text: |-
    Unblocked 2026-10-21. HOOKS-1 is on Hooks main as 226bb35, and EXTRAS-10 ChangeLog is done (f126153). The resolved Hooks package is now at 226bb35.

    HOOKS-1 API:
    - `await store.changes() -> AsyncStream<SnapshotChange>`, where `SnapshotChange { sessionKey: String; checkpoint: Checkpoint }`.
    - There is one stream for the whole store, covering every key, including keys opened after you subscribe. Each call returns a new stream; cancelling a stream unsubscribes it, and all streams finish when the store deinits.
    - A change is sent after each checkpoint commit: take, pending, rollback(to:) and changedWhileClosed. A rollback over unrecorded changes sends 2 events. A take with no change sends nothing.
    - The stream only carries checkpoints made after `changes()` is called. Earlier ones come from `checkpoints(sessionKey:owner:)`. The buffer is unbounded, and order within a key is kept.

    Design notes:
    - One ChangeLog per SnapshotStore, fed by a single `changes()` subscription. Key it by store identity, the same way SessionsGraph does with `SessionsGraph.endpoint(of:)`. Two SnapshotsCapability values over one store must share it.
    - Event ids are `<sessionId>:<index>`. The store gives a sessionKey, so map it to a sessionId with the inverse of the capability's sessionKey resolver. The default resolver treats the key as the id.
    - The external-viewer rule (owned sessions only) needs ACPA-13, which is not built yet. For now, use the same visibility predicate SessionsGraph uses (SessionsVisibility) if it applies; otherwise filter nothing for nil and userDevice viewers, and filter everything for external viewers. Note which one you chose.
  timestamp: 2026-10-21T19:56:35.061174+00:00
- actor: claude-code
  id: 01m5g0sc3my2fn54qbkn998yx5
  text: |-
    Picked up; research done. Findings and design:
    - `SnapshotStore.changes()` is an actor method (async), so a feed made in a sync init cannot subscribe before it returns (SessionsGraphChangeFeed can, because `directory.events()` is sync). The feed therefore holds the subscribing Task, and the `cursor` query and the `changes` resolver await it before they read the log. Any checkpoint after a `cursor` reply is then in the log.
    - One feed per store: a weak table keyed by ObjectIdentifier(store), like `SessionsGraph.endpoint(of:)`. The feed holds the store strongly, so no other store can reuse the identifier while the feed lives.
    - The store has no key->owner API, so key->sessionId needs a host resolver. Added `sessionId: (String) async -> String?` (the inverse of `sessionKey`) to `SnapshotsGraph.init` and `SnapshotsCapability.init` (default: identity, matching the default `sessionKey`). The feed maps each change at record time and drops a key the host does not know (nil); the `where:` filter then works on the session id (sync), as the card asks.
    - Visibility choice: the endpoint's own `SnapshotsGraphContext.canSee` (nil/userDevice see all; external sees owned sessions via `GraphQLViewer.owns`). SessionsVisibility does not apply (no directory here).
    - Name clash: FoundationModelsHooks already has a `SnapshotChange` type; the Swift type is `SnapshotsGraphChange`, GraphQL name `SnapshotChange`.
  timestamp: 2026-10-21T20:00:06.772535+00:00
- actor: claude-code
  id: 01m5g19582nj85wbd6f9hvsk4v
  text: |-
    Implementation landed (not committed).
    - New `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraphChanges.swift`: `SnapshotsGraphChangeFeed` (one per store via a weak table keyed by ObjectIdentifier, with a weak store ref so a reused identifier is detected), `SnapshotChange` type (`SnapshotsGraphChange` in Swift; Hooks already owns the `SnapshotChange` name), `cursor` query, `changes(after:sessionId:)` subscription.
    - `SnapshotStore.changes()` is async, so the feed subscribes in a Task; `readyLog` awaits that subscription before the cursor query or a subscription reads the log, so every checkpoint after a returned cursor is in the log.
    - Public API change: `SnapshotsGraph.init(store:sessionKey:sessionId:)` now takes the inverse resolver (required). `SnapshotsCapability` now has `init(store:)` (identity both ways) and `init(store:sessionKey:sessionId:)`. The old `init(store:sessionKey:)` with a defaulted sessionKey is gone, so a host with lineage keys must give the inverse. The only in-repo callers were tests using `init(store:)`.
    - A checkpoint whose key the host's `sessionId` resolver does not know is dropped (no change), matching `checkpoints` giving nothing for it.
    - Visibility: uses the endpoint's own `SnapshotsGraphContext.canSee` (nil/userDevice see all; external only `viewer.owns(sessionId)`). SessionsVisibility does not apply here because there is no directory.
    - `SnapshotsGraphCheckpoint.id(sessionId:index:)` was extracted so the change ids and `Checkpoint.id` share one format.
    - An internal `changeLogCapacity:` init lets the too-old resync test use capacity 1. Without it the test would need 1025 real git snapshots.
    - Golden recorded with GRAPHQL_GOLDEN_RECORD=1. The conformance test now has the `snapshotChanges` subscription probe and no rule-9 exception.
  timestamp: 2026-10-21T20:08:44.034122+00:00
- actor: claude-code
  id: 01m5g1980bzsnjmnzmerqypetx
  text: |-
    ### implement — changed
    - evidence: `swift test --filter Snapshots` 69 tests / 4 suites passed; full `swift test` 2695 tests / 229 suites passed, 0 failures. The only build warning is SPM's pre-existing "missing creator for mutated node" for mlx-swift_Cmlx.bundle, which is unrelated. Files: Sources/.../Snapshots/{SnapshotsGraphChanges.swift (new), SnapshotsGraph.swift, SnapshotsGraphSchema.swift, SnapshotsCapability.swift}, Tests/.../{SnapshotsGraphChangesTests.swift (new), SnapshotsGraphTests.swift, Goldens/snapshots.graphql}
    - next: /review
  timestamp: 2026-10-21T20:08:46.859089+00:00
- actor: claude-code
  id: 01m5g1gwr9kvzjs6v1waf44xwg
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (31943bf) — 0 findings (0 confirmed, 0 refuted, 7 attempted, 0 failed); no prior Review Findings sections
    - next: task moved to done
  timestamp: 2026-10-21T20:12:57.481433+00:00
- actor: claude-code
  id: 01m5g1h8b79jwkfrd23rfr64gz
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files
    - test: green — swift test, 2695 passed
    - commit: 31943bf
    - review: clean
  timestamp: 2026-10-21T20:13:09.351670+00:00
depends_on:
- 01M5F20JBW6YSTD6GM1X8VTYWZ
position_column: done
position_ordinal: ffffffb880
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
- [x] A `take` or rollback on the store gives one `SnapshotChange` with a newer cursor; its `added` id matches `checkpoint(...).id` (`<sessionId>:<index>`)
- [x] `changes(after: cursor)` gives only later events; a too-old, other-epoch or future cursor gives `RESYNC_REQUIRED`
- [x] `snapshotChanges` works through the alias
- [x] An external viewer does not get events of sessions it does not own
- [x] Two `SnapshotsCapability` values over one store give the same cursor

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphChangesTests.swift` against a real `SnapshotStore` in a temp dir, including: `added` matches `checkpoint(...).id`, and two `SnapshotsCapability` values over one store give the same cursor
- [x] Update the SDL golden; conformance is empty with no rule-9 exception left
- [x] `swift test --filter Snapshots` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.