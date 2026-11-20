---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7vadqnk1aqvyqx29f40wmdb
  text: |-
    Research done.
    - The resolver `importableSessions` calls `SessionsGraphImportableArguments.listArguments(callerFolder:)`, which makes an `ImportListArguments`. `SessionsVisibility.importableRequest(for:)` (SessionsToolImportOperations.swift) sets `preferredFolder` from `callerFolder`. Thus `callerFolder` has two jobs today: the folder of `.` and the folder that comes first.
    - Plan: add `preferredFolder: URL?` to `ImportListArguments` (default nil). The request uses `preferredFolder ?? callerFolder`. The tool op `list imports` does not set it, so the tool does not change. The endpoint argument `preferredFolder: String` goes through `SessionsToolInput.folder` (the reader of `searchSessions`), so `~` expands and a relative path (also `.`) gives INVALID_FOLDER. `listArguments` becomes throwing; the resolver calls it inside `Self.coding`, so the refusal gets its code.
    - The alias table is `SessionsGraph.rules` (byField `Query.importableSessions`). The golden SDL test is `SessionsGraphQueryTests.theSchemaMatchesTheGoldenFile`, with the file Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql.
  timestamp: 2026-11-20T01:51:33.555402+00:00
- actor: claude-code
  id: 01m7vanj38v6tfw202rb7x562y
  text: |-
    ### implement — changed
    - evidence: 5 files. Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphImport.swift (argument `preferredFolder`, read with `SessionsToolInput.folder`; `listArguments` now throws; descriptions and top comment), SessionsToolImportOperations.swift (`ImportListArguments.preferredFolder`; the request uses `preferredFolder ?? callerFolder`), SessionsGraph.swift (doc comment and the alias `preferred_folder`), Tests/FoundationModelsMultitoolTests/SessionsGraphImportTests.swift (7 new tests: client with and with no argument, agent with and with no argument, relative path gives INVALID_FOLDER, the alias, the SDL argument), Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql (re-recorded with GRAPHQL_GOLDEN_RECORD=1, filter on the golden test).
    - RED: 5 new tests failed (unknown argument). The 2 cases with no argument passed at once, because they guard the behavior that exists now. GREEN: `swift test --filter SessionsGraphImportTests` gave 37 passed. Full run: `swift test` gave 3347 tests in 286 suites passed, exit 0. The only warning is the build system line `missing creator for mutated node` of the mlx bundle, which is not from this change.
    - The tool op `list imports` does not change: it does not set `preferredFolder`.
    - next: review.
  timestamp: 2026-11-20T01:55:49.992326+00:00
- actor: claude-code
  id: 01m7vas4458ta22fe2y6610av8
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (954ec560). Findings 0, confirmed 0, refuted 0. 7 validator pairs ran, 0 failed. 4 files reviewed. No validator matched Tests/FoundationModelsMultitoolTests/Goldens/sessions.graphql.
    - next: none. The task moved to done.
  timestamp: 2026-11-20T01:57:46.757809+00:00
- actor: claude-code
  id: 01m7vasjkd3mk06qbwhz6zzj8y
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files
    - test: green — swift test, 3347 tests in 286 suites (run in the implement step)
    - commit: 954ec560
    - review: clean — 0 findings
  timestamp: 2026-11-20T01:58:01.581114+00:00
position_column: done
position_ordinal: ffffffffa980
title: 'Endpoint: preferredFolder argument of importableSessions (D209)'
---
## Goal
A client can tell `importableSessions` which folder comes first, as `searchSessions` lets a client give the folder of its tab. Today only the agent path has a preferred folder (the folder of the caller session), so the app must read the folder of the tab first and then the other folders. Request from TestudoApp (testudoapp-9a).

## Change
- Add the optional argument `preferredFolder: String` to `Query.importableSessions` in `Capabilities/Sessions/SessionsGraphImport.swift`. It does not filter: the sessions of that folder come first, then the others. `~` expands. A path that is not absolute gives `INVALID_FOLDER`.
- Pass it as `ImportableSessionsRequest.preferredFolder`. For a call of the agent with no `preferredFolder`, the folder of the caller session stays the preferred folder. An explicit `preferredFolder` replaces it.
- Update the argument description, the doc comments at the top of the file and in `SessionsGraph.swift`, and add an alias (`preferred_folder`) in the alias table (D86).
- Re-record the golden SDL.

## Tests
- [x] A client call with `preferredFolder` sends that folder to the fake importer as `preferredFolder`, and `folder` stays `nil`.
- [x] A client call with no `preferredFolder` sends `nil`.
- [x] An agent call with no `preferredFolder` sends the folder of the caller session; with one, it sends the argument.
- [x] A relative `preferredFolder` gives `INVALID_FOLDER`.
- [x] The golden SDL has the argument.