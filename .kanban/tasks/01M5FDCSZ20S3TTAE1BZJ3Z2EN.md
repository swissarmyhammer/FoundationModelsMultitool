---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5gf1h3g2bxt8pxhq3mg7cps
  text: |-
    Unblocked 2026-10-21: ACPA-13 is on ACPAgent main as a33bcf0, and Extras a9ae13b is resolved here.

    GraphQLViewer fields, filled from one locked read of the connection row:
    - clientId: the connection id
    - trust: the trust of the connection
    - ownedSessions: sessions this connection owns
    - clientOwnedSessions: sessions any connection owns
    - startedSessions: sessions this connection started (not unioned into owned)

    Implement:
    1. Sessions graph:
       - hasOwner = viewer.clientOwnedSessions.contains(id)
       - ownedByViewer = viewer.ownedSessions.contains(id)
       - With a nil viewer (the agent), these follow the task description (or false/false if it doesn't say). Note the choice.
    2. External visibility in SessionsVisibility: an external viewer sees owned sessions plus startedSessions, plus their subagents through the anchor chain. Check what the current code uses for "started" and switch it to viewer.startedSessions. The mutation rules (section 11.3) stay OWNED only.
    3. Snapshots graph: an external viewer currently sees only owned sessions. Widen this to owned ∪ startedSessions for queries and changes. Rollback stays OWNED only.

    Add tests for each viewer kind. Update the SDL goldens and descriptions.
  timestamp: 2026-10-22T00:09:14.096440+00:00
- actor: claude-code
  id: 01m5gf56xhz4yy35smr1c1e85y
  text: |-
    Research (implement):
    - Extras checkout is 589f27e, which has a9ae13b as ancestor: GraphQLViewer.startedSessions is present. No package update needed.
    - SessionsVisibility.sees(anchorChain:) is the one rule for sessions/session/children/inbox and the sessionChanges feed. "Started" today means only the startedBy anchor chain (sessions that an owned session started); the chain test was `externalViewer.owns(id)`. The fix widens the chain test to owned ∪ viewer.startedSessions and keeps the startedBy/parent anchor chain (section 11.3), so subagents and sessions started by a connection-started session show too.
    - Mutations go through SessionsGraphContext.ownedSession/viewerOwns, which call viewer.owns: they stay owned-only with no change. A started-not-owned session is now visible, so a mutation on it gives NOT_FOUND from ownedSession and a send gives the REFUSED not-owned receipt.
    - Snapshots: SnapshotsGraphContext.canSee gates checkpoints/checkpoint, the changes subscription filter, AND rollbackTimeline. Split: canSee = owned ∪ started; rollback gets an owned-only check.
    - Nil viewer: the task description gives no value, so hasOwner/ownedByViewer are false/false per the unblock comment (the agent is no client, and has no owner registry to read).
  timestamp: 2026-10-22T00:11:14.737663+00:00
- actor: claude-code
  id: 01m5gfq1jn4fpfxmjpvkqzhs57
  text: |-
    Implementation landed (not committed):
    1. Session.ownedByViewer = viewer.ownedSessions.contains(id); Session.hasOwner = viewer.clientOwnedSessions.contains(id). Same rule for each viewer kind. Nil viewer (the agent): false/false. The description gives no value, so this follows the unblock comment: the agent is no client and reads no owner registry.
    2. New `Capabilities/GraphQLViewerSessions.swift`: `GraphQLViewer.externalClient` and `GraphQLViewer.isOwnerOrStarter(of:)` (owned ∪ startedSessions). Both endpoints share them. SessionsVisibility.sees(anchorChain:) now tests owned ∪ started for each session of the chain. The startedBy/parent anchor chain stays, so subagents and the sessions that a started session started also show.
    3. Snapshots: canSee = owned ∪ started (checkpoints, checkpoint, Checkpoint.changes, the changes subscription). New canRollBack = owned only, used by rollbackTimeline. The sessionId description of the rollback input is now separate.
    4. Goldens regenerated with GRAPHQL_GOLDEN_RECORD=1. sessions.graphql adds the two fields and the new Query.sessions wording. snapshots.graphql changes only argument descriptions. Version stays 1.

    OPEN QUESTION for the reviewer and user: session.md 11.3 says `archive` works on "any session that the viewer can see (D72)", and archiveSession uses visibleSession. Wider visibility therefore also lets an external client archive a session that its connection started and that another client owns now. tag/untag/rename/send/reply stay owned-only, and tests cover them. I did not change archive, because 11.3 and D72 both define it as visibility-gated. If "sessions mutations stay owned-only" should cover archive too, archiveSession needs ownedSession instead of visibleSession, plus a D72 amendment.

    Note: the TDD RED step did not fail for the two new SessionsGraphMutationTests cases. I wrote them after the visibility change, as guards that the owned-only rules hold. Every other new test was seen failing first.
  timestamp: 2026-10-22T00:20:59.093748+00:00
- actor: claude-code
  id: 01m5gfq5b5kgc1mgcg3f4ar45q
  text: |-
    ### implement — changed
    - evidence: 13 files — Sources/.../Capabilities/GraphQLViewerSessions.swift (new), Sessions/SessionsVisibility.swift, Sessions/SessionsGraphSchema.swift, Snapshots/SnapshotsGraphSchema.swift, Snapshots/SnapshotsGraph.swift, Tests/.../SessionsGraphQueryTests.swift, SessionsGraphMutationTests.swift, SnapshotsGraphTests.swift, SnapshotsGraphChangesTests.swift, Goldens/sessions.graphql, Goldens/snapshots.graphql (+ .kanban card files). `swift test --filter "Sessions|Snapshots"`: 213 tests, 10 suites, 0 failures. `swift test`: 2715 tests, 229 suites, 0 failures. The only build warning is the pre-existing SwiftPM "missing creator for mutated node" for the mlx-swift_Cmlx bundle (dependency build graph, not project code).
    - next: /review. Open question on the archive rule (see the comment above).
  timestamp: 2026-10-22T00:21:02.949373+00:00
- actor: claude-code
  id: 01m5gg4pt533ww7vgebqze4waj
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (b78c88a): 3 findings (3 confirmed, 0 refuted) — Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraphSchema.swift:168, Tests/FoundationModelsMultitoolTests/SnapshotsGraphChangesTests.swift:582, Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift:941
    - next: implement the three open items in "Review Findings (2026-10-21 19:21)"; task stays in review
  timestamp: 2026-10-22T00:28:26.821789+00:00
- actor: claude-code
  id: 01m5gg58tavz4mxb0n949ds9wk
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 11 files
    - test: green — swift test, 2715 passed
    - commit: b78c88a
    - review: findings — SnapshotsGraphSchema.swift:168, SnapshotsGraphChangesTests.swift:582, SnapshotsGraphTests.swift:941
  timestamp: 2026-10-22T00:28:45.258006+00:00
- actor: claude-code
  id: 01m5gge76w51xn0ttk4hm866pg
  text: |-
    Review findings fixed (implement, iteration 2):
    1. duplication: added `protocol GraphQLViewerScoping { var viewer: GraphQLViewer? { get } }` to Capabilities/GraphQLViewerSessions.swift. Its extension owns `externalViewer` (viewer?.externalClient) and `admits(_ externalRule:)`, which applies a rule to an external client only (`externalViewer.map(rule) ?? true`). SessionsVisibility and SnapshotsGraphContext both conform and drop their private `externalViewer` copies. The same `map { } ?? true` / `guard let externalViewer else { return true }` shape is gone from both files: canSee, canRollBack and sees(anchorChain:) all call `admits`. Behavior is unchanged: the owned-only rollback, owned ∪ started visibility, and archive are as before. The archive decision is still pending with the user.
    2./3. The `externalViewer` helpers in SnapshotsGraphChangesTests and SnapshotsGraphTests now take `owning owned: Set<String> = [], started: Set<String> = []`, matching SessionsGraphQueryTests. The two started-session tests call `Self.externalViewer(started: [...])`. The existing changes-test call now passes `owning: [Self.secondSessionId]`.
    New unit suite GraphQLViewerScopingTests (2 tests): RED was a compile failure (missing type), then GREEN.
  timestamp: 2026-10-22T00:33:38.524003+00:00
- actor: claude-code
  id: 01m5ggeab2xvrzzsy5crsmh5a2
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Capabilities/GraphQLViewerSessions.swift, Capabilities/Sessions/SessionsVisibility.swift, Capabilities/Snapshots/SnapshotsGraphSchema.swift, Tests/FoundationModelsMultitoolTests/GraphQLViewerScopingTests.swift (new), SnapshotsGraphTests.swift, SnapshotsGraphChangesTests.swift. `swift test --filter "Sessions|Snapshots"`: 213 tests, 10 suites, 0 failures. `swift test`: 2717 tests, 230 suites, 0 failures. The only warning is the pre-existing SwiftPM "missing creator for mutated node" for the mlx-swift_Cmlx bundle. All 3 findings are checked.
    - next: /review. The archive question in the earlier comment is still open for the user.
  timestamp: 2026-10-22T00:33:41.730055+00:00
position_column: review
position_ordinal: '80'
title: 'SessionsGraph: Session.ownedByViewer and hasOwner (session.md 11.2)'
---
## What
session.md section 11.2 sketches `ownedByViewer: Boolean!` (D11: this client owns the session now) and `hasOwner: Boolean!` on `Session`. ^9c0fp9m shipped the queries without them: their value comes from the owner registry of ACPAgent (ACPA-5, ACPA-13) through `GraphQLViewer.ownedSessions` / `clientOwnedSessions`, and a call with no viewer (the agent) has no answer for either.
- Decide the value for a call with no viewer, then add both fields to `SessionsGraphSession` in `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphSchema.swift` / `SessionsGraphTypes.swift`, reading `context.sessions.viewer`.
- Update `Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql` (an added field keeps version 1).

## Tests
- [x] Case in `SessionsGraphQueryTests`: an external viewer that owns a session reads `ownedByViewer: true`, `hasOwner: true`; a session owned by another client reads `ownedByViewer: false`, `hasOwner: true`.
- [x] `swift test --filter SessionsGraph` passes. #graphql #sessions

## Review Findings (2026-10-21 19:21)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/Goldens/snapshots.graphql` — no validator matches this file

- [x] `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraphSchema.swift:168` `duplication/duplication` — Verbatim duplicate of the `externalViewer` computed property from SessionsVisibility.swift — both types implement identical logic to extract the external client from their viewer property. Extract the `externalViewer` computation into a shared protocol extension or helper method that both `SessionsVisibility` and `SnapshotsGraphContext` can use, eliminating the duplicate property.
- [x] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphChangesTests.swift:582` `completeness/invariant-propagation` — New test creates GraphQLViewer directly with startedSessions instead of using the externalViewer helper. SessionsGraphQueryTests updated its externalViewer to accept a started parameter (line 262-268), but SnapshotsGraphChangesTests's externalViewer (used in the existing test at line 561) was not similarly updated, forcing this new test to bypass the helper. Update the externalViewer helper in SnapshotsGraphChangesTests to accept a started parameter with a default value, matching the signature at SessionsGraphQueryTests line 262, so the new test can use the helper for consistency.
- [x] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift:941` `completeness/invariant-propagation` — New test creates GraphQLViewer directly with startedSessions instead of using the externalViewer helper. SessionsGraphQueryTests updated its externalViewer to accept a started parameter (line 262-268), but SnapshotsGraphTests's externalViewer (used in the existing test at line 924) was not similarly updated, forcing this new test to bypass the helper. Update the externalViewer helper in SnapshotsGraphTests to accept a started parameter with a default value, matching the signature at SessionsGraphQueryTests line 262, so the new test can use the helper for consistency.