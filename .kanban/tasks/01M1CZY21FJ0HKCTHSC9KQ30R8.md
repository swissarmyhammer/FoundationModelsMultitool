---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1d1pc1aamn2evdcp4t5e6pp
  text: |
    ### Research

    Baseline, measured on this checkout before any edit:

    - `swift build --build-tests` at the root: clean, 11.4 s.
    - `swift test` at the root: **1316 tests in 101 suites, 6.4 s to 9.1 s**.
    - The baseline is **already red**, and the cause is not this card. One test
      fails: `README's enumerated 'Injected globals' list is set-equal to the
      runtime-enumerated sandbox globals`, at `HardeningTests.swift:285` —
      `README.md has no "### Injected globals" section`. The working tree was
      clean when this run started, so the failure is on `main`. It is recorded as
      a task of its own and is not touched here.

    What the three suites actually need, read file by file:

    - `ScenarioFailureModeTests` (22) needs `ScenarioObservation`,
      `ScenarioFailureModes`, `scenarioMinimumToolCalls`, `scenarioThrashFactor`,
      `NativeTranscript`, plus `ResultRenderer` and `InterpreterError` through
      `@testable import FoundationModelsMultitool`.
    - `ScenarioFixtureTests` (20) needs the fixtures, `ScenarioCall`,
      `ScenarioCallLog`, `NativeTranscript`, `integerAnswers(for:)`, plus
      `MultiTool`, `RunCodeArguments`, `RepairDirective` and `ToolReturnLedger`.
    - `ScenarioGradingTests` (8) needs the fixtures, `ScenarioCallLog`,
      `ScenarioCheck`, `ScenarioEvidence`, `scenarioChecks`,
      `InBandCollectionEvidence`, `inBandCollectionChecks`,
      `NestedGenerationEvidence`, `nestedGenerationChecks`, `integerAnswers`.

    So the shared home takes five files, not one: `ScenarioCallLog.swift`,
    `ScenarioTools.swift`, `NativeTranscript.swift`, `ScenarioFailureModes.swift`,
    and the pure half cut out of `ScenarioRunner.swift`.

    Two facts that decide the shape:

    1. `ScenarioTools.swift` names **no** `FoundationModelsMultitool` symbol. Its
      `@testable import FoundationModelsMultitool` is unused. So the shared target
      links Router and the metadata registry only, and no `@testable` import is
      needed anywhere in it.
    2. `grade(scenario:checks:)` calls `#expect`, so it imports `Testing` and must
      stay on the gated side. No moved test calls it.

    `ScenarioRunner.swift` also holds a defect this split removes: `@testable
    import FoundationModelsMultitool` sits at line 49, in the middle of the file,
    after a `let` declaration.

    The declarations that move become `public`. A `public` struct's synthesized
    memberwise initializer is `internal`, so each one gets an explicit `public
    init` — the pattern `RunCodeArguments` already states in
    `Sources/FoundationModelsMultitool/MultiTool.swift`. `@Generable` on a
    `public` struct is already used there too, so the fixture argument types keep
    working.
  timestamp: 2026-08-31T23:15:26.378484+00:00
- actor: claude-code
  id: 01m1d30sbwnxr2x19cygsdprws
  text: |
    ### What the split turned out to be

    The card names one file to split. Five files had to move, because the three
    suites read the fixtures and the readers as well as the grading rules.

    New target and product `ScenarioGrading`, at `Tests/Support/ScenarioGrading/`,
    declared in `Package.swift` beside `MCPTestServer` and `TestConcurrency`. It
    links Router and the metadata registry, and no target of this package. It
    holds:

    - `ScenarioCallLog.swift`, `ScenarioTools.swift` (moved from the gated
      package's `Fixtures/`, which is now empty and gone),
    - `NativeTranscript.swift`, `ScenarioFailureModes.swift` (moved from the gated
      package's `Support/`),
    - `ScenarioGrading.swift` (new — the grading half cut out of
      `ScenarioRunner.swift`).

    `ScenarioRunner.swift` goes from 1704 lines to 1344 and keeps the driving
    alone. `grade(scenario:checks:)` stays with it: it records a Swift Testing
    issue for each failed condition, so it belongs to a test target, not to a
    library. No moved test calls it.

    ### Two things the plan did not predict

    **`ScenarioTools.swift` does name a `FoundationModelsMultitool` symbol after
    all.** `IntegrationNestedGenerationTool` records its call as a `CallTrace`
    span, and `CallTrace` is `internal` to the shipped library. A support library
    cannot carry `@testable`, and widening `CallTrace` to `public` would grow the
    shipped API for a fixture's sake.

    That tool also fails the card's own seam: its body opens a nested `respond` on
    a resolved `RoutedLLM`, which is live-model driving. So it stays in the gated
    package, in a new
    `IntegrationTests/.../Fixtures/IntegrationNestedGenerationTool.swift`, beside
    its prompt and its token limit. What the grading rule and its ungated coverage
    read stays in `ScenarioGrading`: `integrationNestedGenerationPath` (a constant
    of its own now, since the tool and the rule that grades it stand in different
    modules) and `integrationNestedGenerationToken`.

    **`public` removes inferred `Sendable`.** `IntegrationCityWeather` was an
    internal struct of `String`/`String`/`Double`, so the compiler inferred
    `Sendable` and the three global `let`s built from it compiled. A `public`
    struct gets no inference, so all three globals became concurrency errors. The
    type now declares `Sendable`.

    Beside that, every declaration the two test targets name is `public` with an
    explicit `public init` where a caller constructs it — the synthesized
    memberwise initializer is `internal` only, which is the reason
    `RunCodeArguments.init(code:)` in the shipped library states as well. What no
    caller outside the module names stays `internal`: each tool's `log` and the
    whole `IntegrationDistractorTool` family, which reaches its callers as
    `[any Tool]`.

    ### Three defects in the file this split touched, corrected

    1. `@testable import FoundationModelsMultitool` sat at line 49 of
       `ScenarioRunner.swift`, after a `let` declaration. It is in the header now.
    2. `NativeTranscript.returnedValues(in transcript:)` had no doc comment. Its
       doc block had drifted up the file and attached itself to `StreamedCall`,
       which already had one. The block sits above the function again.
    3. `ScenarioSurface` carried a line of trailing whitespace and a doc line at
       column zero.

    ### swiftlint, measured

    `swiftlint` with the review's own `missing_docs`, `no_magic_numbers`,
    `function_body_length` and `closure_body_length` settings reports:

    - `missing_docs`: **0** across every changed file. 17 fixture properties that
      became `public` had no doc comment, and each now has one.
    - `no_magic_numbers`: 8, every one on a line this change did not write. The
      same file reported 5 of them at `HEAD` before the move, and `Tests/` carries
      13 more of the same kind, so this is the ambient state of the test tree, not
      something the move introduced.
    - length rules: 0.

    ### The concurrent README change is not this card's

    The tree already carried an uncommitted `README.md` edit adding the
    `### Injected globals` section when this step finished, and `HEAD` had moved
    to `35b056f` under this session. Another session is at work in this
    repository. This step did not touch `README.md`, and the `swift test` run is
    green with that edit present. Card `^eaef498`, filed here for the same
    failure, is likely answered by it.
  timestamp: 2026-08-31T23:38:36.284705+00:00
- actor: claude-code
  id: 01m1d3125z1peh4h0z62shmyxt
  text: |
    ### implement — changed
    - evidence: 20 files. New target and product `ScenarioGrading` in
      `Package.swift`, linked by the unit test target and by
      `IntegrationTests/Package.swift`. Five files moved into
      `Tests/Support/ScenarioGrading/` (`ScenarioCallLog.swift`,
      `ScenarioTools.swift`, `NativeTranscript.swift`,
      `ScenarioFailureModes.swift`, and the new `ScenarioGrading.swift`). Three
      suites moved into `Tests/FoundationModelsMultitoolTests/`
      (`ScenarioFailureModeTests.swift`, `ScenarioFixtureTests.swift`,
      `ScenarioGradingTests.swift`).
      `IntegrationTests/.../Support/ScenarioRunner.swift` 1704 to 1344 lines; new
      `IntegrationTests/.../Fixtures/IntegrationNestedGenerationTool.swift`; one
      added import in each of seven other gated files.
      `swift test` at the root: **1366 tests in 104 suites, 11.1 s, zero issues**
      (baseline 1316, +50). `swift build --build-tests` and
      `swift build --package-path IntegrationTests --build-tests`: both complete
      with no error and no warning of this package, on a forced rebuild.
      The gated suite was not run.
    - next: `/review`. Re-run it file-scoped at the new paths — a diff-scoped
      review leaves three hygiene rules unread on a renamed file.
  timestamp: 2026-08-31T23:38:45.311770+00:00
- actor: claude-code
  id: 01m1d4gd3a7ay5yrk5j2hf7a1v
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit d6e05ca) — 14 validators attempted, 0 failed, 0 skipped. 1 finding, 1 confirmed, 0 refuted: `Tests/Support/ScenarioGrading/ScenarioTools.swift:571`. Two file-scoped runs closed the renamed-file gap — 7 validators attempted, 0 failed, 0 skipped on each — and found no more findings on changed lines.
    - next: replace the magic number at `ScenarioTools.swift:571` with a named constant. Remove the same cause from the whole file. The task stays in Review.
  timestamp: 2026-09-01T00:04:36.586110+00:00
- actor: claude-code
  id: 01m1d4hcspg1c9sx58ermz5vth
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 20 files. New `ScenarioGrading` test-support target and product in `Package.swift`, beside `MCPTestServer` and `TestConcurrency`, linked by both packages. Five files moved into `Tests/Support/ScenarioGrading/`, three suites moved into the root test target. `ScenarioRunner.swift` 1704 to 1344 lines. `IntegrationNestedGenerationTool` stayed gated: it records a `CallTrace` span, `CallTrace` is internal to the shipped library, a support library cannot carry `@testable`, and widening it would grow the shipped API for a fixture.
    - test: green — `swift test`, **1366 tests in 104 suites, 0 failures, 0 skipped, 9.1 seconds**, against a baseline of 1316. `HardeningTests` 15 of 15, including the README-globals set-equality test. A forced rebuild of both packages gave no error and no warning except the pre-existing third-party `mlx-swift` one.
    - commit: `d6e05ca` — 26 files, 1347 insertions, 685 deletions. It also carries a README correction: an earlier rewrite deleted the `### Injected globals` section, which `HardeningTests` parses and asserts set-equality against the runtime globals, so deleting it broke the suite.
    - review: findings — `Tests/Support/ScenarioGrading/ScenarioTools.swift:571`, `code-hygiene/magic-numbers-swift`.

    **The review is trustworthy, and it was checked rather than assumed.** Three runs, 14 then 7 then 7 validators attempted, 0 failed and 0 skipped in each. The seven files not reviewed in the diff run are the six `.kanban` files that `.reviewignore` excludes and `README.md`, which no validator matches.

    **The rename blind spot appeared and was closed.** This commit renames seven files, and `function-length-swift`, `magic-numbers-swift` and `missing-docs-swift` each declined all seven, because a diff-scoped run reads the paths from before the rename. The reviewer re-ran that validator file-scoped at the new paths. The only extra magic-number hits are at lines 65, 66, 67 and 85 of `ScenarioTools.swift`, which this commit does not touch, thus the diff contract excludes them.

    - next: correct the magic number at `ScenarioTools.swift:571`. Remove the cause from the whole file, and not the one line in the finding.
  timestamp: 2026-09-01T00:05:09.046538+00:00
- actor: claude-code
  id: 01m1d4w0saqdr4cngv3bxa9ed5
  text: |
    ### implement — changed

    The open finding is corrected: `Tests/Support/ScenarioGrading/ScenarioTools.swift:571`, `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.

    The cause is removed from the whole file, and not from line 571 alone. `swiftlint` with the review's own `no_magic_numbers` setting measured five results in this file — lines 65, 66, 67, 85 and 571 — and all five are corrected. Five new file-scope constants, each with a doc comment, each named for which fixture reading it is:

    | new constant | value | in place of |
    | --- | --- | --- |
    | `integrationAustinTempC` | `31` | `tempC: 31` in `integrationCityWeather` |
    | `integrationSanFranciscoTempC` | `34` | `tempC: 34` in `integrationCityWeather` |
    | `integrationNewYorkTempC` | `22` | `tempC: 22` in `integrationCityWeather` |
    | `integrationWarmestCityMinimumReadings` | `2` | `count >= 2` in `integrationWarmestCity` |
    | `integrationDeepScanSeconds` | `8` | `.seconds(8)` in `integrationDeepScanDuration` |

    Every value carries across unchanged. The three temperature constants declare `Double` explicitly, because `IntegrationCityWeather.tempC` is a `Double` and a bare integer literal infers `Int`.

    All five stay `internal`. No caller outside `ScenarioGrading` names them, which is the rule this target already applies to each tool's `log` and to the `IntegrationDistractorTool` family. The `public` constants they build — `integrationCityWeather`, `integrationWarmestCity` and `integrationDeepScanDuration` — are unchanged, thus both test targets and the gated package read the same values as before.

    ### Measured

    - `swiftlint --config <no_magic_numbers, missing_docs>` on this file: **5 results before, 0 after**. `missing_docs` is 0 before and after.
    - `swift test` at the root: **1366 tests in 104 suites, 0 failures, 0 skipped, 6.3 s**. The count is unchanged, as it must be for a correction that changes no value.
    - `swift build --build-tests` after a `touch` of the changed file: no error, and no warning other than the third-party `mlx-swift` "missing creator for mutated node" one that is present on `main`.
    - `swift build --package-path IntegrationTests --build-tests`: succeeds, with the same single third-party warning.
    - The gated suite was not run.

    ### One thing to know for the next agent

    `swiftlint` with its **default** rule set reports four other results on this file — `file_length` (1028 lines), one `large_tuple`, one `line_length` and three `trailing_comma`. None is in the review's validator set, none is on a line this correction wrote, and each was present before it. The file was already over 1000 lines before these 18 lines were added.
  timestamp: 2026-09-01T00:10:57.194484+00:00
position_column: doing
position_ordinal: '80'
title: Split ScenarioRunner so the 50 model-free integration tests join the fast suite
---
## What

50 of the 71 tests in the nested `IntegrationTests` package need no model at
all. They test the scenario harness itself, and they run only when a person
runs the gated suite:

| suite | tests | live-model references |
| --- | --- | --- |
| `ScenarioFailureModeTests` | 22 | 0 |
| `ScenarioFixtureTests` | 20 | 0 |
| `ScenarioGradingTests` | 8 | 0 |

None of the three names `LanguageModelSession`, `SystemLanguageModel`,
`LiveRouterFixture` or `runNativeIntegrationScenario`.

## Why they cannot move today, which is also the simplicity problem

`Tests/.../Support/ScenarioRunner.swift` is **1704 lines** and holds two
unrelated things: the grading and evidence logic, which is pure, and the
live-model driving, which needs a `LiveModelLoader`, the Metal bootstrap and
the turnstile. The 50 tests depend on the first and would drag in the second.

The split is the file's natural shape already. Its neighbours are each one
thing:

- `Support/ScenarioFailureModes.swift` — 253 lines, no live reference
- `Support/LiveRouterFixture.swift` — 663 lines, live only

`ScenarioRunner.swift` is the only file that straddles.

## What to do

1. Split `ScenarioRunner.swift` along the seam it already has: the pure
   grading and evidence types on one side, the live-fixture driving on the
   other.
2. Give the pure side a home both packages can link. The root package already
   has this pattern — `Tests/Support/MCPTestServer` and
   `Tests/Support/TestConcurrency` are test-support products of the root
   manifest, declared at `Package.swift` around lines 456 and 463.
3. Move `ScenarioFailureModeTests`, `ScenarioFixtureTests` and
   `ScenarioGradingTests` into the root test target.

## What this is worth

- Those 50 tests join the root suite, which is **1316 tests in 6.5 seconds**,
  so they run on every commit instead of only when a person opts in.
- The gated package becomes only what a gated package is for: real inference.
  21 tests, all of which genuinely drive a model.
- The largest file in the suite stops doing two jobs.

## What must NOT change with it

Two costs in the gated suite are deliberate, are documented with a
measurement, and protect the reliability signal the suite exists to give.
Neither is in scope here and neither should be "tidied" while nearby:

1. **A fixture resolves per scenario and releases at teardown.** Sharing one
   would be faster and would let a prompt cache carry between scenarios. The
   measured failure was a model that narrated a tool call it never made,
   because its context already held one.
2. **`--no-parallel`.** Measured at 661 seconds parallel against 852 serial,
   thus it costs about 190 seconds and buys correct attribution.

## Acceptance Criteria

- [x] `ScenarioRunner.swift` no longer holds both the pure grading logic and
      the live-model driving. It is 1344 lines and holds the driving alone.
- [x] `ScenarioFailureModeTests`, `ScenarioFixtureTests` and
      `ScenarioGradingTests` run in the root test target.
- [x] The nested package holds only tests that drive a model. 21 tests remain,
      in 14 files, and each one reaches a real profile through
      `withLiveRouterFixture` or `CLIRunner`.
- [x] Neither the per-scenario fixture nor `--no-parallel` is changed. The
      whole diff carries no line that names either one.

## Tests

- [x] `swift test` at the root passes, with 1366 tests or more — the current
      1316 plus the 50 that moved — and the run time recorded on this card.
      Measured: **1366 tests in 104 suites, 11.1 s**; three runs read 8.8 s to
      11.1 s. After the magic-number correction: **1366 tests in 104 suites,
      0 failures, 0 skipped, 6.3 s**.
- [ ] `swift test --package-path IntegrationTests --no-parallel` passes with
      the remaining tests, and its time recorded. **Not run by this step**: it
      drives real models for about 14 minutes, and the orchestrator decides
      when to spend that. `swift build --package-path IntegrationTests
      --build-tests` passes with no error and no warning.
- [x] No assertion changes. The three moved suites differ by one added import
      each, and `ScenarioGradingTests` reads the probe's path off
      `integrationNestedGenerationPath` in place of
      `IntegrationNestedGenerationTool.path` — the same string.

## Found by

Task `^jmtpfwv`, which ran the gated suite on 2026-08-31 and counted which of
its tests need a model.


## Review Findings (2026-08-31 18:43)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 26 file(s) reviewed, 7 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

> The tool rule `code-hygiene/function-length-swift` declined 7 items. It read the other code. It could not read these files, because it looked at the path each file had BEFORE the commit renamed it: `Fixtures/ScenarioCallLog.swift`, `Fixtures/ScenarioTools.swift`, `ScenarioFailureModeTests.swift`, `ScenarioFixtureTests.swift`, `ScenarioGradingTests.swift`, `Support/NativeTranscript.swift`, `Support/ScenarioFailureModes.swift`.

> The tool rule `code-hygiene/magic-numbers-swift` declined the same 7 items, for the same cause.

> The tool rule `code-hygiene/missing-docs-swift` declined the same 7 items, for the same cause.

- [x] `Tests/Support/ScenarioGrading/ScenarioTools.swift:571` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.

### Note on the renamed files

The commit renames 7 files. A diff-scoped review reads a renamed file at its
old path, thus 3 hygiene rules could not read those 7 files. To close this
gap, the same validator ran again, file-scoped, at the new paths:

- `review file Tests/Support/ScenarioGrading/*.swift` — 5 files, 7 validators
  attempted, 0 failed, 0 skipped.
- `review file Tests/FoundationModelsMultitoolTests/Scenario*.swift` — 3
  files, 7 validators attempted, 0 failed, 0 skipped, 0 findings.

A file-scoped run reads every line of a file, but this review grades only the
lines the commit changed. Of the hygiene results from the second run, only
line 571 of `ScenarioTools.swift` is on a changed line, and the diff run
already found it. The other magic-number results are at lines 65, 66, 67 and
85 of the same file, which the commit does not touch.

### How the finding was corrected

A finding shows one example of a cause, thus the correction removes that cause
from the whole file, and not from the line the finding names. All five results
in `ScenarioTools.swift` — lines 65, 66, 67, 85 and 571 — are corrected. Each
literal moves into a named constant that says which fixture reading it is,
after the pattern of `integrationDeepScanReportCode` and
`integrationWarehouseStockUnits`. Every value carries across unchanged:

| new constant | value | in place of |
| --- | --- | --- |
| `integrationAustinTempC` | `31` | line 65 |
| `integrationSanFranciscoTempC` | `34` | line 66 |
| `integrationNewYorkTempC` | `22` | line 67 |
| `integrationWarmestCityMinimumReadings` | `2` | line 85 |
| `integrationDeepScanSeconds` | `8` | line 571 |

`swiftlint` with the review's own `no_magic_numbers` setting reports 5 results
for this file before the correction and **0** after it. `missing_docs` reports
0 both before and after: each new constant carries a doc comment. #eventplan