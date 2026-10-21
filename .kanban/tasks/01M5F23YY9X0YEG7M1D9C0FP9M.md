---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3www750c3haqk1h8dfrfw
  text: 'EXTRAS-10 landed (Extras f126153, on origin). Drop the interim local NOT_FOUND: use `GraphQLToolkitError.notFound(kind:id:)` from the toolkit.'
  timestamp: 2026-10-21T11:35:13.543341+00:00
- actor: claude-code
  id: 01m5f66f909kc3d6ssarawnmr2
  text: 'EXTRAS-3 landed (Extras ceb37f7). Note: SessionQuery defaults to limit 20 (the tool''s list sessions); the graph''s `sessions` query must pass its own limit, 50 per session.md section 11.2. Origin type is SessionDirectoryOrigin.'
  timestamp: 2026-10-21T12:15:24.448166+00:00
depends_on:
- 01M5F236W9NXECHBE44PTMVYQZ
position_column: todo
position_ordinal: '8780'
title: SessionsGraph queries and visibility; SessionsTool gives it (MT-10)
---
## What
MT-10 (`session.md` sections 11.2-11.3 and 14) under EXTRAS-9 (TestudoApp `features/packages/foundationmodels-extras.md`, D115).
- New `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraph.swift` (+ schema file): `public struct SessionsGraph: GraphQLEndpoint`, name `sessions`, version `"1"`, scope `.server`, over `any SessionDirectory`, on the Extras toolkit only (reference: `FoundationModelsACPAgent/.../Settings/SettingsGraph.swift`).
- Queries: `sessions(...)` (filters from `SessionQuery`), `session(id: ID!)` (null when absent or not visible), `inbox(sessionId: ID!)`. `Session` has `id: ID!`, tags, title, agent, cwd, state, lastSummary, `children` (ACPC-2 reads the subagent tree from here). The `inbox` query is read-only and does NOT mark messages read (D72: only the tool's `read inbox` op marks them read).
- Visibility of section 11.3 and EXTRAS-9 rule 4: `nil`/`userDevice` see all; `external` sees only owned sessions, their subagents and the sessions they started. The rules live in one place shared by the tool and the graph (for example `SessionsVisibility.swift`), per MT-10.
- `SessionsTool` conforms to `GraphQLEndpointTool`; `graphQLEndpoints == [SessionsGraph]` over the same directory (D75, D76, D82). Alias tables for the name rewrite (D86); the alias probe uses `listSessions` → `sessions`.
- `NOT_FOUND`: until EXTRAS-10 adds it to the toolkit, use the same code string from the package's own `SessionsGraphError: CodedError`; leave a TODO naming EXTRAS-10 to switch to the toolkit constant.
- Conformance: once EXTRAS-11 exists, rule 9 is listed as an exception naming 01M5F24FFN8EJB0BGPD3XRY2W9.

## Acceptance Criteria
- [ ] `SessionsGraph` conforms with name `sessions`, version `1`, scope `server`
- [ ] `sessions`, `session(id:)` and `inbox` return directory data; an external viewer never sees a session it does not own or start
- [ ] The `inbox(sessionId:)` query does not mark messages read; a later `read inbox` tool op still gives them
- [ ] `(SessionsTool as any Tool) as? any GraphQLEndpointTool` gives `[SessionsGraph]`
- [ ] Rule-11 checks pass (golden, descriptions, conformance with the `listSessions` alias probe; rule 9 listed as an exception naming 01M5F24FFN8EJB0BGPD3XRY2W9)

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SessionsGraphQueryTests.swift` over `InMemorySessionDirectory`, one case per viewer kind
- [ ] Same file: an `inbox` query leaves the messages unread, and a following `read inbox` op still returns them
- [ ] `swift test --filter SessionsGraph` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #sessions