---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wy98g6fw28mzj1tptaf3
  text: 'EXTRAS-10 landed (Extras f126153, on origin). Drop the interim local NOT_FOUND: use `GraphQLToolkitError.notFound(kind:id:)` from the toolkit. For changes cards: `ChangeLog<Event>` + `ChangeLogEntry`, and `ChangedIDs`/`IDChange` in IDChange.swift fit SessionChange.'
  timestamp: 2026-10-21T11:35:14.984742+00:00
- actor: claude-code
  id: 01m5fed7z4ag2kyzv8vn6mhr8w
  text: |-
    Research done. Pattern to follow: SnapshotsGraph (rollbackTimeline(input:), byType["Mutation"] alias, GraphQLToolkitError.notFound). Design:
    - Shared core: SessionsToolContext gets throwing actions (start/changeTags/rename/archive/send/replyTarget) that both the tool ops and the mutations call. The tool turns each error into its corrective text (unchanged answers); the graph turns it into a coded error.
    - SessionsToolInputError is renamed SessionsRefusal and becomes a CodedError (a code kind + the corrective text), so the tool and the endpoint give the same refusal text. SessionDirectoryError.unknownSession and a reply to an unknown message map to the toolkit NOT_FOUND (kinds `session` and `message`).
    - Actor: a viewer acts as `.user(clientID)` (start: origin client, requestedByClient = client, so only that client gets the tab, D90); viewer nil acts as the caller session from ToolContext (origin tool, startedBy caller), the same request as the op.
    - 11.3 rules: an external viewer acts only on sessions it can see (else NOT_FOUND); start is userDevice only (11.3), so an external start is refused; an external send must name a session id.
    - InMemorySessionDirectory emits `.started(summary, requestedByClient:)`, which the tests read for the tab rule.
    - Reply in the graph needs the session that got the message (`SessionDirectory.message(_:to:)` takes the recipient), so ReplyMessageInput has `sessionId: ID!`.
  timestamp: 2026-10-21T14:38:54.948479+00:00
- actor: claude-code
  id: 01m5fffjyhc9657tz8svrwsepb
  text: |-
    Implementation landed (TDD: SessionsGraphMutationTests failed first with "Schema is not configured for mutations", then green).
    - Shared core: `SessionsToolContext` now holds the work of each change (`start(_:by:)`, `addTags`, `removeTags`, `rename`, `archive(_:by:)`, `send(_:to:inReplyTo:from:)` with a `SessionMessageSender`, `replyTarget(of:to:)`). The tool ops and the mutations both call it; the tool answers are unchanged.
    - `SessionsToolInputError` was renamed `SessionsRefusal` and is now a `CodedError` (kind + corrective text). New file SessionsRefusal.swift, also with `SessionsUnknownMessage` (tool: unknownMessage corrective; graph: NOT_FOUND kind `message`). `SessionsGraphError` is gone: its two codes are `SessionsRefusal` kinds now, and NOT_FOUND is `GraphQLToolkitError.notFound(kind:id:)` (the card's interim local NOT_FOUND rule was obsolete per the earlier comment).
    - New file SessionsGraphMutations.swift: `SessionsGraphMutation` derives each mutation name from `OperationVerbTool.verbName(for: op.opString)`, the bare-verb alias from `op.verb`, and the input field aliases from `op.parameterMetadata` (so the graph aliases follow the op aliases). Resolvers, the who-acts rule, the coded-error mapping, and the schema parts are in that file too.
    - Who acts: a viewer acts as `.user(clientID)` (start: origin CLIENT, requestedByClient = the client, startedBy nil, so only that client opens a tab); viewer nil acts as the caller session from ToolContext (origin TOOL, startedBy the caller), and with no caller it gets MISSING_CALLER with the tool's corrective.
    - Section 11.3 rules: an external viewer gets NOT_FOUND for a session it cannot see (tag/untag/rename/archive/send target/reply recipient/reply sender); an external start gets UNTRUSTED_CLIENT; an external send must name a session id (else INVALID_ADDRESS).
    - ReplyMessageInput has `sessionId: ID!` (the session that got the message), because `SessionDirectory.message(_:to:)` needs the recipient. StartSessionInput has an optional `agentId`, as the op has.
    - Gotcha: `OperationDefinition` is ambiguous between the Operations and GraphQL modules; it is spelled `Operations.OperationDefinition`.
    - Gotcha: `InMemorySessionDirectory.register` emits `.started` too, so a test must match the started event by session id.
    - Golden recorded with GRAPHQL_GOLDEN_RECORD=1. The conformance test now passes `SessionsRefusal.codes`, with only the rule-9 exception (01M5F24FFN8EJB0BGPD3XRY2W9).
    - New codes (UPPER_SNAKE, qualifier first): INVALID_MESSAGE_ID, INVALID_ADDRESS, INVALID_VALUE, INVALID_TAG, MISSING_TAGS, BLANK_TEXT, UNKNOWN_AGENT, MISSING_LAUNCHER, DEEP_CHAIN, LONG_MESSAGE, ARCHIVED_SESSION, USER_MESSAGE, MISSING_CALLER, UNTRUSTED_CLIENT (plus the existing INVALID_FOLDER, INVALID_SESSION_ID).
    - Could not tick the acceptance boxes in the description: `update task` returns the whole board (134k chars) and errors out on output size. All acceptance criteria and tests are met.
  timestamp: 2026-10-21T14:57:40.305828+00:00
- actor: claude-code
  id: 01m5fffw1kvkkr0316jqhsqah6
  text: |-
    ### implement — changed
    - Correction to the previous comment: the description update did go through, and the acceptance boxes are ticked. Only the tool response was too large to show.
    - evidence: `swift test`: 2673 tests in 227 suites passed, 0 failures, no compiler warnings. `swift test --filter Sessions`: 113 tests in 6 suites passed. 17 files touched: Sources/.../Sessions/{SessionsGraph,SessionsGraphSchema,SessionsGraphTypes,SessionsToolChangeOperations,SessionsToolContext,SessionsToolInput,SessionsToolMessageOperations,SessionsToolOperations,SessionsToolText,SessionsToolText+Changes}.swift (modified), SessionsGraphMutations.swift and SessionsRefusal.swift (new); Tests/.../SessionsGraphMutationTests.swift (new), SessionsGraphQueryTests.swift, Fixtures/GraphQLReply.swift, Goldens/sessions.graphql (modified).
    - next: /review
  timestamp: 2026-10-21T14:57:49.619784+00:00
- actor: claude-code
  id: 01m5ffqnd3ej53g4ys9g4wwtxp
  text: |-
    ### implement — changed (coordinator correction: ownership, not visibility, per session.md 11.3)
    - External tag/untag/rename now require `viewer.owns(id)`: a session the client sees but does not own gives the toolkit NOT_FOUND (`SessionsGraphContext.ownedSession`). Archive still needs only visibility.
    - External sendMessage to a session id it sees but does not own, and replyMessage whose original sender it does not own, return one REFUSED receipt with reason `SessionsGraphText.notOwnedReason`, and no message goes. Hidden sessions still give NOT_FOUND.
    - Tests (TDD, red first): the external scene now has a subagent of the owned session. New: tag/untag/rename of that subagent gives NOT_FOUND although `session(id:)` shows it; send/reply to it gives REFUSED with the reason and changes nothing; send to the owned session is DELIVERED from the external client's user. The tag-of-owned test stays green.
    - evidence: `swift test` — 2676 tests in 227 suites passed, 0 failures, no compiler warnings. Files: Sources/.../Sessions/SessionsGraphMutations.swift, Tests/.../SessionsGraphMutationTests.swift.
    - next: /review
  timestamp: 2026-10-21T15:02:04.963345+00:00
- actor: claude-code
  id: 01m5ffxxt3q6qqcxa97mg7jbjr
  text: |-
    step: implement (SDL descriptions follow the ownership rule)
    - tag/untag/rename inputs: `id` says "A session that you cannot see, or that an external client does not own, is NOT_FOUND." archive keeps "cannot see" (D72).
    - SendMessageInput.to, ReplyMessageInput.inReplyTo, and the sendMessage/replyMessage fields now say: "An external client sends only to a session that it owns: a session that it sees but does not own gives a REFUSED receipt." ReplyMessageInput.sessionId says that a session you cannot see is NOT_FOUND.
    - Re-recorded Goldens/sessions.graphql.
    - `swift test --filter Sessions`: 116 tests in 6 suites passed. Full `swift test`: 2676 tests in 227 suites passed, no warnings.
    - The task stays in doing, not committed.
  timestamp: 2026-10-21T15:05:30.179071+00:00
depends_on:
- 01M5F23YY9X0YEG7M1D9C0FP9M
- 01M5F23F0NMKMEXGZESNEZB6S0
- 01M5F23K19C0N3TH4A2AZJPXDF
position_column: doing
position_ordinal: '80'
title: SessionsGraph mutations (MT-10)
---
## What
In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraph.swift`, under EXTRAS-9 rule 7 (TestudoApp `features/packages/foundationmodels-extras.md`):
- `startSession`, `tagSession`, `untagSession`, `renameSession`, `sendMessage`, `replyMessage`, `archiveSession`, each `verbNoun(input: VerbNounInput!)`, named after the tool verbs in code mode. Each returns the changed `Session` (send/reply return the receipt).
- The alias tables accept the bare verbs of `session.md` 14 (`start`, `tag`, `untag`, `rename`, `send`, `reply`, `archive`); rewrites show in `extensions.rewrites`.
- A start from a client opens a tab only for that client (section 11.5, D90). `StartSessionInput` has no `openInTab`.
- Mutation rules of section 11.3: an `external` viewer acts only on sessions it can see, otherwise `NOT_FOUND`. Until EXTRAS-10 adds `NOT_FOUND` to the toolkit, use the same code string from the package's own `SessionsGraphError: CodedError`; leave a TODO naming EXTRAS-10 to switch to the toolkit constant.
- The tool ops and the mutations share the correctives and limits, so both give the same refusal text.

## Acceptance Criteria
- [x] Each mutation changes the `InMemorySessionDirectory` the same way the matching tool op does
- [x] Each bare-verb alias works and is reported in `extensions.rewrites`
- [x] An external viewer gets `NOT_FOUND` (from `SessionsGraphError` until EXTRAS-10) for a session it cannot see
- [x] The SDL golden is updated

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/SessionsGraphMutationTests.swift`, including a parity test that runs each tool op and its mutation on two fresh directories and compares the result
- [x] `swift test --filter SessionsGraph` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #sessions