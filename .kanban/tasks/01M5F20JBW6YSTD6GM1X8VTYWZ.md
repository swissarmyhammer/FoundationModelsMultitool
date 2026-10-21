---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wvmxktd39qdsd3qhc5m6
  text: 'EXTRAS-10 landed (Extras f126153, on origin). Drop the interim local NOT_FOUND: use `GraphQLToolkitError.notFound(kind:id:)` from the toolkit. `swift package update FoundationModelsExtras` first.'
  timestamp: 2026-10-21T11:35:12.285578+00:00
depends_on:
- 01M5F200PV1QFFH82EK6197PXX
- 01M5F2FRK43MH90K2KVNK0RXQ2
position_column: todo
position_ordinal: '8180'
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
- [ ] `SnapshotsGraph` conforms to `GraphQLEndpoint` with name `snapshots`, version `1`, scope `server`; `MultiTool.graphQLEndpoints` contains `snapshots` when the capability is registered
- [ ] `checkpoints`/`checkpoint` return the store timeline through the session-key resolver; `Checkpoint.id` is `"<sessionId>:<index>"`; an unknown index gives `null`
- [ ] An unknown or released session gives `[]` from `checkpoints`, null from `checkpoint` and `NOT_FOUND` from `rollbackTimeline`; the released case uses the HOOKS-5 read API where it can (`timelineSummary` cannot list checkpoints) and the code documents the limit with a TODO naming HOOKS-5
- [ ] `rollbackTimeline` returns the new checkpoint; `rollback(...)` and `listCheckpoints` work through the aliases and show in `extensions.rewrites`
- [ ] An `external` viewer cannot see or roll back a session it does not own

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift` against a real `SnapshotStore` in a temp dir: queries, rollback, viewer cases, error codes, unknown and released sessions
- [ ] Same file: the `Checkpoint.id` format `"<sessionId>:<index>"` is stable; a stub resolver maps a session id to its key; the default resolver treats the session id as the key
- [ ] Same file: `GraphQLSchemaGolden`, `GraphQLSchemaDescriptions.undescribed` empty, `GraphQLEndpointConformance.problems` empty with the alias probe (EXTRAS-9 rule 11); once EXTRAS-11 exists, rule 9 is listed as an exception naming 01M5F225QGNMD545GC6MTS9MTV
- [ ] `swift test --filter Snapshots` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #snapshots