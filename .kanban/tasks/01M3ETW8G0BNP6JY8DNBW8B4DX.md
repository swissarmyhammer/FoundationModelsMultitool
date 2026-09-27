---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fpff9xxrj743h7vbr1zb64
  text: |-
    Scope addition (2026-09-26), from the router session:
    - plan.md still names the removed `wait` tool and the word "turn" (`turnWillBegin`). Lines on 2026-09-26: :97, :306, :394, :402, :452, :462. plan.md "Resolved #1" (about :1079) describes the old semaphore bridge. Make these lines state the current design: mail delivery, submissions, and the generation queue for each model.
    - `RunCodeArguments` doc (`Sources/FoundationModelsMultitool/MultiTool.swift:239-250`) says that `runCode` "always backgrounds" and gives one return shape. But a run that settles inside `inlineSettleGrace` returns `pending:false` with its result. Correct the doc to match the code.
    - eventplan.md (:106-107) says that the inline grace default is two seconds. The code says 5 s (`MultiToolConfiguration.defaultInlineSettleGrace`). Correct it.
    - The statement that tool hosting comes from FoundationModelsExtras belongs to task "Take tool hosting from FoundationModelsExtras ...", not to this task.
  timestamp: 2026-09-26T20:28:32.957312+00:00
- actor: claude-code
  id: 01m3g3cyhrbf9hynjes2011986
  text: |-
    Research (2026-09-26):
    - README.md and docs/SECURITY.md already state mail delivery, the removed sandbox `wait()`, the detail caps, and the rule that the librarian model is not the session model. Other tasks did this.
    - Open items: SECURITY.md does not state the inner-call bound. The bound is `RunBinding.innerCallMount` (run to completion, timeout `MultiToolConfiguration.defaultExecutionTimeLimit`). The return-value and console caps must name `ResultRendererLimits.defaultReturnValueCharacterLimit` / `defaultConsoleCharacterLimit`.
    - eventplan.md: line 846 names `TurnBoundaryTool.turnWillBegin()` (now `SubmissionBoundaryTool.submissionWillBegin()`); line 107 says two seconds (code: 5 s); lines 124-130 and 622 say "turn boundary".
    - plan.md: the `wait` tool at :97, :306, :394, :402, :452, :462, :494, :498, :579; `makeSessionTools(librarian:)` is now `makeSessionTools(selection:embedder:sampleSession:)` with `RouterDiscoverySeams` in MultitoolCLI; `DetachConfiguration.nativeSessionMount` does not exist; "Resolved #1" semaphore bridge is now an async host function that returns a Promise, with a promise pump; :555 same-session reason is now the generation queue for each model.
    - `RunCodeArguments` doc says "always backgrounds" and "one shape"; `inlineSettleGrace` gives `pending:false` with the result.
    - No docs guard test exists in ExamplesTests. `RepositoryFile.sightings(of:inRelativeFile:)` is the helper to reuse.
  timestamp: 2026-09-27T00:14:21.752377+00:00
- actor: claude-code
  id: 01m3g3kanc9hecwsh3nf4vzyg7
  text: |-
    ### implement — changed
    - evidence: 8 files — README.md (new section "Background runs and mail delivery"), docs/SECURITY.md (inner-call bound `RunBinding.innerCallMount`, constant names for each cap, live-snippet cap), eventplan.md (2026-09-26 update note, 5 s grace, "before the next submission", `SubmissionBoundaryTool.submissionWillBegin()`), plan.md (no `wait` tool, current `makeSessionTools(selection:embedder:sampleSession:)` + `RouterDiscoverySeams`, promise-pump Resolved #1, generation-queue reason for a different librarian model), Sources/FoundationModelsMultitool/MultiTool.swift (`RunCodeArguments` doc: inline `pending:false` case), MultiTool+Background.swift and MultiToolConfiguration.swift (same "at once" claim), Tests/FoundationModelsMultitoolTests/ExamplesTests.swift (docs guard tests).
    - The task rg command returns no match.
    - Discovery: a plain substring scan for "wait tool" matches `await tools.web.search` in README. The phrases start with a space or a capital letter.
    - next: test
  timestamp: 2026-09-27T00:17:50.764887+00:00
- actor: claude-code
  id: 01m3g3mst8p09g5ezyhax3h0c9
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` 0 compiler warnings (one SwiftPM "missing creator for mutated node" line for the mlx-swift_Cmlx bundle, from the build system, not from source); `swift test` — 1817 tests in 145 suites passed, 0 failed. ExamplesTests docs guards pass (4 + 2 cases).
    - next: commit
  timestamp: 2026-09-27T00:18:39.048272+00:00
depends_on:
- 01M3ETT2G7K03B6JMTPV6EN6BA
- 01M3EVJTWPV4MEG2KFHVRF9403
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
- 01M3ETTBXPEYFR2DSBAZHMQVXB
position_column: doing
position_ordinal: '80'
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