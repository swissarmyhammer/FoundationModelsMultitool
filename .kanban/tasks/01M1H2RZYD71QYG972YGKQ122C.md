---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
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
- [ ] A runner with `defaultWorkingDirectory` set runs a request with `workingDirectory == nil` in that directory: `pwd` prints `ShellRunner.resolvedDirectory(path:)` of the default.
- [ ] A request with a `workingDirectory` wins over the runner default.
- [ ] A runner with no default runs a request with no directory in the current directory of the process (the existing behavior).
- [ ] `effectiveWorkingDirectory(for:defaultWorkingDirectory:)` gives the request directory, then the default, then the process directory, in that order.
- [ ] `resolvedSandboxDirectories(request:defaultWorkingDirectory:)` gives `work` equal to the resolved default when the request names no directory.
- [ ] `swift build` gives no new warning.

## Tests
- [ ] Update `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift`: the two tests `resolvedSandboxDirectoriesResolvesSymlinks` (line 777) and `resolvedSandboxDirectoriesFallsBackToCurrentDirectory` (line 811) pass `defaultWorkingDirectory: nil`. They stay pure: no `throws`, no runner.
- [ ] Add to `ShellRunnerTests.swift`: `effectiveWorkingDirectoryPrefersTheRequestThenTheDefault` (pure, three cases), `resolvedSandboxDirectoriesTakesTheRunnerDefault` (pure, a symlinked default such as `/tmp` resolves to `/private/tmp`), `aRequestWithNoDirectoryRunsInTheRunnerDefault` (make a runner with `makeRunner(...)` at line 123, set `runner.defaultWorkingDirectory` to a temporary directory, run `pwd`, read the stored lines), `aRequestDirectoryWinsOverTheRunnerDefault`.
- [ ] Run `swift test --filter ShellRunnerTests` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #ask-6 #upstream-asks