---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m25wvk6cax6gbde3xz1jp1qb
  text: |
    Research, before any edit.

    The surface holds nine entries, and this list is the ground of the correct-tool
    declarations below:

    - `files.glob` — finds files whose relative path matches a pattern, newest first.
    - `files.read` — reads a file, whole or by line range.
    - `files.grep` — searches file text with a regular expression.
    - `files.write` — writes content to a file whole, atomically.
    - `files.edit` — changes lines of an existing file.
    - `files.patch` — one envelope that adds, updates, deletes or renames files.
    - `shell.execute` — runs a command.
    - `shell.getLines` — reads the captured output of one run, by line number.
    - `shell.grepHistory` — searches the captured output of this session's runs.

    How the held-out queries were written. A separate model wrote them, in its own
    context, with no file and no repository and no tool call at all. It was given a
    task description only: an autonomous coding agent works on a checkout of a
    Python library, must find a defect, read the code, change the source, run the
    test suite, and clean up after itself; it holds no fixed tool list and must ask
    a discovery service in a short phrase. The instruction told it to write from the
    work, and forbade any dotted identifier, camelCase name or brand name. It
    returned fifteen phrases and nothing else. No tool name of this surface was in
    its context, so no phrase can copy one.

    The correct tools of each query were declared after the phrases were fixed, by
    reading the nine descriptions above. The declaration therefore cannot have
    steered the wording.
  timestamp: 2026-09-10T14:51:55.468214+00:00
- actor: claude-code
  id: 01m25xs4h1d5pep23kt0pe1v3e
  text: |
    The counts of each round, and the run time. Measured 2026-09-10 on a warm
    machine, model `mlx-community/Qwen3-4B-4bit`, nine-entry files-and-shell
    surface, prefix 7,601 characters against a 32,000-character budget.

    Group one — the ten queries of card `^zqz1zan`. They declare 25 correct paths
    in all.

    | round | correct found | wrong returned |
    | --- | --- | --- |
    | 1 | 19 | 3 |
    | 2 | 19 | 3 |
    | 3 | 19 | 3 |

    Group two — the fifteen held-out queries. They declare 22 correct paths in all.

    | round | correct found | wrong returned |
    | --- | --- | --- |
    | 1 | 9 | 8 |
    | 2 | 9 | 8 |
    | 3 | 9 | 8 |

    The three rounds of each group answered identically, query by query. The tier
    decodes under a grammar, so it is deterministic here. That is why the level of
    group one sits at the measurement (19) and not under it.

    Run time. Group one takes 26.4 s for the model load plus thirty calls. Group
    two takes 35.0 s for the model load plus forty-five calls. The two suites
    together take 61.4 s of test time, and 1 m 6 s of wall time with the build. The
    time limits are 5 minutes and 6 minutes, each far over a cold model load.

    Six of the fifteen held-out queries find no declared path in any round, so the
    new suite is red. The reading and the six queries are on card `^p06rh7z`.
  timestamp: 2026-09-10T15:08:03.489539+00:00
- actor: claude-code
  id: 01m25xsgkctbc7th86n8m0vtj8
  text: |
    ### implement — stuck

    - evidence: 5 files. New `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/HeldOutSurfaceDiscoveryTests.swift` (fifteen held-out queries, three rounds, declared correct paths, level 15). New `Support/DiscoveryGrading.swift` (the graded query, the grade, the round, the three-round runner, the per-query floor). New `Support/FilesAndShellSurface.swift` (the shared nine-entry mount and the catalog-size line). `AgentSurfaceDiscoveryTests.swift` now runs three rounds, declares the correct paths of its ten queries, keeps every assertion of card `^zqz1zan` whole, and holds a level of 19. `Support/CatalogFeedback.swift` gains `selectionPrefix(of:)`, which `OverBudgetSurfaceDiscoveryTests.swift` now takes in place of its own copy. The held-out queries were written by a separate model from a task description alone, with no file, no repository and no tool call, and no tool name in its context; the correct paths were declared afterwards by a reader of the nine tool descriptions. Counts: group one 19/19/19 correct and 3/3/3 wrong over three rounds; group two 9/9/9 correct and 8/8/8 wrong over three rounds. Run time 26.4 s and 35.0 s, 61.4 s for both suites. `swift test` at the root passed 1,414 tests in 111 suites. `swift build --package-path IntegrationTests --build-tests` is clean. `OverBudgetSurfaceDiscoveryTests` still passes.
    - next: a person decides. Every acceptance criterion of this card is met, but the new suite is red, and it is red on the defect it was written to look for: six of the fifteen held-out queries find no declared path in any round, and one gets an empty answer. The rules of this card forbid both ways to make it green, so the level stays at 15 and the defect is card `^p06rh7z`. Either fix `^p06rh7z` first, or say that the held-out suite may stand red until it is fixed.
  timestamp: 2026-09-10T15:08:15.852426+00:00
- actor: claude-code
  id: 01m25xw3g18j347gqcj32a6wgg
  text: |-
    ### finish iteration 1 — stuck

    - implement: changed, then stuck. The held-out suite, the three-round runner and the level grade are all in the tree. Six of the fifteen held-out queries find no declared path, thus the suite is red.
    - test: the root suite gives 1414 pass, 0 fail. The nested package builds. `OverBudgetSurfaceDiscoveryTests` and `AgentSurfaceDiscoveryTests` pass. `HeldOutSurfaceDiscoveryTests` is red.
    - review: not run this iteration.

    **The suite is red because it found the defect it was made to look for.** That is the correct result of this card, not a failure of it. The card forbids the two ways to make it green: do not lower the level, and do not change a held-out query to match what the tier answers.

    The defect has its own card, `^p06rh7z`. The finish loop goes to that card next. When the tier finds the shell verbs and answers the test-suite query, this suite goes green and this card closes.

    Nothing is pushed. The commit is local, thus no CI run sees the red suite before a person pushes.
  timestamp: 2026-09-10T15:09:40.737431+00:00
- actor: claude-code
  id: 01m25xxb8m106jdk5r8d6an9vm
  text: |-
    ### commit — changed
    - evidence: c940b21, 14 files changed
    - next: none. The commit is local and not pushed. The commit message states that HeldOutSurfaceDiscoveryTests is RED on purpose and names card ^p06rh7z as the defect it measures.
  timestamp: 2026-09-10T15:10:21.460033+00:00
- actor: claude-code
  id: 01m2610gpd1mq1c98ha69qmbxv
  text: |
    This card is no longer stuck.

    The held-out suite was red when it was written. That redness was the defect the
    suite was built to find. Card `^p06rh7z` corrected the cause at commit f5e895c:
    it added the missing work-words to the descriptions of nine tools. It did not
    correct the queries.

    No held-out query was changed. No level was lowered.

    I compared the two test files with commit c940b21. Both are byte for byte the
    same:

    - `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/HeldOutSurfaceDiscoveryTests.swift`
      — SHA-1 316b204b6afe6d512387bfebcb49631f1741274b at c940b21 and in the tree.
      Thus `heldOutRoundCorrectLevel` stays at 15.
    - `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/AgentSurfaceDiscoveryTests.swift`
      — SHA-1 11525c88d7ef2501d61676dde86a95a9bc76af9e at c940b21 and in the tree.
      Thus the ten query strings of card `^zqz1zan` stay as they were.

    The current measurement, on the real flash model, three rounds of each group:

    | group | declared correct paths | correct found, each round | undeclared returned, each round |
    | --- | --- | --- | --- |
    | held-out queries | 22 | 16 | 2 |
    | the ten queries of `^zqz1zan` | 25 | 19 | 3 |

    The root suite passes 1415 tests in 112 suites. The full gated bundle passes 24
    tests in 17 suites in 845 seconds.

    The description now shows the Tests item as done, and it holds this measurement.
  timestamp: 2026-09-10T16:04:31.053217+00:00
- actor: claude-code
  id: 01m2610tmxy0gb8mbd3q47zwqb
  text: |
    ### implement — changed

    - evidence: The card description only. No source file and no test file was
      changed. The Tests item is now `- [x]`, and all six acceptance criteria stay
      `- [x]`. The description holds two new parts: "The measurement" and "Why the
      suite was red, and what made it green". `heldOutRoundCorrectLevel` and the ten
      query strings of card `^zqz1zan` are unchanged since commit c940b21: both test
      files are byte for byte the same as at that commit (SHA-1
      316b204b6afe6d512387bfebcb49631f1741274b and
      11525c88d7ef2501d61676dde86a95a9bc76af9e). `swift test` at the root: 1415
      tests in 112 suites, pass. `swift test --package-path IntegrationTests
      --no-parallel --filter "HeldOutSurfaceDiscoveryTests|AgentSurfaceDiscoveryTests"`:
      2 tests in 2 suites, pass. The held-out group gave 16 correct of 22 declared
      with 2 undeclared, in each of three rounds. The ten recorded queries gave 19
      correct of 25 with 3 undeclared, in each of three rounds. The full gated
      bundle passes 24 tests in 17 suites in 845 seconds.
    - next: the card is ready for `/review`. It stays in the doing column.
  timestamp: 2026-09-10T16:04:41.245068+00:00
- actor: claude-code
  id: 01m2612yg978kc7wek0r1apag8
  text: |-
    ### commit — changed
    - evidence: 7815680, 4 files changed (2 kanban task files for this card, 2 kanban task files for card ^p06rh7z, 109 insertions, 10 deletions)
    - next: run review on the change
  timestamp: 2026-09-10T16:05:50.729770+00:00
- actor: claude-code
  id: 01m2614p4h29crapxkh32pkw9n
  text: |-
    ### review — clean
    - evidence: 0 findings over HEAD~1..HEAD. The local review engine read commit 7815680. That commit holds kanban card files only, and the ignore rule for .kanban excluded all 4 files. No prior `## Review Findings` section is on this card, and all acceptance items and test items are checked.
    - next: The card moves from review to done. No work is open.
  timestamp: 2026-09-10T16:06:47.697588+00:00
- actor: claude-code
  id: 01m2615drycm82wpvc3dqentpa
  text: |-
    ### finish iteration 2 — clean

    - implement: changed, on the card only. No source file and no test file changed. The one open test item is now checked, thus the card is 7 of 7. The measurement is on the card.
    - test: green. `swift test` gives 1415 pass in 112 suites. The gated filter gives 2 pass. The full gated bundle gives 24 pass in 17 suites.
    - commit: 7815680, 4 files.
    - review: clean. 0 finding over `HEAD~1..HEAD`. The task moved to done.

    **The record of this card.** The held-out suite was red when it was written. That was the correct result, not a failure: the suite found a real defect. Card `^p06rh7z` found the cause and corrected it at commit f5e895c. The cause was the tool descriptions. Each description named the mechanism of its verb, and never the work a person brings, thus a query that named a test suite matched no candidate at all.

    No held-out query was changed, and no level was lowered. Both test files are byte identical to commit c940b21, and the two SHA-1 values on this card prove it.
  timestamp: 2026-09-10T16:07:11.902701+00:00
depends_on:
- 01M25KGJZVPVF5XW0WQ46J5HQW
position_column: done
position_ordinal: ffbd80
title: The gated discovery suite is graded on the ten queries its own preamble was chosen with
---
## What happened

`IntegrationTests/.../AgentSurfaceDiscoveryTests.swift` holds ten queries. Those ten queries come from one `acp-agent` run of `astropy__astropy-12907`, recorded on card `^zqz1zan`.

The preamble of card `^zqz1zan` was selected by measurement against those same ten queries. Card `^zqz1zan` records the table: wording V0 answered 2 of 10, and wordings V2 to V5 answered 10 of 10. The wording that won is now the code, and the ten queries that chose it are now the test.

So the suite grades the answer against its own answer key. It shows that the wording works for the queries that selected it. It shows nothing about a query nobody has seen.

## Two more limits of the same suite

**One round.** The suite makes one pass of the ten queries. A 4B model is stochastic. Between two recorded runs, query 9 answered five matches and then six matches. Nothing observed that. A change that makes the model answer eight of ten can pass or fail by chance.

**A floor, not a level.** The suite asserts that queries 4 to 9 each answer at least one match, and that one match is the write verb, the edit verb or the shell verb. A run that answered with all nine tools for every query passes that test. Precision is not measured, so it can fall to nothing without a failure.

## What to do

1. Write a set of held-out queries. Write them without reading the names of the tools of the surface. A person can write them, or a larger model can write them from a task description alone. Ten to twenty queries are enough. Record how they were written on this card, because that record is the value of the set.
2. Keep the ten queries of `^zqz1zan` as a separate group. They are a regression record of a real failure. Do not mix the two groups, and report them apart.
3. Run each group three rounds. Report the count of answers for each round.
4. Grade a level, not only a floor. For each query, record which tools the surface holds that a person says are correct. Report how many correct tools the run found, and how many wrong tools it returned. Assert on the count of correct tools. Print the count of wrong tools without asserting on it, until a level is known.
5. Keep the run short. The suite is gated and uses a live model. Say on this card how long the new suite takes.

## Rules

- Do not write a held-out query by reading the tool names. That repeats the fault this card names.
- Do not delete the ten queries of `^zqz1zan`.
- Do not make an assertion weaker to make a run green.

## Acceptance Criteria

- [x] A held-out query set is in the suite, and this card records how it was written.
- [x] The two groups are reported apart.
- [x] Each group runs three rounds, and the counts of each round are on this card.
- [x] The correct tools of each query are declared, and the suite asserts on the count found.
- [x] The count of wrong tools is printed for each query.
- [x] This card states the run time of the new suite.

## The measurement

This is the current measurement, on the real flash model. The three rounds gave
the same counts.

| group | declared correct paths | correct found, each round | undeclared returned, each round |
| --- | --- | --- | --- |
| held-out queries | 22 | 16 | 2 |
| the ten queries of `^zqz1zan` | 25 | 19 | 3 |

The root suite passes 1415 tests in 112 suites. The full gated bundle passes 24
tests in 17 suites in 845 seconds.

## Why the suite was red, and what made it green

The suite was red when it was written. That redness was the defect the suite was
built to find, not a fault of the suite.

Card `^p06rh7z` corrected the cause at commit f5e895c. It added the missing
work-words to the descriptions of nine tools. It did not correct the queries.

No held-out query was changed. No level was lowered. The file
`HeldOutSurfaceDiscoveryTests.swift` and the file `AgentSurfaceDiscoveryTests.swift`
are byte for byte the same as at commit c940b21, thus `heldOutRoundCorrectLevel`
stays at 15 and the ten query strings of card `^zqz1zan` stay as they were.

## Tests

- [x] `swift test --package-path IntegrationTests --no-parallel`, for the new suite and for `AgentSurfaceDiscoveryTests`.

  Both suites pass. `HeldOutSurfaceDiscoveryTests` finds 16 correct paths of 22
  in each of three rounds, which is over the level of 15.
  `AgentSurfaceDiscoveryTests` finds 19 correct paths of 25 in each of three
  rounds.

#discovery #search-tools #test-coverage