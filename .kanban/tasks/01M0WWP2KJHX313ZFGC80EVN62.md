---
assignees:
- claude-code
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8280'
title: Port Hashline and its golden fixtures into Capabilities/Files
---
## What
Port `Hashline` from the FileTool package into this package, with the golden fixtures that pin the cross-tool anchor dialect.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/Hashline.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/Hashline.swift`

Fixtures — read this with care:
- Make a new directory `Tests/FoundationModelsMultitoolTests/FilesGoldens/` and copy the hashline golden-vector JSON files there from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/Fixtures/`.
- Add `.copy("FilesGoldens")` to the test-target `resources` in `Package.swift`, beside the `.copy("Goldens")` rule, if it is not present yet.
- Never add a resource rule for the existing `Tests/FoundationModelsMultitoolTests/Fixtures/` directory. That directory holds compiled `.swift` files, and a resource rule stops their compilation and breaks the test target.
- Adjust the `Bundle.module` lookups in the ported tests to the new directory.

The golden vectors come from the Rust `swissarmyhammer-hashline` crate. They keep the dialect equal across tools. Do not edit them.

## Acceptance Criteria
- [ ] `Hashline` renders and parses the anchor dialect exactly as the source does.
- [ ] The golden-vector parity tests load the fixtures through `Bundle.module` and pass.
- [ ] `Package.swift` copies `FilesGoldens` as a resource, and `Fixtures` has no resource rule.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `HashlineTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter HashlineTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass.