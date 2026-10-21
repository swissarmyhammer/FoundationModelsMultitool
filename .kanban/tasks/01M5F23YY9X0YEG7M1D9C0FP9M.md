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
- actor: claude-code
  id: 01m5fc9c1vr145s62ndrtkgp5z
  text: |-
    Picked up. Research:
    - Reference: SnapshotsGraph (static `builtSchema`, `GraphQLRunContext` with viewer, `GraphQLToolkitError.notFound`). Agents/Skills make the endpoint a `final class` owned by the port (registry) so every tool copy gives `===` the same endpoint.
    - Here the port is `any SessionDirectory` (Extras protocol, only `Sendable`), so it cannot hold the endpoint. Both real directories are reference types (`InMemorySessionDirectory` final class, `RouterSessionDirectory` actor). Plan: a process-wide table keyed by the directory's object identity that holds each endpoint weakly; `SessionsTool.init(directory:)` keeps its shape and takes the endpoint from that table, so two inits over one directory and every copy give the same `SessionsGraph`.
    - Visibility (session.md 11.3, EXTRAS-9 rule 4): nil/userDevice see all; external sees a session when it, or an anchor up its chain (a subagent's `parentID`, a root's `startedBy`), is owned. The rule goes in `SessionsVisibility.swift`; the tool's context reads the directory through it with a nil viewer (the agent), the graph with the call's viewer.
    - External list: the directory cuts at `query.limit` before filtering, so the graph asks the directory with no cut for an external viewer and cuts after the filter (else visible sessions past the first 50 would vanish).
    - Scope of this card: queries only. Mutations are ^b0r8yk5-style card 01M5F249SHTG5BWEM0HAF25EM5, `changes(after:)` is 01M5F24FFN8EJB0BGPD3XRY2W9 (rule-9 exception).
  timestamp: 2026-10-21T14:01:50.907863+00:00
- actor: claude-code
  id: 01m5fddz1td5cge6d9d55m4h0a
  text: |-
    Implementation landed (not committed). Notes for review:
    - Correction to my first comment: the mutations card is 01M5F249SHTG5BWEM0HAF25EM5 (the "^b0r8yk5" I wrote there is not a real id).
    - `SessionsGraph` is a `public final class`, not the `public struct` the card text names: the brief asks for two tool copies to give the identical graph (EXTRAS-9 rule 1), and Agents/Skills make their endpoint a final class for `===`. `SessionsGraph.endpoint(of:)` is the only way to get one: a process-wide `Mutex<[ObjectIdentifier: weak endpoint]>` keyed by the directory's identity, so every `SessionsTool(directory:)` over one directory, and every copy, gives the same instance. A value-type directory (no identity) gets a new endpoint per call. Without that guard, `directory as AnyObject` boxes the struct, and a later box could take a freed address.
    - NOT_FOUND: these are queries only, and EXTRAS-9 rules 4/5 make a missing or hidden session `null` (or left out of a list), never an error. So this card uses no NOT_FOUND code and needs no TODO. EXTRAS-10 has landed, so the mutations card should use `GraphQLToolkitError.notFound(kind:id:)`.
    - Coded errors: `INVALID_FOLDER` (relative `cwd` in the filter) and `INVALID_SESSION_ID` (an id argument that is not a ULID). Their messages are the tool's own correctives (`SessionsToolText.relativeFolder` / `notASessionID`). Ids are read in any letter case through `SessionsToolInput.sessionID`.
    - Shared rules: `SessionsVisibility` is the one visibility rule. The tool's `list sessions` and `check session` (`existingSummary`) now read through it with a nil viewer. The listing rule (ARCHIVED also finds recorded sessions, limit clamped to 1...100) moved to `SessionsToolInput.listQuery(_:includeRecorded:limit:defaultingTo:)`. The tool passes 20 and the graph passes 50.
    - External visibility follows the anchor chain: a subagent's `parentID`, else `startedBy`. A fork is not made visible by its original. For an external viewer the directory is asked with `SessionsVisibility.unboundedLimit` and the limit is applied after filtering. A test pins this: an owned session older than 60 hidden ones still lists.
    - Schema beyond the card's field list, taken from the 11.2 sketch: `agentName`, `kind`/`state`/`origin` enums (UPPER_SNAKE), `parent`, `startedBy`, `createdAt`, `updatedAt`, `isLive`, `unreadCount`, and the `Message`/`Sender` types for `inbox`. `children` gives subagents only, live or recorded. Aliases: `Session.agent`→`agentId`, `Session.folder`→`cwd`, `session(sessionId:)`→`id`, `inbox(id:)`→`sessionId`.
    - Left out: `ownedByViewer` and `hasOwner` (they need the ACPA owner registry, and have no answer for a nil viewer). Filed as task 01M5FDCSZ20S3TTAE1BZJ3Z2EN.
    - Test fixtures: added `Fixtures/GraphQLReply.swift` (a shared response reader) and `Fixtures/ForwardingSessionDirectory.swift` (a value-type directory). `SessionsToolFixtures.summary` gained `kind`, `parentID` and `startedBy`. SnapshotsGraphTests still has its own private `Reply` copy, so moving it onto `GraphQLReply` is filed as task 01M5FDCWQBNC26M13F3J5JB8AN.
    - TDD honesty: the filter cases and the value-type-directory case passed on their first run. The filter input and the identity guard were written in cycle 1, because the endpoint needed a schema to exist. Every other case went RED first.
  timestamp: 2026-10-21T14:21:50.010272+00:00
- actor: claude-code
  id: 01m5fde3v3x8akpmfj5xeh6tvx
  text: |-
    ### implement — changed
    - evidence: `swift test` 2658 tests in 226 suites passed, 0 failures, no compiler warnings; then, after a test-file-only line wrap, `swift test --filter SessionsGraph` 36 tests passed. 13 files: new Sources/.../Sessions/SessionsGraph.swift, SessionsGraphSchema.swift, SessionsGraphTypes.swift, SessionsVisibility.swift; changed SessionsTool.swift, SessionsToolContext.swift, SessionsToolInput.swift, SessionsToolOperations.swift; new Tests/.../SessionsGraphQueryTests.swift, Fixtures/GraphQLReply.swift, Fixtures/ForwardingSessionDirectory.swift, Goldens/sessions.graphql; changed Fixtures/SessionsToolFixtures.swift
    - next: /review (task left in doing, not committed)
  timestamp: 2026-10-21T14:21:54.915012+00:00
- actor: claude-code
  id: 01m5fe04gdjk8cszrc9swjc114
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (c272c95) — 0 findings (14 attempted, 1 refuted, 0 failed); 12 files reviewed; 8 .kanban files skipped by .reviewignore; Goldens/sessions.graphql matched no validator
    - next: task moved to done
  timestamp: 2026-10-21T14:31:45.421546+00:00
- actor: claude-code
  id: 01m5fe0fmcewmkfktqkb1qvapr
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 13 files (SessionsGraph, schema, types, visibility, tool changes, tests, fixtures, golden)
    - test: green — swift test, 2658 tests / 226 suites (run by implement)
    - commit: c272c95
    - review: clean — 0 findings
  timestamp: 2026-10-21T14:31:56.812013+00:00
depends_on:
- 01M5F236W9NXECHBE44PTMVYQZ
position_column: done
position_ordinal: ffffffb480
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
- [x] `SessionsGraph` conforms with name `sessions`, version `1`, scope `server`
- [x] `sessions`, `session(id:)` and `inbox` return directory data; an external viewer never sees a session it does not own or start
- [x] The `inbox(sessionId:)` query does not mark messages read; a later `read inbox` tool op still gives them
- [x] `(SessionsTool as any Tool) as? any GraphQLEndpointTool` gives `[SessionsGraph]`
- [x] Rule-11 checks pass (golden, descriptions, conformance with the `listSessions` alias probe; rule 9 listed as an exception naming 01M5F24FFN8EJB0BGPD3XRY2W9)

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/SessionsGraphQueryTests.swift` over `InMemorySessionDirectory`, one case per viewer kind
- [x] Same file: an `inbox` query leaves the messages unread, and a following `read inbox` op still returns them
- [x] `swift test --filter SessionsGraph` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #sessions