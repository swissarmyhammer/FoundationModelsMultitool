---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1hbxx7qmzgt02pygk30yawv
  text: |-
    ### research
    - `resolvedSandboxDirectories(request:)` has two production callers: `ShellRunner.configuration(for:)` (ShellRunner.swift:443) and `Execute.confinementRefusal(for:)` (Execute.swift:279). Two tests call it: `resolvedSandboxDirectoriesResolvesSymlinks` and `resolvedSandboxDirectoriesFallsBackToCurrentDirectory`.
    - Every `ShellRunner(...)` call uses argument labels (ShellCapability.swift:115, five test files). A new stored property after `sandbox` keeps the label order, so no caller changes.
    - `runsInRequestedWorkingDirectory` (ShellRunnerTests.swift:351) already runs `/bin/pwd` and compares resolved paths. The two new `pwd` tests share that shape, so the shape moves into two helpers (`makeWorkDirectory(named:in:)`, `printedWorkingDirectory(of:in:workingDirectory:)`) and all three tests call them. This keeps the duplication validator clean.
    - Plan: tests first, then `defaultWorkingDirectory`, `effectiveWorkingDirectory(for:defaultWorkingDirectory:)`, the new parameter on `resolvedSandboxDirectories`, the `Configuration.workingDirectory` change, and the two doc-comment updates.
  timestamp: 2026-09-02T15:31:16.855827+00:00
- actor: claude-code
  id: 01m1hc60mywzgeq4eqxfk42r6d
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift (new `defaultWorkingDirectory`, new `effectiveWorkingDirectory(for:defaultWorkingDirectory:)`, `resolvedSandboxDirectories(request:defaultWorkingDirectory:)`, `Configuration.workingDirectory` always stated, three doc comments), Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift (`confinementRefusal` passes `runner.defaultWorkingDirectory`), Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift (two tests take `defaultWorkingDirectory: nil`, four new tests, two shared helpers `makeWorkDirectory(named:in:)` and `printedWorkingDirectory(of:in:workingDirectory:)`).
    - TDD: `swift build --build-tests` was red first (`type 'ShellRunner' has no member 'effectiveWorkingDirectory'`, `extra argument 'defaultWorkingDirectory'`). After the implementation `swift test --filter ShellRunnerTests` passed 31 tests in 1 suite. The only build warning is the pre-existing SwiftPM note for `mlx-swift_Cmlx.bundle`.
    - next: `/test` over the whole suite, then `/commit`, then `/review`.
  timestamp: 2026-09-02T15:35:42.494997+00:00
- actor: claude-code
  id: 01m1hc79ergtfkbp2zzqrgchvg
  text: |-
    ### test — green
    - evidence: `swift test` — 1393 tests in 108 suites passed, 0 failed, 0 skipped. The one build warning is the pre-existing SwiftPM note for `mlx-swift_Cmlx.bundle`, which is not from this repository.
    - next: `/commit` (local only), then `/review`.
  timestamp: 2026-09-02T15:36:24.280388+00:00
- actor: claude-code
  id: 01m1hc87xewxprc4234fwk9b40
  text: |-
    ### commit — changed
    - evidence: d860128 feat(shell): add a default working directory to ShellRunner (local commit, not pushed; the two `.kanban/` files travel in it)
    - next: `/review 01M1H2RZYD71QYG972YGKQ122C HEAD~1..HEAD`.
  timestamp: 2026-09-02T15:36:55.470825+00:00
- actor: claude-code
  id: 01m1hcf4794wt08yzb332755rd
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (d860128) — counts: 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 3 files reviewed; the 2 `.kanban/` files are excluded by `.reviewignore`. No prior `## Review Findings` section on the card.
    - next: the card moves `review → done`.
  timestamp: 2026-09-02T15:40:41.065231+00:00
- actor: claude-code
  id: 01m1hcfw1eg2r86qe3hd2r58wc
  text: |-
    ### finish iteration 1 — review clean, task done
    - implement: changed — 3 files (ShellRunner.swift, Execute.swift, ShellRunnerTests.swift); red first on the missing API, then `swift test --filter ShellRunnerTests` passed 31 tests
    - test: green — `swift test` passed 1393 tests in 108 suites, 0 failed, 0 skipped; the one warning is the pre-existing `mlx-swift_Cmlx.bundle` note
    - commit: d860128
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings, 7 validators attempted, 0 failed; the card moved review → done
  timestamp: 2026-09-02T15:41:05.454375+00:00
position_column: done
position_ordinal: ffae80
title: Add a default working directory to ShellRunner
---
## What
Ask 6, part 1 (UPSTREAM_ASKS.md). A request that omits `workingDirectory` runs in the current directory of the agent PROCESS. `ShellRunner` must take a default that the composition supplies, and a request that names no directory must run in that default.

Change `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`:
- Add `var defaultWorkingDirectory: String?` (default `nil`) AFTER `sandbox`, so the label order of the memberwise initializer that `ShellCapability.init` and the tests call does not change. Document: the directory a request runs in when it names none; `nil` keeps the current directory of this process.
- Add `static func effectiveWorkingDirectory(for request: Request, defaultWorkingDirectory: String?) -> String`: `request.workingDirectory ?? defaultWorkingDirectory ?? FileManager.default.currentDirectoryPath`. This is the ONE place that spells the fallback. It is `static` for the same reason `resolvedSandboxDirectories` is: a test proves it with no runner and no spawn.
- In `configuration(for:)` (line 454-460 at e8c91a6), pass `workingDirectory: FilePath(Self.effectiveWorkingDirectory(for: request, defaultWorkingDirectory: defaultWorkingDirectory))`. The spawned `Configuration` no longer gets `nil`, so the child no longer inherits the process directory.
- Keep `static func resolvedSandboxDirectories` static. Add a parameter with no default value: `resolvedSandboxDirectories(request: Request, defaultWorkingDirectory: String?)`. It resolves `effectiveWorkingDirectory(for:defaultWorkingDirectory:)`. Update the two production callers: `configuration(for:)` in the same file (passes `defaultWorkingDirectory`), and `Execute.confinementRefusal(for:)` in `Capabilities/Shell/Execute.swift` (line 279; passes `runner.defaultWorkingDirectory`).
- Update the doc comments of `Request.workingDirectory` and `Request.init` ("or `nil` to take the default working directory of the runner, or the current directory of this process when the runner has none"), and the doc comment of `resolvedSandboxDirectories` (the "falls back to the current directory of this process" sentence).

Do not change `ShellCapability` or `withShell` here. That is the next task.

## Acceptance Criteria
- [x] A runner with `defaultWorkingDirectory` set runs a request with `workingDirectory == nil` in that directory: `pwd` prints `ShellRunner.resolvedDirectory(path:)` of the default.
- [x] A request with a `workingDirectory` wins over the runner default.
- [x] A runner with no default runs a request with no directory in the current directory of the process (the existing behavior).
- [x] `effectiveWorkingDirectory(for:defaultWorkingDirectory:)` gives the request directory, then the default, then the process directory, in that order.
- [x] `resolvedSandboxDirectories(request:defaultWorkingDirectory:)` gives `work` equal to the resolved default when the request names no directory.
- [x] `swift build` gives no new warning.

## Tests
- [x] Update `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift`: the two tests `resolvedSandboxDirectoriesResolvesSymlinks` (line 777) and `resolvedSandboxDirectoriesFallsBackToCurrentDirectory` (line 811) pass `defaultWorkingDirectory: nil`. They stay pure: no `throws`, no runner.
- [x] Add to `ShellRunnerTests.swift`: `effectiveWorkingDirectoryPrefersTheRequestThenTheDefault` (pure, three cases), `resolvedSandboxDirectoriesTakesTheRunnerDefault` (pure, a symlinked default such as `/tmp` resolves to `/private/tmp`), `aRequestWithNoDirectoryRunsInTheRunnerDefault` (make a runner with `makeRunner(...)` at line 123, set `runner.defaultWorkingDirectory` to a temporary directory, run `pwd`, read the stored lines), `aRequestDirectoryWinsOverTheRunnerDefault`.
- [x] Run `swift test --filter ShellRunnerTests` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #ask-6 #upstream-asks