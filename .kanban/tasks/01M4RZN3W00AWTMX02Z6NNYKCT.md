---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4s4m7hcrxf19s4ps6hpsfyv
  text: |-
    Research (implement step).

    Where the pending object comes from: `RunBinding.invoke` mounts each inner call with `ToolContext.mount(tool, op:, as: RunBinding.innerCallMount)`. The mount is `.runToCompletion`, but `ToolMounting.makeWrapped` and `ToolMounting.call` (FoundationModelsExtras) let a declared `BackgroundTool.mount` win. `Execute` declares `.background`, so an inner `tools.shell.execute` became a `BackgroundToolRunner` run. Its settle wait is the configured grace, cut to (outer settle deadline - 1 s) by `BackgroundToolRunner.innerCallSettleReserve`. After that wait the snippet got `{pending: true, commandID, ...}` from `Execute.snippetValue`.

    Constraint found: `JSCInterpreter` keeps settle-before-return (eventplan.md "Async JavaScript"). A run does not end while a bridge promise is pending, also for a call that the snippet did not await. So when inner calls run to completion, an unawaited call cannot outlive the run. Thus the old ^qg52whq text "They continue in the background" cannot be true for a call of this mount any more.

    FoundationModelsExtras gives no public way to free an inner background wait at the end of a snippet, or to withdraw the staged mail of an inner run (ToolContext.runPlane, sink and inlineSettleDeadline are internal). A hybrid (background until the snippet ends) thus needs an Extras change. I asked the user; the user told me to make the correct decision.

    Decision: (1) each inner call runs to completion (a wrapper hides the declared background mode of the tool, and keeps a per-call timeout); (2) the settle period and envelope stay on the outer runCode only; (3) remove the pending-object path (Execute.snippetValue pending branch, the pending skip of ToolReturnLedger, the pending detection of PendingInnerCalls); (4) PendingInnerCalls now names each inner call that was still running when the snippet code ended (not awaited). A per-run end mark, set by a wrapper around the snippet code, gives that moment. The text says that the result waited for those calls and that the model must not run them again. The values of those calls do not go into ToolReturnLedger, so its "call runCode again" notice does not push a second run.
  timestamp: 2026-10-12T22:44:40.620049+00:00
- actor: claude-code
  id: 01m4s8v9ntfkxg358sd5vf4dbb
  text: |-
    Implementation landed (not committed).

    What changed:
    - `RunBinding.invoke` mounts each inner call through the new `RunToCompletionInnerTool`. It keeps the declared mount and the per-call timeout of the tool, and sets the mode to `.runToCompletion`. Thus an `await` of an inner call always gives the real result.
    - New `SnippetEndMark`. `MultiTool.wrappingSnippet(_:after:)` puts the snippet code in an async function; its `.finally` calls the host function `__snippetEnded` (the preamble line keeps it in a local constant and deletes the global, so the global surface does not change). Line numbers of the snippet code do not change.
    - `InnerCallRecords.account(for:of:)` reads the mark one time: a call that ended before the snippet code ended goes to `ToolReturnLedger.record(_:)`; a later call goes to `PendingInnerCalls.note(_:gave:)`.
    - `PendingInnerCalls` now names unawaited calls: path, tool, op, and `commandID` for `tools.shell.execute`. New lead text: the result waited for each call. No pendingWorkInstruction in it (nothing is pending).
    - Removed: `Execute.snippetValue` pending branch, `SnippetPendingField`, `InterpreterValue.pendingCompletionToken`, `PendingRunEnvelope.snippetFields`, the pending skip and `recording(_:)` of `ToolReturnLedger`, the duplicate-identifier skip of `PendingInnerCalls`.
    - Docs updated: RunBinding, Execute, MultiTool+Background, MultiToolConfiguration, SnippetOutput, plan.md, README "Background runs and mail delivery".

    Tests (BackgroundSettleGraceTests): test 1 `awaitedLongExecuteGivesTheRealResult` (RED before: the cat ran 1 s after the start and read no file; GREEN after), test 2 `shortSnippetStillAnswersInline`, test 3 `unawaitedLongExecuteIsNamedInTheMail` (RED before, GREEN after). Also: `unawaitedShortExecuteIsNamedInline`, `nestedUnawaitedExecuteIsNamedInTheOuterResult`, `failedSnippetNamesTheUnawaitedCall`. Removed tests of the pending-object path (Acceptance 3, nested returned pending, fail on pending object, background pending).

    Other tests changed because the behavior changed: RegisteredJournalOpTests (an inner held execute now stays off the run plane and the cancel ends it; the old test hung for ever), MultiToolExecutionTests floating call (now named by PendingInnerCalls), ToolReturnLedgerTests (use `record`). Integration: ShellBackgroundRunner now reads the background `runCode` run (swiftTask), cancels it after the turn (a cancel during the in-band settle period ends the turn call with CancellationError — found in the first run), and starts the swept run with a direct mount of `Execute` (a snippet would wait 600 s).

    Note: the IntegrationTests package needed `swift package update` (stale swift-distributed-tracing pin: InstrumentationContext not found).
  timestamp: 2026-10-12T23:58:26.490825+00:00
- actor: claude-code
  id: 01m4s8vjf639pnsbw4s89fz2ra
  text: |-
    ### implement — changed
    - evidence: new Sources/FoundationModelsMultitool/Invocation/SnippetEndMark.swift; changed RunBinding.swift (RunToCompletionInnerTool), PendingInnerCalls.swift, ToolReturnLedger.swift, SnippetOutput.swift, MultiTool.swift, MultiTool+Background.swift, MultiToolConfiguration.swift, Capabilities/Shell/Execute.swift, README.md, plan.md; tests BackgroundSettleGraceTests (tests 1-3: awaitedLongExecuteGivesTheRealResult, shortSnippetStillAnswersInline, unawaitedLongExecuteIsNamedInTheMail, plus 3 more), RegisteredJournalOpTests, MultiToolExecutionTests, ToolReturnLedgerTests; integration ShellBackgroundRunner/ShellBackgroundTests/ShellBackgroundReportTests. `swift test`: 2375 tests in 209 suites passed, 0 warnings. `swift test --package-path IntegrationTests --no-parallel`: 115 tests in 39 suites passed.
    - deviation: test 3 names the unawaited call as a call that the result waited for, not as a call that continues in the background (settle-before-return; see the research comment). The user told me to decide.
    - next: /review
  timestamp: 2026-10-12T23:58:35.494687+00:00
- actor: claude-code
  id: 01m4s9a90cv84d0v6zh9s75c0d
  text: |-
    ### test — green
    - evidence: swift test: 2375 tests in 209 suites passed, 0 failed. swift test --package-path IntegrationTests --no-parallel: 115 tests in 39 suites passed, 0 failed. Build warnings: 0 from package code (one toolchain note "missing creator for mutated node" for the mlx-swift_Cmlx bundle).
    - skips: 6 keyed live-provider tests skip when their API key variable is not set. This is the written user exception of 2026-09-26 (test-integrity/test-partitioning), documented in IntegrationTests/Package.swift.
    - next: review.
  timestamp: 2026-10-13T00:06:37.324709+00:00
- actor: claude-code
  id: 01m4s9ayks0vbg6ezseb7760wb
  text: |-
    ### commit — changed
    - evidence: c841d08 fix(runcode): give the real result for an await of an inner tools call
    - next: review
  timestamp: 2026-10-13T00:06:59.449855+00:00
- actor: claude-code
  id: 01m4s9ket2x8hwpvm2yzn8xs61
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (37b9407). Zero findings. 16 files reviewed, 14 validator runs, 0 failed. Not reviewed: 2 .kanban files (ignore rule), README.md and plan.md (no validator matches). The commit renames no file.
    - next: The task is in done. Send the commit sha 37b9407 to the requester (foundationmodelsacpagent-2a, task ^nwy1gcf).
  timestamp: 2026-10-13T00:11:38.178256+00:00
- actor: claude-code
  id: 01m4s9m0kgw8wpjdde4ejzechr
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — new SnippetEndMark.swift; RunBinding.swift (RunToCompletionInnerTool), PendingInnerCalls.swift, ToolReturnLedger.swift, MultiTool.swift and others; tests in BackgroundSettleGraceTests
    - test: green — swift test 2375 passed; IntegrationTests 115 passed
    - commit: 37b9407
    - review: clean — zero findings
  timestamp: 2026-10-13T00:11:56.400835+00:00
position_column: done
position_ordinal: ffffdd80
title: 'runCode: an await of an inner tools.* call always gives the real result'
---
## Problem

In a runCode snippet, an awaited inner tools.* call that runs past the settle period gives a pending object to the snippet code. The snippet then continues as if the work is done.

Evidence (FoundationModelsACPAgent repo, bench/preds.pending-inner-1012.transcripts/django__django-13964/01M4RPZBENF2YJKXH8HAZABPK9/transcript.jsonl, seq 1017-1032): a snippet did `await tools.shell.execute({ command: "python tests/runtests.py ... > full_run_tmp.log 2>&1" })`, then grep on the log, then `rm full_run_tmp.log`. The await gave a pending object at once. The snippet deleted the log about 5 s after the command started. The 375 s test run gave only "grep: full_run_tmp.log: No such file or directory" (seq 1023). The model ran the full suite again (seq 1032). Same class: run no-otel-1011 django__django-13447 seq 428-432 (`s.output.slice` on the pending object); run noop-stop-1012 django__django-13447 seq 298-302.

The named-pending text from ^qg52whq (369a1b5) cannot fix this, because the statements after the await already ran.

## Decision

- "Background" means: the work takes longer than the grace period. There are no turns. The result of pending work is injected as a new message. There is no wait tool.
- An inner await gives the REAL result. It blocks the snippet until the inner call ends.
- The settle period applies to the OUTER runCode call only. When the whole snippet runs past it, the snippet goes pending (one completion token). Its real return value is injected later with the shared pending-work text (PendingRunEnvelope.pendingWorkInstruction).
- An inner call never gives a pending object to snippet code.
- Parallel work stays possible: inside a snippet with `Promise.all` or a call that is not awaited; outside with parallel tool calls.

## Work

1. Make inner tools.* calls in a snippet always give their real result to `await`.
2. Keep the settle period and the pending envelope for the outer runCode only.
3. Remove the pending-object path for awaited inner calls.
4. Keep the "name the pending inner calls" text only for inner calls that the snippet started and did not await before it ended.

## Tests

1. A snippet awaits a long inner execute that writes a file, then reads and deletes the file. The read sees the full output. The outer call goes pending and injects that result.
2. A short snippet still answers inline.
3. A snippet that starts a long call without await and ends still names that call.

## Requester

The FoundationModelsACPAgent session (foundationmodelsacpagent-2a) asked for this task. Send it the commit sha when the commit is pushed. Its task ^nwy1gcf then runs the bench check again. #bug