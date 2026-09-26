---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ffr5ezhw26ynnzgk9yrh7p
  text: |-
    ### implement — research
    - A call under a context gets no bare timer (`dispatch` starts `startBareTimeout` only when `context == nil`). The bound comes from the mount: `RunBinding.invoke` mounts the tool with `innerMount`, and Router `ToolRun.raceAgainstTimeout` races the inner task against the timeout. At expiry it cancels the inner task and returns `ToolMountError.timedOut` at once. It does not wait for the inner task.
    - `MCPServer.call` has a cancellation handler that settles the in-flight entry with `CancellationError` and sends `notifications/cancelled`. Thus the MCP call also ends.
    - `HangingTransport.connect()` never returns, so a server over it never gets to `.ready`, and a call on it answers "not ready" in band. It cannot carry the call itself. The plan: move its never-resumed continuation into a shared `HangingTransport.hangForever()`, and use it in the handler of a scripted tool. That tool makes no progress and does not obey cancellation.
    - The file header of `MCPServer+Call.swift` names no Router constant (it says "the engine's clock"). No change is necessary there.
    - The validator rules file is 730K characters. I read the rule list and the swift, test-integrity and magic-number sections, not the full file.
  timestamp: 2026-09-26T18:30:57.759444+00:00
- actor: claude-code
  id: 01m3fftmk77yt2v00wxbksntpc
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift (new test `aCallUnderAContextEndsAtTheInnerCallBound`, the scripted `hangingTool`, and named constants), Tests/FoundationModelsMultitoolTests/Support/HangingTransport.swift (the never-resumed continuation moved into `static func hangForever() async -> Never`; `connect()` calls it).
    - The test passed on its first run. Thus the bound already reaches an MCP call under a context, and no fix to source is necessary. The test calls `RunBinding(context:innerMount:)` with a 0.05 s injected bound, and expects `ToolMountError.timedOut(tool: "mcpProbe", timeoutSeconds: 0.05)`, elapsed >= bound and < 5 s, `notifications/cancelled` on the wire, and `inFlightCalls` empty.
    - `MCPServer+Call.swift` names no Router constant. No change there.

    ### test — green
    - evidence: `swift build --build-tests && swift test` — 1798 tests in 145 suites passed, 0 failed, 0 skipped. `swift test --filter 'MCPServerCallTests|RunBindingTests'` — 16 tests in 2 suites passed. The one SwiftPM `missing creator for mutated node` line for `mlx-swift_Cmlx.bundle` is a known build-system message about a third-party bundle, already on record in other tasks.
    - next: commit.
  timestamp: 2026-09-26T18:32:18.791336+00:00
- actor: claude-code
  id: 01m3fg0jyetqzn8my3gzg4nyjr
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed. 2 `.kanban/` files not reviewed (from `.reviewignore`). No prior `## Review Findings` sections.
    - next: the task moved to `done`.

    ### finish iteration 1 — clean
    - implement: changed — MCPServerCallTests.swift (new test `aCallUnderAContextEndsAtTheInnerCallBound`), Support/HangingTransport.swift (`hangForever()`). No fix to source was necessary; the bound already reaches the MCP call.
    - test: green — `swift test` 1798 tests in 145 suites passed; the filtered run of `MCPServerCallTests|RunBindingTests` passed 16 tests in 2 suites.
    - commit: changed — 21bc6dd test(mcp): prove that an MCP call under a context ends at the inner-call bound
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings.
  timestamp: 2026-09-26T18:35:33.710958+00:00
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: done
position_ordinal: ffed80
title: Prove that an MCP call under a context ends at the inner-call bound
---
## What
Router's `ToolMount` has no default timeout now. Upstream commit `2f4707f` already set `RunBinding.innerCallMount = ToolMount(mode: .runToCompletion, timeout: MultiToolConfiguration.defaultExecutionTimeLimit)` (`Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:64`). The two other `ToolMount(` sites (`MultiTool+Background.swift:99`, `Capabilities/Shell/Execute.swift:133`) are `.background` with `timeout: nil`, and that is intended. No test proves that the bound reaches an MCP call made under a context. The file header of `Capabilities/MCP/MCPServer+Call.swift` says that "the engine's clock ... bounds every call made under a context".
- [x] Add a test with a short injected bound and `Tests/FoundationModelsMultitoolTests/Support/HangingTransport.swift`.
- [x] If the test fails, fix the path so the bound reaches the MCP call. (The test passed on its first run. No fix was necessary.)
- [x] If the doc comment of `MCPServer+Call.swift` names the old Router constant, update it. (It names no Router constant. No change was necessary.)

## Acceptance Criteria
- [x] An MCP call made under a context, to a server that makes no progress, ends with a timeout error at the bound. It does not hang.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift`: the new test above.
- [x] Run `swift test --filter 'MCPServerCallTests|RunBindingTests'`, then `swift test`. Expected result: both pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.