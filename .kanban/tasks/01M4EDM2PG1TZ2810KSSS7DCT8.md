---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4eqbmx6awqmc3j1vth60fqq
  text: |-
    Research: the same wrong claim (a second owner of a noun is always `.duplicateNoun`) stood in more doc comments than `withGit(root:)`. The tests show the real order: `buildRegistry()` examines the verb paths before the nouns. A verb that has the name of a verb already under the noun gives `.duplicateName` (GitCapabilityTests, EnvironmentCapabilityTests, FilesCapabilityTests, CapabilityRegistrationTests.duplicateNounAndVerbThrows). Only an owner whose verbs differ gives `.duplicateNoun` (WebCapabilityTests, MCPCapabilityTests, EnvironmentCapabilityTests with WeatherTool).

    Corrected comments:
    - `withGit(root:)`: a second call fails with `.duplicateName`, which names the first verb.
    - `withEnvironment()`: states `.duplicateName` explicitly, not only "the same as for git".
    - `withWeb(...)` and `withMCP(servers:)`: `.duplicateName` when a verb name collides, else `.duplicateNoun`.
    - `MultiTool.Builder.withCapability(_:)`: removed "however the verbs fall", which was false.
    - `MultiToolBuilderError.Kind.duplicateNoun`: added that a path collision is reported first as `duplicateName`.
    - `MCPCapability.swift` file header: the same correction.
    `withShell` and `withFiles` doc comments make no claim about a second call; no change.

    Not changed: `web.md` (a design document, not a doc comment) also says `.duplicateNoun` for a different owner of `web`. This is correct for the cases it names when the verbs differ.

    Build: `swift build --build-tests` passes. One SwiftPM build-graph warning stays: "missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS". It comes from the mlx-swift dependency bundle, not from this change.
  timestamp: 2026-10-08T21:40:23.590448+00:00
- actor: claude-code
  id: 01m4eqbpw4az69yanw0n5n1dnn
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift, Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPCapability.swift. `swift build --build-tests` OK; `swift test`: 2324 tests in 205 suites passed, 0 failures.
    - next: /review
  timestamp: 2026-10-08T21:40:25.604629+00:00
- actor: claude-code
  id: 01m4eqkr6d8ycckq7tjak8qwm8
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (1137b0c). 0 findings, 0 confirmed, 0 refuted. 3 files reviewed. 4 .kanban files not reviewed because of .reviewignore.
    - next: none. The task moved to done.
  timestamp: 2026-10-08T21:44:49.101366+00:00
- actor: claude-code
  id: 01m4eqm3xp2bqrt1s2aze033fc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 source files (doc comments)
    - test: green — swift test, 2324 passed
    - commit: 1137b0c
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-08T21:45:01.110680+00:00
position_column: done
position_ordinal: ffffce80
title: Correct the withGit(root:) doc comment about a second call
---
## What
The doc comment of `MultiTool.Builder.withGit(root:)` in `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift` says that a second call "is the `.duplicateNoun` failure of `buildRegistry()`". This is not correct. `RegistrySource.buildRegistry()` runs the render loop before `validateNounOwnership`. Thus the verbs of the second capability collide path by path first, and the failure is `.duplicateName` with the name of the first verb. `GitCapabilityTests.aSecondWithGitRegistrationThrows` asserts `.duplicateName`.

Found during task ^9p3e1nh. Kanban cards copied the wrong text (the environment card asked for `.duplicateNoun`).

## Acceptance Criteria
- [x] The `withGit(root:)` doc comment states that a second call fails `buildRegistry()` with `.duplicateName`, which names the first verb.
- [x] Comments use ASD-STE100 Simplified Technical English.

## Tests
- [x] No behavior change. `swift test` stays green.