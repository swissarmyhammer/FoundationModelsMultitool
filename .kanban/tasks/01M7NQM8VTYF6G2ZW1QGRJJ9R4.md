---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qbmbef05yahjapnpr1pxev
  text: |-
    ### finish — skipped (blocked-external)
    - evidence: 2026-11-18, `git fetch` of ../FoundationModelsExtras: origin/main is 1c69b4f and has no `shortID`, `slug`, `SessionReference` or `sourceSession`. The local Extras tree has the work in progress (uncommitted changes in Tests/FoundationModelsExtrasTests/Sessions).
    - next: start when the Extras change is on origin/main. The TestudoApp session will tell this session.
  timestamp: 2026-11-18T12:55:41.263958+00:00
- actor: claude-code
  id: 01m7qbre5ya5zepjryt06rwkaq
  text: |-
    Added test (TestudoApp needs it, 2026-11-18): the app keeps its list of sessions current from `changes(after:)`, and reads `shortId` and `slug` from it.
    - [ ] A rename of a session gives a `changed` entry on `changes(after:)`, and the session then has the new `slug`.
    - [ ] An archive of a session gives a `changed` entry on `changes(after:)`.
    Today the code already does this (`factsChanged` for a rename, `.archived` maps to `changed` at `SessionsGraphChanges.swift:57`). The tests make sure that it stays true.
  timestamp: 2026-11-18T12:57:55.134546+00:00
position_column: todo
position_ordinal: '80'
title: Session.shortId and Session.slug in the sessions endpoint and the tool (D199)
---
Decision: D199 (b) in TestudoApp/features/decisions.md. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-at-sessions.md, item 4 and item 6.

Precondition: FoundationModelsExtras gives `SessionSummary.shortID` and `SessionSummary.slug` on origin/main. Before you start, examine origin/main of ../FoundationModelsExtras. When it does not have them, the task stays blocked.

## Work

- Add `shortId: String!` and `slug: String` to the `Session` type (`Capabilities/Sessions/SessionsGraphSchema.swift:396-402`) and to `SessionsGraphSession`. Read them from `SessionSummary.shortID` and `SessionSummary.slug`. Do not make a second slug rule or short id rule here.
- `list sessions` of the `sessions` tool shows the short id and the slug of each session.
- Add the aliases of the new names to the alias tables of `SessionsGraph` (D86), for example `short_id`, `shortID`.

## Tests

- [ ] `Session.shortId` and `Session.slug` are correct in `sessions`, `pinnedSessions` and `recentSessions`.
- [ ] A query with the alias `short_id` gives the same value as `shortId`.
- [ ] `list sessions` of the tool shows the short id and the slug.
- [ ] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql #blocked-external