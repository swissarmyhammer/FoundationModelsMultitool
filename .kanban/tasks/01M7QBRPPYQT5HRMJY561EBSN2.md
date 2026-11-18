---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qdvhdpqv5wft5fgfdacdwa
  text: |-
    Research done.
    - `SessionDirectory.sessions(matching:)` has no id order and no "after" key. The orders are newestFirst, pinOrder and lastUsedFirst. Thus the page resolver reads each match (limit `SessionsVisibility.unboundedLimit`), sorts by ULID, and cuts after the cursor.
    - An archived session is never live. Thus the default filter (includeRecorded false) already leaves it out, but includeRecorded true gives it. The page leaves out archived sessions unless the filter has `state: ARCHIVED`, so `includeRecorded: true` gives each session that is not archived (D199 (a)).
    - Plan: new field `Query.sessionPage(filter: SessionFilter, after: String): SessionPage!`, type `SessionPage { sessions: [Session!]!, nextCursor: String }`. The cursor is the id of the last session of the page. `after` is an argument of the field, not a field of `SessionFilter`: a field in the filter would also show on `sessions`, where it has no meaning. A text that is not a ULID gives the new code `INVALID_CURSOR`.
    - The schema golden file `Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql` must change (record with GRAPHQL_GOLDEN_RECORD=1).
    - Conventions kit: `GraphQLEndpointConformance.problems(of:scope:probes:codes:clock:)` in `SessionsGraphQueryTests.theEndpointConforms`.
  timestamp: 2026-11-18T13:34:33.910071+00:00
- actor: claude-code
  id: 01m7qe5e3xgvz2f9vds52m89zm
  text: |-
    Implementation landed.
    - New `Query.sessionPage(filter: SessionFilter, after: String): SessionPage!` and type `SessionPage { sessions: [Session!]!, nextCursor: String }` in `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphPages.swift`. The order is the ULID order. The limit of the filter is the page size (default 50, max 100). The resolver reads one session more than the page to know if a next page exists, thus a full last page has `nextCursor: null`.
    - A page has no archived session unless the filter has `state: ARCHIVED`. `includeRecorded: true` gives each session that is not archived.
    - `SessionsVisibility.sessionsInIDOrder(matching:after:where:)`: the visibility cut of the external viewer is now a shared helper `visible(among:limit:)`, which `sessions(matching:)` also uses. The `sessions` query and the `list sessions` op do not change.
    - New refusal code `INVALID_CURSOR` (`SessionsRefusal.Kind.invalidCursor`). `SessionsToolInput.requiredULID` is now internal, so the cursor reader uses it.
    - Aliases (D86) in `SessionsGraph.rules`: `sessionsPage`, `pagedSessions` -> `sessionPage`; `cursor` -> `after`; `items`, `nodes` -> `sessions`; `endCursor` -> `nextCursor`.
    - Deviation from the "Recommended" text: `after` is an argument of `sessionPage`, not a field of `SessionFilter`. A filter field would also show on `sessions`, where it has no meaning.
    - Golden `Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql` recorded: only the new type and field are added; `sessions` is the same.
    - Test ids use whole-second ULID timestamps: a millisecond step from 1_800_000_000 can truncate to the same millisecond in `ULID(timestamp:)`.

    ### implement — changed
    - evidence: 9 files — SessionsGraphPages.swift (new), SessionsGraph.swift, SessionsGraphSchema.swift, SessionsVisibility.swift, SessionsRefusal.swift, SessionsToolInput.swift, Tests/.../SessionsGraphPageTests.swift (new, 12 tests), Tests/.../Goldens/sessions.graphql; `swift build` complete; RED: `swift test --filter SessionsGraphPageTests` 11 of 12 failed; GREEN: `GRAPHQL_GOLDEN_RECORD=1 swift test --filter "SessionsGraphPageTests|SessionsGraphQueryTests"` 53 tests passed, 0 issues.
    - next: /test (full suite), then /review.
  timestamp: 2026-11-18T13:39:58.205275+00:00
- actor: claude-code
  id: 01m7qejkz0cfk7skfpwq5r2tv3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (da5809b9); 0 findings, 0 confirmed, 0 refuted; 7 files reviewed. The golden file Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql has no validator.
    - next: the task moves to done.
  timestamp: 2026-11-18T13:47:10.176164+00:00
- actor: claude-code
  id: 01m7qek5k4n933tfkcpqq435sb
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SessionsGraphPages.swift (new), SessionsGraph.swift, SessionsGraphSchema.swift, SessionsVisibility.swift, SessionsRefusal.swift, SessionsToolInput.swift, SessionsGraphPageTests.swift (new), Goldens/sessions.graphql
    - test: green — swift test, 2998 passed, 0 failed, 0 skipped
    - commit: da5809b9
    - review: clean — 0 findings
  timestamp: 2026-11-18T13:47:28.228400+00:00
position_column: done
position_ordinal: ffffffff8980
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

- [x] With 250 sessions that are not archived, the client reads all 250 in pages, each one time.
- [x] A session that starts during the read does not make a session show two times or not show.
- [x] An archived session is not in the pages, unless the filter asks for archived sessions.
- [x] An external viewer gets only the sessions that it can see, on each page.
- [x] The current `sessions` query gives the same answer as before.
- [x] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql