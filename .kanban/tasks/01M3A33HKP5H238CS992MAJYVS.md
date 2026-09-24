---
assignees:
- claude-code
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
position_column: todo
position_ordinal: 8c80
title: 'Web: create the WebIntegrationTests package with keyless live search tests'
---
## What
Add the live test package that searches the real web, with no model. Design: `web.md` § "Testing / Level 2" (why a separate package, the assertion rule, the suite table). The next task adds the live fetch, guard, and runCode suites to this package.

- Create `WebIntegrationTests/Package.swift`, modelled on `IntegrationTests/Package.swift`: `platforms: [.macOS("27.0")]`, `.package(path: "..")`, and the SwiftSoup dependency with the same URL and requirement as the root `Package.swift`. One test target `FoundationModelsMultitoolWebIntegrationTests` that links only `FoundationModelsMultitool` (no MLX, no Router live wiring). A doc comment states that this package reads the environment on purpose, because the keyed tests test that feature, and that `IntegrationTests/` keeps its rule of no environment read.
- Create these suites under `WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/`, each `.serialized` with `.timeLimit(.minutes(1))`:
  - `BraveHTMLLiveTests`: `[.braveHTML]` only; query `swift programming language` gives at least 3 hits, each `https`, and a host that is `swift.org` or ends in `.swift.org`; `site: "developer.apple.com"` gives hosts that end in `apple.com`.
  - `DuckDuckGoHTMLLiveTests`: the same two tests with `[.duckDuckGoHTML]`.
  - `KeylessChainLiveTests`: `.keyless` gives hits from one of the two keyless providers.
- No test retries. A test asserts only the stable facts above.

## Acceptance Criteria
- [ ] `swift build --package-path WebIntegrationTests --build-tests` succeeds.
- [ ] `swift test --package-path WebIntegrationTests --no-parallel` passes on a machine with network access.
- [ ] The root `swift test` does not compile or run any of these suites.

## Tests
- [ ] The three suites above.
- [ ] Run `swift test --package-path WebIntegrationTests --no-parallel`. All pass.
- [ ] Run `swift test` at the root. All pass, and no web live suite runs.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web