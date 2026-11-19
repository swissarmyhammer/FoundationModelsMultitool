---
assignees:
- claude-code
depends_on:
- 01M7SY6A33T5FEKCS8245E2JWW
position_column: todo
position_ordinal: '8280'
title: The searchSessions field of the sessions endpoint (D207)
---
Decision: D207 (d), (h) in TestudoApp/features/decisions.md (commit ba585e0). Brief: /Users/wballard/github/swissarmyhammer/.briefs/search/mt-brief.md, item 4.

Precondition: ^45e2jww (the host API `SessionsGraph.endpoint(of:exporter:searcher:)` and the request build of the operation; reuse that code, do not copy it).

## Work

- Add `searchSessions(query: String!, folder: String, session: ID, archived: Boolean = false, first: Int = 20, after: String): SessionSearchConnection!` on `Query`.
- Types: `SessionSearchConnection { results, nextCursor, unavailableFolders }`, `SessionSearchResult { session: Session!, score: Float!, hitCount: Int!, hits }`, `SessionSearchHit { entryId, kind: SessionSearchHitKind!, author, at: DateTime, snippet, ranges: [TextRange!]!, terms }`, `TextRange { start, end }`, `SessionSearchHitKind { USER AGENT MESSAGE TOOL PLAN THOUGHT SESSION }`.
- `session` is the `Session` of the endpoint, read from the directory, so a client gets the current name, folder, state, recap and archived mark.
- With `session:`, the field gives all hits of that session, up to `first`.
- The same visibility rule as `sessions` (D72 (c)).
- No searcher: the refusal of the endpoint with the MISSING_SEARCHER text of the tool (reuse it).
- Follow D115 (EXTRAS-9) and keep the EXTRAS-11 kit green. Aliases (D86). Re-record the golden schema; the diff only adds lines.

## Tests

- [ ] A query of `searchSessions` with a fake searcher gives the results, `score`, `hits`, `terms`, `ranges` and a `SESSION` hit.
- [ ] `session` gives the fields of the directory, for example the name after a rename.
- [ ] `session:` gives all hits of one session.
- [ ] An external viewer gets only the sessions that it can see.
- [ ] No searcher: the refusal.
- [ ] The SDL has the new types. #sessions #search #graphql