---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: The sessions query can list all the sessions that are not archived (D199)
---
Decision: D199 (a), (d) in TestudoApp/features/decisions.md. Request from the TestudoApp session, 2026-11-18: the app keeps a list of all the sessions that are not archived, and it resolves each `@` mention in memory from that list. It reads `id shortId slug title cwd` of each session.

## Current behavior

- `Query.sessions(filter:)` gives at most `limit` sessions, the newest first. The default is 50 (`SessionsGraphResolver.defaultListLimit`, `Capabilities/Sessions/SessionsGraphSchema.swift:34`). The maximum is 100 (`SessionsToolInput.maximumListLimit`, `Capabilities/Sessions/SessionsToolInput.swift:20`).
- There is no page cursor. Thus a client with more than 100 sessions cannot get all of them.

## Work

- Let a client get all the sessions that are not archived. Recommended: a page cursor. Add an `after` argument to the filter (the cursor of the last session of the page before) and a cursor on each page (for example `SessionPage { sessions, nextCursor }`, or the connection style that the endpoint already uses, when it has one). The order of the pages must be stable when a new session starts during the read: use the session id (ULID) order, or another stable key, not the recency order.
- Do not break the current `sessions` query. When a new type is necessary, add a new field (for example `sessionPage`) and keep `sessions`.
- The `list sessions` operation of the tool can stay at the limit of 100.
- Follow the conventions of D115 (EXTRAS-9) and examine them with the test kit (EXTRAS-11). Add aliases for the new names (D86).
- No precondition: this task does not need the Extras change.

## Tests

- [ ] With 250 sessions that are not archived, the client reads all 250 in pages, each one time.
- [ ] A session that starts during the read does not make a session show two times or not show.
- [ ] An archived session is not in the pages, unless the filter asks for archived sessions.
- [ ] An external viewer gets only the sessions that it can see, on each page.
- [ ] The current `sessions` query gives the same answer as before.
- [ ] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql