---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7333nx211taw3mqw5fnezmb
  text: 'foundationmodelsacpagent-ec (2026-11-10): ^xfeamnv gives `mode:` in every MultiTool.Builder call in ACPAgent, in Sources and in Tests. Today there are 5 calls: Sources ToolCatalog.swift:464; Tests SettingsToolTests.swift:294, ShellSessionOwnerTests.swift:57, PromptContentTests.swift:42, MCPCompositionTests.swift:270. Before you push, check all of them on ACPAgent origin/main: `git -C ../FoundationModelsACPAgent grep -n "MultiTool.Builder(" origin/main -- Sources Tests`. Each call must give `mode:`. That session sends the ^xfeamnv commit when it is pushed.'
  timestamp: 2026-11-10T16:01:57.666839+00:00
- actor: claude-code
  id: 01m738k2rpppg96p46pj04dk0r
  text: |-
    Picked up. The wait is complete: `git -C ../FoundationModelsACPAgent grep -n "MultiTool.Builder(" origin/main -- Sources Tests` gives `mode:` in all 5 calls (ToolCatalog.swift:475 gives `mode: context.toolMode`; four tests give `mode: .open`).

    Discoveries:
    - The internal `init(mode:sandboxProbe:spawnObserver:)` had no defaults. Only the public init had `mode: ToolMode = .open`.
    - All callers in this repo used the form `MultiTool.Builder()`. No caller used `Builder(sandboxProbe:)` alone or `.init()`. The two multi-line calls in SandboxedRegistryNoProcessTests already gave `mode:`.
    - Doc examples in 11 Sources files, README.md and docs/GUIDE.md also used `MultiTool.Builder()`.
    - The `review` rules apply no line-length limit (the swift-format idioms gate drops the `LineLength` tag). The repo had 462 Swift lines over 120 columns before this change, so I did not wrap the lines that became longer.
    - Both builds write `warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS`. That is a SwiftPM build-system note about the mlx dependency bundle, not a compiler warning, and it is not from this change.

    TDD: RED was the build. After I removed the default, `swift build --build-tests` failed with `missing argument for parameter 'mode' in call` (first at Tests/Support/MCPTestServer/LargeCatalogSurface.swift). A runtime test cannot assert that code does not compile, so the compiler is the test. GREEN: each caller gives `mode: .open`.
  timestamp: 2026-11-10T17:37:45.238286+00:00
- actor: claude-code
  id: 01m738k98njjx8h6z57hgpsg54
  text: |-
    ### implement — changed
    - evidence: 123 files. Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift (removed `= .open` from `mode` in `init(mode:sandboxProbe:)`, kept `sandboxProbe = .live`, changed the `mode` doc text); doc examples in 10 other Sources files; 101 files under Tests/ (Tests/FoundationModelsMultitoolTests, its Fixtures, Tests/Support/MCPTestServer); 8 files under IntegrationTests/Tests; README.md; docs/GUIDE.md and docs/SECURITY.md (the text now says that `mode` has no default value, and the "a later change removes that default" text is gone). `StdioServerProcess.init` keeps `mode: ToolMode = .open` (not in scope). `swift build --build-tests`: Build complete, 0 compiler warnings. IntegrationTests `swift build --build-tests`: Build complete, 0 compiler warnings. `swift test` one time: 2868 tests in 253 suites passed, 0 failures. Not committed.
    - next: /review
  timestamp: 2026-11-10T17:37:51.893030+00:00
depends_on:
- 01M73030WWZF8M6HM1S3XS0D60
position_column: doing
position_ordinal: '80'
title: 'MT-15: Remove the default of the builder mode, so each host names its mode'
---
## Wait first (order rule across repos)
Do not start this task until ACPAgent card ^xfeamnv (ACPA-19b) is on FoundationModelsACPAgent origin/main and ACPAgent gives the mode explicitly: `MultiTool.Builder(mode: ...)` in `Tools/ToolCatalog.swift` (`makeRegistry`). Check `git -C ../FoundationModelsACPAgent grep -n "MultiTool.Builder(" origin/main -- Sources` yourself. Each call must give `mode:`. ACPAgent CI builds against Multitool main, so if this commit is pushed first, the ACPAgent build breaks. When the ACPAgent commit is on origin/main, remove the `blocked-external` tag.

## What
Commit d5090dea gave `MultiTool.Builder.init(mode: ToolMode = .open, sandboxProbe: SandboxProbe = .live)` a default for `mode`, so that ACPAgent did not break. ARCHITECTURE.md ("No backward compatibility") and the agreement with testudoapp-75 (2026-11-10): each host must name its mode.

- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`: remove the `= .open` default of `mode`. Keep the `.live` default of `sandboxProbe`.
- Change each caller in `Tests/` and in `IntegrationTests/` to give `mode:` (usually `.open`).
- Change the doc comments that say "defaults to open".

## Acceptance Criteria
- [x] `MultiTool.Builder()` with no `mode` does not compile.
- [x] Each caller in this repo gives `mode:`.
- [x] `swift build` of the package and of `IntegrationTests` gives no warnings.

## Tests
- [x] The existing tests in `Tests/FoundationModelsMultitoolTests/ToolModeBuilderTests.swift` pass with the explicit mode.
- [x] Run `swift test` one time; all tests pass.
- [x] Build the IntegrationTests package (`swift build` in `IntegrationTests`).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1