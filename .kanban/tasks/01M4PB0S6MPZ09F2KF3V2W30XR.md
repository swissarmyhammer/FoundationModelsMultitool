---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ph292znbd77wg4rpg7y89j
  text: |-
    Research and work done.
    - `swift package update` resolved FoundationModelsExtras at main c0e46ae. `PendingRunEnvelope.pendingWorkInstruction` is in `Hosting/PendingRunEnvelope.swift`. The text is the same, word for word.
    - The IntegrationTests package has its own Package.resolved. It also had a stale Extras pin, and its build failed on the new symbol until `swift package update` ran in `IntegrationTests/` too. Run the update in BOTH packages.
    - Deleted `Invocation/PendingWorkInstruction.swift` (git rm). The five places now use `PendingRunEnvelope.pendingWorkInstruction`: MultiTool+Background.swift, Capabilities/Shell/Execute.swift (pending sentence and description), MultiTool+Description.swift, MultiTool+SandboxGlobals.swift. Doc links changed to ``PendingRunEnvelope/pendingWorkInstruction``; the doc comment in MultiTool.swift changed too.
    - MultiTool+Description.swift had no imports. It now has `import FoundationModelsExtras`.
    - Six unit-test asserts compare against `PendingRunEnvelope.pendingWorkInstruction`.
    - IntegrationTests `ShellBackgroundReportTests` held a fragment of the text ("This is not the result.") as filler. It now uses `PendingRunEnvelope.pendingWorkInstruction`, so no copy is left.
    - The text is unchanged, so the changed asserts did not fail before the change (refactor only). The deletion is checked by the compiler.
    - The "missing creator for mutated node ... mlx-swift_Cmlx.bundle" warning comes from SwiftPM for the mlx dependency bundle. It was there before this work.
  timestamp: 2026-10-11T22:24:20.575921+00:00
- actor: claude-code
  id: 01m4ph2n4qxjnpmtpm2t7zdsg9
  text: |-
    ### implement — changed
    - evidence: 11 files. Deleted Sources/FoundationModelsMultitool/Invocation/PendingWorkInstruction.swift. Changed Sources: Capabilities/Shell/Execute.swift, MultiTool+Background.swift, MultiTool+Description.swift, MultiTool+SandboxGlobals.swift, MultiTool.swift. Changed Tests: InlineSettleGraceTests, MultiToolExecutionTests, RouterSessionMountTests, SandboxGlobalsTests, ShellExecuteTests. Changed IntegrationTests: ShellBackgroundReportTests. `swift test`: 2370 tests in 209 suites passed. `swift test --package-path IntegrationTests --filter ShellBackgroundReportTests`: 2 tests passed. The full model integration suite did not run.
    - next: review
  timestamp: 2026-10-11T22:24:32.919269+00:00
- actor: claude-code
  id: 01m4phq47t7yd6dr0bqt3rjrnq
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (cbc8a35). 12 files reviewed. Findings 0, confirmed 0, refuted 0, attempted 14, failed 0. Five code-hygiene Swift rules declined only the deleted file PendingWorkInstruction.swift, because the file does not exist.
    - next: none. The task is in done.
  timestamp: 2026-10-11T22:35:43.738023+00:00
- actor: claude-code
  id: 01m4phqfv4w07t2wszadzzjhxb
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 12 files (1 deleted)
    - test: green — swift test, 2370 passed, 0 skipped; IntegrationTests build complete
    - commit: cbc8a35
    - review: clean — 0 findings, 12 files
  timestamp: 2026-10-11T22:35:55.620343+00:00
position_column: done
position_ordinal: ffffda80
title: Use PendingRunEnvelope.pendingWorkInstruction from Extras; delete PendingWorkInstruction
---
## Problem

The pending-work text is in two packages that must stay the same: the Multitool `PendingWorkInstruction.text` (task ^1dzf1za, commit dd32c9e) and the Agents copy `AgentsToolText.injectionSentences`. The user does not permit copies that must stay in sync. The user decided that FoundationModelsExtras owns the one text.

## Precondition

Start this task only after FoundationModelsExtras is on main with `public static let pendingWorkInstruction: String` on `PendingRunEnvelope`. The session foundationmodelsextras-f0 sends the commit sha. Requested by the session foundationmodelsagents-e9.

## Work

1. Update the Extras dependency (it follows main): `swift package update`.
2. Delete `Sources/FoundationModelsMultitool/Invocation/PendingWorkInstruction.swift`. Use `PendingRunEnvelope.pendingWorkInstruction` in each place that used `PendingWorkInstruction.text`:
   - the runCode pending sentence (`MultiTool+Background.swift`)
   - the tools.shell.execute pending sentence (`Capabilities/Shell/Execute.swift`, near line 200)
   - the runCode description (`MultiTool+Description.swift`)
   - the tools.shell.execute description (`Capabilities/Shell/Execute.swift`, near line 853)
   - the repair text of the removed `wait()` global (`MultiTool+SandboxGlobals.swift`)
3. In the tests, compare against `PendingRunEnvelope.pendingWorkInstruction`. Do not keep a second copy of the text.

## Acceptance

- [x] `PendingWorkInstruction.swift` is deleted, and no source refers to `PendingWorkInstruction`.
- [x] The five places use `PendingRunEnvelope.pendingWorkInstruction`.
- [x] No test or source holds a second copy of the text.
- [x] Tests pass. #refactor