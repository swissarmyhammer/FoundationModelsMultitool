---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5fjrtx8fkt1d6s5fdh3pn2t
  text: |-
    Research (implement):
    - Extras at 6716646 (Package.resolved already there; `swift package update FoundationModelsExtras` changed nothing). `ChangeLog.changes(after:where:)` takes a SYNC `@Sendable (Event) -> Bool`, but `SessionsVisibility` is async (it walks the anchor chain through the directory). Plan: the feed reads the anchor chain of the session when it records the event (the chain never changes), and the event carries it; the `where` filter then runs the shared rule synchronously over that chain (`SessionsVisibility.sees(chain:)`), and `isVisible` uses the same two halves.
    - `IDChange` can only be built from `ChangeLogEntry<ChangedIDs>` and `ChangeLogEntry` has no public init, so an event that carries the chain cannot map through `IDChange`. The endpoint gets its own `SessionChange` output type with the same rule-9 fields (cursor String!, at DateTime!, added/changed/removed [ID!]!).
    - Directory events (SessionDirectoryEvent): started -> added; factsChanged, stateChanged, messageDelivered (the target), archived -> changed. No directory event removes a session (archive keeps it, state ARCHIVED), so `removed` is always empty today. Each directory event names exactly one session, so filtering whole events is filtering ids, and an event a viewer cannot see is never sent.
    - In-memory directory: `start` emits `started` then `stateChanged(working)` (the first turn begins), and a send to an IDLE target emits `messageDelivered` then `stateChanged`. So a start gives two SessionChanges (added, then changed). Coalescing them is not safe (a client that fetched between the two would keep a stale state), so the start test expects added then changed, each with a newer cursor; tag, archive and a send to a working target give exactly one.
    - `SessionsGraph.endpoint(of:)` keeps endpoints weakly; `SessionsTool` holds its endpoint strongly, so copies share one ChangeLog. The feed task captures the log and the directory, never the endpoint, and `deinit` cancels it. `directory.events()` is called in init so no event between creation and the task start is lost.
  timestamp: 2026-10-21T15:55:09.096963+00:00
- actor: claude-code
  id: 01m5fk8g7arzzsb46rsmwvd4xp
  text: |-
    Implementation landed (TDD: SessionsGraphChangesTests written first; RED was the compile error on the missing `SessionsGraph.changeLogCapacity`, then GREEN).
    - New `SessionsGraphChanges.swift`: `SessionsGraphChangeFeed` (final class, one per endpoint; `ChangeLog<SessionsGraphChangeEvent>` + the feed Task; asks `directory.events()` in init, `deinit` cancels the task; the Task never captures the feed or the endpoint). Each directory event -> one change: started -> added; factsChanged/stateChanged/messageDelivered(target)/archived -> changed; `removed` is always empty (the directory removes no session). The event carries the session's anchor chain, read once by the feed; the `where` filter applies `SessionsVisibility.sees(anchorChain:)`.
    - Deviation from the card wording, with reason: the log is `ChangeLog<SessionsGraphChangeEvent>` (not `ChangeLog<SessionChange>`) and the output type is the endpoint's own `SessionChange` (`SessionsGraphChange`), not `IDChange`: the event must carry the anchor chain for the sync `where` filter, and `IDChange` can only be built from `ChangeLogEntry<ChangedIDs>` (ChangeLogEntry has no public init). The SDL shape is exactly rule 9.
    - `SessionsVisibility` now exposes the rule in two halves: `anchorChain(of:)` (async, directory) and `sees(anchorChain:)` (sync); `isVisible` uses both, so the queries and the subscription share one rule.
    - A directory error while reading the chain: `assertionFailure` + error log `session anchor chain read failed` (new `MultitoolTelemetry.LogMessage.sessionAnchorChainReadFailed`), and the chain falls back to the session alone (fails closed for external viewers).
    - Alias `Subscription.changes` <- `sessionChanges`; `SessionsGraph.changeLogCapacity = 1024`.
    - Start gives TWO changes in order: `added` then `changed` (the in-memory and real directories emit `started` then `stateChanged(working)`). Coalescing would leave a client that fetched in between with a stale state, so the start test asserts added then changed with increasing cursors; tag, archive and a send to a working session each give exactly one change (proved by a marker change that follows).
    - Conformance: rule-9 exception and `changesTask` constant removed; a `.subscription` probe for `sessionChanges` (read `cursor`, register one session, subscribe after the cursor) with `ManualRunClock`. Golden re-recorded (+SessionChange, Query.cursor, Subscription.changes).
    - Known limit (not in scope): the viewer is a snapshot at subscribe time, so a session the client comes to own after it subscribed is not visible to that subscription.
  timestamp: 2026-10-21T16:03:42.442792+00:00
- actor: claude-code
  id: 01m5fk8mx3x8snwahv0r1v0wp9
  text: |-
    ### implement — changed
    - evidence: `swift test` -> 2684 tests in 228 suites passed, 0 failures, no compiler warnings; files: Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphChanges.swift (new), SessionsGraph.swift, SessionsGraphSchema.swift, SessionsVisibility.swift, Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift, Tests/FoundationModelsMultitoolTests/SessionsGraphChangesTests.swift (new), SessionsGraphQueryTests.swift, Goldens/sessions.graphql
    - next: /review
  timestamp: 2026-10-21T16:03:47.235962+00:00
- actor: claude-code
  id: 01m5fkny7tj957gx6v6j7jypdb
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (9d556d6) — 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsMultitoolTests/SessionsGraphQueryTests.swift:345 (completeness/inverse-operation-coverage)
    - next: implementer resolves the unchecked item in the 2026-10-21 11:04 Review Findings section, then re-run /review
  timestamp: 2026-10-21T16:11:02.778474+00:00
- actor: claude-code
  id: 01m5fkpbmk85kjgmht0f8z2rha
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files (SessionsGraphChanges, visibility split, schema, tests, golden)
    - test: green — swift test, 2684 tests / 228 suites (run by implement)
    - commit: 9d556d6
    - review: findings — SessionsGraphQueryTests.swift:345
  timestamp: 2026-10-21T16:11:16.499457+00:00
- actor: claude-code
  id: 01m5fkxvfw41s654j1yh73r4nh
  text: |-
    Resolved the review finding at SessionsGraphQueryTests.swift (completeness/inverse-operation-coverage), the stronger way:
    - The probe document is now the constant `sessionChangesSubscription` and selects `cursor added changed removed` (it was `{ cursor }`). `{ cursor }` is now the constant `cursorQuery`.
    - `GraphQLAliasProbe` has no data assertion (FoundationModelsExtras GraphQLTestKit: the subscription probe checks only the rewrite and that no error came back), so the id is asserted in a sibling test, `theFirstSessionChangesResponseAddsTheRegisteredSession`. It subscribes with the same document after the same cursor, reads the first response, and expects no error, `added == [registered id]`, `changed == []` and `removed == []`.
    - A shared setup struct, `RegisteredAfterCursor` (directory, the endpoint, the cursor, then one registered live root session), feeds both tests. It holds the endpoint strongly. `SessionsGraph.endpoint(of:)` caches endpoints weakly, and a new endpoint has a new ChangeLog epoch, so if the endpoint were dropped between reading the cursor and subscribing, the result would be RESYNC_REQUIRED.
    - The conformance doc comment now says exactly what each probe checks (the rewrite, and no error), says that the probe does not read the data, and names the sibling test that does.
    - TDD: RED was the sibling test against the old `{ cursor }` selection (added/changed/removed came back nil, 3 issues). GREEN came after widening the selection.
    - Note: `swift test` prints one SwiftPM/llbuild line, `warning: missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS`. It comes from the dependency resource bundle during an incremental build, not from a compiler diagnostic in this repo, and this change touched only one test file.
  timestamp: 2026-10-21T16:15:22.108818+00:00
- actor: claude-code
  id: 01m5fkxxjqgbxd5x6nnw05hyyg
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/SessionsGraphQueryTests.swift; `swift test` -> 2685 tests in 228 suites passed, 0 failures (one llbuild "missing creator for mutated node" line for the mlx-swift_Cmlx bundle, no compiler warnings); review finding checked
    - next: /review
  timestamp: 2026-10-21T16:15:24.247128+00:00
- actor: claude-code
  id: 01m5fm2xzqj2mhwvvmek4m13tn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (64f159f): 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed; 1 file reviewed, 2 .kanban files excluded by .reviewignore. Prior finding SessionsGraphQueryTests.swift:345 completeness/inverse-operation-coverage is checked; fixed by sessionChangesSubscription requesting `cursor added changed removed` and the new test theFirstSessionChangesResponseAddsTheRegisteredSession asserting added == [registered session id], changed == [], removed == [].
    - next: task moved to done.
  timestamp: 2026-10-21T16:18:08.503748+00:00
- actor: claude-code
  id: 01m5fm3cjva34s735yxt5a823k
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — SessionsGraphQueryTests.swift (probe reads added; sibling test)
    - test: green — swift test, 2685 tests / 228 suites (run by implement)
    - commit: 64f159f
    - review: clean — 0 findings, 1/1 prior checked
  timestamp: 2026-10-21T16:18:23.451655+00:00
depends_on:
- 01M5F23YY9X0YEG7M1D9C0FP9M
- 01M5F249SHTG5BWEM0HAF25EM5
position_column: done
position_ordinal: ffffffb680
title: SessionsGraph changes(after:) subscription and cursor (MT-10)
---
## What
**Blocked outside this repo:** EXTRAS-10 (`ChangeLog`, `RESYNC_REQUIRED`) in FoundationModelsExtras. Also depends on 01M5F249SHTG5BWEM0HAF25EM5, which changes the same file and SDL golden.

In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraph.swift`, under EXTRAS-9 rule 9:
- `changes(after: String): SessionChange!` with `cursor: String!`, `at`, `added`, `changed`, `removed` (session ids), fed by `directory.events()` wrapped in one `ChangeLog<SessionChange>` per directory. Root query `cursor: String!`.
- A new root session shows up on this subscription as `added` (section 11.5).
- Alias: `sessionChanges` → `changes`.
- Viewer filtering through `changes(after:where:)`: an external viewer gets only the events of sessions it can see.
- The `ChangeLog` is built once per directory, not per `SessionsTool` copy. The tool is a value type that gets copied, so every copy must give the same cursor (EXTRAS-9 rule 1).

## Acceptance Criteria
- [x] start/tag/send/archive each give one `SessionChange` with a newer cursor
- [x] `changes(after:)` with a too-old, other-epoch or future cursor gives `RESYNC_REQUIRED`
- [x] `sessionChanges` works through the alias
- [x] Two copies of `SessionsTool` give endpoints with the same `cursor`
- [x] An external viewer receives no event for a session it cannot see

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/SessionsGraphChangesTests.swift`, including a case where an external viewer receives no event for a session it cannot see
- [x] `swift test --filter SessionsGraph` passes; conformance has no rule-9 exception left

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-21 11:04)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql` — no validator matches this file

- [x] `Tests/FoundationModelsMultitoolTests/SessionsGraphQueryTests.swift:345` `completeness/inverse-operation-coverage` — The docstring claims the subscription probe verifies 'its first response is that change' — that the change registered in the write direction comes through in the subscription response. However, the subscription query at lines 345–346 only requests `{ cursor }`, not the change itself. The test verifies the subscription alias works and accepts the cursor parameter, but does not verify the expected change appears in the response. Either clarify the docstring to document that the test verifies only the alias and cursor parameter work (not full round-trip), or expand the subscription query to request change fields (e.g., `added`, `removed`, or `changed`) to confirm the registered change appears in the response.