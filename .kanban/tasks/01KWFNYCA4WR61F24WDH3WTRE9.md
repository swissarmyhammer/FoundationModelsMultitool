---
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
- 01KWFNWJECBNSZCANVMNTR3Z8J
- 01KWFNWYGEJHW6X7VV7T92T9K1
- 01KWFNXEWE0EYWYQVS6M70R7K9
position_column: todo
position_ordinal: 8d80
title: 'M9: Sample CLI executable'
---
## What
Per plan.md M9: a runnable demonstration of the whole pipeline.
- Add executable target `multitool-cli` to `Package.swift`; `Sources/multitool-cli/main.swift` with the run flow factored into a testable `CLIRunner` entry function.
- Flow: author a small `ProfileDefinition` → `Router().resolve(_:reporting:)` with console progress → build a registry of 2–3 demo tools (e.g. `tripCities`, `weather` fixtures) → `MultiToolAgent` → one prompt that triggers findAPIs then a composing runCode → print the answer plus a readable trace of the loop turns.
- `--direct` flag exercises directMode; `--help` documents usage; degrade gracefully (clear message + nonzero exit) when the Router live path is unavailable.
- The live demo is verified by an automated gated smoke test in the integration target (no human eyeballing): it invokes the `CLIRunner` entry function under the env var and asserts the emitted trace lines (findAPIs before runCode, final answer non-empty).

## Acceptance Criteria
- [ ] `swift build` builds the executable in normal CI
- [ ] `swift run multitool-cli --help` exits 0 with usage text (no model required)
- [ ] Argument parsing (flags, error on unknown flag) is unit-tested without a model
- [ ] Router-unavailable path exits nonzero with the documented message — unit-tested via an injected failing resolver
- [ ] *(gated — verifiable when Router live inference lands)* `CLISmokeTests` asserts the demo produces a findAPIs→runCode trace and a non-empty answer; closing this task requires the ungated criteria only

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` — parse `--direct`, `--help`, unknown-flag error, failing-resolver path
- [ ] `Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift` — gated: run `CLIRunner` end to end, assert trace lines
- [ ] CI step: `swift run multitool-cli --help` → exit 0
- [ ] `swift test --filter CLIArgumentTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.