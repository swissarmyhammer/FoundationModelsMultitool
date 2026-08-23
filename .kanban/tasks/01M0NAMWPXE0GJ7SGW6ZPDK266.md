---
assignees:
- claude-code
depends_on:
- 01M0NAKY7B8H1Z0J2VCBWV86SY
- 01M0NAMBSX4GXQ1ETQXZ6ZWRN5
position_column: todo
position_ordinal: 8d80
title: Add ShellCapability and Builder.withShell()
---
## What

eventplan.md § "The capability contract": the modules are opt-in, and they are
off by default. eventplan.md § "Registration of capabilities: noun/verb":
*"`withShell()` is a short form of `withCapability(ShellCapability(...))`."*

- Create
  `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellCapability.swift`.
  - `public struct ShellCapability: Capability`.
  - `noun` is `"shell"`.
  - `tools` is exactly `[Execute(...), GetLines(...), GrepHistory(...)]`.
  - The initializer takes the store directory, the policy, the sandbox, and the
    output chunk stream. Each has a default.
- Add `public func withShell(...) -> Self` to
  `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`. It calls
  `withCapability(ShellCapability(...))`.
- Shell is off by default. A `MultiTool` that is built with no `withShell()`
  has no `tools.shell` namespace at all.
- Do not add `listProcesses` and do not add `killProcess`. eventplan.md §
  "Consolidation of the siblings" removes them. `status()` and
  `cancel(completionToken)` replace them.
- Add one sentence to `MultiTool.description` only if the shell capability
  needs it. The globals sentence is already there.

## Acceptance Criteria

- [ ] `ShellCapability.noun` is `"shell"`, and `tools` holds exactly three
      tools.
- [ ] `Builder().withShell().buildRegistry()` renders exactly
      `shell.execute`, `shell.getLines`, and `shell.grepHistory`.
- [ ] A builder with no `withShell()` renders no entry whose path starts with
      `shell.`.
- [ ] The surface has no `listProcesses` entry and no `killProcess` entry.
- [ ] `findAPIs` finds the three shell entries, each with its sample snippet.
- [ ] `help()` and `docs()` render the three entries.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellCapabilityTests.swift`.
- [ ] A test asserts the three rendered paths, and asserts the set has exactly
      three members.
- [ ] A test asserts a builder with no `withShell()` renders no `shell.` entry.
- [ ] A test asserts `findAPIs` returns each shell entry with a runnable sample
      snippet.
- [ ] A test asserts the journal `op` of an execute run is `"execute shell"`.
- [ ] `swift test --filter ShellCapability` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan