---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wvmxktd39qdsd3qhc5m6
  text: 'EXTRAS-10 landed (Extras f126153, on origin). Drop the interim local NOT_FOUND: use `GraphQLToolkitError.notFound(kind:id:)` from the toolkit. `swift package update FoundationModelsExtras` first.'
  timestamp: 2026-10-21T11:35:12.285578+00:00
- actor: claude-code
  id: 01m5f5g8d2te9xkzjpp64ss1rx
  text: |-
    Picked up. Research:
    - `swift package update FoundationModelsExtras` → Extras 02a207c (EXTRAS-10 + EXTRAS-11). `addToolkitIDScalar()` is NOT on Extras origin/main yet, so `Checkpoint.id` and the `sessionId` arguments are `String!` with a TODO naming ^70231sy.
    - Toolkit: `GraphQLToolkitError.notFound(kind:id:)` for NOT_FOUND; `GraphQLEndpointConformance.problems(of:scope:probe:codes:exceptions:)`; rule 7 asks `rollbackTimeline(input: RollbackTimelineInput!)`; rule 9 excepted (removedBy 01M5F225QGNMD545GC6MTS9MTV).
    - `SnapshotStore.checkpoints/rollback(sessionKey:owner:)` throw `SnapshotError.unavailable` when the owner has the key not open (unknown or released) → `[]` / null / NOT_FOUND. `rollback` gives nil when the work tree already equals the target → `rollbackTimeline` null.
    - `SnapshotsCapability.init` is non-throwing; Graphiti `SchemaBuilder.build()` throws. Plan: build the Graphiti schema once in a static `Result` (it does not depend on the store), so `SnapshotsGraph.init(store:sessionKey:)` stays non-throwing as the card writes it, and `execute`/`subscribe` throw a build fault.
    - Reuse `SnapshotCheckpoint.text(of:)` for the `trigger` text. Golden file: Tests/FoundationModelsMultitoolTests/Goldens/snapshots.graphql (read off disk through RepositoryFile.root).
  timestamp: 2026-10-21T12:03:16.514471+00:00
- actor: claude-code
  id: 01m5f5y9gvhv47yadhmrbpv1hd
  text: |-
    Implementation landed (TDD: SnapshotsGraphTests failed to compile on the missing `SnapshotsGraph`, then 23/23 green).
    - Correction to my research comment: the coordinator reported that the toolkit ID scalar landed. `swift package update FoundationModelsExtras` resolved Extras 9c47e10, which has `addToolkitIDScalar()` and `ToolkitID`. `Checkpoint.id` and every `sessionId` (arguments and `RollbackTimelineInput`) are `ID!`, and no String fallback or TODO for ^70231sy remains.
    - NOT_FOUND is the toolkit's `GraphQLToolkitError.notFound(kind: "session", id:)`. There is no local copy, so the EXTRAS-10 TODO the card describes is not needed. `SnapshotsGraphError` covers the 8 other store errors: SNAPSHOTS_NOT_AVAILABLE, NO_TIMELINE, INVALID_CHECKPOINT, WORKING_DIRECTORY_MISMATCH, CONFLICTING_TIMELINE, UNREADABLE_TIMELINE, SESSION_KEY_OPEN, INVALID_SESSION_KEY. `SnapshotError.unavailable` maps to NOT_FOUND.
    - The Graphiti schema is built once in a static `Result`. `SnapshotsGraph.init` and `SnapshotsCapability.init` therefore stay non-throwing, and `execute`/`subscribe` throw a build fault if the build failed.
    - `rollbackTimeline` gives null when the work tree already equals the target (the store adds no checkpoint).
    - Golden: Tests/FoundationModelsMultitoolTests/Goldens/snapshots.graphql (recorded with GRAPHQL_GOLDEN_RECORD=1).
    - Process slip: one test-file edit was made through a python heredoc in the shell instead of the files tool. Every later edit used the files tool.
  timestamp: 2026-10-21T12:10:56.411652+00:00
- actor: claude-code
  id: 01m5f5yc3xbkef0t6tyekgsadt
  text: |-
    ### implement — changed
    - evidence: `swift test` → 2561 tests in 222 suites passed, 0 failures, no compiler warnings (only SwiftPM's "missing creator" note for the mlx bundle); `swift test --filter SnapshotsGraphTests` → 23 passed. Files: Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraph.swift (new), SnapshotsGraphSchema.swift (new), SnapshotsCapability.swift; Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift (new), Tests/FoundationModelsMultitoolTests/Goldens/snapshots.graphql (new).
    - next: /review
  timestamp: 2026-10-21T12:10:59.069034+00:00
- actor: claude-code
  id: 01m5f66wyxcsx1q49wy2kp5xvz
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 2a30e09) — 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed; 4 files reviewed; .kanban/ ignored by .reviewignore; Goldens/snapshots.graphql matched no validator
    - next: task moved to done
  timestamp: 2026-10-21T12:15:38.461220+00:00
- actor: claude-code
  id: 01m5f679g22m5a2z84q1pyzk44
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SnapshotsGraph.swift, SnapshotsGraphSchema.swift, SnapshotsCapability.swift, SnapshotsGraphTests.swift, Goldens/snapshots.graphql
    - test: green — swift test, 2561 tests / 222 suites (run by implement)
    - commit: 2a30e09
    - review: clean — 0 findings
  timestamp: 2026-10-21T12:15:51.298948+00:00
depends_on:
- 01M5F200PV1QFFH82EK6197PXX
- 01M5F2FRK43MH90K2KVNK0RXQ2
position_column: done
position_ordinal: ffffffae80
title: 'SnapshotsGraph: checkpoint queries and rollbackTimeline mutation (MT-13)'
---
## What
MT-13 (TestudoApp `features/packages/foundationmodels-multitool.md:115`) under the conventions of EXTRAS-9 (`features/packages/foundationmodels-extras.md`, D115). This task covers queries and the mutation. Subscriptions and diffs are separate tasks (they need HOOKS-1 / HOOKS-2 / EXTRAS-10). Files: only `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraph.swift`, `SnapshotsGraphSchema.swift`, `SnapshotsCapability.swift` (same directory) and the test file.

- `SnapshotsGraph.swift` (+ `SnapshotsGraphSchema.swift`): `public struct SnapshotsGraph: GraphQLEndpoint`, name `snapshots`, version `"1"`, scope `.server`, `init(store: SnapshotStore, sessionKey: @escaping @Sendable (String) async -> String?)`. The `SnapshotStore` APIs take `sessionKey` (the lineage key) and `owner` (the session id), but a GraphQL call has only `sessionId`. The host-injected resolver maps a session id to its session key, and the session id is the owner. Built on the Extras toolkit only: `GraphQLRunContext`, `addToolkitScalars()`, `api.respond`, `GraphQLNameRules` (reference: `FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Settings/SettingsGraph.swift`).
- Queries: `checkpoints(sessionId: ID!): [Checkpoint!]!` (oldest first) and `checkpoint(sessionId: ID!, index: Int!): Checkpoint` (null when absent). `Checkpoint { id: ID!, index: Int!, trigger: String!, toolCallId: String, files: [String!]!, at: DateTime! }`; `Checkpoint.id` is `"<sessionId>:<index>"` (EXTRAS-9 rule 6). Mutation: `rollbackTimeline(input: RollbackTimelineInput!): Checkpoint` (`{sessionId, index}`), the new rollback checkpoint (D95). Alias probe: `listCheckpoints` → `checkpoints` (the toolkit strips query verbs like list/get) and `rollback` → `rollbackTimeline`.
- Unknown or released session (the resolver gives `nil`, or the store has no open timeline for the owner): `checkpoints` → `[]`, `checkpoint` → null, `rollbackTimeline` → `NOT_FOUND`. Checked: HOOKS-5 (Hooks c66f336, on Hooks `main`) adds only `SnapshotStore.timelineSummary(sessionKey:)` (count, last date, working directory) as a read of a closed timeline. It cannot list checkpoints, so a released session's checkpoints cannot be read through the store yet; leave a TODO naming HOOKS-5 there.
- Viewer (rule 4): `nil` and `userDevice` see every session; `external` only `viewer.owns(sessionId)`, otherwise query → `null`/`[]`, mutation → `NOT_FOUND`. Errors: `SnapshotsGraphError: CodedError` maps the store errors that `SnapshotsContext.correctiveMessage` handles (`SnapshotsContext.swift:88`) to `UPPER_SNAKE` codes (e.g. `NO_TIMELINE`, `INVALID_CHECKPOINT`, `CONFLICTING_TIMELINE`). Until EXTRAS-10 adds `NOT_FOUND` to the toolkit, `SnapshotsGraphError` gives the same code string `NOT_FOUND`; leave a TODO naming EXTRAS-10 to switch to the toolkit constant.
- `SnapshotsCapability.swift:54`: `init` gains an optional session-key resolver parameter whose default treats the session id as the key; document this. It overrides `graphQLEndpoints` directly and returns its one `SnapshotsGraph`, built once per capability instance over its store. Its verb tools are not `GraphQLEndpointTool`s, so the default would be empty.

## Acceptance Criteria
- [x] `SnapshotsGraph` conforms to `GraphQLEndpoint` with name `snapshots`, version `1`, scope `server`; `MultiTool.graphQLEndpoints` contains `snapshots` when the capability is registered
- [x] `checkpoints`/`checkpoint` return the store timeline through the session-key resolver; `Checkpoint.id` is `"<sessionId>:<index>"`; an unknown index gives `null`
- [x] An unknown or released session gives `[]` from `checkpoints`, null from `checkpoint` and `NOT_FOUND` from `rollbackTimeline`; the released case uses the HOOKS-5 read API where it can (`timelineSummary` cannot list checkpoints) and the code documents the limit with a TODO naming HOOKS-5
- [x] `rollbackTimeline` returns the new checkpoint; `rollback(...)` and `listCheckpoints` work through the aliases and show in `extensions.rewrites`
- [x] An `external` viewer cannot see or roll back a session it does not own

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift` against a real `SnapshotStore` in a temp dir: queries, rollback, viewer cases, error codes, unknown and released sessions
- [x] Same file: the `Checkpoint.id` format `"<sessionId>:<index>"` is stable; a stub resolver maps a session id to its key; the default resolver treats the session id as the key
- [x] Same file: `GraphQLSchemaGolden`, `GraphQLSchemaDescriptions.undescribed` empty, `GraphQLEndpointConformance.problems` empty with the alias probe (EXTRAS-9 rule 11); once EXTRAS-11 exists, rule 9 is listed as an exception naming 01M5F225QGNMD545GC6MTS9MTV
- [x] `swift test --filter Snapshots` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #snapshots