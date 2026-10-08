---
assignees:
- claude-code
depends_on:
- 01M4E1XR9RGN1BNPYHWDKT9H63
- 01M4E2HPENAVR0VT8MWC73RK0S
position_column: todo
position_ordinal: '8680'
title: Prove the environment verbs work from a runCode snippet and from tool search
---
## What
Add the two tests that the git capability has and the environment capability does not have yet. Write no production code unless a test shows a defect.

Files to create:
- `Tests/FoundationModelsMultitoolTests/EnvironmentGoalSnippetTests.swift` — model it on `GitGoalSnippetTests.swift`. Mount `withEnvironment(context:)` with an injected `EnvironmentContext` (fixed variables, fixed clock, fixed time zone, fixed `os` values). Run one JavaScript snippet through `MultiTool(registry:).call(arguments: RunCodeArguments(...))` that calls all three verbs, for example:
  ```js
  const vars = await tools.environment.variables({ prefix: "APP_" });
  const os = await tools.environment.os({});
  const now = await tools.environment.now({ timeZone: "UTC" });
  return { names: vars.variables.map(v => v.name), correction: vars.correction, os: os.name, date: now.date, weekday: now.weekday };
  ```
- `Tests/FoundationModelsMultitoolTests/EnvironmentSearchTests.swift` — model it on `GitSearchTests.swift`. Each query puts the expected verb first:
  - "environment variable" → `environment.variables`
  - "operating system" → `environment.os`
  - "current date" → `environment.now`
  - "what time is it" → `environment.now`
  When a query does not rank first, improve the verb `description` text (in `Variables.swift`, `OperatingSystem.swift`, or `Now.swift`); do not change the test.

Write comments in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [ ] The snippet output in JavaScript holds the nested `[EnvironmentVariable]` as an array of objects, `null` for the `nil` `correction`, and the injected `os` and `now` values.
- [ ] Each of the four search queries ranks the expected `environment.*` verb first.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentGoalSnippetTests.swift` — the snippet above, with exact expected output.
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentSearchTests.swift` — the four queries.
- [ ] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment