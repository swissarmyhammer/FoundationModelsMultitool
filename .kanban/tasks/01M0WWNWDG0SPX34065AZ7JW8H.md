---
assignees:
- claude-code
depends_on:
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8180'
title: Port AtomicWriter into Capabilities/Files
---
## What
Port `AtomicWriter` from the FileTool package into this package. This is a behavioral port: keep the write-then-rename atomicity and the error mapping the same.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/AtomicWriter.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift`

Refer to eventplan.md § "Consolidation of the siblings": the Files capability gets `AtomicWriter`, and "Capabilities keep their own serialization where order is important (atomic file writes...)".

## Acceptance Criteria
- [ ] A write is atomic: a reader sees the old content or the new content, never a partial file.
- [ ] Encoding and permission behavior agree with the source.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `AtomicWriterTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter AtomicWriterTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan