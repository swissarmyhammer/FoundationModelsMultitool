---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: Correct the withGit(root:) doc comment about a second call
---
## What
The doc comment of `MultiTool.Builder.withGit(root:)` in `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift` says that a second call "is the `.duplicateNoun` failure of `buildRegistry()`". This is not correct. `RegistrySource.buildRegistry()` runs the render loop before `validateNounOwnership`. Thus the verbs of the second capability collide path by path first, and the failure is `.duplicateName` with the name of the first verb. `GitCapabilityTests.aSecondWithGitRegistrationThrows` asserts `.duplicateName`.

Found during task ^9p3e1nh. Kanban cards copied the wrong text (the environment card asked for `.duplicateNoun`).

## Acceptance Criteria
- [ ] The `withGit(root:)` doc comment states that a second call fails `buildRegistry()` with `.duplicateName`, which names the first verb.
- [ ] Comments use ASD-STE100 Simplified Technical English.

## Tests
- [ ] No behavior change. `swift test` stays green.