---
assignees:
- claude-code
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
position_column: todo
position_ordinal: '9080'
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
- [ ] `multitool-cli --web` parses, and `CLIArguments.web == true`.
- [ ] `--help` lists `--web` with its description.
- [ ] With `--web`, the demo registry has `web.search` and `web.fetch`; without it, the registry has no `web` entry.

## Tests
- [ ] Extend `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift`: parse of `--web`, the usage text, and `--web` with `--mcp` in any order.
- [ ] Add a test (in `CLIArgumentTests.swift` or the test that covers the demo registry) that the registry of a `--web` run has the two web entries.
- [ ] Run `swift test --filter CLIArgumentTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web