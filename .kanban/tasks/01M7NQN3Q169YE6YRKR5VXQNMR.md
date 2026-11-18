---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7nqpt95rwz0gzzgatt3j0gy
  text: 'Extras API (from the Extras session, 2026-11-17): `sourceSession` is on `OutgoingSessionMessage` and on `SessionMessage`. There is no new event: `messageDelivered(SessionMessage)` carries the sender, so a test can read `sourceSession` from that event.'
  timestamp: 2026-11-17T21:48:16.037086+00:00
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: todo
position_ordinal: '8280'
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

- [ ] `sendMessage(input: {to: "@fix-the-api-tests", message: "...", fromSession: <id>})` gives a receipt, and the in-memory directory gets `sourceSession`.
- [ ] The slug resolves in the folder of the `fromSession` session first.
- [ ] A `fromSession` that the viewer cannot see gives `NOT_FOUND`.
- [ ] A session caller with a different `fromSession` is refused.
- [ ] The alias `fromSessionId` works.
- [ ] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql