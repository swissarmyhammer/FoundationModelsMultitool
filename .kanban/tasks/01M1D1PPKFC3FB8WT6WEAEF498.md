---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1d5ppbf5gtd1txfrazr5fsq
  text: |-
    Commit `d6e05ca` ("test(scenario): split ScenarioGrading out, and put back a deleted README section") corrected this card. It took option 1 of the two: it put the `### Injected globals` section back in `README.md`. No more work is necessary.

    Evidence:

    - `git show d6e05ca~1:README.md | grep -c "### Injected globals"` gives `0`. The section was absent before that commit.
    - `git show d6e05ca -- README.md` shows the commit adds the heading, the list of ten globals, and the paragraph that tells a reader not to delete or reword the list items.
    - On HEAD (`355ae83`, clean tree) the heading is at `README.md` line 57.

    How the test reads the section: `HardeningTests.readmeInjectedGlobals()` finds the text `### Injected globals`, keeps the text from there to the next `\n#`, and collects each line that starts with ``- ` `` and ends with a backtick. It compares that set with `injectedGlobals()`, which is the globals of a `MultiTool` run minus the globals of a vanilla `JSContext`.

    The README list holds these ten names: `console`, `tools`, `help`, `docs`, `status`, `wait`, `cancel`, `elicit`, `notify`, `progress`. The sibling test `sandboxInjectedGlobalsAreExactlyTheDocumentedSet` asserts the runtime set is the same ten names, and it also passes. So the two sets are equal.

    Test results on HEAD, tree clean:

    - `swift test` at the root: `Test run with 1366 tests in 104 suites passed after 8.919 seconds`, exit code 0, zero issues.
    - `swift test --filter HardeningTests`: `Test run with 15 tests in 1 suite passed`. Both named tests pass — `README's enumerated 'Injected globals' list is set-equal to the runtime-enumerated sandbox globals` and `the injected globals reachable in a fresh MultiTool run, beyond JavaScriptCore's own standard environment, are exactly the documented set`.

    I changed no files. Both acceptance-criteria boxes are now checked.
  timestamp: 2026-09-01T00:25:31.247439+00:00
- actor: claude-code
  id: 01m1d5pt39etnbjc3gjen7p77z
  text: |-
    ### implement — no-change
    - evidence: `swift test` at the root gives 1366 tests in 104 suites, all pass, zero issues, exit code 0. Commit `d6e05ca` had already put the `### Injected globals` section back in `README.md`. I changed no files.
    - next: ready for `/review`.
  timestamp: 2026-09-01T00:25:35.081415+00:00
- actor: claude-code
  id: 01m1d6grken94pg1xqdyk15fg3
  text: |
    ### review — clean
    - scope: `review sha d6e05ca~1..d6e05ca` — the commit that holds this card's change. `HEAD~1..HEAD` (355ae83) is a different card's magic-number correction and holds none of this work.
    - evidence: 0 findings, 0 confirmed, 0 refuted. Validators: 14 attempted, 0 failed, 0 skipped. 26 files reviewed, 7 not reviewed (6 `.kanban/` files excluded by `.reviewignore`, `README.md` matched no validator).
    - rename check: `git show --name-status d6e05ca` shows 7 renamed files. Three hygiene rules (`function-length-swift`, `magic-numbers-swift`, `missing-docs-swift`) declined at the old paths, so the diff-scoped run could not read them.
    - re-run 1: `review file Tests/Support/ScenarioGrading/*.swift` — 5 files, 7 validators attempted, 0 failed, 0 skipped, 0 findings.
    - re-run 2: `review file Tests/FoundationModelsMultitoolTests/Scenario*.swift` — 3 files, 7 validators attempted, 0 failed, 0 skipped, 0 findings.
    - card claim confirmed: `README.md` holds the `### Injected globals` heading. Its list is `console`, `tools`, `help`, `docs`, `status`, `wait`, `cancel`, `elicit`, `notify`, `progress` — set-equal to the set `HardeningTests.swift` enumerates.
    - root suite: `swift test` — 1366 tests in 104 suites passed in 9.186 seconds. Zero issues, zero warnings.
    - next: none. The card moves to done.
  timestamp: 2026-09-01T00:39:45.518543+00:00
- actor: claude-code
  id: 01m1d6hjsgec30hq44z6m1g8ea
  text: |-
    ### finish iteration 1 — clean
    - implement: no-change — no source file changed. Commit `d6e05ca` had already corrected this, and it took option 1 of the two the card gives: it put the `### Injected globals` section back in `README.md`. `git show d6e05ca~1:README.md` holds no such heading, thus the card's premise was true when a person wrote it and is not true now.
    - test: green — root `swift test`, 1366 tests in 104 suites, 0 issues, 0 warnings. `swift test --filter HardeningTests`, 15 tests, all pass, and both of the two tests that read the README list pass by name.
    - commit: no-change — nothing to commit.
    - review: clean — `review sha d6e05ca~1..d6e05ca`, 0 findings, 14 validators attempted, 0 failed, 0 skipped.

    **The two sets are equal.** The README list holds ten names: `console`, `tools`, `help`, `docs`, `status`, `wait`, `cancel`, `elicit`, `notify`, `progress`. `HardeningTests` reads the text from the heading to the next heading, collects each line between backticks, and compares that set with the globals a `MultiTool` run installs beyond a plain `JSContext`. The passing test is the evidence that the two are the same ten.

    **The rename blind spot applied here, and the reviewer covered it.** `d6e05ca` renames 7 files, because it also splits `ScenarioGrading` into its own target. The diff-scoped run reported that `function-length-swift`, `magic-numbers-swift` and `missing-docs-swift` each declined an item at all 7 old paths, thus none of them read those bodies, literals or declarations. The reviewer ran the review again file-scoped at the new paths — `Tests/Support/ScenarioGrading/*.swift`, 5 files, and `Tests/FoundationModelsMultitoolTests/Scenario*.swift`, 3 files — and each gave 0 findings with 7 validators attempted, 0 failed, 0 skipped.

    - next: nothing. The card is closed.
  timestamp: 2026-09-01T00:40:12.336455+00:00
position_column: done
position_ordinal: ffa980
title: README has no "### Injected globals" section, so HardeningTests fails on main
---
## What

`swift test` at the root is red on `main` with one issue:

```
✘ Test "README's enumerated 'Injected globals' list is set-equal to the
  runtime-enumerated sandbox globals" recorded an issue at
  HardeningTests.swift:285:6: Caught error: README.md has no
  "### Injected globals" section.
```

The test reads `README.md` for a `### Injected globals` heading and compares
the list under it with the globals the sandbox really installs. `README.md`
carries no such heading now, so the test throws before it can compare
anything.

## Why it matters

The list is the one place a reader learns which globals a snippet gets. While
the heading is absent, nothing holds the README to what the sandbox installs,
and every root `swift test` run is red for a reason that hides a real one.

## What to do

Decide which of the two is correct, then make the other match:

1. put the `### Injected globals` section back in `README.md`, with the
   globals the sandbox enumerates; or
2. if that section is deliberately gone, retire the test and say in the commit
   what now holds the README to the sandbox.

Option 1 is the likely answer: the test exists to stop the two drifting apart.

## Acceptance Criteria

- [x] `swift test` at the root reports zero issues.
- [x] The README list and the runtime-enumerated globals are set-equal, or the
      test is retired with a stated replacement.

## Found by

Task `^9kq30r8`, measuring the root suite's baseline on 2026-08-31. It is not
that card's to correct.
#eventplan