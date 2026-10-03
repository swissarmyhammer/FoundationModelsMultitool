---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m418sq8zzy4rg977e6pjw14b
  text: |-
    Research:
    - `ToolRun` (FoundationModelsExtras) uses `tool.timeout(from:) ?? mountTimeout`. The engine clock sleeps on real time (`RunEventFunnel.waitForTimeout`). There is no clock to inject. The timeout of a run is not recorded in any event or record.
    - Thus no test can make the old inner 120 s clock fire fast. The RED driver of this task is the `RunBindingTests` expectation `innerCallMount.timeout == nil`, and the `timeout(from:)` test for `depth > 0`.
    - The mounted test: a test-only `BackgroundTool` decorator named `runCode` forwards to a `MultiTool` with `executionTimeLimit` of more than 120 s and declares a small mount timeout (the small test clock). It proves that the inner call ends with the outer `.timedOut` text of the small window, and that the host config does not reach an inner clock. It cannot fail on the old code, because a 120 s clock cannot fire in a short window.
    - The nested `tools.runCode` host function calls `nested.call(arguments:)` directly, not through a mount. Thus today the engine does not read `timeout(from:)` of a nested `MultiTool`. The card change makes the value `nil` for `depth > 0`, so that a later mount of a nested run cannot add a second clock.
    - Comments to change: `MCPServerCallTests.shortInnerCallMount` and the doc of `aCallUnderAContextEndsAtTheInnerCallBound`. `ShellRunPlaneFixtures` says only "The configuration is `RunBinding.innerCallMount`", which stays true.
  timestamp: 2026-10-03T16:15:48.511384+00:00
- actor: claude-code
  id: 01m4194e23w19w8tkm4d0zskw2
  text: |-
    Implementation:
    - `RunBinding.innerCallMount` is now `ToolMount(mode: .runToCompletion)` with no clock. Its doc and the type doc say that the outer `runCode` clock bounds an inner call, and that cancellation reaches the inner call through `InFlightInnerCalls`.
    - `MultiTool.timeout(from:)` answers `nil` when `depth > 0`. `MultiTool.depth` changed from `private` to internal, because `MultiTool+Background.swift` reads it.
    - TDD: RED was 2 issues (`theInnerCallMountHasNoClock`, `nestedRunCodeStatesNoTimeout`). GREEN after the change.
    - The mounted test `pendingToolCallUnderALongHostConfigEndsAtTheOuterClock` uses a test-only `SmallClockRunCode` decorator: a `MultiTool` with `executionTimeLimit` 600 s behind a mount clock of 0.3 s. It passed on the old code too, because no fast test can wait for a 120 s clock (the engine clock is real time and cannot be injected). It shares one helper with `pendingToolCallEndsAtTheEngineClock`, so the two tests have no copied body.
    - `MCPServerCallTests`: the comments on `shortInnerCallMount` and on `aCallUnderAContextEndsAtTheInnerCallBound` now say that the test injects its own clock because it has no outer `runCode`. `ShellRunPlaneFixtures` did not need a change.
    - The only warning in the build output is the build-system line "missing creator for mutated node ... mlx-swift_Cmlx.bundle". It is not a compiler warning and does not come from this change.

    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsMultitool/Invocation/RunBinding.swift, Sources/FoundationModelsMultitool/MultiTool+Background.swift, Sources/FoundationModelsMultitool/MultiTool.swift, Tests/FoundationModelsMultitoolTests/RunBindingTests.swift, Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift, Tests/FoundationModelsMultitoolTests/RunCodeToolTimeoutTests.swift, Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift. `swift test --filter '...|RunBinding|MCPServerCallTests'` 20 tests passed; `swift test` 1893 tests in 157 suites passed, 0 failures.
    - next: /review
  timestamp: 2026-10-03T16:21:39.523688+00:00
position_column: doing
position_ordinal: '80'
title: Remove the clock from inner tools.* calls and from nested tools.runCode
---
## What
Rule: each call path has one outer, tool-level timeout. Inside a `runCode` snippet, the outer clock is the `runCode` engine timeout (`MultiTool.timeout(from:)`). Today two more clocks are under it:

1. `RunBinding.innerCallMount` (`Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:64`) gives each inner `tools.*` call a 120 s clock. It reads the static `MultiToolConfiguration.defaultExecutionTimeLimit`, not the instance config. With the default config it can never fire. If a host sets more than 120 s, it cuts each inner call at 120 s. This is a conflict.
2. A nested `tools.runCode` (a `MultiTool` with `depth > 0`, made near `MultiTool.swift:929`) answers `timeout(from:)` with `executionTimeLimit` too. The engine reads the tool value before the mount value (`.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/Hosting/ToolRun.swift:56`). Thus a nested run gets a second clock under the outer one.

Changes:
- [x] `RunBinding.swift`: `innerCallMount = ToolMount(mode: .runToCompletion)` with no timeout (`ToolMount.init(mode:timeout:)` takes `nil` by default). Rewrite its doc: the outer `runCode` clock bounds the inner call, and cancellation of the outer run reaches the inner call through `InFlightInnerCalls`.
- [x] `Sources/FoundationModelsMultitool/MultiTool+Background.swift`: `timeout(from:)` returns `nil` when `depth > 0`, and `configuration.executionTimeLimit` when `depth == 0`. Update its doc.
- [x] `Tests/FoundationModelsMultitoolTests/RunBindingTests.swift:30`: expect `innerCallMount.timeout == nil`.
- [x] Check `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift` (near line 106) and `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift`. The MCP tests that inject their own short mount test that MCP progress reaches an engine clock. They may keep their own injected mount. Change only the comments that say the mount is `innerCallMount` "with the short bound".

## Acceptance Criteria
- [x] `RunBinding.innerCallMount.timeout` is `nil`.
- [x] `MultiTool.timeout(from:)` is `nil` for a nested run and `executionTimeLimit` for a top-level run.
- [x] An inner `tools.*` call that never completes inside a mounted `runCode` ends when the outer `runCode` times out, with the outer `.timedOut` outcome, and not with an inner `ToolMountError.timedOut`.

## Tests
- [x] Update `RunBindingTests.swift` for the nil timeout.
- [x] Add a test in `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift` (near the existing `timeout(from:)` test at line 47) for the nested `depth > 0` value.
- [x] Add a mounted test (pattern of `^e2xvhtk`) with a host config of more than 120 s and a small test clock. It proves that no inner 120 s clock fires.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt