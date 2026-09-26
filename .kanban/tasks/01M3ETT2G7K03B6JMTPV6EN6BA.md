---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fjpsht08p4sta1nh9q0qqe
  text: |-
    Research:
    - runCode: the terminal detail is the text runCode returns. `ResultRenderer.render(_:limits:notice:)` cuts the serialized return value to `limits.returnValueCharacterLimit` and the joined console output to `limits.consoleCharacterLimit`, and adds one note line `[truncated: ...]` after each cut. The limits come from `MultiToolConfiguration.resultLimits` (defaults 4,000 and 2,000).
    - Shell: `Execute.report(of:in:)` posts the same text it returns as the terminal detail. `Execute.rendered(_:)` goes through `ResultRenderer.render` with `ResultRendererLimits.default`, so the whole shell report is cut to `ResultRendererLimits.default.returnValueCharacterLimit` (4,000). The tail is also limited to `Execute.tailLineCount` (32) lines, but each line has no length limit; the character cap is the real bound. The report keys are sorted, so `commandID` comes first and stays in the kept part after a cut.
    - Thus the shell detail already has a Multitool-owned cap. No new constant is necessary. The tests prove the cap for both paths; docs/SECURITY.md gets the names.
    - Test harness: `makeOuterRunContext()` + `context.mount(...)` + `context.wait(completionToken:seconds:)` (the Router context API, not the removed tool) gives the terminal event.
  timestamp: 2026-09-26T19:22:38.522508+00:00
- actor: claude-code
  id: 01m3fjx30hryer15vfewpcg0ns
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift (named `consoleSectionSeparator`), Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift (doc comment names the cap on the detail), Tests/FoundationModelsMultitoolTests/Fixtures/TerminalDetailFixtures.swift (new), Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift (runCode case), Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift (shell case), docs/SECURITY.md (new section "The detail of a finished background run").
    - The shell detail already had a cap: `ResultRendererLimits.default.returnValueCharacterLimit`, through `Execute.rendered(_:)`. No new constant was necessary.
    - test: `swift build --build-tests && swift test` — 1788 tests in 144 suites passed, 0 failed, 0 skipped, no compiler warning.
    - next: commit
  timestamp: 2026-09-26T19:26:04.817704+00:00
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
position_column: doing
position_ordinal: '80'
title: Prove that the detail of a finished background run that becomes mail has a bound
---
## What
Router commit f3b72f5 removed the tail cut of a run's `detail`. Upstream commit `2f4707f` made Multitool give the whole report (the `wait()` text, `docs/SECURITY.md` and the tests). After the `wait` removal tasks, the model gets a run's detail as mail. Find and prove the bound on that detail:
- [ ] `runCode`: `ResultRenderer` caps the return value and the console output (`MultiToolConfiguration.returnValueCharacterLimit`, `consoleCharacterLimit`). Show with a test that a background `runCode` snippet with an overlong return value gives a terminal detail within those caps.
- [ ] Shell (`Capabilities/Shell/Execute.swift`, background mount): find the cap on the terminal detail of a background shell run. If it has no cap, add one Multitool-owned constant and a tail cut where the detail is set, and write the reason in its doc comment.
- [ ] Make `docs/SECURITY.md` name each cap that bounds the mail detail.

## Acceptance Criteria
- [ ] For `runCode` and for shell, a background run with 10× too much output gives a terminal detail whose length is within a named Multitool constant.
- [ ] `docs/SECURITY.md` names those constants.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`: the `runCode` case.
- [ ] `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`: the shell case.
- [ ] Run `swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.