---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ckgdfrgyjsfspaqx6802rg
  text: |-
    Research done.
    - `CLIRunner.swift` has 1127 lines before this change. The 400-line limit cannot hold for it. The changes there are only the wiring that the card names: `CLIArguments.web`, `webFlag` beside `directFlag`, the `flags` entry, and a `web` parameter on `makeDemoRegistry` and `runDemo`.
    - `CLIArgumentTests.swift` has 374 lines. The new tests go in `CLIArgumentTests+Web.swift` as `extension CLIArgumentTests` (the same pattern as `WebVerbArgumentTests` and `BraveHTMLProviderTests`). Thus `swift test --filter CLIArgumentTests` runs them, and each file stays under 400 lines.
    - `flagNames` comes from `flags`. When `webFlag` is in `flags`, a `--mcp` server command stops at `--web` with no other change.
    - `withWeb()` with no arguments uses `WebConfiguration.fromEnvironment()`. It reads the environment at build time and does no network I/O, so the registry test needs no network.
  timestamp: 2026-09-25T15:38:54.840479+00:00
- actor: claude-code
  id: 01m3ckr9jc4nqwe52dmrtp81ps
  text: |-
    Implementation landed (TDD).
    - RED: first a stub (`CLIArguments.web` and a `web:` parameter that did nothing). 5 of the 6 new tests failed for the correct reason: "unknown argument --web", no `--web` line in the usage text, and no `web.*` entries in the registry. The test "no --web renders no web entry" passed on the stub. That is correct, because it guards the default.
    - GREEN: `webFlag` beside `directFlag`, `flags = [directFlag, webFlag, mcpFlag, helpFlag]`, and `builder.withWeb()` in `makeDemoRegistry(direct:web:mcpServers:)` when `web` is true. The signature change reached 2 callers: `runDemo` (it now takes `web:` from `parsed.web`) and `CLIArgumentTests.makeEchoDemo` (`web: false`). No caller in `IntegrationTests/` uses `makeDemoRegistry`.
    - `swift test --filter CLIArgumentTests`: 29 tests passed. `swift test`: 1782 tests in 141 suites passed.
    - The only build warning is "missing creator for mutated node ... mlx-swift_Cmlx.bundle". It comes from the build system for the MLX bundle. No file of this change causes it.
    - I checked `swift run multitool-cli --help` manually: `[--web]` shows in USAGE, and the `--web` block shows in OPTIONS between `--direct` and `--mcp`.
  timestamp: 2026-09-25T15:43:12.972813+00:00
- actor: claude-code
  id: 01m3ckrdnx0f1gzzwvj328tgtn
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/MultitoolCLI/CLIRunner.swift, Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift, Tests/FoundationModelsMultitoolTests/CLIArgumentTests+Web.swift (new). `swift test --filter CLIArgumentTests`: 29 passed. `swift test`: 1782 tests in 141 suites passed.
    - next: /test, then /review. The task stays in `doing`. No commit.
  timestamp: 2026-09-25T15:43:17.181157+00:00
- actor: claude-code
  id: 01m3cmeqerbqv0akfs3zr6avnh
  text: |-
    ### test — green
    - evidence: swift test — 1782 tests, 141 suites, 0 failed, 0 skipped. swift package clean && swift build --build-tests — build OK, 0 warnings in project code (4 pre-existing C++17-extension warnings in the vendored .build/checkouts/mlx-swift package are out of scope; the task bars `swift package update`).
    - next: send the task to review.
  timestamp: 2026-09-25T15:55:28.088458+00:00
- actor: claude-code
  id: 01m3cmn0b88zwqd8k1wy22bzse
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (ccc1866). 0 findings, 0 confirmed, 0 refuted. The engine reviewed 3 source files. It did not review 4 .kanban files because of .reviewignore. The commit renames no files.
    - next: The task moved to done.
  timestamp: 2026-09-25T15:58:53.800907+00:00
- actor: claude-code
  id: 01m3cmn94rhfe5mh02ywthysce
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files
    - test: green — swift test, 1782 passed
    - commit: ccc1866
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-25T15:59:02.808604+00:00
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
position_column: done
position_ordinal: ffde80
title: 'Web: add the --web flag to multitool-cli'
---
## What
Let the demo CLI mount the web capability. Design: `web.md` § "Files to add or change" (`Sources/MultitoolCLI/CLIRunner.swift + --web flag`).

- `Sources/MultitoolCLI/CLIRunner.swift`:
  - Add `var web = false` to `CLIArguments` (`:36`).
  - Add `static let webFlag = Flag(names: ["--web"], valueSyntax: nil, descriptionLines: [...], apply: ...)` beside `directFlag` (`:280`). The description says that the flag mounts `tools.web.search` and `tools.web.fetch`, and that API keys come from the environment variables of `web.md` § "The provider list".
  - Add `webFlag` to `flags` (`:332`).
  - Where the demo registry is built (`:659` onward), call `.withWeb()` when `arguments.web` is `true`.

## Acceptance Criteria
- [x] `multitool-cli --web` parses, and `CLIArguments.web == true`.
- [x] `--help` lists `--web` with its description.
- [x] With `--web`, the demo registry has `web.search` and `web.fetch`; without it, the registry has no `web` entry.

## Tests
- [x] Extend `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift`: parse of `--web`, the usage text, and `--web` with `--mcp` in any order.
- [x] Add a test (in `CLIArgumentTests.swift` or the test that covers the demo registry) that the registry of a `--web` run has the two web entries.
- [x] Run `swift test --filter CLIArgumentTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web