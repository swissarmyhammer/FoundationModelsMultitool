---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0x22hqc4590y7s5et3nsp6f
  text: |-
    Research and port notes.

    - TDD order was kept. The ported test file went in first. The RED run failed with "cannot find 'Hashline' in scope". The ported source made the suite GREEN (16 tests).
    - The fixture `hashline-golden.json` was copied byte-for-byte into the new `Tests/FoundationModelsMultitoolTests/FilesGoldens/`. The MD5 of the copy is equal to the MD5 of the source (44d177203d57837358db226164adf1cb). Only the hashline fixture was copied; `edit-match-golden.json` belongs to the EditMatch card (^gx95ztx).
    - `Package.swift` got `.copy("FilesGoldens")` beside `.copy("Goldens")`. The `Fixtures/` directory got NO resource rule, and the comment on the new rule states why.
    - The port drops `public` and keeps the type internal, to agree with `PathGuard` and `PathCorrective` in the same directory. The tests reach it through `@testable import`.
    - Two adaptations came from the validator rules: (1) `radix: 16` became the named constant `hexRadix`, because 16 is not in the allowed literal set {0, 1, -1, 100}; (2) `taggedLines(of:)` has no caller in this package until the read verb card (^d3px093) lands, so it carries a reason comment plus `// periphery:ignore` (bare marker, reason on its own line, per the dead-code-swift staging contract). All other members have callers: the tests count as callers because periphery runs with `--build-tests`.
    - Test adaptations: `Bundle.module` subdirectory changed to "FilesGoldens"; the window-boundary test derives its sizes from `Hashline.proximityWindow` instead of literal 50/51; the filler force-unwrap became `try #require`.
    - Do not edit the golden JSON. It pins the cross-tool anchor dialect against the Rust crate.
  timestamp: 2026-08-25T18:14:14.508820+00:00
- actor: claude-code
  id: 01m0x22p9n0yce1xqs496kn5p5
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Capabilities/Files/Hashline.swift (new), Tests/FoundationModelsMultitoolTests/HashlineTests.swift (new), Tests/FoundationModelsMultitoolTests/FilesGoldens/hashline-golden.json (new, verbatim copy), Package.swift (adds .copy("FilesGoldens")). `swift test --filter HashlineTests`: 16 tests passed. Full `swift test`: 659 tests in 53 suites passed, zero failures, zero warnings. `swift build`: success.
    - next: /review
  timestamp: 2026-08-25T18:14:19.189132+00:00
- actor: claude-code
  id: 01m0x255djbzawh3wxmyn00ppn
  text: |-
    ### test — green
    - evidence: swift test — 659 tests, 53 suites, all passed; 0 failed; 0 skipped. Only warning seen: the known pre-existing "missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')". No new warning found.
    - next: none. The build is clean.
  timestamp: 2026-08-25T18:15:40.210059+00:00
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: doing
position_ordinal: '80'
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
- [x] `Hashline` renders and parses the anchor dialect exactly as the source does.
- [x] The golden-vector parity tests load the fixtures through `Bundle.module` and pass.
- [x] `Package.swift` copies `FilesGoldens` as a resource, and `Fixtures` has no resource rule.
- [x] `swift build` succeeds.

## Tests
- [x] Port `HashlineTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [x] `swift test --filter HashlineTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan