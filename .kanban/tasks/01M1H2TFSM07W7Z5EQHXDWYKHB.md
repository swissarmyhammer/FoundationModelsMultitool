---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1hctbbm6sr6ermzggqvxr45
  text: |-
    ### implement — research
    - `ShellRunner` is a struct. `defaultWorkingDirectory: String?` is a `var` after `sandbox` (ShellRunner.swift:175). `effectiveWorkingDirectory(for:defaultWorkingDirectory:)` is the one reader.
    - `ShellCapabilityTests` already has a private `verb(_:in:)` helper of the same shape as `FilesCapabilityTests.verb(_:in:)`. The new tests reuse it. No new helper.
    - `MultiTool.Registry.tools` is `[String: any Tool]`, keyed by the rendered path. The test reads `registry.tools["shell.execute"]` through a constant built from the noun and the verb.
    - The signature `withShell(storeDirectory:sandbox:outputChunkStream:)` was spelled in four places: ShellCapability.swift:46, MultiToolBuilder.swift:13 and :232, and the header comment of IntegrationTests/.../Support/ShellRunContextProbe.swift:24. All four now spell the four-argument form. UPSTREAM_ASKS.md spells the old form as the cause at revision e8c91a6, so it stays.
  timestamp: 2026-09-02T15:46:48.820330+00:00
- actor: claude-code
  id: 01m1hctgazavaypftb0nrsznec
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Capabilities/Shell/ShellCapability.swift (fourth parameter `defaultWorkingDirectory: URL? = nil`, `var runner` then `runner.defaultWorkingDirectory = defaultWorkingDirectory?.path`, doc text says four arguments), Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift (same parameter on `withShell`, passed through; header comment and `- Throws` spell the four-argument form), Tests/FoundationModelsMultitoolTests/ShellCapabilityTests.swift (three new tests: `theDefaultWorkingDirectoryReachesTheRunner`, `theDefaultWorkingDirectoryIsNilWhenNotGiven`, `withShellPassesTheDefaultWorkingDirectoryThrough`; one `executeVerb` constant and one `executePath` constant), IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ShellRunContextProbe.swift (header comment spells the new signature).
    - tests: `swift test --filter "ShellCapabilityTests|ShellExecuteTests|ShellRunnerTests"` — 66 tests in 3 suites passed. The one build warning is the pre-existing SwiftPM note for `mlx-swift_Cmlx.bundle`.
    - next: `/test` over the whole suite, then `/commit`, then `/review`.
  timestamp: 2026-09-02T15:46:53.919722+00:00
- actor: claude-code
  id: 01m1hd2n6fhv9a1q14hcswfven
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (a2ce987) — 0 findings, 0 confirmed, 0 refuted, 7 validator runs attempted, 0 failed. 4 files reviewed; the 2 `.kanban/` files are excluded by `.reviewignore`. No prior `## Review Findings` section on the card.
    - next: the task is done. The orchestrator writes the ledger and commits the kanban state.
  timestamp: 2026-09-02T15:51:21.039304+00:00
- actor: claude-code
  id: 01m1hd35z2bwd5gh3v693ss6mc
  text: |-
    ### finish iteration 1 — review clean, task done
    - implement: changed — 4 files: ShellCapability.swift, MultiToolBuilder.swift, ShellCapabilityTests.swift (3 new tests), ShellRunContextProbe.swift (comment)
    - test: green — `swift test` — 1396 tests in 108 suites passed, 0 failed, 0 skipped; the one warning is the pre-existing SwiftPM note for `mlx-swift_Cmlx.bundle`
    - commit: a2ce987
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings
  timestamp: 2026-09-02T15:51:38.210270+00:00
depends_on:
- 01M1H2RZYD71QYG972YGKQ122C
position_column: done
position_ordinal: ffaf80
title: Add defaultWorkingDirectory to ShellCapability.init and withShell
---
## What
Ask 6, part 2 (UPSTREAM_ASKS.md). Expose the runner default on the public composition, so a host gives the session root one time.

- `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellCapability.swift`: add a fourth parameter `defaultWorkingDirectory: URL? = nil` to `public init(storeDirectory:sandbox:outputChunkStream:)`. `ShellRunner` is a struct, so build it as `var runner = ShellRunner(state:outputChunkStream:sandbox:)` and then set `runner.defaultWorkingDirectory = defaultWorkingDirectory?.path`. Document: the directory a `tools.shell.execute` call runs in when it omits `workingDirectory`; the default, `nil`, keeps the current directory of this process; a host with a session root passes that root. Update the doc comment that says "the same three arguments" to four.
- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`: add the same parameter to `withShell(storeDirectory:sandbox:outputChunkStream:)` and pass it through. Update the parameter list in its doc comment, and the `MultiToolBuilderError` header comment (line 13) that spells the `withShell` signature.

The model-facing text and the sandbox scenario are the next task ("Correct the shell working-directory text and prove the Ask 6 scenario").

## Acceptance Criteria
- [x] `ShellCapability(storeDirectory:defaultWorkingDirectory:)` gives an `Execute` verb whose `runner.defaultWorkingDirectory` is the `path` of the URL.
- [x] `ShellCapability(storeDirectory:)` gives an `Execute` verb whose `runner.defaultWorkingDirectory` is `nil`.
- [x] `MultiTool.Builder().withShell(storeDirectory:defaultWorkingDirectory:).buildRegistry()` renders the same three verbs, and `registry.tools["shell.execute"] as? Execute` carries the default.
- [x] Every existing shell test stays green.

## Tests
- [x] Add to `Tests/FoundationModelsMultitoolTests/ShellCapabilityTests.swift`: `theDefaultWorkingDirectoryReachesTheRunner`, `theDefaultWorkingDirectoryIsNilWhenNotGiven`, `withShellPassesTheDefaultWorkingDirectoryThrough`. Find the verb by type as `FilesCapabilityTests.verb(_:in:)` does.
- [x] Run `swift test --filter "ShellCapabilityTests|ShellExecuteTests|ShellRunnerTests"` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #ask-6 #upstream-asks