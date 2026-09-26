---
assignees:
- claude-code
depends_on:
- 01M3EVK4VR545ABV6R9YHFQH76
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
position_column: todo
position_ordinal: '8180'
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