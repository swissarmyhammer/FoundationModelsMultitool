---
assignees:
- claude-code
depends_on:
- 01M3ETT2G7K03B6JMTPV6EN6BA
- 01M3EVJTWPV4MEG2KFHVRF9403
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
- 01M3ETTBXPEYFR2DSBAZHMQVXB
position_column: todo
position_ordinal: '8580'
title: Make docs/SECURITY.md, README.md and eventplan.md true for the work-queue Router, mail delivery and the new bounds
---
## What
After the other tasks, the prose must state what the code does, not only use the new names:
- [ ] `docs/SECURITY.md:46` names `terminalDetailTailLimit` and says that `wait()` returns a bounded tail. Change it to the detail bound from the detail-bound task, and state that results come back as mail (no `wait`). `SECURITY.md:76`: change the timeout claim to `MultiToolConfiguration.defaultExecutionTimeLimit` and the inner-call bound.
- [ ] `eventplan.md`: "at the next turn boundary" becomes "before the next submission" (`SubmissionBoundaryTool.submissionWillBegin()`).
- [ ] README.md: remove the `wait` tool and the sandbox `wait()` global. Describe mail delivery. State the rule that the librarian (flash) model must be different from the session model.
- [ ] Run `rg -w 'turnWillBegin|TurnBoundaryTool|turnStarted|turnEnded|synchronousUnbounded|deadlineSecondsCeiling|terminalDetailTailLimit|defaultTimeoutSeconds|WaitTool' README.md docs eventplan.md plan.md` and fix each match.

## Acceptance Criteria
- [ ] The `rg` command above returns no match.
- [ ] Each bound that `docs/SECURITY.md` states names the constant that holds it in `Sources/`.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ExamplesTests.swift` (or the existing docs test): assert that README.md and docs/SECURITY.md do not contain the removed names above, and do not describe a `wait` tool.
- [ ] Run `swift test --filter ExamplesTests`. Expected result: it passes.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.