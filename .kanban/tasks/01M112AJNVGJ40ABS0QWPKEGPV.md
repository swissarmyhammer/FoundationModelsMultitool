---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11m7ex9wsr44nh3epfpaq8k
  text: |-
    Research before the port:
    - The two packages resolve the same `swift-sdk` revision (`a0ae212`), so `Tool.Content`, `Resource.Content.text/binary` and `Value.data` have the same shape here as in the sibling.
    - `RenderBudgetTests` in the sibling drives `MCPTool` and `MCPServer`, which this package does not hold yet. The port keeps the type test and exercises each `RenderBudget` case through a `render(result:outputSchema:budget: RenderBudget)` overload on the renderer. The `MCPTool` and `MCPServer` halves come with those ports.
    - `jsonString(for:)` is `private` here. The sibling kept it internal for `MCPElicitationTool`, which is not in this package.
    - The Swift test suites are structs, so `magic-numbers-swift` reads every numeric literal in them. Each number in the ported tests is a named constant.
    - `Value+ScalarString.swift` says the renderer "comes to this folder in a later task". That header line is updated.
  timestamp: 2026-08-27T12:48:27.561835+00:00
- actor: claude-code
  id: 01m11mgmh79h08jmcjp1vzfzbq
  text: |-
    Implementation landed. The tests were written first, then the two source files.

    - `Sources/FoundationModelsMultitool/Capabilities/MCP/ToolContentRenderer.swift`: the renderer, internal. The header states the layer split from `ResultRenderer`, the in-band `isError` contract, and why `jsonString(for:)` is private. One addition to the sibling: `render(result:outputSchema:budget: RenderBudget)`, a one-line overload that maps the budget case to the `Int` overload through `characterLimit`. The `Int` overload keeps the sibling's signature and default. The `/ 2` of the head/tail split is the named constant `keptPartCount`.
    - `Sources/FoundationModelsMultitool/Capabilities/MCP/RenderBudget.swift`: the type, internal, cases and `characterLimit` unchanged.
    - `Value+ScalarString.swift`: the header no longer says the renderer "comes in a later task".
    - Tests: `RendererTests`, `RendererTrimTests`, `RenderBudgetTests`. Every numeric literal is a named constant. `RenderBudgetTests` drives each case through the renderer, because `MCPTool` and `MCPServer` are not in this package yet.

    `swift build`: complete, no warnings. `swift test --filter 'RendererTests|RendererTrimTests|RenderBudgetTests'`: 87 tests in 5 suites passed, no warnings.

    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Capabilities/MCP/ToolContentRenderer.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/RenderBudget.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/Value+ScalarString.swift, Tests/FoundationModelsMultitoolTests/RendererTests.swift, Tests/FoundationModelsMultitoolTests/RendererTrimTests.swift, Tests/FoundationModelsMultitoolTests/RenderBudgetTests.swift
    - next: test, commit, review
  timestamp: 2026-08-27T12:53:28.231886+00:00
- actor: claude-code
  id: 01m11mv36w1rfenbe349j5d2r8
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings, 0 confirmed, 0 refuted; 6 files reviewed, 2 `.kanban/` files excluded by .reviewignore
    - next: move to done
  timestamp: 2026-08-27T12:59:10.940191+00:00
- actor: claude-code
  id: 01m11mves0c8vbmjbrrxqe0s81
  text: |-
    ### finish iteration 1 — review clean, task done
    - implement: changed — 6 files (ToolContentRenderer.swift, RenderBudget.swift, Value+ScalarString.swift, RendererTests.swift, RendererTrimTests.swift, RenderBudgetTests.swift)
    - test: green — swift test: 1107 tests in 79 suites passed, 0 failed, 0 skipped, no compiler warnings
    - commit: e83464e
    - review: clean — review sha HEAD~1..HEAD, 0 findings
  timestamp: 2026-08-27T12:59:22.784053+00:00
depends_on:
- 01M11286356T1VMGHBSMF9V7W5
position_column: done
position_ordinal: ff8c80
title: Port ToolContentRenderer and RenderBudget into Capabilities/MCP
---
## What
Port the result renderer that eventplan.md § "Consolidation of the siblings" names: "`ToolContentRenderer` with its `RenderBudget`". Behavioral port; new header comments in the `//` block style of `Capabilities/Shell/ShellCapability.swift`.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Sources/FoundationModelsMCP/ToolContentRenderer.swift` (500 lines) and `RenderBudget.swift`.
- Target: `Sources/FoundationModelsMultitool/Capabilities/MCP/ToolContentRenderer.swift` and `RenderBudget.swift`.
- `ToolContentRenderer.render(result:outputSchema:budget:)` turns a `CallTool.Result` (text, image, audio, resource, `structuredContent`, `isError`) into the one string the model reads. Keep the trim rules and the budget cases exactly.
- This package already has `ResultRendererLimits` for the `runCode` result. The two are different layers: the MCP renderer bounds one verb's output; `ResultRenderer` bounds the snippet result. State this in the header, and do not merge them.
- Keep the types internal.

## Acceptance Criteria
- [x] Each content kind renders to the same text as the source, at each `RenderBudget` case.
- [x] An `isError` result renders as the source does: the text is in-band, and it is not thrown. This agrees with the in-band corrective contract of the other capabilities.
- [x] `swift build` succeeds.

## Tests
- [x] Port `RendererTests.swift`, `RendererTrimTests.swift`, and `RenderBudgetTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [x] `swift test --filter Renderer` passes.
- [x] `swift test --filter RenderBudget` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #eventplan #phase-4