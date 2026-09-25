---
assignees:
- claude-code
position_column: todo
position_ordinal: '9480'
title: Split MultiToolBuilder.swift under 400 lines
---
## What
`Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` has 483 lines. It was 461 lines before ^3332gzb added the internal `withWeb(configuration:sessionConfiguration:resolver:)` overload. The project limit is 400 lines for each file.

The capability short forms (`withShell`, `withFiles`, `withWeb`, `withMCP`) can move to an extension file, for example `Surface/MultiToolBuilder+Capabilities.swift`. `Builder.source` is `private` now. The move needs a narrower way to write the registrations from the extension (for example `fileprivate` is not sufficient across files, thus an internal method that replaces or appends a capability registration).

## Acceptance Criteria
- [ ] `MultiToolBuilder.swift` and each new file have fewer than 400 lines.
- [ ] The public API of `MultiTool.Builder` does not change.

## Tests
- [ ] `swift test` passes with no change to a test. #web