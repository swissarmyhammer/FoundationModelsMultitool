---
assignees:
- claude-code
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8480'
title: Port EditMatch into Capabilities/Files
---
## What
Port `EditMatch` from the FileTool package into this package. This is the pure matching layer under `EditEngine`. It has no file IO and no context dependency, so it ports alone.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/EditMatch.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift`

Fixture: `EditMatchTests` loads `edit-match-golden.json` through `Bundle.module` (source lines 63-68). Copy `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/Fixtures/edit-match-golden.json` into `Tests/FoundationModelsMultitoolTests/FilesGoldens/`, and add `.copy("FilesGoldens")` to the test-target `resources` in `Package.swift` if it is not present yet. Never add a resource rule for the existing `Fixtures/` directory — it holds compiled `.swift` files.

## Acceptance Criteria
- [ ] Match selection, ambiguity detection, and near-miss reporting agree with the source.
- [ ] The golden fixture loads through `Bundle.module` from `FilesGoldens`.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `EditMatchTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter EditMatchTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan