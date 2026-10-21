---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: 'Port: look up a received message by id, so reply message drops its in-tool record'
---
## What
`reply message` (^azjpxdf) must find the sender of the message `inReplyTo`. The Extras `SessionDirectory` port gives no message by its id: `inbox(of:markRead:)` gives only unread messages, and `read inbox` marks each message read. So `SessionsTool` keeps `SessionsToolReceivedMessages` (Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsToolReceivedMessages.swift), an in-memory record of what `read inbox` gave, one per tool instance, capped at 1000 messages.

Limits of that record: it is lost when the host makes a new `SessionsTool` or the process restarts, and two tool instances over one directory do not share it. The Router keeps each message (with `inReplyTo` and the read flag) in `messages.jsonl` already (session.md section 6 notes).

Proposal: add `func message(_ id: MailID, to session: ULID) async throws -> SessionMessage?` (read or unread) to `SessionDirectory` in FoundationModelsExtras, implement it in `InMemorySessionDirectory` and the Router, then make `SessionsToolContext.receivedMessage(_:by:)` call it and delete `SessionsToolReceivedMessages`.

## Acceptance Criteria
- [ ] The port gives a delivered message by id, read or unread, only to the session it went to
- [ ] `reply message` resolves `inReplyTo` through the port; `SessionsToolReceivedMessages` is gone
- [ ] A reply to a message read in an earlier tool instance works

## Tests
- [ ] `SessionsToolMessageTests` reply cases pass with a fresh `SessionsTool` between `read inbox` and `reply message`
- [ ] `swift test` passes

#sessions