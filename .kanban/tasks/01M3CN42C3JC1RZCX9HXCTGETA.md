---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3cxhnvmz2nzmnvmj716sbg5
  text: 'Research: `MultiToolBuilder.swift` has 483 lines. The capability short forms (`withShell`, `withFiles`, both `withWeb` overloads, `withMCP`) occupy approximately 188 lines. Only the internal `withWeb(configuration:sessionConfiguration:resolver:)` writes `source` directly (it replaces an earlier `WebCapability` at its position). `withMCP` uses the private `pool`, but the public `serverPool` returns the same `MCPServerPool` instance, thus an extension can use `serverPool`. Plan: add one internal method in the main file, `withCapability(_:replacing:)`, that replaces the first earlier capability that a predicate selects, or appends. `source` and `pool` stay `private`. Move the five short forms to `Surface/MultiToolBuilder+Capabilities.swift`. No `ARCHITECTURE.md` exists.'
  timestamp: 2026-09-25T18:34:21.940231+00:00
- actor: claude-code
  id: 01m3cxp29jppmweysh777vgmm7
  text: |-
    Implementation done. `withShell`, `withFiles`, both `withWeb` overloads and `withMCP` moved with no change to their signatures or doc comments into the new file `Surface/MultiToolBuilder+Capabilities.swift` (192 lines, `extension MultiTool.Builder`). `MultiToolBuilder.swift` has 325 lines now. `source` and `pool` stay `private`. The main file has one new internal method, `withCapability(_:replacing:)`. It replaces the first recorded capability that a predicate selects at its position, or it appends. The internal `withWeb(configuration:sessionConfiguration:resolver:)` calls it with `{ $0 is WebCapability }`, thus "last call wins" does not change. `withMCP` uses the public `serverPool` (the same `MCPServerPool` instance as `pool`). Evidence: `swift build --build-tests` OK; `swift test` 1786 tests in 142 suites passed, 0 failures; `swiftlint lint` on the two files: 0 violations. No test file changed. The only build warning is the SwiftPM "missing creator for mutated node" warning for the mlx-swift_Cmlx bundle. It existed before this change. Note: `web.md` (a plan document) still says the `withWeb` short form is in `Surface/MultiToolBuilder.swift`. I did not change it.

    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift, Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift (new); swift test 1786/1786 passed; swiftlint 0 violations
    - next: /review
  timestamp: 2026-09-25T18:36:45.746017+00:00
- actor: claude-code
  id: 01m3cyjk735k4ctk4arh6c892z
  text: |-
    ### test — green
    - evidence: `swift test` ran the full suite. Result: 1786 tests in 142 suites, all passed, 0 failed, 0 skipped. `swift build` gave one warning only: "missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')". This warning comes from the vendored mlx-swift dependency under `.build/checkouts`. It is outside this repository. It does not block this outcome.
    - lint: `swiftlint lint --strict` on the two changed files (`Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`, `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift`) gave 0 violations. A repo-wide `swiftlint lint --strict Sources Tests` run (the repo has no `.swiftlint.yml`, so the tool used its default rule set) found 739 pre-existing violations in 347 files, all outside the two changed files. These are not new. They are not warnings from `swift build` or `swift test`. They are out of scope for this test step.
    - next: /review
  timestamp: 2026-09-25T18:52:20.579637+00:00
- actor: claude-code
  id: 01m3cyqhbh9eaz2g05wvg63n4g
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit c6dfba8). 0 findings, 0 confirmed, 0 refuted. 2 files reviewed. 6 files in `.kanban/` were not reviewed because of `.reviewignore`. The commit has no rename. Git shows `MultiToolBuilder+Capabilities.swift` as a new file, thus the diff review read each line of it.
    - next: none. The task moved to done.
  timestamp: 2026-09-25T18:55:02.513567+00:00
- actor: claude-code
  id: 01m3cyqyx2jw2ncpzearm4mwjx
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (MultiToolBuilder.swift 325 lines, new MultiToolBuilder+Capabilities.swift 192 lines)
    - test: green — swift test, 1786 passed
    - commit: c6dfba8
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-25T18:55:16.386327+00:00
position_column: done
position_ordinal: ffe180
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