---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffff80
title: 'MT-10: pinnedSessions and recentSessions queries of SessionsGraph'
---
TestudoApp Step 2 (D184, D118, APP-21). Add to the `sessions` endpoint:

- `Session.pinned: Boolean!` and `Session.lastUsedAt: DateTime` (from `SessionSummary.pinned` and `SessionSummary.lastUsedAt`).
- Query `pinnedSessions: [Session!]!`: the pinned sessions that the viewer can see, in pin order.
- Query `recentSessions(limit: Int): [Session!]!`: the sessions with a `lastUsedAt` that are not pinned, newest first. The viewer rules apply.
- The client reads `id`, `title`, `cwd` for each row.

Multitool reads the pins and the last-used times only through `SessionDirectory` and `SessionSummary`, not a file (storage design of foundationmodelsacpagent-30 and foundationmodelsextras-0a).

Precondition: the FoundationModelsExtras API (`SessionSummary.pinned`, `lastUsedAt`, a pin order, `SessionDirectory.setPinned`, `markUsed`, the in-memory directory support) is on Extras origin/main.

Tests: use `InMemorySessionDirectory`. Pin two sessions, use three; check the order of each list, that a pinned session is not in the recent list, and that a session that the viewer cannot see is not in either list.