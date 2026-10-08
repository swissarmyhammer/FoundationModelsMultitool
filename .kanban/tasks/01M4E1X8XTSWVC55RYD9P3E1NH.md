---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ed97zgj08qybwzrhp1wvbw
  text: |-
    Research done.
    - Pattern: GitCapability + Branches (in-band `correction`, never throw). Verb tests call the verb directly (GitBranchesTests).
    - Duplicate registration: `buildRegistry()` runs the render loop BEFORE the noun-ownership check. Thus a second `withGit(root:)` fails with `.duplicateName` (name = first verb), not `.duplicateNoun`. GitCapabilityTests asserts `.duplicateName` for that case, and `.duplicateNoun` for `register(noun: "git", ...)`. The `withGit` doc comment says `.duplicateNoun`, which is not the real result.
    - User decision (2026-10-08): "make it work like other tools". Thus `withEnvironment()` uses plain `withCapability(_:)`, the same as `withGit`. The tests assert what `withGit` gives: `.duplicateName` for a second `withEnvironment()`, and `.duplicateNoun` for another tool under the noun.
    - `now` and `timeZone` of EnvironmentContext have no production reader in this task. Task ^c73rk0s (the `now` verb) reads them. They get a `// periphery:ignore` marker with that reason.
  timestamp: 2026-10-08T18:44:19.056649+00:00
- actor: claude-code
  id: 01m4edmfffvh28d0zjqfempckz
  text: |-
    ### implement — changed
    - evidence: 3 new sources (Capabilities/Environment/EnvironmentContext.swift, EnvironmentCapability.swift, Variables.swift), 1 modified (Surface/MultiToolBuilder+Capabilities.swift: `withEnvironment()` and internal `withEnvironment(context:)`), 2 new test files (EnvironmentCapabilityTests.swift, 10 tests; EnvironmentVariablesTests.swift, 11 tests). RED: test build failed on the missing types. GREEN: the 21 new tests pass. Full `swift test --scratch-path <clean-build> --skip-build`: 2306 tests in 201 suites pass, exit 0. BuilderSurfaceTests stays green, no golden change.
    - decision: a second `withEnvironment()` fails `buildRegistry()` with `.duplicateName` (name `variables`), the same as a second `withGit(root:)`. The user said "make it work like other tools". `.duplicateNoun` is asserted for another tool registered under the `environment` noun.
    - extra coverage: names and prefixes match with the same case (environment names are case-sensitive on macOS); a prefix with no match gives an empty list and no correction; the default context reads the process, the clock, and the current time zone.
    - new work: task ^ss7dct8 corrects the `withGit(root:)` doc comment, which says `.duplicateNoun` for a second call.
    - next: /review
  timestamp: 2026-10-08T18:50:27.183378+00:00
position_column: doing
position_ordinal: '80'
title: Add the environment capability and the tools.environment.variables verb
---
## What
Add a new read-only capability with `noun = "environment"`. Use the same pattern as `GitCapability` (`Sources/FoundationModelsMultitool/Capabilities/Git/GitCapability.swift`) and its verbs (for example `Branches.swift`). This task adds the capability, the builder short form, and the first verb, `variables`.

Decisions from the user (2026-10-08):
- The `variables` verb gives ALL names and values. There is NO redaction filter.
- The capability is OFF by default, the same as `git` and `web`.

Files to create:
- `Sources/FoundationModelsMultitool/Capabilities/Environment/EnvironmentContext.swift` — a `struct EnvironmentContext: Sendable` that holds the inputs that the verbs read: `variables: @Sendable () -> [String: String]`, `now: @Sendable () -> Date`, `timeZone: TimeZone`. Each input is a closure that the verb calls at each call (a live read, not a copy taken at `init`), the same as `WebConfiguration` reads its environment "at the time of each call". A test injects each input. The defaults are `{ ProcessInfo.processInfo.environment }`, `{ Date() }`, and `TimeZone.current`.
- `Sources/FoundationModelsMultitool/Capabilities/Environment/EnvironmentCapability.swift` — `public struct EnvironmentCapability: Capability` with `noun = "environment"`, `tools: [any Tool]`, `context: EnvironmentContext`. A public `init()` uses the default context. An internal `init(context:)` is for tests.
- `Sources/FoundationModelsMultitool/Capabilities/Environment/Variables.swift` — `struct Variables: Tool` with `name = "variables"`. `@Generable struct VariablesArguments { var name: String?; var prefix: String? }`. `@Generable struct VariablesResult { var variables: [EnvironmentVariable]; var correction: String? }` where `@Generable struct EnvironmentVariable` has `name` and `value` (both `String`).
  - No argument: give all variables, in name order.
  - `name`: give only that variable. When it is not set, give no variable and a `correction` that says the variable is not set.
  - `prefix`: give each variable whose name starts with the prefix, in name order.
  - `name` and `prefix` together: give a `correction` and no variable.
  - The verb never throws for these cases (the corrections stay in band, as in `Branches.swift`).

File to modify:
- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder+Capabilities.swift` — add `@discardableResult public func withEnvironment() -> Self` that calls `withCapability(EnvironmentCapability())`, and an internal `withEnvironment(context:)` for tests. A second call is `.duplicateNoun` at `buildRegistry()`, the same as `withGit(root:)`.

Write each comment and doc comment in ASD-STE100 Simplified Technical English, as the other capability files do.

## Acceptance Criteria
- [ ] `MultiTool.Builder().withEnvironment().build()` renders `tools.environment.variables`.
- [ ] A builder that does not call `withEnvironment()` renders no `tools.environment` namespace.
- [ ] `tools.environment.variables({})` gives all injected variables in name order, with the values not changed.
- [ ] A change to the injected variables between two calls shows in the second result (live read).
- [ ] `name` and `prefix` filter as stated above; an unset name and the two arguments together each give a `correction`, not a thrown error.
- [ ] A second `withEnvironment()` fails `buildRegistry()` with `.duplicateNoun`.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentCapabilityTests.swift` — the noun, the verb names, off by default, duplicate noun (model it on `GitCapabilityTests.swift`).
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentVariablesTests.swift` — all, `name`, `prefix`, unset name, both arguments, live read; use an injected `EnvironmentContext`, never the real process environment.
- [ ] No golden change: `BuilderSurfaceFixtures.swift` mounts no built-in capability. `BuilderSurfaceTests` stays green.
- [ ] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment