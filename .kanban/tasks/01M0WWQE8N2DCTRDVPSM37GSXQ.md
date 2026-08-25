---
assignees:
- claude-code
depends_on:
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8780'
title: Port PatchParser into Capabilities/Files
---
## What
Port `PatchParser` from the FileTool package into this package. This is the pure parsing layer under `PatchEngine`. It has no file IO, so it ports alone.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/PatchParser.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/PatchParser.swift`

Keep the corrective posture: a patch that cannot parse comes back as a corrective description, not as a thrown error.

## Acceptance Criteria
- [ ] The parser accepts and rejects the same patch texts as the source.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `PatchParserTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter PatchParserTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan