---
assignees:
- claude-code
depends_on:
- 01M4E1X8XTSWVC55RYD9P3E1NH
position_column: todo
position_ordinal: '8280'
title: Add the tools.environment.os verb
---
## What
Add the `os` verb to `EnvironmentCapability`. It gives the facts of the operating system and of the host.

File to create:
- `Sources/FoundationModelsMultitool/Capabilities/Environment/OperatingSystem.swift` — `struct OperatingSystem: Tool` with `name = "os"`. `@Generable struct OperatingSystemArguments {}`. `@Generable struct OperatingSystemResult` with these fields:
  - `name: String` — the platform name, for example `macOS` (from `#if os(...)`).
  - `version: String` — `major.minor.patch` from `ProcessInfo.operatingSystemVersion`.
  - `build: String` — the text of `ProcessInfo.operatingSystemVersionString`.
  - `architecture: String` — for example `arm64` or `x86_64` (from `#if arch(...)`).
  - `hostName: String` — read with `gethostname()`. Do NOT use `ProcessInfo.hostName`: on macOS it can do a name-service lookup that blocks for some seconds.
  - `userName: String` — `NSUserName()`.
  - `homeDirectory: String` — `NSHomeDirectory()`.
  - `processorCount: Int` — `ProcessInfo.activeProcessorCount`.
  - `physicalMemoryBytes: Int` — `Int(clamping: ProcessInfo.physicalMemory)`. Use `Int`, not `UInt64`: no `@Generable` struct in the repo has an unsigned field, and `UInt64` is possibly not a `Generable` type.
  - `locale: String` — `Locale.current.identifier`.

Files to modify:
- `Sources/FoundationModelsMultitool/Capabilities/Environment/EnvironmentContext.swift` — add an `operatingSystem: @Sendable () -> OperatingSystemResult` input, so a test injects fixed values. The default closure reads the real values at each call.
- `Sources/FoundationModelsMultitool/Capabilities/Environment/EnvironmentCapability.swift` — add `OperatingSystem(context:)` to `tools`.

The verb description tells the model each field. Write comments in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [ ] `tools.environment.os({})` renders and gives each field above.
- [ ] With an injected context, the result is equal to the injected values.
- [ ] With the default context, `name` is `macOS` on macOS, `version` matches `^\d+\.\d+\.\d+$`, `hostName` is not empty, and `processorCount` and `physicalMemoryBytes` are more than 0.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentOperatingSystemTests.swift` — injected values; the default-context properties above (no fixed host values).
- [ ] Update `EnvironmentCapabilityTests.swift` for the new verb name.
- [ ] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment