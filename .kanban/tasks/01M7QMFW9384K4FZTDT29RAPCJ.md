---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
title: The change feed gives a changed entry when a message goes into the queue or the inbox of a target (D199)
---
Decision: D199 (f) in TestudoApp/features/decisions.md. Request from the TestudoApp session, 2026-11-18: choice (a), the fix at the source.

Precondition (FoundationModelsExtras and FoundationModelsRouter): a new directory event when a message goes into the ledger or the inbox of a target. TestudoApp asks Extras and the Router for it. Before you start, examine origin/main of ../FoundationModelsExtras and ../FoundationModelsRouter, and read the name and the payload of the new event.

## Current behavior

- `SessionsGraphChanges.swift:56` maps `messageDelivered` to a `changed` entry of the target.
- Router 709d82c5 (^jf3j3v5) sends `messageDelivered` when the target takes the message (for a queued message, when its turn starts), not at send time.
- The Router writes the ledger when the mail goes in the queue. Thus `Session.unreadCount` of the target grows at send time, but the `changed` entry comes later. A recorded target (inbox file, receipt `sent`) gives no entry until its next open or inbox read. A client of `changes(after:)` shows an old `unreadCount` in that time.

## Work

- Map the new event to a `changed` entry of the target in `SessionChange` (`SessionsGraphChanges.swift`), with the anchor chain of the target, as for the other events.
- Keep `messageDelivered` as a `changed` entry too.
- Update the doc comments of the change feed.

## Tests

- [ ] A send to a working target gives a `changed` entry for the target at send time, and `unreadCount` is then 1.
- [ ] A send to a recorded target (receipt `sent`) gives a `changed` entry for the target.
- [ ] An external viewer gets the entry only for a session that it can see.
- [ ] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql #blocked-external