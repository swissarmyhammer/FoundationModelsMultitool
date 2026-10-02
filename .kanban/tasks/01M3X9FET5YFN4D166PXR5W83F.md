---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3xe08p3bqg23t1qyw1cra3s
  text: |-
    Note from the implement step of `^3vtvrzg` (for this card's search for fixed model-quality assertions):
    - `OverBudgetSurfaceDiscoveryTests.swift:140` asserts `matchedPathCount > 0` over its two queries. That is a model-quality floor on `Qwen3-1.7B-4bit`. On 2026-10-01 it failed locally at HEAD (both queries answered no match), also with the `^3vtvrzg` changes stashed. CI run 36951032341 passed it with one match only, and that match was a wrong path (`deploy.download_artifact` for "read the contents of a file on disk").
    - `^3vtvrzg` renamed `agentSurfaceRoundCorrectLevel` to `agentSurfaceCorrectLevel` and `heldOutRoundCorrectLevel` to `heldOutCorrectLevel` (values unchanged), and removed the discovery rounds. `expectEveryQueryFindsACorrectPath` now takes a `DiscoveryGroupGrade`.
  timestamp: 2026-10-02T04:29:48.099220+00:00
- actor: claude-code
  id: 01m3xfebfs263pc4whhma28vxm
  text: |-
    Research (implement step). A search at HEAD de553cf found these fixed discovery-score assertions in `IntegrationTests/`:
    - `AgentSurfaceDiscoveryTests`: `group.correctCount >= agentSurfaceCorrectLevel` (19), `expectEveryQueryFindsACorrectPath` (each query `correctCount >= 1`), and `expectTheMutatingQueriesAnswer` (queries 4 to 9 must answer a match, and a match must be `files.write`, `files.edit` or `shell.execute`). The third one also depends on how well the model selects.
    - `HeldOutSurfaceDiscoveryTests`: `group.correctCount >= heldOutCorrectLevel` (15) and `expectEveryQueryFindsACorrectPath`.
    - `OperationToolLiveTests.notesVerbsAreFoundBesideTheDistractors`: `expectEveryQueryFindsACorrectPath` (a per-query floor).
    - `OverBudgetSurfaceDiscoveryTests`: `matchedPathCount > 0`. Its other three checks (no repeated path, count in limit, path in catalog) are already the properties of item 1.
    - `NoDescriptionSurfaceDiscoveryTests`: `shipped > 0` (the shipped text must find one declared path over the run).
    - `RetrievalTextSurfaceDiscoveryTests`: `shippedAgentSurfaceTopPlaceLevel` (10), `shippedHeldOutTopPlaceLevel` (14), and `expectEveryQueryRanksADeclaredPath` (each query must rank a declared path). This suite uses no generation, but the ranking comes from the embedding model, so these are model-quality scores too.
    Facts for the new checks:
    - `SearchToolsTool.call` throws on a searcher error or a selection-session error, so a `try` on the call is the "answer without an error" check.
    - The limit of `searchTools` defaults to `registry.surface.entries.count`.
    - `APISurface.Entry.id` is its `path`, so a searcher match id is a catalog path.
    - `UnknownToolHintLiveTests` asserts a fixed best path for each imagined path (`suggestedPaths.first == bestPath`). That is a retrieval-ranking expectation, not a count of correct discovery paths. It is out of the scope of this card; I record it here for a person to decide.
  timestamp: 2026-10-02T04:54:58.297343+00:00
- actor: claude-code
  id: 01m3xfvebfhg5knbbyzms6xmpd
  text: |-
    `OverBudgetSurfaceDiscoveryTests` investigation result: the failure of `matchedPathCount > 0` is a model-quality score, not a defect of this package.
    Evidence (local run, 2026-10-02, M3 Ultra, `swift test --package-path IntegrationTests --no-parallel --filter OverBudgetSurfaceDiscoveryTests`, after the test was changed to print the raw ids of each slice):
    - `entries=49 prefixCharacters=38340 budget=32000`, so the over-budget path ran.
    - Both queries: `matches=0 slices=2 selection=[[], []]`.
    - The Router recording shows four `.flash` responses from `mlx-community/Qwen3-1.7B-4bit`, each with `contentJSON` `{"ids": []}`.
    - For "read the contents of a file on disk", slice 1 had `// tools.files.read` in its instructions, `files.read` in the "Choose only from these ids" list of its prompt, and `files.read` in the enum of its grammar. The model still answered no id.
    - `SearchToolsTool.format` then gave "found no matching functions", which is the correct text for an empty selection. No id was lost by the code.
    - CI run 36951032341 passed the old assertion with one match, and that match was a wrong path (`deploy.download_artifact`). Thus the old assertion passed or failed on the model only.
  timestamp: 2026-10-02T05:02:07.215888+00:00
- actor: claude-code
  id: 01m3xgpe2za311anhn33jg7h6q
  text: |-
    Implementation landed (not committed).
    What changed:
    - New `Support/DiscoveryAnswerCheck.swift`: `DiscoveryAnswerFault` (`pathNotInCatalog`, `repeatedPath`, `overLimit`) and `DiscoveryAnswerCheck` (catalog plus limit; `faults(in:)`, `expectNoFault(in:answering:)` for one answer and for a `DiscoveryGroupGrade`, `declaredPathsOutsideTheCatalog(of:)`, `expectEveryDeclaredPathIsInTheCatalog(of:)`, `init(surfaceOf:)` with the default `searchTools` limit).
    - New offline `DiscoveryAnswerCheckTests.swift` (6 tests, no model). `aPathOutsideTheCatalogIsAFault` is the acceptance test: an answer with `files.delete` (not in the catalog) gives `.pathNotInCatalog("files.delete")`. RED was seen first for each rule.
    - `FilesAndShellSurface.driveGradedGroup(_:recordedBy:reportedAs:)` holds the shared flow of the agent-surface, held-out and operation-tool groups.
    - Removed: `agentSurfaceCorrectLevel`, `heldOutCorrectLevel`, `expectEveryQueryFindsACorrectPath`, `expectTheMutatingQueriesAnswer` with `agentSurfaceQueriesThatMustAnswer` and `agentSurfaceMutatingPaths`, `matchedPathCount > 0`, NoDescription `shipped > 0`, RetrievalText `shippedAgentSurfaceTopPlaceLevel`, `shippedHeldOutTopPlaceLevel`, `shippedRetrievalTextSetting`, `expectEveryQueryRanksADeclaredPath`, `expectTheShippedSettingHoldsItsLevel`.
    - OverBudget now also prints the raw ids of each slice (`selection=[[...], ...]`).
    - The `RESULT` lines with correct and wrong counts are unchanged.
    - No test was skipped, moved or repeated. The CI workflow is not changed.
    Decision for a person to see: `expectTheMutatingQueriesAnswer` (queries 4 to 9 must match a write, edit or shell path) was the regression guard of `^zqz1zan`. It depends on how well the model selects, so item 1 of Work removes it. The counts stay printed.
    Test results (2026-10-02, M3 Ultra):
    - `swift build --build-tests --package-path IntegrationTests`: Build complete, 0 compiler warnings. (SwiftPM prints "missing creator for mutated node ... mlx-swift_Cmlx.bundle" on every build of this package; it is not from this change.)
    - `swift test --package-path IntegrationTests --no-parallel --filter 'AgentSurfaceDiscoveryTests|HeldOutSurfaceDiscoveryTests|OverBudgetSurfaceDiscoveryTests|NoDescriptionSurfaceDiscoveryTests|RetrievalTextSurfaceDiscoveryTests|OperationToolLiveTests|DiscoveryAnswerCheckTests'`: 13 tests in 7 suites passed, 127.5 s.
    - Readings: agentSurface correctTotal=18 wrongTotal=1 (the old level of 19 would fail); heldOut 16/4; operationToolDiscovery 5/0; noDescription banner=2/19 name=2/4 arguments=1/3; overBudget 0 matches, raw ids `[[], []]` for both queries; retrievalText block/description agentSurface bestRankTopThree=10, heldOut 14.
    - Root `swift test --scratch-path <scratchpad>`: 1882 tests in 154 suites passed. (The default scratch path failed: another process holds `.build/checkouts/FoundationModelsRouter`.)
    Open: the CI run id for the last criterion. I cannot make a CI run from this step.
  timestamp: 2026-10-02T05:16:51.679879+00:00
- actor: claude-code
  id: 01m3xgph6b9zrbnw9075dfn20f
  text: |-
    ### implement — changed
    - evidence: 10 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/{Support/DiscoveryAnswerCheck.swift (new), DiscoveryAnswerCheckTests.swift (new), Support/DiscoveryGrading.swift, Support/FilesAndShellSurface.swift, AgentSurfaceDiscoveryTests.swift, HeldOutSurfaceDiscoveryTests.swift, OperationToolLiveTests.swift, OverBudgetSurfaceDiscoveryTests.swift, NoDescriptionSurfaceDiscoveryTests.swift, RetrievalTextSurfaceDiscoveryTests.swift}; integration build passes; 13 discovery tests in 7 suites pass locally; root 1882 tests pass.
    - next: /review. The CI run id of the last criterion stays open.
  timestamp: 2026-10-02T05:16:54.859714+00:00
- actor: claude-code
  id: 01m3xh6r1h2tcwq15mxcmfh9s7
  text: |-
    ### test — green
    - evidence: (1) swift test at the root (with --scratch-path, because .build/checkouts is not removable): 1882 tests in 154 suites passed, 0 warnings from this package. (2) swift build --build-tests --package-path IntegrationTests: build complete, 0 errors, 0 warnings from IntegrationTests sources. (3) --filter DiscoveryAnswerCheckTests: 6 tests in 1 suite passed. (4) Live models, one run, --no-parallel, filter AgentSurfaceDiscovery|HeldOutSurfaceDiscovery|OperationTool|OverBudgetSurfaceDiscovery|NoDescriptionSurfaceDiscovery|RetrievalTextSurfaceDiscovery: 7 tests in 6 suites passed, 0 failed, 0 skipped.
    - next: review. The CI run id for the last acceptance item is still open.
  timestamp: 2026-10-02T05:25:46.161119+00:00
- actor: claude-code
  id: 01m3xh7d3392psz1235gyzv0a1
  text: |-
    ### commit — changed
    - evidence: this commit, "test(integration): check the properties of a discovery answer, not the model score". It holds the 10 Swift files of the implement step and the .kanban files.
    - next: review. The CI run id of the last acceptance item stays open.
  timestamp: 2026-10-02T05:26:07.715581+00:00
- actor: claude-code
  id: 01m3xhh7bfdp344rxftg3bsmps
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit 4757f51): 1 finding (1 confirmed, 0 refuted) — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/FilesAndShellSurface.swift:57 (swift/fluent-usage). `git diff --name-status -M HEAD~1..HEAD` shows no renamed file, thus no file-scoped review was necessary. The rule code-hygiene/dead-code-swift did not run: it tried to remove .build/checkouts/FoundationModelsRouter and got "Operation not permitted". Its findings are missing from this pass. The .build/ directory was not changed.
    - next: implement the finding, and remove the same cause from the whole file. Then run /review again. The task stays in `review`. Also when a later review is clean, the task stays in `review` (not `done`) until the user pushes and the CI run id of the last acceptance item is recorded.
  timestamp: 2026-10-02T05:31:29.519905+00:00
- actor: claude-code
  id: 01m3xhhr9k67j9g7ja1mztxycx
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files (DiscoveryAnswerCheck, DiscoveryAnswerCheckTests, fixed scores removed)
    - test: green — swift test 1882 passed; IntegrationTests build passes; DiscoveryAnswerCheckTests 6 passed; 6 discovery suites on the real models, 7 tests passed
    - commit: 4757f51
    - review: findings — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/FilesAndShellSurface.swift:57 (swift/fluent-usage); the rule code-hygiene/dead-code-swift did not run, because it could not remove .build/checkouts/FoundationModelsRouter ("Operation not permitted")
  timestamp: 2026-10-02T05:31:46.867865+00:00
- actor: claude-code
  id: 01m3xhrnykk4ra3x45gg164fwp
  text: |-
    Finding swift/fluent-usage (FilesAndShellSurface.swift `driveGradedGroup`) is corrected. I looked for the same cause (an unlabeled first parameter on a function that is not a value-preserving conversion) in all 10 Swift files of commit 4757f51, and corrected each one:
    - `FilesAndShellSurface.driveGradedGroup(_:recordedBy:reportedAs:)` is now `driveGradedGroup(of:recordedBy:reportedAs:)`. I updated the 3 call sites in AgentSurfaceDiscoveryTests, HeldOutSurfaceDiscoveryTests and OperationToolLiveTests.
    - OverBudgetSurfaceDiscoveryTests: `reportOverBudgetLine(_:)` is now `reportOverBudget(line:)` (2 call sites).
    - OperationToolLiveTests: `holdsTheExpectedNote(_:)` is now `expectedNoteIsTheOnlyOne(in:)` (1 call site). `describe(_:)` is now `descriptions(of:)` (2 call sites). Each side-effect-free function now has a noun-phrase name or an assertion name.
    - RetrievalTextSurfaceDiscoveryTests: `format(_:)` is now `renderedMean(of:)` (1 call site).
    - NoDescriptionSurfaceDiscoveryTests: `Sequence.mappedInOrder(_:)` is now `mappedInOrder(by:)`. The 2 trailing-closure call sites do not change. The recursive call now passes `by:`.
    Not changed: `SubstitutingTextEmbedding.embed(_:)` in RetrievalTextSurfaceDiscoveryTests. It is the witness of the `TextEmbedding.embed(_:)` requirement in FoundationModelsRanker (TextEmbedding.swift). The protocol sets the label, so a different label does not compile as a conformance. DiscoveryAnswerCheck.swift, DiscoveryGrading.swift and DiscoveryAnswerCheckTests.swift already label each first parameter.
    Behavior did not change: only labels and names changed, so no new test is necessary. The compiler checks each call site.
  timestamp: 2026-10-02T05:35:33.843990+00:00
- actor: claude-code
  id: 01m3xhrsh4bdwwxvqxan55sjga
  text: |-
    ### implement — changed
    - evidence: 7 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/{Support/FilesAndShellSurface.swift, AgentSurfaceDiscoveryTests.swift, HeldOutSurfaceDiscoveryTests.swift, OperationToolLiveTests.swift, OverBudgetSurfaceDiscoveryTests.swift, RetrievalTextSurfaceDiscoveryTests.swift, NoDescriptionSurfaceDiscoveryTests.swift}. `swift build --build-tests --package-path IntegrationTests`: Build complete, 0 errors, 0 warnings from IntegrationTests sources (the "missing creator for mutated node ... mlx-swift_Cmlx.bundle" warning comes from SwiftPM and was there before this change). `swift test --package-path IntegrationTests --filter DiscoveryAnswerCheckTests`: 6 tests in 1 suite passed. The finding is checked. The default .build path worked; .build/ was not changed by hand.
    - next: /review. The task stays in `doing`. The CI run id of the last acceptance item is still open.
  timestamp: 2026-10-02T05:35:37.508373+00:00
- actor: claude-code
  id: 01m3xj1edr5nfy1gbrp7nh6am3
  text: |-
    ### test - green
    - evidence: `swift test` at root: 1882 tests in 154 suites passed, 0 failed, 0 skipped. `swift build --build-tests --package-path IntegrationTests`: Build complete, 0 errors. `swift test --package-path IntegrationTests --filter DiscoveryAnswerCheckTests`: 6 tests in 1 suite passed.
    - warnings: 0 from this package's sources. The only warnings come from the mlx-swift dependency (C++17 extension in Metal headers) and from the build system ("missing creator for mutated node").
    - not run: live-model suites (the change only renames labels).
    - next: review.
  timestamp: 2026-10-02T05:40:21.048445+00:00
- actor: claude-code
  id: 01m3xj20afz573hw4dj4jdqjf1
  text: |-
    ### commit — changed
    - evidence: this commit, "fix(integration): label the first parameter of action functions". It holds the 7 Swift files of the fluent-usage fix and the .kanban files.
    - next: review. The task stays in `doing`/`review`. The CI run id of the last acceptance item stays open.
  timestamp: 2026-10-02T05:40:39.375856+00:00
- actor: claude-code
  id: 01m3xjexgs0xt356ayyrbd73wm
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit bc26800): 1 finding (1 confirmed, 2 refuted, 7 attempted, 0 failed) — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OverBudgetSurfaceDiscoveryTests.swift:152 (swift/fluent-usage). The prior finding (Support/FilesAndShellSurface.swift:57, swift/fluent-usage) is checked, and this pass found nothing on that line. `git diff --name-status -M HEAD~1..HEAD` shows no renamed file, thus no file-scoped review was necessary. The rule code-hygiene/dead-code-swift ran this time: the report has no tool-rule failure warning, and `failed` is 0. The .build/ directory was not changed.
    - next: implement the finding (the label `reportOverBudget(line:)` at each call site in OverBudgetSurfaceDiscoveryTests.swift, and the same cause in the whole file). Then run /review again. The task stays in `review`. Also when a later review is clean, the task stays in `review` (not `done`) until the user pushes and the CI run id of the last acceptance item is recorded.
  timestamp: 2026-10-02T05:47:42.489418+00:00
- actor: claude-code
  id: 01m3xjfp82gm8vyq35ymme09zc
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 7 files (labels on the first parameter of action functions)
    - test: green — swift test 1882 passed; IntegrationTests build passes; DiscoveryAnswerCheckTests 6 passed
    - commit: bc26800
    - review: findings — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OverBudgetSurfaceDiscoveryTests.swift:152 (swift/fluent-usage, same cause at line 134); the prior finding at Support/FilesAndShellSurface.swift:57 is fixed; code-hygiene/dead-code-swift ran
  timestamp: 2026-10-02T05:48:07.810865+00:00
- actor: claude-code
  id: 01m3xjkqy1phw1fjsxgwe3pjdr
  text: |-
    Finding swift/fluent-usage (OverBudgetSurfaceDiscoveryTests `reportOverBudget(line:)`) is corrected. The function is now `report(overBudgetLine:)`, so each call reads "report over-budget line". I changed the declaration and the 2 call sites (in the test body and in `reportOverBudgetCatalogSize(of:)`). The doc key stays `- Parameter line:`, because it names the internal parameter.
    I read the other names that commit bc26800 added, at each call site. Each one already reads as a grammatical phrase, so I did not change them:
    - `driveGradedGroup(of:recordedBy:reportedAs:)`: "drive graded group of queries, recorded by fixture, reported as scenario".
    - `expectedNoteIsTheOnlyOne(in:)`: a Boolean assertion, "expected note is the only one in stored".
    - `descriptions(of:)` and `renderedMean(of:)`: noun phrases for functions with no side effect.
    - `mappedInOrder(by:)`: the same shape as `sorted(by:)`. The 2 call sites use a trailing closure.
    - `reportOverBudgetCatalogSize(of:)` was not added by bc26800, and it reads "report over-budget catalog size of registry".
    Only labels changed, and behavior did not change. The compiler checks each call site.
  timestamp: 2026-10-02T05:50:20.609455+00:00
- actor: claude-code
  id: 01m3xjkwhe3jk835dgt8m9szvb
  text: |-
    ### implement — changed
    - evidence: 1 file — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OverBudgetSurfaceDiscoveryTests.swift (`reportOverBudget(line:)` is now `report(overBudgetLine:)`, with 2 call sites). `swift build --build-tests --package-path IntegrationTests`: Build complete, 0 errors, 0 warnings from IntegrationTests sources (the SwiftPM "missing creator for mutated node ... mlx-swift_Cmlx.bundle" warning was there before). `swift test --package-path IntegrationTests --filter DiscoveryAnswerCheckTests`: 6 tests in 1 suite passed. The 2026-10-02 00:41 finding is checked. The default .build path worked; .build/ was not changed by hand.
    - next: /review. The task stays in `doing`. The CI run id of the last acceptance item is still open.
  timestamp: 2026-10-02T05:50:25.326570+00:00
- actor: claude-code
  id: 01m3xjqd8hygqa1d0pev7eak5s
  text: |-
    ### test - green
    - evidence: swift test (root) - 1882 tests in 154 suites passed, 0 failed. swift build --build-tests --package-path IntegrationTests - build complete, 0 errors. swift test --package-path IntegrationTests --filter DiscoveryAnswerCheckTests - 6 tests in 1 suite passed.
    - note: SwiftPM prints one build-system warning: "missing creator for mutated node" for the mlx-swift_Cmlx.bundle path under .build. It comes from a dependency bundle, not from package sources.
    - next: review. No live-model suite was run. No commit was made.
  timestamp: 2026-10-02T05:52:20.753919+00:00
- actor: claude-code
  id: 01m3xjqz8dnj0k6xjkqmats9tm
  text: |-
    ### commit — changed
    - evidence: this commit, "fix(integration): name the over-budget report helper as a phrase". It holds OverBudgetSurfaceDiscoveryTests.swift (`reportOverBudget(line:)` is now `report(overBudgetLine:)`, 2 call sites) and the .kanban files.
    - next: review. The task stays in `review`. The CI run id of the last acceptance item stays open.
  timestamp: 2026-10-02T05:52:39.181355+00:00
- actor: claude-code
  id: 01m3xjxb6wdhpcw65ag769jj14
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 402cdf8): 0 findings (0 confirmed, 0 refuted, 7 attempted, 0 failed, 0 skipped). 1 file reviewed (OverBudgetSurfaceDiscoveryTests.swift); 2 .kanban files excluded by .reviewignore. The prior finding (OverBudgetSurfaceDiscoveryTests.swift:152, swift/fluent-usage, same cause at line 134) is fixed: the declaration and the 2 call sites use `report(overBudgetLine:)`, and a search finds no `reportOverBudget(line:)` in IntegrationTests/Tests. All prior review items are checked. `git diff --name-status -M HEAD~1..HEAD` shows no renamed file, thus no file-scoped review was necessary. The report has no tool-rule failure warning. The .build/ directory was not changed.
    - next: the task stays in `review`, not `done`. The last acceptance item needs a real CI run id, and that run cannot exist until the user pushes. After the push, record the run id, check the item, and then move the task to `done`.
  timestamp: 2026-10-02T05:55:35.260723+00:00
- actor: claude-code
  id: 01m3xjxv7xk9hdstnb1xd0thmc
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 1 file (report(overBudgetLine:))
    - test: green — swift test 1882 passed; IntegrationTests build passes; DiscoveryAnswerCheckTests 6 passed
    - commit: 402cdf8
    - review: clean — 0 findings; every prior finding checked
    - the task stays in review: the last acceptance criterion needs a real CI run id, and that needs a push that the user approves
  timestamp: 2026-10-02T05:55:51.677095+00:00
- actor: claude-code
  id: 01m3z0ck53w4xzv24tgdhsprnt
  text: |-
    ### finish iteration 4 — clean
    - CI run 37048824337 (commit abe79da): the nested package built, and every discovery suite passed. The last acceptance box is checked with this run id.
    - every review finding is checked, and the last review (402cdf8) was clean; task moved to done
  timestamp: 2026-10-02T19:10:20.835551+00:00
position_column: done
position_ordinal: ffff9480
title: Replace the fixed discovery scores in the integration tests with checks that do not depend on model quality
---
## Problem

The discovery integration tests fail when a model selects one tool less than before, also when the code is correct. The user said: "Having a hard-wired 'discovery score' is going to be brittle."

Evidence: CI run 36951032341 (commit ef905bf, 2026-10-02):

- `AgentSurfaceDiscoveryTests.swift:175` asserts `round.correctCount >= agentSurfaceRoundCorrectLevel`, and `agentSurfaceRoundCorrectLevel = 19` (`AgentSurfaceDiscoveryTests.swift:98`). The run scored 18 correct and 1 wrong in each round. On 2026-09-29 it scored 19 correct and 3 wrong. Thus the selection changed: it gave fewer wrong paths, and one correct path less. The fixed level of 19 calls that a failure.
- `DiscoveryGrading.swift:145` asserts `grade.correctCount >= 1` for each query of `HeldOutSurfaceDiscoveryTests`. In each round, at least one of the 15 queries found no declared path. On 2026-09-29: 16 correct and 2 wrong; on 2026-10-02: 16 correct and 4 wrong.
- The selection changes when a model, a prompt or the ranker changes. FoundationModelsRanker changed the default selection sentence (`dbda1ae`) and the candidate format (`30b6d91`) on 2026-10-01. This is a possible cause of the change; it is not verified.

A fixed score is a measurement of model quality, and it is written as a test of the code. Thus each change of a model or a prompt can make it fail.

## Work

1. Assert only properties that the code of this package controls, and that do not depend on how well the model selects. For example:
   - each query gives an answer without an error;
   - each path in an answer is a real path of the catalog;
   - no path occurs two times in one answer;
   - the answer stays inside the selection limit.
2. Keep the correct and wrong counts in the printed `RESULT` lines, as a report. Do not assert them.
3. Remove `agentSurfaceRoundCorrectLevel` and the other fixed score levels, and the `correctCount >= 1` assertion for each query. Find every fixed level with a search (`CorrectLevel`, `correctCount >=`, `correctTotal >=`).
4. Every discovery test still runs on each push, in the same integration job. Do not move a test to a different workflow, and do not skip it.

## Acceptance criteria

- [x] No integration test asserts a fixed number of correct discovery paths, in total or for each query.
- [x] Each discovery test asserts the properties of item 1 of Work, and prints its correct and wrong counts.
- [x] A test shows that a catalog path that does not exist in an answer fails the check.
- [x] `swift build --build-tests --package-path IntegrationTests` passes, and the discovery suites pass in one real integration run (record the run id). Local part done on 2026-10-02 (build passes; 13 tests in 7 suites pass on the M3 Ultra). CI run 37048824337 (commit abe79da, 2026-10-02): the nested package built, and every discovery suite passed (agent surface, held-out, operation tool, no description, over budget, retrieval text). The job failed only on live web-search tests, which this card does not touch.

## Review Findings (2026-10-02 00:26)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 10 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> ⚠️ tool rule 'code-hygiene/dead-code-swift' failed — the tool judged nothing, so its findings are missing:
> error: 'foundationmodelsrouter': Error Domain=NSCocoaErrorDomain Code=513 "“FoundationModelsRouter” couldn’t be removed because you don’t have permission to access it." UserInfo={NSUserStringVariant=(
>     Remove
> ), NSFilePath=/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/.build/checkouts/FoundationModelsRouter, NSURL=file:///Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/.build/checkouts/FoundationModelsRouter, NSUnderlyingError=0x759eec4540 {Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"}}

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/FilesAndShellSurface.swift:57` `swift/fluent-usage` — First parameter of an action method should have a label unless it is a value-preserving conversion. `driveGradedGroup` is not a conversion but an action, so the first parameter `queries` should have an external label (e.g., `of:` or `with:`) to form a complete grammatical phrase at the call site. Change the signature to `func driveGradedGroup(of queries: [GradedDiscoveryQuery], recordedBy fixture: LiveRouterFixture, reportedAs scenario: String) async throws` so the call reads `.driveGradedGroup(of: agentSurfaceQueries, recordedBy: fixture, reportedAs: agentSurfaceScenarioName)`.

## Review Findings (2026-10-02 00:41)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OverBudgetSurfaceDiscoveryTests.swift:152` `swift/fluent-usage` — `reportOverBudget(line: ...)` does not form a grammatical phrase at the call site, same issue as line 134. Same as line 134.
#ci