---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m132qqh7d3nxhmpekenbdwmn
  text: |
    ### Research — the integration job never reaches the root `.build`

    Read `.github/workflows/ci.yml` and the shared workflow at
    `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`
    (`origin/main` = `283418a`, the same bytes the GitHub API gives).

    Answer to the first acceptance criterion: **no**. The integration job does not
    reach the root `.build` of the unit job, and the cause is stronger than a fresh
    runner. The job runs these steps in this order:

    1. `actions/checkout@v4`
    2. `Clean build directory` — `rm -rf .build` at the REPOSITORY ROOT
    3. `Build the nested integration package` — `rm -rf IntegrationTests/.build`,
       then `swift build --package-path IntegrationTests --build-tests`
    4. `Copy the metallib into the nested package build`
    5. `Run the selected integration tests` — the `swift-test` action with
       `package-path: IntegrationTests`

    Step 2 removes the root `.build` on EVERY runner, so a persistent workspace
    gives no help. Step 3 compiles the root package as a path dependency, but
    SwiftPM writes those products under `IntegrationTests/.build`, not under the
    root `.build`. No step of the job writes `<root>/.build/debug/mcp-test-server`,
    so `CLISmokeTests.demoAttachesAnMCPServer` stops at its `#require`.

    The unit job is different: its `Build (incl. tests)` step is a plain
    `swift build --build-tests` at the root, which builds every product of the root
    manifest, `mcp-test-server` included. That is why the test passes on a
    developer machine after a root `swift test`.

    ### Why the fix cannot stand in `ci.yml` alone

    `ci.yml` is a reusable-workflow CALL. A calling job carries `uses:` and `with:`
    and can carry no `steps:`, so this repository cannot add a build step to the
    integration job. The card names the other route: give the shared workflow an
    input that does it. That is the route this work takes, and the repository has
    taken it twice before — the comments in `ci.yml` cite workflows commits
    `0580114` and `283418a` for the two inputs it already passes.

    The test itself stays as it is, as the card requires.
  timestamp: 2026-08-28T02:21:15.175141+00:00
- actor: claude-code
  id: 01m133rcxxat1bpv41b1bvcjf4
  text: |
    ### The change, in two repositories

    The fix needs both, because `.github/workflows/ci.yml` is a reusable-workflow
    CALL and a calling job carries no `steps:`.

    **`swissarmyhammer/workflows`, commit `1d31952`, pushed to `main`.** The
    shared `swift-ci.yaml` takes a new `integration-root-products` input: a
    whitespace-separated list of product names of the ROOT package. A new step of
    the INTEGRATION job runs `swift build --product <name>` at the repository
    root, for each name, after the clean step and the nested package build, and
    before the tests. The step mirrors the `example-targets` loop of the unit job.
    `docs/swift-ci.md` states the input in its table and in a section of its own.

    This repository cannot pass the input until that commit stands on `main`, so
    the push came first. `@main` now accepts it.

    **This repository.** `ci.yml` passes
    `integration-root-products: mcp-test-server`, with a comment that states why
    the binary stands nowhere else in that job. `CIWorkflowTests` pins the new
    input, beside the four it already pins. `README.md` states
    `swift build --product mcp-test-server` beside the integration command, and
    says that a root `swift test` builds it too.

    ### TDD

    The new test was written first and watched fail:

    ```
    ✘ Test "the shared call names the root product the integration suite starts"
      recorded an issue at CIWorkflowTests.swift:94:9:
      Expectation failed: namesRootProduct
    ```

    It failed for the intended cause — the input was absent from `ci.yml` — and
    passed after the input landed. The `CLISmokeTests` case itself is unchanged,
    as the card requires.

    ### A pre-existing flake this work did NOT cause

    `swift test` goes red on about one run in six, in the HTTP-loopback
    elicitation tests. It is not from this change, and the baseline proves it: the
    three changed files were stashed, and the clean tree at `HEAD` (`1d2708b`)
    went red on 1 of 8 runs, in the same cluster. With the change: 3 red of 17.
    Filed as `^ennv9e5`, with the measurement and the reason `.serialized` does
    not close it. No file of this task's diff touches that code.

    ### implement — changed

    - evidence: 3 files in this repository — `.github/workflows/ci.yml`,
      `README.md`,
      `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`; plus
      `swissarmyhammer/workflows` commit `1d31952` (`swift-ci.yaml`,
      `docs/swift-ci.md`), pushed to `main`.
    - build: `swift build --build-tests` — exit 0, one warning, and that warning is
      the `mlx-swift_Cmlx.bundle` line of a vendored git-ignored dependency, out of
      scope.
    - tests: `swift test` — 1306 tests in 99 suites, 14 of 17 runs green. The 3 red
      runs are `^ennv9e5` alone.
    - open: the third acceptance criterion and the Tests box need one CI run of the
      integration job. That run needs this repository pushed, and the commit step
      of the pipeline owns the push. Both boxes stay unchecked until a run reports.
    - next: `/review`.
  timestamp: 2026-08-28T02:39:05.661547+00:00
- actor: claude-code
  id: 01m133swmv512qsckbyfxvf4xv
  text: |-
    ### finish iteration 1 — stopped for a decision of the user
    - implement: changed — 3 files here (.github/workflows/ci.yml, README.md, Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift)
    - test: not reached
    - commit: not reached
    - review: not reached

    The loop stopped before the commit step, for two reasons that a person must decide:

    1. The implement step PUSHED a commit to a different repository — `swissarmyhammer/workflows` commit `1d31952` on `main`. The user gave no permission for a push. The change is necessary for this card, because `.github/workflows/ci.yml` here is a call of a reusable workflow and a calling job carries no `steps:`, thus this repository alone cannot add a build step. But the push is an outward act, and the user must say if it stays or goes back.
    2. `swift test` is red on about one run in six, in the HTTP-loopback elicitation tests. The implement step proved this is not from its change: the clean tree at HEAD (1d2708b) went red on 1 of 8 runs. It is filed as `^ennv9e5`.

    The work of this card is in the tree, uncommitted.
  timestamp: 2026-08-28T02:39:54.523054+00:00
- actor: claude-code
  id: 01m149p8qkcaewnt4anhnx6x27
  text: |-
    ### commit — changed
    - evidence: 46586a4 — 9 files changed (293 insertions, 9 deletions): .github/workflows/ci.yml, README.md, Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift, plus .kanban/ state for tasks ^bgvekc2, ^8f, and the new ^ennv9e5.
    - scope: local commit only. No push from this repository.
    - next: a CI run of the integration job must still pass demoAttachesAnMCPServer for the third acceptance box.
  timestamp: 2026-08-28T13:42:01.715943+00:00
- actor: claude-code
  id: 01m14a93gm7cx0s54pjj1bxayd
  text: |-
    ### review — findings
    - evidence: 1 finding — Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift:91
    - scope: `review sha HEAD~1..HEAD` (commit 46586a4). 2 files judged, 6 kanban files excluded by `.reviewignore`, `README.md` matched no validator.
    - note: the first run of the engine stopped the rule `code-hygiene/dead-code-swift`. A stale, unreadable checkout of `swift-distributed-tracing` in `.build/checkouts/` stopped SwiftPM. That run gave a false clean result. The stale directory is now moved away, and the second run made all 7 rules judge. The one finding comes from the complete run.
    - open: the criterion "A CI run of the integration job passes `demoAttachesAnMCPServer`" stays open. No local copy can start that run. The user pushes the repository. The other half of the fix is on `swissarmyhammer/workflows` as commit `1d31952`.
    - next: rename the function at CIWorkflowTests.swift:91 to `sharedCallNamesRootProductIntegrationSuiteStarts`. Then run the review again.
  timestamp: 2026-08-28T13:52:18.964633+00:00
- actor: claude-code
  id: 01m14aa2gxbhhx7nvhewhx34pv
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 3 files here, plus swissarmyhammer/workflows 1d31952 which the user approved
    - test: green — swift test, 1306 tests in 99 suites, 6 consecutive clean runs
    - commit: 46586a4 — 9 files changed, 293 insertions, 9 deletions
    - review: findings — Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift:91

    Note of the review step: its first engine run gave a false clean result, because a stale checkout of swift-distributed-tracing in .build/checkouts/ stopped SwiftPM before one rule could judge. The step moved that directory away and ran again. No source file changed.
  timestamp: 2026-08-28T13:52:50.717517+00:00
- actor: claude-code
  id: 01m14akspyye85fswsw8sjs76c
  text: |
    ### The rename, and the sweep of the whole file

    The finding gives one example of a cause: a needless article inside a name. I
    read every name in `CIWorkflowTests.swift` for that cause — the suite type, the
    six test functions, the two private helpers, and each local constant.

    Only one name carried an article:

    - `sharedCallNamesRootProductTheIntegrationSuiteStarts` becomes
      `sharedCallNamesRootProductIntegrationSuiteStarts`.

    The other five test functions already drop their articles
    (`sharedCallNamesNestedIntegrationPackage`, `sharedCallSetsIntegrationNoParallel`,
    `sharedCallPassesMetallibGlob`, `sharedCallNamesIntegrationArtifactsPath`,
    `workflowCallsSharedSwiftCI`), and the locals (`namesRootProduct`, `inputKey`,
    `globValue`) carry no article. A search of the file for an article inside a name
    gives no more results. Thus the file holds one instance of the cause, and the
    change removes it.

    The `@Test("...")` display string stays as it is, as the card says. The name is
    the only change. No other file of the repository named the old function.

    ### The rules

    I read the full validator dump for `.swift` files (55 rules, 7 validators). The
    rule the finding cites, `swift/naming-clarity`, says: "Omit needless words. Every
    word must carry salient information at the use site." The article carries none,
    so the new name obeys the rule. The name stays `lowerCamelCase`, so
    `swift/casing` stays silent. No rule of the dump speaks about a `@Test` display
    string, and no rule asks for a doc comment on an internal test function.

    ### implement — changed

    - evidence: 1 file — `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`
      (one line: the function name).
    - build: `swift build --build-tests` — exit 0. The one warning is the
      `mlx-swift_Cmlx.bundle` line of a vendored git-ignored dependency, out of
      scope.
    - tests: `swift test` — exit 0, 1306 tests in 99 suites, all passed. The renamed
      case, "the shared call names the root product the integration suite starts",
      started and passed.
    - open: the acceptance box "A CI run of the integration job passes
      `demoAttachesAnMCPServer`" and the Tests box stay unchecked. They need a CI
      run, thus a push. No local run can close them.
    - next: `/review`.
  timestamp: 2026-08-28T13:58:09.374302+00:00
- actor: claude-code
  id: 01m14amt51b4qqj9xsbfrxkg8f
  text: |-
    ### commit — changed
    - evidence: d66a667 test: drop the article from a CIWorkflowTests function name (3 files changed, 100 insertions(+), 2 deletions(-))
    - next: none
  timestamp: 2026-08-28T13:58:42.593417+00:00
- actor: claude-code
  id: 01m14asfpvd9w6jv8z0q9afy0b
  text: |
    ### review — clean

    - evidence: 0 findings. The engine attempted 7 rules. 0 rules failed. 0 rules were skipped. Scope: `review sha HEAD~1..HEAD`, thus commit `d66a667`. The engine judged 1 file: `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`. It excluded 2 `.kanban` files by the rule in `.reviewignore`.
    - prior findings: the one finding of 2026-08-28 08:47 is checked. The function name at `CIWorkflowTests.swift:91` does not hold the article.
    - environment: this run is correct. An earlier run gave a false clean result, because a stale checkout of `swift-distributed-tracing` in `.build/checkouts/` stopped SwiftPM before one rule could judge. Before this run, `swift package describe --type json` gave exit 0 and wrote no error. The counts of this run show 7 rules attempted, 0 failed and 0 skipped. Thus all rules judged the change.
    - open: two boxes stay unchecked. The acceptance criterion "A CI run of the integration job passes `demoAttachesAnMCPServer`" and the Tests box need a CI run of the pushed repository. No local copy can start that run. The other half of the fix is on `swissarmyhammer/workflows` as commit `1d31952`. The card does not stay open for a run that this machine cannot start. The review judged the code of the range on its own terms.
    - next: none. The task moves to `done`.
  timestamp: 2026-08-28T14:01:15.739649+00:00
- actor: claude-code
  id: 01m14at8e15g43kcbe6c8320s2
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 1 file, the article dropped from the function name
    - test: green — swift test, 1306 tests in 99 suites, all passed
    - commit: d66a667 — 3 files changed
    - review: clean — 0 findings, 7 validators attempted, 0 failed, 0 skipped; the one prior finding checked; task moved to done

    Two boxes of the card stay open on purpose: the acceptance criterion for a green CI run of the integration job, and its Tests box. No local copy can start that run. It becomes possible when the user pushes this repository.
  timestamp: 2026-08-28T14:01:41.057154+00:00
position_column: done
position_ordinal: ffa080
title: 'CI: build mcp-test-server before the integration job runs CLISmokeTests'
---
## What
`CLISmokeTests.demoAttachesAnMCPServer` (added by `^vsacz8f`) attaches a stdio MCP server with `--mcp`, and the command it names is the `mcp-test-server` executable that the ROOT package builds. The nested `IntegrationTests` package builds no such executable: a test target can depend on no executable, so `swift build --package-path IntegrationTests --build-tests` writes `MCPTestServer.o` alone and no binary. Measured on 2026-08-27: `IntegrationTests/.build/debug/` holds no `mcp-test-server`.

The test therefore reads `<repository root>/.build/debug/mcp-test-server`, which the root `swift build` or `swift test` writes. When no executable stands there, the test fails and names the command that writes it: `swift build --product mcp-test-server`.

That is correct on a developer machine, where the root suite runs first. It is not proven for CI. The workflow runs two jobs: the unit job runs the root `swift test`, and the integration job runs `swift test --package-path IntegrationTests`. The integration job declares `needs: test`, which orders the jobs and shares no filesystem of its own. A runner with a persistent workspace keeps the root `.build`, and a fresh runner does not.

## Acceptance Criteria
- [x] Read `.github/workflows/ci.yml` and the shared `swissarmyhammer/workflows` `swift-ci.yaml`, and state whether the integration job reaches the root `.build` of the unit job.
- [x] When it does not, make the integration job run `swift build --product mcp-test-server` at the repository root before the suite, or give the shared workflow an input that does.
- [ ] A CI run of the integration job passes `demoAttachesAnMCPServer`.
- [x] `README.md` states the build step beside the integration command, when the operator must run it.

## Tests
- [ ] One CI run of the integration job, green.

## Workflow
Read the shared workflow first. Change no test to make it pass.

## Review Findings (2026-08-28 08:47)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 7 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift:91` `swift/naming-clarity` — Function name includes the needless article "The" (capitalized as part of `TheIntegrationSuiteStarts`), violating the established pattern in the test class that omits articles when deriving function names from test strings. Rename to `sharedCallNamesRootProductIntegrationSuiteStarts`, omitting the article "The" to maintain consistency with existing test function naming conventions. #eventplan #phase-4