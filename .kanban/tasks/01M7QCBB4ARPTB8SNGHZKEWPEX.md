---
assignees:
- claude-code
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: todo
position_ordinal: '8480'
title: The session id of check session and of each change operation takes a short id and @slug (D200)
---
Decision: D200 (e) in TestudoApp/features/decisions.md, after D199. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-sessions-skill.md, item 3.

Precondition: the address reader of ^6xznegm. Use the same resolver. Do not write a second lookup (D100).

## Current behavior

The `id` of `check session`, `rename session`, `pin session`, `unpin session`, `tag session`, `untag session` and `archive session` is a full ULID only: `SessionsToolInput.sessionID(_:)` (`Capabilities/Sessions/SessionsToolInput.swift:44-78`) through `ulid(_:)` (`:142`). The skill of D200 gives examples with a short id, so they fail today.

## Work

- The `id` of each of these operations takes `<id>`, `@<id>`, `<short id>`, `@<short id>` and `@<slug>`, with the resolver of ^6xznegm, filtered by the visibility of the caller. The lookup looks first in the folder of the caller.
- The resolver is async, so the sync `sessionID(_:)` becomes an async reader for these operations. An `id` that is absent still means the caller session, where it does so today.
- An ambiguous reference gives the corrective with the id, the name and the folder of each match, and changes nothing.
- A reference with no match gives the corrective that names `list sessions`. It does not start an agent: only `send message` starts an agent.
- Update the `@Guide` text of each `id`, and `SessionsToolText.notASessionID`.
- The `reply message` operation keeps a message id. This task does not change it.

## Tests

- [ ] `rename session` with a short id acts on that session.
- [ ] `pin session` with `@<slug>` acts on that session.
- [ ] `archive session` with `@<short id>` acts on that session.
- [ ] `check session` with a full id, with and without `@`, still works.
- [ ] An ambiguous slug gives the corrective with each match and changes nothing.
- [ ] A slug of a session that the caller cannot see is not a match.
- [ ] The existing session tool tests stay green. #sessions #at-sessions