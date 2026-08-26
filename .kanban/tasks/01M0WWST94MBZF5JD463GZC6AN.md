---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0xp8tf41mkzy3ygrv9zszvf
  text: |-
    Research done. Discoveries:
    - The six verbs (Read, Write, Edit, Patch, Glob, Grep) exist. Each holds `let context: FileContext` and each has the initializer `(context:)`. The verb names are "read", "write", "edit", "patch", "glob", "grep".
    - `FileContext.init(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)` has the same parameter list the card gives, and it does not throw. Thus `FilesCapability.init` and `withFiles(...)` do not throw — different from `withShell(...)`, which throws for store preparation.
    - `Capability` protocol doc in Surface/Capability.swift already shows a `FilesCapability` example with `noun = "files"`.
    - Test pattern sources: ShellCapabilityTests.swift for the surface, opt-in, searchTools/help()/docs() tests; CapabilityRegistrationTests.swift for the duplicate-noun shape (`register(noun: "files", ...)` after the capability); FilesWriteTests.swift for the write-then-read proof (WriteArguments(path:content:), ReadArguments(path:offset:limit:format:), WriteResult.hash/.taggedContent, ReadResult.hash/.lines).
    - File suites use `TestSupport.makeTemporaryDirectory(named:)` for roots, not TestScratch — the OS reclaims the tree, and the URL keeps the `/var` spelling.
    Plan: write Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift first (RED), then Sources/.../Capabilities/Files/FilesCapability.swift and the `withFiles` method in Surface/MultiToolBuilder.swift (GREEN), then the full `swift test`.
  timestamp: 2026-08-26T00:07:11.588541+00:00
- actor: claude-code
  id: 01m0xpfd6me9dycs0sdyd34gcy
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift (new), Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift (withFiles added after withShell), Tests/FoundationModelsMultitoolTests/FilesCapabilityTests.swift (new, 11 tests). TDD: the suite failed first for the correct cause (FilesCapability and withFiles not in scope), then passed. `swift test --filter FilesCapabilityTests`: 11/11 passed. Full `swift test`: 989 tests in 71 suites, all passed. `swift build --build-tests`: no compiler warning in project sources (one SwiftPM build-graph warning names the third-party mlx-swift_Cmlx.bundle node; not caused by this change).
    - notes: `withFiles(...)` does not throw, different from `withShell(...)` — `FileContext` acquires no resource at construction, and the doc comment states this. Two rejection shapes are covered: `register(noun: "files", ...)` after `withFiles` throws `.duplicateNoun` "files"; a second `withFiles` throws `.duplicateName` on the first verb path collision. eventplan.md shows a modification in the work tree from outside this session (a dated 2026-08-25 plan update); this task did not touch it.
    - next: ready for /review; the task stays in doing.
  timestamp: 2026-08-26T00:10:47.380385+00:00
- actor: claude-code
  id: 01m0xpj1wja3p52v4bcd44k54c
  text: |-
    ### test — green
    - evidence: swift test — 989 tests passed, 0 failed, 0 skipped, in 71 suites. Only warning seen: the known mlx-swift notice "missing creator for mutated node" (Cmlx.bundle). No new warning found.
    - next: none. The build is clean.
  timestamp: 2026-08-26T00:12:14.098250+00:00
depends_on:
- 01M0WWQYXE8CCDSKQRPD3PX093
- 01M0WWR5S34QZDKV15KP238ZZP
- 01M0WWS1T0ZST1W20APV5XAP97
- 01M0WWSCM9CHRT7B5AWVB4DVZP
- 01M0WWQR0QYAT02TQ1D4CMVJQH
- 01M0WWRTNNZSJ623GRW2J06ZB7
position_column: doing
position_ordinal: '80'
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