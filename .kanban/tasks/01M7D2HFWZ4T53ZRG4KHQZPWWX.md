---
assignees:
- claude-code
position_column: done
position_ordinal: fffffffe80
title: An MCP tool result keeps its image blocks for the host
---
## What
Request from testudoapp-75 (TestudoApp ^v30ggjj, Step 2). `MCPTool.call(arguments:)` returns only the text of `ToolContentRenderer.render`. The renderer changes an image block to `[image: <mimeType>]`, thus the image data is lost before FoundationModelsACPAgent gets the result.

- New public type `MCPToolContent` in Sources/FoundationModelsMultitool/Capabilities/MCP/MCPToolContent.swift: the ordered `MCP.Tool.Content` blocks of one result and `isError`. It encodes to a `ToolDisplayContent.json` with one key `mcpToolContent`, and `init?(display:)` decodes it again (nil for each other display part).
- `MCPTool.call(arguments:)` (Capabilities/MCP/MCPTool.swift): under an ambient `ToolContext`, when the result has a block that is not text, post one display chunk with all blocks. The model text does not change.

## Acceptance Criteria
- [ ] The text that the model reads does not change.
- [ ] A result with an image block posts one display chunk; `MCPToolContent(display:)` gives the image data and mimeType.
- [ ] A text-only result posts no display chunk. A call with no ambient context posts nothing and does not fail.
- [ ] A call inside a runCode snippet posts the chunk under the runCode run.

## Tests
- [ ] Tests/FoundationModelsMultitoolTests/MCPToolContentTests.swift
- [ ] `swift test` is green with no new warnings.

## Workflow
- Use `/tdd`. #step2