---
assignees:
- claude-code
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
position_column: todo
position_ordinal: '8680'
title: Prove that an MCP call under a context ends at the inner-call bound
---
## What
Router's `ToolMount` has no default timeout now. Upstream commit `2f4707f` already set `RunBinding.innerCallMount = ToolMount(mode: .runToCompletion, timeout: MultiToolConfiguration.defaultExecutionTimeLimit)` (`Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:64`). The two other `ToolMount(` sites (`MultiTool+Background.swift:99`, `Capabilities/Shell/Execute.swift:133`) are `.background` with `timeout: nil`, and that is intended. No test proves that the bound reaches an MCP call made under a context. The file header of `Capabilities/MCP/MCPServer+Call.swift` says that "the engine's clock ... bounds every call made under a context".
- [ ] Add a test with a short injected bound and `Tests/FoundationModelsMultitoolTests/Support/HangingTransport.swift`.
- [ ] If the test fails, fix the path so the bound reaches the MCP call.
- [ ] If the doc comment of `MCPServer+Call.swift` names the old Router constant, update it.

## Acceptance Criteria
- [ ] An MCP call made under a context, to a server that makes no progress, ends with a timeout error at the bound. It does not hang.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift`: the new test above.
- [ ] Run `swift test --filter 'MCPServerCallTests|RunBindingTests'`, then `swift test`. Expected result: both pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.