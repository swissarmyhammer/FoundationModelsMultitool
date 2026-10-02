---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3wn5pn4djg3q8v5wmy3y6kt
  text: |-
    Research: cause of the serialization found. Layer: Multitool (`MultiTool.dispatchRun`). The trigger is in FoundationModelsCodeContext.

    Evidence from the transcript (django__django-14667):
    - The quick snippets ("waiting", "ok", "ping", "done-waiting", "halt", "final-wait") all wrote their terminal at 953.928 to 953.932. The grepCode snippet 01M3WBBGKG wrote its terminal at 953.960. Thus the quick snippets finished only when that grepCode call returned.
    - The full-pool refusals settled at once all through that time. A refusal goes through the same Router path (BackgroundToolRunner, RunEventFunnel, SessionOutbox journal chain). It does not go into the sandbox. Thus Router and Extras do not block. The block is between the live-context claim and the end of the sandbox run.
    - Second wave: "halt-4" to "halt-9" all finished at 2089.99, also together.

    Cause:
    - `GrepCode.run` (FoundationModelsCodeContext, Ops/GrepCode.swift) adds one TaskGroup child for each index chunk. Each child does CPU-bound regex work. The children inherit the priority of the inner call task. That task starts on the sandbox thread (QoS userInitiated), so the priority is `.high`. For approximately 95 s, the children keep every thread of the cooperative pool busy.
    - `MultiTool.dispatchRun` sends each snippet to `DispatchQueue.global(qos: .userInitiated)`. That is a constrained (non-overcommit) global queue. The kernel does not give it a new thread while all CPUs are busy at that QoS or higher. Thus the snippet does not start until grepCode ends.
    - Probe (scratchpad, 32 CPUs): one busy child for each CPU at `.high`, each one spins 5 ms and then yields. Result: a block on `DispatchQueue.global(qos: .userInitiated)` did not run in 3 s. A block on a private serial queue (overcommit) ran in 0.000 s. A `.high` cooperative hop ran in 0.000 s. A hog at `.medium` did not block the global queue.

    Not the cause (examined): Router `BackgroundToolRunner`, `ToolRun`, `RunEventFunnel` (one chain for each run), `SessionOutbox.journalChain` (short writes), `SessionMailbox`, `ModelCallMark`, JSCInterpreter (one serial queue and one JSContextGroup for each run). The thread limit of GCD (64) is not the cause: 100 blocked global blocks did not stop a new one.

    Fix in this package: run each snippet on its own serial queue (overcommit) in place of the constrained global queue.

    Card necessary in FoundationModelsCodeContext (I did not make it): `GrepCode.run` makes one CPU-bound child task for each chunk at the inherited priority and keeps the full cooperative pool busy for the whole grep. It slows every other task of the process at that priority. Recommend a bounded number of workers, a lower priority, or work off the cooperative pool.
  timestamp: 2026-10-01T21:15:51.844753+00:00
- actor: claude-code
  id: 01m3wqr3ztfbz6gnp07yd1d2f0
  text: |-
    ### Decision of the user — no cap
    - The user said: "There is no valid reason to have a limit of 8." and "It's JS — like browser tabs, folks have scores and scores of them."
    - Thus many runCode snippets (scores, for example 100) must be able to run or wait at the same time, with no cap.
    - Consequence: a suspended run must not hold an OS thread while it waits for an async tool. Now `JSCInterpreter.run` does `DispatchQueue.sync` on a global-queue thread, and `pumpUntilSettled` blocks that thread until the promises settle. GCD has a thread limit (approximately 64). With scores of suspended runs, the threads can all be in use, and a new snippet cannot start. This can be the cause of the serialization (Work item 1). Examine it first.
    - The test for acceptance criterion 2 must start a number of slow snippets that is much larger than the GCD thread limit (for example 100). While they wait, a `return "x"` snippet must give its result inline, inside the grace.
  timestamp: 2026-10-01T22:00:52.474606+00:00
- actor: claude-code
  id: 01m3wqs77xpfsazj62bdp4es2p
  text: |-
    ### Correction from the user — no load test
    - The user said: "You do not need to start or test 100 slow snippets."
    - This comment replaces the test requirement in the comment "Decision of the user — no cap". Do not write a test that starts many slow snippets (not 100, and not more than 8).
    - The tests are: (1) one slow snippet runs, and a second snippet `return "x"` gives its result inline, inside the grace; (2) the pending envelope contains the new sentence. Removal of the cap is verified by the absence of the cap symbols and texts in source, tests and documents.
    - The thread hypothesis (a suspended run holds a GCD thread) is still one possible cause of the serialization. Examine it under Work item 1, but do not make a load test for it.
  timestamp: 2026-10-01T22:01:28.573657+00:00
- actor: claude-code
  id: 01m3wqzv19r0v1qt1sz5ch1h05
  text: |-
    ### Design correction — the job queues must not target a constrained queue
    - The research comment above found the cause: `MultiTool.dispatchRun` uses `DispatchQueue.global(qos: .userInitiated)`, a constrained (non-overcommit) queue. When `GrepCode` keeps every CPU busy at `.high`, the kernel gives that queue no thread, and a new snippet cannot start.
    - The description says "a serial `DispatchQueue` for each run, with a shared concurrent queue as its target" and "GCD sizes the thread pool of the shared target queue to the cores". That is wrong. If the target is a constrained global queue, the defect stays.
    - Correct rule: the job queue of each run is a private serial `DispatchQueue` with no constrained target (an overcommit queue). It gets a thread when it has a job, also when all CPUs are busy. It holds no thread when it has no job.
    - Concurrency is still not set by a number: only runs that have a job ready use a thread, and jobs are short.
    - The partial work in the tree from the stopped implement step (private serial queue in `dispatchRun`, `CooperativePoolHogFixtures.swift`, the tests in `InlineSettleGraceTests.swift`, `CLIAnswerDrain` changes, the cap-test removal in `SuspendedContextTests.swift`) agrees with this rule. Keep the parts that agree with the event-loop design, and use the pool-hog fixture for the test of acceptance criterion 3.
    - A card is necessary in FoundationModelsCodeContext: `GrepCode.run` makes one CPU-bound child task for each chunk at the inherited priority and keeps the full cooperative pool busy. The orchestrator reports this to the user; do not make the card from this task.
  timestamp: 2026-10-01T22:05:05.449961+00:00
- actor: claude-code
  id: 01m3wtezv8yq5ashtm034nr274
  text: |-
    ### Implementation: the event loop landed

    What changed:
    - `Interpreter.run(code:installing:installingAsync:)` is `async` and is the one requirement. The `isCancelled` overloads are removed; the cancellation of the calling `Task` cancels the run.
    - `JSCInterpreter` runs each snippet as a `Run` with jobs on a private serial `DispatchQueue(label:autoreleaseFrequency: .workItem)`, with no constrained target (the design correction). Jobs: start job, settle job, cancel job, wall-clock timer job. The finish step ends each job: a run with a recorded watchdog cause ends now; a run with a pending bridge promise keeps waiting (state `awaiting`, no thread); a run with none settles. States: `queued(Snippet)`, `awaiting(LiveRun)`, `settled`, `cancelled`, `failed`. The design state `running` is the span of one job; no other job can see it, so it is not modelled.
    - The wall-clock limit is a `DispatchSourceTimer` on the job queue. The CPU watchdog (`WatchdogState`, 20 ms JSC poll) stays for a job that executes JS.
    - `PromiseRegistry` has no semaphore, no lock and no `waitAndTakeReadyToSettle`. A completed call `Task` calls `deliver`, which puts a settle job on the queue. `pumpUntilSettled`, `PollOutcome` and `handleSettlements` are removed.
    - `MultiTool.run` and `dispatchRun` are removed. `runCapturingOutcome` awaits `interpreter.run` directly, inside `withTaskCancellationHandler` (which still cancels `InFlightInnerCalls` synchronously).
    - The cap is removed: `liveContextLimit`, `defaultLiveContextLimit`, `LiveContextCounter`, `liveContextCapError`, the claim and release, and their tests and documents (docs/SECURITY.md, UPSTREAM_ASKS.md, FileChangeJournal, Forking, ToolReturnLedger). eventplan.md § "Async JavaScript" now describes the event loop.
    - `TypedMockDryRun.apiUsageFailure` awaits. `SampleSnippet.verdictOffCooperativePool` (a bridge to `DispatchQueue.global(qos: .userInitiated)`, the same constrained queue) is removed; `verdict` is `async`.
    - `collectInstruction(forCompletionToken:)` ends with "Do not call runCode to wait or to check; the result comes to you without a call." `RouterSessionMountTests` asserted that the sentence never names `runCode`; that assertion now checks the new prohibition, because the card requires the name.

    Decisions and discoveries:
    - **Run table.** The run table keyed by completion token, with `status()` and `cancel(token)`, already exists in the run plane of FoundationModelsExtras (`ToolContext.backgroundRuns()`, `ToolContext.cancel(completionToken:)`). `cancel(token)` cancels the `Task` of the `runCode` call, and that cancellation reaches the `Run` (cancel flag + cancel job) and the tool `Task`s. I did not add a second table in `MultiTool`: nothing would read it. `SuspendedContextTests.cancellingASuspendedRunTearsDownItsContext` covers acceptance criterion 6 through that path.
    - **Telemetry must stay in the calling task.** The first version logged `snippetStarted`/`snippetEnded` in the jobs. `TelemetryCapture` routes records by a task-local value at log time, so `CoreLogRecordTests` lost them. The start and the end are now recorded in `JSCInterpreter.run` (the caller's task); the jobs still bind `boundLogger` and the metrics factory for host functions and the `Task`s they start.
    - **The caller is resumed in a job of its own.** `asyncHostFunctionDoesNotLeakTheSandbox` failed when the job that ended the run resumed the caller: the job's stack and autorelease pool still held the sandbox. The inputs (`Snippet`) are now held only in the `queued` state, and `complete` resumes the caller with `queue.async`, after the job unwound.
    - **RED evidence for criterion 3:** with `dispatchRun` back on `DispatchQueue.global(qos: .userInitiated)`, `quickSnippetAnswersBesideABusySlowTool` failed: the `return "x"` snippet answered `pending: true`. With the event loop it answers inline. The test now also proves that the slow snippet outlasts the grace (its call answers pending first; grace 1 s).
    - **RED evidence for criterion 8:** `pendingSentenceForbidsPollingCalls` failed before the sentence was added.
    - New test `JSCInterpreterTests.wallClockLimitEndsARunThatWaitsForever`: a run that awaits a call that never completes ends with `.timeout` at a 0.3 s limit, and the call `Task` sees its cancellation. The interpreter cancellation tests use `Task.cancel()` and event gates (`TestPoll`) in place of `isCancelled` and sleeps.
    - `HardeningTests.cancellationStressTestNoDeadlock` (existing, not changed) starts 40 `while (true)` snippets for 20 ms each. No test that this task added or changed starts many slow snippets.
    - Partial work kept: the private queue reasoning (now in `JSCInterpreter`), `CooperativePoolHogFixtures.swift`, the two `InlineSettleGraceTests` tests, the cap-test removal, and the `CLIAnswerDrain` `.reasoningStopped` case (needed to compile against the current Router). The partial test `reasoningStopIsPrinted` expected a printed line, so `CLIEventReporter` now prints a reasoning stop as it prints a repetition stop.

    Test result: `swift test` — 1882 tests, 3 tests fail (4 issues), all from upstream changes of 2026-10-01 and not from this work, also after `swift package update`: `CallSpanTests.thrownErrorSetsTheErrorStatus` (FoundationModelsExtras `50fd4a5` removed the error event), `RouterDiscoverySeamsTests` preamble sentence, and two `OverBudgetSelectionOrderTests`. New card `^9255d9b` holds them. Every runCode, interpreter, hardening, suspended-context and inline-grace test passes.
  timestamp: 2026-10-01T22:48:19.048537+00:00
- actor: claude-code
  id: 01m3wtf904qfqe46evyc9237qs
  text: |-
    ### implement — changed
    - evidence: 29 files. Sources: Interpreter/Interpreter.swift, Interpreter/JSCInterpreter.swift, MultiTool.swift, MultiTool+Background.swift, MultiTool+Forking.swift, MultiToolConfiguration.swift, Discovery/SampleSnippet.swift, Discovery/TypedMockDryRun.swift, Invocation/InFlightInnerCalls.swift, Invocation/RunBinding.swift, Invocation/ToolReturnLedger.swift, Capabilities/Files/FileChangeJournal.swift, MultitoolCLI/CLIAnswerDrain.swift. Tests: JSCInterpreterTests, InlineSettleGraceTests, SuspendedContextTests, HardeningTests, TypedMockDryRunTests, CoreLogRecordTests, MetricsTests, ResultRendererTests, MCPCapabilityTests, ReadmeOperationSectionTests, RouterSessionMountTests, CLIAnswerDrainTests, Fixtures/CooperativePoolHogFixtures.swift (new). Docs: eventplan.md, docs/SECURITY.md, UPSTREAM_ASKS.md. `swift test`: 1882 tests, 3 fail from upstream drift (card `^9255d9b`), 0 from this work.
    - next: review. The acceptance box "`swift test` passes" stays open until `^9255d9b` is done.
  timestamp: 2026-10-01T22:48:28.420252+00:00
- actor: claude-code
  id: 01m3wv15s1w8pd4k6e360fv4aw
  text: |-
    ### test - green
    - evidence: swift package update (pins current), then swift test: 1882 tests in 154 suites passed, 0 failed, 0 skipped. First run had 4 issues in 3 tests, all from upstream changes recorded on ^9255d9b. They are fixed in the tests, and the fixes are recorded on ^9255d9b. The only warning is the linker line "missing creator for mutated node" for the mlx-swift_Cmlx bundle in .build. It comes from the build tool, not from a source file of this package.
    - next: review
  timestamp: 2026-10-01T22:58:14.945576+00:00
- actor: claude-code
  id: 01m3wv2ttxjdmavc74d4eenf3z
  text: |-
    ### commit — changed
    - evidence: 4dfacb3 feat(interpreter): run runCode as jobs on an event loop; d8de90e test(contracts): follow the upstream changes to span errors, the selection default and the prefix format (task ^9255d9b)
    - note: The repo holds no formatter config (no .swift-format, .swiftformat or .swiftlint.yml). The committed code passes neither swift-format lint nor swiftformat lint with default rules. So no formatter ran. A run would rewrite whole files.
    - next: review
  timestamp: 2026-10-01T22:59:09.277925+00:00
- actor: claude-code
  id: 01m3wvzzfxa3tvp1j6jw7fzvqc
  text: |-
    ### review — findings
    - evidence: review sha d2816ca..HEAD. 2 findings (2 confirmed, 1 refuted). Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift:21, Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift:28 (code-hygiene/magic-numbers-swift). No file in the range is renamed (git diff --name-status -M), so no file-scoped review was necessary. Not reviewed: .kanban/ (ignore rule); UPSTREAM_ASKS.md, docs/SECURITY.md, eventplan.md (no validator matches).
    - next: implement. Replace the magic numbers in CooperativePoolHogFixtures.swift with named constants, in all of the file. The task stays in review.
  timestamp: 2026-10-01T23:15:04.317965+00:00
- actor: claude-code
  id: 01m3ww0g8xqsphjsct08gk1k7f
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 29 files (event loop, cap removed, pending sentence)
    - test: green — swift test, 1882 passed, 0 failed (3 upstream contract test fixes, ^9255d9b)
    - commit: d8de90e, 4dfacb3, 817be44
    - review: findings — Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift:21, Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift:28
  timestamp: 2026-10-01T23:15:21.501320+00:00
- actor: claude-code
  id: 01m3ww70w4nbmwr1xfs7h20wek
  text: |-
    ### Findings: magic numbers in CooperativePoolHogFixtures.swift
    - Cause: swiftlint `no_magic_numbers` reports a literal that is an argument of a call, also in a `let` declaration. `.milliseconds(5)` and `.seconds(10)` were such arguments. A `let` with a plain literal is not reported.
    - Correction: the file now has `hogSliceMilliseconds = 5` and `hogCeilingSeconds = 10` (integer constants with the unit in the name, the same pattern as `TestPoll.intervalMilliseconds`). `hogSliceDuration` and `hogCeiling` are made from them. The only other literal in the file is `0` in `0..<activeProcessorCount`; `0` is in the allowed list.
    - RED: swiftlint with the rule config (`only_rules: [no_magic_numbers]`, `allowed_numbers: [0, 1, -1, 100]`) gave 2 violations, at lines 21 and 28. GREEN: the same command gives 0 violations.
    - `swift test --filter InlineSettleGraceTests` (the only suite that uses the fixture): 7 tests in 1 suite passed, 0 failed. The only warning is the known linker line "missing creator for mutated node" for the mlx-swift_Cmlx bundle in .build.
    - Acceptance box "`swift test` passes" checked: the test step of iteration 1 was green (1882 passed, 0 failed), and this change touches only constants of a test fixture.
  timestamp: 2026-10-01T23:18:55.108654+00:00
- actor: claude-code
  id: 01m3ww72nmnxjkjkqcq1jg8bta
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift. swiftlint no_magic_numbers: 2 violations before, 0 after. swift test --filter InlineSettleGraceTests: 7 passed, 0 failed.
    - next: test, then review. The task stays in doing.
  timestamp: 2026-10-01T23:18:56.948370+00:00
- actor: claude-code
  id: 01m3ww9frabekdxz1fcddjfxj0
  text: |-
    ### test — green
    - evidence: `swift test` — 1882 tests in 154 suites passed, 0 failed, 0 skipped. No compiler warning from a file of this package.
    - note: The build tool printed one linker line: "missing creator for mutated node" for the mlx-swift_Cmlx bundle in .build. It comes from the build tool. It was not fixed.
    - next: review.
  timestamp: 2026-10-01T23:20:15.882036+00:00
- actor: claude-code
  id: 01m3wwa16qym5jac6s405wxkcm
  text: |-
    ### commit — changed
    - evidence: 61e0842 test(fixtures): name the hog slice and ceiling constants
    - next: review
  timestamp: 2026-10-01T23:20:33.751144+00:00
- actor: claude-code
  id: 01m3wwf9mwbbmm4771rxkkkj4b
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (3dd26f5). 0 findings (0 confirmed, 0 refuted, 7 validators attempted, 0 failed). 1 file reviewed: Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift. Not reviewed: 2 files in .kanban/ (ignore rule). No file in the range is renamed (git diff --name-status -M), so no file-scoped review was necessary. The two prior findings (2026-10-01 17:59, lines 21 and 28, code-hygiene/magic-numbers-swift) are checked. The diff shows that the literals are now the named constants hogSliceMilliseconds and hogCeilingSeconds.
    - note: The commit comment above gives sha 61e0842. The commit in HEAD is 3dd26f5, with the same subject.
    - next: none. The task moved to done.
  timestamp: 2026-10-01T23:23:26.236509+00:00
- actor: claude-code
  id: 01m3wwfrg37ancbrhktvcaqmg1
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file (CooperativePoolHogFixtures.swift, named constants)
    - test: green — swift test, 1882 passed, 0 failed, 0 skipped
    - commit: 3dd26f5 (the commit comment names 61e0842, the sha before an amend)
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-10-01T23:23:41.443154+00:00
position_column: done
position_ordinal: ffff8a80
title: 'runCode as a queue: run JS as jobs on an event loop, so a waiting snippet holds no thread and no limit is necessary'
---
## Source

The FoundationModelsACPAgent session sent this report (SWE-bench run of 2026-10-01). The agent side of the problem is card `^64pav2a` in FoundationModelsACPAgent (the agent ends the ACP turn while a background run is in flight). This card is for the Multitool side only.

## Evidence

Instance `django__django-14667`. Transcript: `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/bench/preds.code-context.transcripts/django__django-14667/`. The times come from the ULID completion tokens.

- 13:24:16 and 13:24:25: two snippets call `tools.code_context.grepCode`. Both go pending. One settles after approximately 95 s. The other ends with "runCode timed out after 120.0 seconds with no progress".
- 13:24:33: the model calls runCode with only `return "waiting"`. This snippet also goes PENDING. It settles only at approximately 13:25:51, in the same batch as the grepCode result.
- Then: "Too many runCode snippets are running at once (limit 8). Do not start another now. End your answer: ... Fix the snippet and call runCode again."
- 348 runCode calls. Approximately 210 failed with "Too many...", or timed out, or stayed pending. 133 of them were `return "waiting1"` to `return "waiting130"`. The context grew to 124k tokens.
- Same pattern in `django__django-13447`.

## Decisions of the user (2026-10-01)

- "There is no valid reason to have a limit of 8."
- "It's JS — like browser tabs, folks have scores and scores of them."
- "The JS working through for a call needs to be in a work queue with some concurrency. There is no reason to have a limit on how many tasks can be requested."
- "No hard-coded limit of concurrent sessions is allowed."
- "You do not need to start or test 100 slow snippets."
- "Think more deeply and design a better solution that treats runCode as a queue."

## Root problem: a run holds a thread for its full life

- `JSCInterpreter.run` (`Interpreter/JSCInterpreter.swift:334`) is synchronous. It does `DispatchQueue.sync` on a new queue, and `MultiTool.dispatchRun` (`MultiTool.swift:785`) calls it on a GCD global-queue thread.
- `pumpUntilSettled` (`JSCInterpreter.swift:1320`) then blocks that thread in `waitAndTakeReadyToSettle` until every tool promise settles, and it polls the watchdog every 20 ms. A snippet that waits 95 s for `grepCode` holds one OS thread for 95 s, and it does no work.
- Because each run holds a thread, the package needed `liveContextLimit` to stop thread exhaustion. The limit is a symptom of the blocking design. A browser has scores of tabs because a tab that waits for I/O holds no thread. The new design does the same.
- The cause of the `return "waiting"` delay in the transcript is not verified. Two blocked threads alone cannot use all GCD threads, so another layer can also contribute (FoundationModelsExtras `BackgroundToolRunner`, the Router generation queue, or the mail batch delivery). Work item 1 finds it.

## Design: an event loop of JS jobs

The model is the browser event loop. JS executes only in short **jobs**. Between jobs a snippet is only data in memory: a `JSContext`, its pending promises, and its record in the run table. It holds no thread.

### Parts

1. **Run** — one `runCode` snippet. It has its own `JSContextGroup` and `JSContext` (isolation does not change), its own completion token, its own **serial job queue**, and a state: `queued`, `running`, `awaiting`, `settled`, `cancelled`, `failed`.
2. **Job queue of a run** — a serial `DispatchQueue` for each run, with a shared concurrent queue as its target. A serial queue that has no jobs holds no thread. Every touch of the run's `JSContext`, `JSValue`s, `resolve` and `reject` occurs in a job on this queue. Thus JSC is never used from two threads at the same time.
3. **Jobs** — there are three kinds:
   - **start job**: make the context, install the host functions, evaluate the snippet, drain the microtasks. Then the job ends. It does not wait for the promises.
   - **settle job**: a tool `Task` that completes puts a settle job on the job queue of its run. The job calls `resolve` or `reject` and drains the microtasks. This can start more tool calls.
   - **finish step**: at the end of each job, if the promise registry is empty and the top-level promise settled, the run settles: it records the result or the floating-rejection error, releases its context, and resumes the waiter of the call.
4. **Tool calls** — an async host function starts a Swift `Task` on the cooperative pool, as now. The `Task` never blocks a JS thread. When it completes, it puts a settle job on the job queue of its run (`queue.async`). The old deadlock note (`JSCInterpreter.swift:747`) does not apply, because no job holds the queue while it waits.
5. **Run table** — one table for each `MultiTool`, keyed by completion token. `runCode` adds a run and returns. `status()` reads the table. `cancel(token)` changes the state and cancels the tool `Task`s of the run. The table has no size limit.

### Concurrency

- There is no number in the design. Requests are not limited, and there is no worker count.
- Only jobs use threads, and a job is short: it is CPU work of JS only. GCD sizes the thread pool of the shared target queue to the cores of the machine. Thus the machine bounds concurrency, and no constant in code does.
- A run that waits for a tool uses memory only. Scores of waiting runs cost scores of contexts in memory, as browser tabs do.

### Clocks

- **CPU watchdog**: the JSC execution time limit callback (`jscTerminateCallback`, `WatchdogState`) stays. It stops a job that executes JS for too long (for example `while (true) {}`).
- **Wall-clock limit** (`executionTimeLimit`): a timer for each run (a `DispatchSourceTimer` on the run's job queue) replaces the 20 ms poll. When it fires, the run cancels its tool `Task`s and fails with the timeout error that it has now.
- **Inline settle grace**: the `runCode` call waits for the run's completion for the grace only. The grace starts when the call adds the run. A short snippet completes inside the grace and gives its result inline. A snippet still in `awaiting` at the end of the grace gets the pending envelope. No snippet waits behind a different snippet, because no snippet holds a resource that a different snippet needs.

### Interface changes

- `Interpreter.run` becomes `async`. `MultiTool.run` and `dispatchRun` (the continuation and global-queue bridge) are removed; the call awaits the run directly.
- The sync path of `TypedMockDryRun` (`Discovery/TypedMockDryRun.swift:99`) installs no async host functions. Give it a sync helper or let it await; it must not keep the blocking pump alive.
- Remove `pumpUntilSettled`, `waitAndTakeReadyToSettle`, the semaphore of `PromiseRegistry`, and the 20 ms `watchdogPollInterval` poll for the idle case.
- Remove the cap: `MultiToolConfiguration.liveContextLimit`, `MultiTool.LiveContextCounter`, `MultiTool.liveContextCapError` (`MultiTool+Background.swift:134-199`), the claim and release code, the cap tests (`SuspendedContextTests.swift:150-160`), and every reference in the documents (for example eventplan.md § "The constraint boundary, and the escape hatch"). Update the documents to describe the event loop.

### Rules that do not change

- Settle-before-return: a run does not settle while a tool promise is pending, so a floating `tools.files.write(...)` always completes.
- Floating-rejection detection: decided once, when the registry is empty.
- Isolation: nothing that one run sets is visible to a different run.
- On termination (timeout or cancel), pending tool `Task`s are cancelled and their promises are not settled, as `PromiseRegistry.cancelAllPending` documents now.

## Work

1. Find the cause of the `return "waiting"` delay in the transcript, with file:line evidence, and record it with its layer. If it is in another package, report it; the orchestrator decides about a card in that package.
2. Implement the event loop above in `JSCInterpreter` and `MultiTool`.
3. Remove the cap and the blocking pump, as listed above.
4. Add this sentence to the pending envelope (`collectInstruction(forCompletionToken:)`, `MultiTool+Background.swift:43`): "Do not call runCode to wait or to check; the result comes to you without a call."

## Acceptance criteria

- [x] No hard-coded number limits the requests or the concurrent runs. No source, test or document contains `liveContextLimit`, `LiveContextCounter`, `liveContextCapError` or "Too many runCode snippets".
- [x] A run that waits for a tool holds no thread: `pumpUntilSettled` and the blocking wait in `PromiseRegistry` are removed, and `Interpreter.run` is `async`.
- [x] A test starts one snippet that awaits a slow fake tool (longer than the inline settle grace). While it waits, a second snippet `return "x"` gives its result inline, inside the grace.
- [x] A test shows settle-before-return: a snippet that does `tools.x(...)` without `await` and returns at once does not settle until the tool call completes.
- [x] A test shows that the wall-clock limit stops a snippet that waits for a tool that never completes, and that the CPU watchdog stops `while (true) {}`.
- [x] A test shows that `cancel(completionToken)` stops a snippet that waits for a tool, and that its tool `Task` is cancelled.
- [x] All tests of floating rejections, isolation and timeouts that exist now still pass.
- [x] The pending envelope contains "Do not call runCode to wait or to check; the result comes to you without a call."
- [x] The card records the cause of the `return "waiting"` delay, and its layer.
- [x] No test starts many slow snippets.
- [x] `swift test` passes.

## Review Findings (2026-10-01 17:59)

> Scope: `review sha d2816ca..HEAD` — reviewed the diffs only — lines this change added or modified. 30 file(s) reviewed, 7 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `UPSTREAM_ASKS.md` — no validator matches this file
> - `docs/SECURITY.md` — no validator matches this file
> - `eventplan.md` — no validator matches this file

- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift:21` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/CooperativePoolHogFixtures.swift:28` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants. #defect