---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f8k2be9b75bs54g4dhzfgp
  text: 'Decided by the coordinator (owner of session.md): drop `limit` from `read inbox` in session.md section 8.2. The Extras port does not change. Done in the docs commit that follows ^ptmvyqz.'
  timestamp: 2026-10-21T12:57:14.350026+00:00
position_column: done
position_ordinal: ffffffaf80
title: read inbox limit needs a SessionDirectory.inbox limit (session.md 8.2)
---
## What
session.md section 8.2 gives `read inbox` a `limit` parameter (default 10). `SessionDirectory.inbox(of:markRead:)` (FoundationModelsExtras EXTRAS-3) marks EVERY unread message read and takes no limit, so a `limit` in the tool would consume messages that the model never sees. ^ptmvyqz therefore built `read inbox` with no `limit`: it shows each unread message that it marks read (`Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsToolOperations.swift`, `ReadInbox`).

Decide one of:
- add a limit to the port (for example `inbox(of:markRead:limit:)`, which marks only the messages it gives) in FoundationModelsExtras, then add `limit` to `ReadInbox`; or
- change session.md 8.2 to drop `limit` from `read inbox`.

## Acceptance Criteria
- [ ] session.md 8.2 and the `read inbox` op agree on `limit`
- [ ] No message is marked read that the answer does not hold

## Tests
- [ ] If `limit` lands: a `SessionsToolReadTests` case with more unread messages than the limit; the second read gives the rest #sessions #blocked-external