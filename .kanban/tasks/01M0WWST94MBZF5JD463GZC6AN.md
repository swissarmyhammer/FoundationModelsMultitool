---
assignees:
- claude-code
depends_on:
- 01M0WWQYXE8CCDSKQRPD3PX093
- 01M0WWR5S34QZDKV15KP238ZZP
- 01M0WWS1T0ZST1W20APV5XAP97
- 01M0WWSCM9CHRT7B5AWVB4DVZP
- 01M0WWQR0QYAT02TQ1D4CMVJQH
- 01M0WWRTNNZSJ623GRW2J06ZB7
position_column: todo
position_ordinal: 8f80
title: Make FilesCapability and Builder.withFiles(root:)
---
## What
Compose the six verbs into the capability, and give the Builder its short form. Follow `Capabilities/Shell/ShellCapability.swift` and `MultiTool.Builder.withShell(...)` exactly.

- New file: `Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift`
  - `struct FilesCapability: Capability` with `noun = "files"`.
  - One `FileContext` for the session; each verb holds it. The initializer takes `root: URL`, `additionalRoots: Set<URL> = []`, `readOnly: Bool = false`, `allowSymlinks: Bool = false`, `recordsChanges: Bool = false`.
  - `tools` in render order: `Read`, `Write`, `Edit`, `Patch`, `Glob`, `Grep`.
  - The capability is off by default, per eventplan.md § "The capability contract".
- Modify: `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`
  - Add `withFiles(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)` as the short form of `withCapability(FilesCapability(...))`, in the pattern of `withShell(...)`. eventplan.md: "The Builder opts modules in explicitly: `withShell()`, `withFiles(root:)`...".

## Acceptance Criteria
- [ ] `.withFiles(root:)` renders `tools.files.read`, `.write`, `.edit`, `.patch`, `.glob`, and `.grep`, and nothing else under `tools.files`.
- [ ] A build with no `withFiles` renders no `tools.files` namespace.
- [ ] A second registration of the `files` noun fails loudly at `buildRegistry()`.
- [ ] `findAPIs` and `help()` serve each verb entry with its doc comment and its example snippet.
- [ ] `swift build` succeeds.

## Tests
- [ ] Write `Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift` in the pattern of `ShellCapabilityTests.swift`: the rendered surface, the opt-in default, the duplicate-noun rejection, and the shared-context wiring (a `tools.files.write` result is visible to a following `tools.files.read`).
- [ ] `swift test --filter FilesCapabilityTests` passes.
- [ ] The full suite `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-3 #eventplan