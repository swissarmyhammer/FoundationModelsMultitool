---
assignees:
- claude-code
depends_on:
- 01M0WWQE8N2DCTRDVPSM37GSXQ
- 01M0WWNWDG0SPX34065AZ7JW8H
- 01M0WWP84DQAHJXYF04DRTZX60
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WWQAT9YQ2XN087287TZKDP
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: 8b80
title: Port PatchEngine into Capabilities/Files
---
## What
Port `PatchEngine` from the FileTool package into this package. The engine applies a parsed patch to the tree, with write atomicity through `AtomicWriter` and bounds through `PathGuard`.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/PatchEngine.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/PatchEngine.swift`

Keep the corrective posture: a hunk that cannot apply comes back in-band. It is never thrown.

## Acceptance Criteria
- [ ] The engine applies and rejects the same patches as the source.
- [ ] A hunk that cannot apply gives a corrective result in-band. It does not throw.
- [ ] Writes are atomic, and each path is bounded through `PathGuard`.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `PatchEngineTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter PatchEngineTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan