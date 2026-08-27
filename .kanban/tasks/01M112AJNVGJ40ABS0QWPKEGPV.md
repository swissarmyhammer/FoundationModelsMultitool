---
assignees:
- claude-code
depends_on:
- 01M11286356T1VMGHBSMF9V7W5
position_column: todo
position_ordinal: '8380'
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
- [ ] Each content kind renders to the same text as the source, at each `RenderBudget` case.
- [ ] An `isError` result renders as the source does: the text is in-band, and it is not thrown. This agrees with the in-band corrective contract of the other capabilities.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `RendererTests.swift`, `RendererTrimTests.swift`, and `RenderBudgetTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter Renderer` passes.
- [ ] `swift test --filter RenderBudget` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #eventplan #phase-4