---
assignees:
- claude-code
position_column: todo
position_ordinal: '9480'
title: 'IntegrationTests: send the remaining direct print calls through reportTraceLine'
---
## What
The `no_direct_standard_out_logs` rule (validator `code-hygiene/disallowed-constructs-swift`) does not let a file write to standard out with `print(…)`. Task ^zf65c6p removed each direct `print` from `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift`. It added `reportTraceLine(_:)` in `Support/CatalogFeedback.swift`. That function holds the one silenced `print` of the gated suites, and `reportGatedResult(scenario:line:)` calls it.

Other files in `IntegrationTests/Tests/` still call `print` directly. Find them with `rg -n '\bprint\(' IntegrationTests/Tests`. On 2026-09-24 these files had direct calls:
- `Support/ShellBackgroundRunner.swift`
- `Support/LiveRouterFixture.swift`
- `Support/BareSessionScenario.swift`
- `SelectionForkPerCallTests.swift`

Send each of these lines through `reportTraceLine(_:)`, or through `reportGatedResult(scenario:line:)` for a `RESULT [name] …` line. Keep the text of each line the same.

## Acceptance Criteria
- [ ] No file in `IntegrationTests/Tests/` calls `print` directly, except the one silenced line in `reportTraceLine(_:)`.
- [ ] Each trace line has the same text as before.
- [ ] `swift build --build-tests` in `IntegrationTests/` completes with no error.

## Tests
- [ ] Run `swift build --build-tests` in `IntegrationTests/`. It compiles.
- [ ] Run `swift test` in the root. All pass. #web