---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7nqpt95rwz0gzzgatt3j0gy
  text: 'Extras API (from the Extras session, 2026-11-17): `sourceSession` is on `OutgoingSessionMessage` and on `SessionMessage`. There is no new event: `messageDelivered(SessionMessage)` carries the sender, so a test can read `sourceSession` from that event.'
  timestamp: 2026-11-17T21:48:16.037086+00:00
- actor: claude-code
  id: 01m7qhb4mxp9e9j8t6mvyvvcpx
  text: |-
    Research (implement):
    - Precondition is true. origin/main of ../FoundationModelsExtras (b87233e) has `OutgoingSessionMessage.sourceSession` and `SessionMessage.sourceSession`. Package.resolved pins b87233ec.
    - `SessionsVisibility.messageAddress(_:from:)` (SessionsAddressReader.swift) gets the lookup folder only from `workingFolder(of: sender)`. A user sender has no lookup folder. Plan: add the parameter `sourceFolder: URL? = nil`. The lookup folder is `sourceFolder`, else the folder of the sender. The `send message` op of the tool does not change.
    - `SessionsGraphContext.ownedSession(_:)` already gives NOT_FOUND for a session that the viewer cannot see, or that an external viewer does not own. Plan: add `ownedSummary(_:)` and let `ownedSession` call it, so the source check uses the same rule.
    - `SessionsToolContext.send(text:to:inReplyTo:from:)` makes the `OutgoingSessionMessage`. Plan: add `sourceSession: ULID? = nil`.
    - A session caller with a different `fromSession`: no refusal code fits. Plan: add `SessionsRefusal.Kind.sourceNotCaller = "SOURCE_NOT_CALLER"` with a corrective in `SessionsGraphText`.
    - `from_session` matches by step 2 of `NameMatcher` (word style). `fromSessionId` needs the alias table. Both go into the `adding:` table of `SessionsGraphMutation.send`.
    - The golden file Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql changes: `SendMessageInput` gets `fromSession: ID`.
  timestamp: 2026-11-18T14:35:30.845257+00:00
- actor: claude-code
  id: 01m7qhm8vdw6421pn0haqfrtdk
  text: |-
    ### implement — changed
    - evidence: 7 files. Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphMutations.swift (alias table, `SessionsGraphText.sourceNotCaller`, `ownedSummary`, `sourceSession(_:of:)`, `address(_:from:sourceFolder:)`, resolver, schema field), SessionsGraphTypes.swift (`fromSession: ToolkitID?`), SessionsRefusal.swift (new code `SOURCE_NOT_CALLER`), SessionsAddressReader.swift (`messageAddress(_:from:sourceFolder:)`), SessionsToolMessageOperations.swift (`send(..., sourceSession:)`), Tests/FoundationModelsMultitoolTests/SessionsGraphMutationTests.swift (6 new tests, 8 cases), Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql (re-recorded; the diff only adds `fromSession: ID` and its description).
    - RED: the 6 new tests failed one time (unknown field). GREEN: `swift test --filter "SessionsGraph|SessionsTool"` 187 tests in 9 suites passed, with the conformance test (EXTRAS-11) and the golden test. Full `swift test`: 3024 tests in 270 suites passed. The only warning is the build-system warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle, which `swift build` gave before this change too.
    - Discovery: `from_session` matches through step 2 of `NameMatcher` (word style) without the table; the table lists it too, as the card asks. The check of `fromSession` comes before the address reader, so a source that the viewer cannot use stops the send before the address.
    - next: review.
  timestamp: 2026-11-18T14:40:30.061443+00:00
- actor: claude-code
  id: 01m7qhrwffnd8mgt11sjj3asq3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (087c3789): 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. Files not reviewed: 2 .kanban files (ignore rule), Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql (no validator matches).
    - next: none. The task is in done.
  timestamp: 2026-11-18T14:43:01.231428+00:00
- actor: claude-code
  id: 01m7qhs7z0gv3wf83ayjt9drt1
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SessionsGraphMutations, SessionsGraphTypes, SessionsRefusal (SOURCE_NOT_CALLER), SessionsAddressReader, SessionsToolMessageOperations, SessionsGraphMutationTests, golden schema (adds only)
    - test: green — swift test, 3024 passed (run in the implement step)
    - commit: 087c3789
    - review: clean — 0 findings
  timestamp: 2026-11-18T14:43:12.992100+00:00
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: done
position_ordinal: ffffffff8c80
title: 'SendMessageInput.fromSession: the source session of a send from the app (D199)'
---
Decision: D199 (f) in TestudoApp/features/decisions.md. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-at-sessions.md, item 3 and item 6.

Precondition: FoundationModelsExtras gives `OutgoingSessionMessage.sourceSession` on origin/main. Before you start, examine origin/main of ../FoundationModelsExtras. When it does not have it, the task stays blocked. This task also uses the address reader of ^6xznegm.

## Current behavior

`SendMessageInput` (`SessionsGraphMutations.swift:662-672`, type `SessionsGraphTypes.swift:437`) has `to` and `message`. It has no source session. The sender of `Mutation.sendMessage` is `context.actor(of: .send)` (`:172-177`), `.user(clientID:)` for a viewer.

## Work

- Add the optional field `fromSession: ID` to `SendMessageInput`.
- The viewer must see the session. An external viewer must also own it. A session that the viewer cannot see gives `NOT_FOUND`.
- With a `.user` sender, `fromSession` sets `OutgoingSessionMessage.sourceSession`. The working folder of that session is the `sourceFolder` of the address reader.
- With a session caller, the caller is the source. A `fromSession` that is not the caller is refused.
- Add the aliases, for example `fromSessionId` and `from_session` (D86).
- Follow the conventions of D115 (EXTRAS-9) and examine them with the test kit (EXTRAS-11).

## Tests

- [x] `sendMessage(input: {to: "@fix-the-api-tests", message: "...", fromSession: <id>})` gives a receipt, and the in-memory directory gets `sourceSession`.
- [x] The slug resolves in the folder of the `fromSession` session first.
- [x] A `fromSession` that the viewer cannot see gives `NOT_FOUND`.
- [x] A session caller with a different `fromSession` is refused.
- [x] The alias `fromSessionId` works.
- [x] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql