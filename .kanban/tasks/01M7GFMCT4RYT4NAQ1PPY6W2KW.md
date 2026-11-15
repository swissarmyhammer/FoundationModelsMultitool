---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7gfnsb8ez7wj93cc7fprf5a
  text: 'Agreed with testudoapp-75: no markSessionUsed mutation. ACPAgent calls markUsed on session/new and session/load (ACPA-9). The app reads pinnedSessions and recentSessions, follows sessionChanges, and sends pinSession and unpinSession.'
  timestamp: 2026-11-15T20:51:41.544085+00:00
depends_on:
- 01M7GFM9D95YVQQNVZAFA5RF47
position_column: done
position_ordinal: ffffffff8180
title: 'MT-10: pinSession and unpinSession mutations and their sessionChanges events'
---
TestudoApp Step 2 (D184, D118). Add to the `sessions` endpoint:

- Mutation `pinSession(id: ID!): Session!` and `unpinSession(id: ID!): Session!`, through `SessionDirectory.setPinned`. These are control actions (D84), so a UI client can call them. A session that the viewer cannot see gives the same refusal as the other mutations.
- Each change of the Pinned or Recent list gives a `sessionChanges` event (`changed`, with the session id). The directory sends `factsChanged` for `setPinned` and `markUsed`, and the change feed maps it.
- Pin and unpin are idempotent: a second pin keeps the pin order.

Precondition: the Extras pin API is on Extras origin/main. Depends on the queries task.

Tests: use `InMemorySessionDirectory`. Pin, unpin, and pin again; check the lists after each step and the events in `changes(after:)`.