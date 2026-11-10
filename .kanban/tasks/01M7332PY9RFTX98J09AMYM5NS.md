---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7333nx211taw3mqw5fnezmb
  text: 'foundationmodelsacpagent-ec (2026-11-10): ^xfeamnv gives `mode:` in every MultiTool.Builder call in ACPAgent, in Sources and in Tests. Today there are 5 calls: Sources ToolCatalog.swift:464; Tests SettingsToolTests.swift:294, ShellSessionOwnerTests.swift:57, PromptContentTests.swift:42, MCPCompositionTests.swift:270. Before you push, check all of them on ACPAgent origin/main: `git -C ../FoundationModelsACPAgent grep -n "MultiTool.Builder(" origin/main -- Sources Tests`. Each call must give `mode:`. That session sends the ^xfeamnv commit when it is pushed.'
  timestamp: 2026-11-10T16:01:57.666839+00:00
depends_on:
- 01M73030WWZF8M6HM1S3XS0D60
position_column: todo
position_ordinal: '8580'
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
- [ ] `MultiTool.Builder()` with no `mode` does not compile.
- [ ] Each caller in this repo gives `mode:`.
- [ ] `swift build` of the package and of `IntegrationTests` gives no warnings.

## Tests
- [ ] The existing tests in `Tests/FoundationModelsMultitoolTests/ToolModeBuilderTests.swift` pass with the explicit mode.
- [ ] Run `swift test` one time; all tests pass.
- [ ] Build the IntegrationTests package (`swift build` in `IntegrationTests`).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #blocked-external