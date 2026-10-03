---
assignees:
- claude-code
position_column: todo
position_ordinal: '8480'
title: Remove the clock from inner tools.* calls and from nested tools.runCode
---
## What
Rule: each call path has one outer, tool-level timeout. Inside a `runCode` snippet, the outer clock is the `runCode` engine timeout (`MultiTool.timeout(from:)`). Today two more clocks are under it:

1. `RunBinding.innerCallMount` (`Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:64`) gives each inner `tools.*` call a 120 s clock. It reads the static `MultiToolConfiguration.defaultExecutionTimeLimit`, not the instance config. With the default config it can never fire. If a host sets more than 120 s, it cuts each inner call at 120 s. This is a conflict.
2. A nested `tools.runCode` (a `MultiTool` with `depth > 0`, made near `MultiTool.swift:929`) answers `timeout(from:)` with `executionTimeLimit` too. The engine reads the tool value before the mount value (`.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/Hosting/ToolRun.swift:56`). Thus a nested run gets a second clock under the outer one.

Changes:
- [ ] `RunBinding.swift`: `innerCallMount = ToolMount(mode: .runToCompletion)` with no timeout (`ToolMount.init(mode:timeout:)` takes `nil` by default). Rewrite its doc: the outer `runCode` clock bounds the inner call, and cancellation of the outer run reaches the inner call through `InFlightInnerCalls`.
- [ ] `Sources/FoundationModelsMultitool/MultiTool+Background.swift`: `timeout(from:)` returns `nil` when `depth > 0`, and `configuration.executionTimeLimit` when `depth == 0`. Update its doc.
- [ ] `Tests/FoundationModelsMultitoolTests/RunBindingTests.swift:30`: expect `innerCallMount.timeout == nil`.
- [ ] Check `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift` (near line 106) and `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift`. The MCP tests that inject their own short mount test that MCP progress reaches an engine clock. They may keep their own injected mount. Change only the comments that say the mount is `innerCallMount` "with the short bound".

## Acceptance Criteria
- [ ] `RunBinding.innerCallMount.timeout` is `nil`.
- [ ] `MultiTool.timeout(from:)` is `nil` for a nested run and `executionTimeLimit` for a top-level run.
- [ ] An inner `tools.*` call that never completes inside a mounted `runCode` ends when the outer `runCode` times out, with the outer `.timedOut` outcome, and not with an inner `ToolMountError.timedOut`.

## Tests
- [ ] Update `RunBindingTests.swift` for the nil timeout.
- [ ] Add a test in `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift` (near the existing `timeout(from:)` test at line 47) for the nested `depth > 0` value.
- [ ] Add a mounted test (pattern of `^e2xvhtk`) with a host config of more than 120 s and a small test clock. It proves that no inner 120 s clock fires.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt