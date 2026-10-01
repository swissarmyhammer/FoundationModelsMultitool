---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3wc4q44nrrmd2qwr9s2apwm
  text: |-
    Research (2026-10-01). Sources: scratchpad integ2.log (load about 100) and integration.log (2026-09-30, a quieter run, same code for these suites). Load average at 12:31 today: 109.65 85.79 71.43.

    Step times. Each Router resolve loads 3 models (standard, flash, embedding), one after the other.

    1. NestedGenerationProbeTests (limit 60 s). Resolve started 07:15:24. Loads: 22 s, 19 s, 14 s. The turn started 07:16:20, 56 s into the test. The limit stopped the test 4 s later, before the model made its tool call (entered=[]). On 2026-09-30 the whole test took 16.9 s (elapsed 11.8 s). Cause: machine load. The profile load used 93% of the limit. The probe uses only the standard slot, but Router resolves and loads all 3 slots. That is Router behavior, not code in this repo.

    2. NoDescriptionSurfaceDiscoveryTests (limit 600 s). Resolve 37 s (loads 9 s, 12 s, 12 s). Then 27 selection generations (3 candidates x 3 rounds x 3 queries), one at a time. Each took 2 s to 39 s, and one took 130 s (arguments, round 2, query 1, 07:23:23 to 07:25:33). The limit stopped it in the 23rd generation. On 2026-09-30 the whole test took 113 s. Cause: machine load (about 5x slower). The test does 27 generations by design: 3 candidates from card ^cfyj4gc and 3 rounds from discoveryRoundCount (DiscoveryGrading.swift states why). Only the "arguments" candidate has an assertion. The "banner" and "name" candidates (18 generations) are measurements that no assertion reads. I did not remove them, because that changes a recorded decision.

    3. OverBudgetSurfaceDiscoveryTests (limit 360 s). Resolve 07:40:12 to 07:44:18 = 246 s (loads 52 s, 94 s, about 99 s). Embedding catch-up of 49 entries: 55 s. The first selection generation started at 07:45:13, and the limit stopped it 59 s later. On 2026-09-30 this suite failed for a different cause (Hugging Face metadata request time-out). Cause: machine load. The same plumbing models loaded in 2 s each at 08:15:31 when they were in memory.

    4. SearchThenCallTests, singleCallWeather (limit 720 s). Resolve 07:49:30 to 07:55:29 = 359 s (loads of the 27B profile: 139 s, 59 s, about 151 s). The first model turn then ran 362 s with zero tool calls and no reply, and the limit stopped it. On 2026-09-30 the whole suite (4 tests) took 204 s. Cause: machine load. Note: each of the 4 tests of this suite resolves again and loads the 3 models again (compose/chain spent 342 s in resolve). This does not cause the failure of the first test, which must load the models one time in all cases.

    5. FilesBareSessionTests (wrong answer). Reply: "It appears there are no lines in the file at the specified path." On 2026-09-30 the same code answered "1:b9|pelican". No change to the files verbs or to this test since that run. The log does not hold the tool call arguments or the tool output, because a bare session has no Router recording. Possible causes from the Read code: (a) offset past the end of the 1-line file gives lines=[] and the note "showing lines none; the window begins past the end of the file of 1", with no correction; (b) offset 0, limit 0, or an unknown format gives a correction and lines=[]. Each is a model choice of arguments, and each is possible for the on-device model. I added TOOL trace lines to runBareSessionScenario, so that each run writes the tool calls and tool outputs.
  timestamp: 2026-10-01T18:38:02.372803+00:00
- actor: claude-code
  id: 01m3wd1x82qr4wanaxg88n5hky
  text: |-
    Results (2026-10-01, afternoon).

    Run 1: `swift test --package-path IntegrationTests --no-parallel --filter 'FilesBareSessionTests|NestedGenerationProbeTests|NoDescriptionSurfaceDiscoveryTests|OverBudgetSurfaceDiscoveryTests|SearchThenCallTests'`, with the TOOL trace lines and before the Read fix. Load average 45.21 at the start (it fell from 109 at 12:31). Result: 8 tests in 5 suites, 1 issue, 378.8 s. Log: scratchpad integ3.log.
    - NestedGenerationProbeTests passed, 17.4 s.
    - NoDescriptionSurfaceDiscoveryTests passed, 98.4 s.
    - OverBudgetSurfaceDiscoveryTests passed, 26.2 s.
    - SearchThenCallTests passed, 201.5 s (singleCallWeather 41.7 s; each resolve 5 s to 6 s, each model load 2 s to 9 s).
    - FilesBareSessionTests failed again, and the TOOL lines show the cause:
      CALL read {"limit": 0, "offset": 1, "format": "hashline", "path": ".../seed.txt"}
      OUTPUT {"hash": "", "lines": [], "correction": "The `limit` parameter must be a line count between 1 and 100000."}
      The model then answered "the file is empty. There are no lines to read."

    Cause of FilesBareSessionTests: a tool schema problem. `Read` refuses `limit: 0` (and `offset: 0`) with a correction, but the generation schema of `ReadArguments` did not carry the bound, so guided generation let the on-device model write `limit: 0`. The model did not retry after the correction. On 2026-09-30 the model omitted the bad value by chance.

    Fix (TDD):
    - RED: `FilesReadTests.generationSchemaBoundsOffset` and `generationSchemaBoundsLimit` (the rendered surface doc must hold `(range 1…1000000)` and `(range 1…100000)`). One run: 2 tests failed as expected.
    - GREEN: `ReadArguments.offsetRange` (1...1_000_000) and `ReadArguments.limitRange` (1...100_000). The `@Guide` of `offset` and `limit` takes `.range(...)` of them, and `Read.offsetBound` / `Read.limitBound` read the same ranges. The in-band correction stays for snippets in `runCode`. One run: 2 tests passed.
    - Root `swift test`, one run: 1881 tests in 154 suites passed, exit 0. The one warning is the SwiftPM "missing creator for mutated node ... mlx-swift_Cmlx.bundle" warning, which was in earlier logs too (unit2.log, root.log) and is not from this change.
    - `swift test --package-path IntegrationTests --no-parallel --filter 'FilesBareSessionTests'`, one run after the fix, load 39.96: passed, 8.4 s. TOOL lines: CALL read {"offset": 1, "limit": 100000, ...}, OUTPUT lines ["1:b9|pelican"], reply "1:b9|pelican".

    Files changed:
    - Sources/FoundationModelsMultitool/Capabilities/Files/Read.swift
    - Tests/FoundationModelsMultitoolTests/FilesReadTests.swift
    - IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/BareSessionScenario.swift (TOOL trace lines for each tool call and tool output of a bare session)

    New card ^gmhbe7g: the web verbs (Search `count`, Fetch `offset`, `maxCharacters`, `timeout`) have the same defect.

    Time limits: no code cause in this repo. All 4 pass at load 45 and fail at load about 100. The time goes to model loads (Router loads all 3 slots at each resolve; 14 s to 176 s each under load, 2 s to 9 s at load 45) and to model generation (singleCallWeather: 362 s with no tool call at load 100, 28 s at load 45). I did not widen a limit and did not skip a test. A person must decide for these 4 items. Options I see:
    1. Accept that the integration suite needs a machine with a low load (record the load average with each run).
    2. Change Router so that a resolve loads only the slots a session uses (a Router card, on the Router board), which helps NestedGenerationProbeTests.
    3. In SearchThenCallTests, resolve one fixture for the 4 tests, so the 3 later tests do not load the 27B profile again (at load 100 the compose/chain test spent 342 s in resolve). This does not help the first test.
    4. In NoDescriptionSurfaceDiscoveryTests, drop the "banner" and "name" measurements (18 of 27 generations, no assertion reads them), if card ^cfyj4gc no longer needs them.
    5. Widen the time limits.
  timestamp: 2026-10-01T18:53:58.914759+00:00
- actor: claude-code
  id: 01m3wd24bf0zx3tmmgdcq7z7ka
  text: |-
    ### implement — stuck
    - evidence: FilesBareSessionTests cause = `ReadArguments` schema had no bound, model wrote `limit: 0`; fixed in Read.swift with `.range` guides from shared `offsetRange`/`limitRange`, plus FilesReadTests (2 new tests, RED then GREEN) and TOOL trace lines in BareSessionScenario.swift. Root `swift test`: 1881 passed, exit 0. Integration filter run of the 5 suites (load 45.21): 4 passed, FilesBareSession failed before the fix; FilesBareSessionTests alone after the fix (load 39.96): passed. The 4 time-limit failures are machine load (load ~100: model loads 14 s to 176 s, generation steps up to 362 s); no code cause in this repo; they pass at load 45.
    - next: a person decides how the 4 time-limit suites stay stable under load (options in the comment above). The full `swift test --package-path IntegrationTests --no-parallel` was not run in this step. Card ^gmhbe7g holds the same schema defect for the web verbs.
  timestamp: 2026-10-01T18:54:06.191325+00:00
- actor: claude-code
  id: 01m3wd2yydy4h2ecfwejyr5n5m
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — FilesBareSessionTests fixed: the read schema now states the allowed ranges of offset and limit (Read.swift, FilesReadTests.swift +2 tests, BareSessionScenario.swift trace). Files are not committed.
    - time limits: NestedGenerationProbe, NoDescriptionSurfaceDiscovery, OverBudgetSurfaceDiscovery, SearchThenCall fail at load about 100 and pass at load 45 (17.4 s, 98.4 s, 26.2 s, 201.5 s). No code cause in this repo.
    - test runs: root swift test 1881 passed; FilesBareSessionTests passed after the fix. The full integration suite was not run.
    - new card: ^gmhbe7g (web verbs miss the same ranges in their schema).
    - blocker: a person must choose an option for the 4 time-limit suites (see the options in the implement comment).
  timestamp: 2026-10-01T18:54:33.421609+00:00
- actor: claude-code
  id: 01m3wdhfxq1vzwwk11z0r021b7
  text: |-
    ### decision (user, 2026-10-01) — low-load rule
    - The user chose: the integration suite needs a machine with low load. Write this rule in web.md § "Testing" and in IntegrationTests/Package.swift. No code change for the 4 time-limit suites, no wider time limits, no skips.
    - The 4 suites passed at load 45 (see iteration 1). That run is the evidence for the item "swift test --package-path IntegrationTests --no-parallel passes" on a low-load machine.
    - Next: write the rule, then /test, /commit, /review.
  timestamp: 2026-10-01T19:02:29.559160+00:00
- actor: claude-code
  id: 01m3wdvpteznmg49z3674nmpey
  text: |-
    Low-load rule written (2026-10-01), as the user decided.
    - web.md § "Testing": a new paragraph "The low-load rule", before Level 1. web.md is the web document, but its § "Testing" is where the rules for the whole `IntegrationTests/` package are (environment rule, blocked provider rule), so the rule is there. It states that the rule is for each run of the integration package, not only for the web suites.
    - IntegrationTests/Package.swift: a new doc paragraph "The low-load rule", after "The blocked provider rule" (comment text only).
    - Low load = 1-minute load average (first number of `uptime`) of 45 or less when the run starts. Record the load average with each run. A time-limit failure at high load is not a code defect; the fix is a new run at low load, not a longer time limit and not a skip. Evidence: the 4 time-limit suites failed at about 100 and passed at 45 with the same code.
    - No change to time limits, no skip, no other code change. No integration run and no root `swift test` (no Swift code changed; the Package.swift change is a comment).
    - Ticked: "Each failure is fixed, or the card records the decision of a person for it." Not ticked: the Tests item, because the full `swift test --package-path IntegrationTests --no-parallel` was not run in one run (only the filter run of the 5 suites at load 45). The /test step must run it on a low-load computer.
  timestamp: 2026-10-01T19:08:04.302204+00:00
- actor: claude-code
  id: 01m3wdw805ex91y0prttj6p1ff
  text: |-
    ### implement — changed
    - evidence: web.md (§ "Testing", "The low-load rule"), IntegrationTests/Package.swift (doc comment "The low-load rule"); ticked "Each failure is fixed, or the card records the decision of a person for it". Uncommitted iteration-1 files stay: Read.swift, FilesReadTests.swift, BareSessionScenario.swift.
    - next: /test (full integration run on a computer with load average 45 or less, record the load), then /commit, /review. Tests item stays open until that run passes.
  timestamp: 2026-10-01T19:08:21.893367+00:00
- actor: claude-code
  id: 01m3wkr6f5fdkstmaqnnfh820n
  text: |-
    ### test - red
    - load: root start 42.20 42.20/44.78/47.75 (13:09); root end 49.46/45.27/46.91 (13:13); integration start 39.54/42.40/44.62 (13:24, waited 10 min after 49.46); one sample mid-run 47.58/49.94/53.10 (14:47); integration end 30.08/40.22/48.40 (14:50).
    - root: swift test, 1881 tests, 154 suites, 6 issues, 0 known issues, 0 skipped, 0 compile warnings (only the linker note "missing creator for mutated node"). All 6 are time or timing checks: HardeningTests:187 and :153 (elapsed < 3 s, took 10 s), ShellRunnerTests:702 (lines empty while command runs), ShellRunnerTests:844 (child pid not registered while it runs), CLITelemetryShutdownTests:133 (clock.now - start < boundedEnd), ResilienceTests:328 (elapsed < promptReturnBound). Ordinary tests ran about 10 s each in that run, so the load was high. None is in Read.swift or FilesReadTests.
    - integration: swift test --package-path IntegrationTests --no-parallel, 74 tests, 35 suites, 5 issues, 0 known issues, 6 skipped (the 6 keyed live provider skips), 4899.575 s. All 5 issues are "Time limit was exceeded": AgentSurfaceDiscoveryTests:160 (300 s), HeldOutSurfaceDiscoveryTests:169 (360 s), InBandCollectionCanaryTests:124 (900 s), NestedGenerationProbeTests:84 (60 s), NoDescriptionSurfaceDiscoveryTests:155 (600 s). No web failure. No failure is in the code of this task.
    - no time limit widened, no retry, no skip, no rerun, no commit.
    - next: person decides on the time-limit failures; load rose to 53 during the run.
  timestamp: 2026-10-01T20:51:00.709519+00:00
- actor: claude-code
  id: 01m3wks1rw4tpssfz5sxed9ctz
  text: |-
    ### finish iteration 2 — red
    - implement: changed — the low-load rule is in web.md § "Testing" and IntegrationTests/Package.swift (load average 45 or less at the start).
    - test: red.
      - root swift test (load 42 to 49): 1881 tests, 6 issues, all wall-clock checks: HardeningTests.swift:187, HardeningTests.swift:153, ShellRunnerTests.swift:702, ShellRunnerTests.swift:844, CLITelemetryShutdownTests.swift:133, ResilienceTests.swift:328. These passed in earlier runs at load 60 to 110.
      - integration (load 39.5 at the start, 53 in the middle, 30 at the end): 74 tests, 5 issues, 6 keyed skips, no web failures. The 5 issues are time limits: AgentSurfaceDiscoveryTests (300 s), HeldOutSurfaceDiscoveryTests (360 s), InBandCollectionCanaryTests (900 s), NestedGenerationProbeTests (60 s), NoDescriptionSurfaceDiscoveryTests (600 s).
    - commit: not run. review: not run.
    - blocker: the integration suite failed at a start load under 45. Thus the evidence does not support the threshold of 45 in the low-load rule. The root failures are wall-clock tests that ^0hd2aq3 did not convert. A person must decide.
  timestamp: 2026-10-01T20:51:28.668231+00:00
- actor: claude-code
  id: 01m3wmbbjq69c571jdxfmdv0k8
  text: |-
    ### decision (user, 2026-10-01) — no load testing
    - The user said: "there should not be a load problem to do web search. we should also not be load testing".
    - This replaces the decision "low-load rule". Remove the low-load rule from web.md and IntegrationTests/Package.swift.
    - Principle: no test checks the speed of the machine.
      - A check of the form `elapsed < X` on the real clock changes to an injected clock or a wait for an event (the method of ^0hd2aq3). Root tests: HardeningTests.swift:153 and :187, ShellRunnerTests.swift:702 and :844, CLITelemetryShutdownTests.swift:133, ResilienceTests.swift:328.
      - A `.timeLimit` on a model-driven integration test is a hang guard only. It must not fail a test that makes progress on a busy machine.
    - Keep the read-schema fix (Read.swift, FilesReadTests.swift, BareSessionScenario.swift).
  timestamp: 2026-10-01T21:01:28.535006+00:00
- actor: claude-code
  id: 01m3wmp0jg7j3cshxm1s0fe431
  text: |-
    Research (2026-10-01, "no load testing" decision).

    Root real-clock speed checks found (upper bounds on real time, and polls with a short real deadline):
    - HardeningTests: `executionTimeLimitBoundaryTerminatesNearConfiguredLimit` and `executionTimeLimitBelowAnInjectedInterpretersOwnLimitIsEnforced` (`elapsed < 3 s`). The timeout message of `JSCInterpreter` names the armed limit ("Execution exceeded the 0.3s time limit."), thus the test can read the armed limit from the output. The two cancellation tests (`< 3 s`) are the same kind: with a 10 s limit, `MultiTool` still throws `CancellationError` after the watchdog, because it checks `Task.isCancelled` after the run. Fix: an execution limit that no test reaches, and a hang guard.
    - ShellRunnerTests: `waitForLines` (3 s poll) and `waitForProcessCount` (5 s poll). The live view gets a chunk BEFORE the store write, thus the store poll stays; the deadline becomes the hang guard.
    - CLITelemetryShutdownTests `flushThatDoesNotEndIsBounded`: `CLIExitPath.wait(atMost:)` sleeps on `Task.sleep`. Fix: inject a clock into `CLIExitPath` (the method of ^0hd2aq3).
    - ResilienceTests `connectAttemptTimeoutBoundsRealWallClockTimeEvenWhenTransportHangs`: the per-attempt timeout sleeps on `Task.sleep`, not on `clock`. Fix: a new internal `connectAttemptClock` on `MCPServer`, beside `clientQueueClock`.
    - Also: SuspendedContextTests (2 x `< promptResponseBound`), MCPServerCallTests (`< promptReturnBound`), ShellExecuteTests (2 x `< doesNotBlockUpperBound`), JSCInterpreterTests DIAGNOSTIC (`< 3 s`), ShellHistoryOpsTests poll (10 s), SurfaceRefresherTests poll (20 s), MCPServerCallTests/MCPSessionSweepTests `notificationTimeout` (5 s), TestPoll.deadline (10 s, used by many polls), SandboxGlobalsFixtures `awaitProgress` and `scriptedRunSettlementSeconds` (10 s).
    - Lower bounds (`elapsed >=`) do not fail on a busy machine; they stay.

    Integration `.timeLimit`: 28 traits, values 1 to 15 minutes, in 27 suites, plus `LiveSearch.timeLimitMinutes` and `bareSessionTimeLimitMinutes`.
  timestamp: 2026-10-01T21:07:17.712167+00:00
- actor: claude-code
  id: 01m3wnb20tysjs3y7vhz80ysbt
  text: |-
    Implementation (2026-10-01, "no load testing" decision). Not committed.

    Rule text: web.md § "Testing" and IntegrationTests/Package.swift: the low-load rule is gone. In its place: "No test checks the speed of the machine." A time check uses an injected clock or an event; a `.timeLimit` on a model-driven test is a hang guard only. web.md also: "Each test has `.timeLimit(IntegrationHangGuard.timeLimit)`" (was 1 minute), and the unit hang guards are named.

    Hang guards:
    - Integration: `IntegrationHangGuard.timeLimit` = 30 minutes (IntegrationTests/.../Support/IntegrationHangGuard.swift). All 28 `.timeLimit` traits in 28 suites use it. Deleted constants: overBudget/agentSurface/unknownToolHint/operationTool/webResearch/retrievalText/heldOut/noDescription TimeLimitMinutes, bareSessionTimeLimitMinutes, LiveSearch.timeLimitMinutes.
    - Unit: `TestHangGuard.timeLimit` = 10 minutes (Tests/Support/MultitoolTestSupport/TestHangGuard.swift). `TestPoll.deadline` 10 s -> 300 s (hang guard). New `TestPoll.lastReading(of:until:)`.

    Root conversions:
    - HardeningTests :153/:187: the timeout text names the armed limit; test asserts "Execution exceeded the 0.3s time limit." (no elapsed). Two cancellation tests: execution limit and slow tool of one day, hang guard; no elapsed.
    - ShellRunnerTests :702/:844: waitForLines and waitForProcessCount wait for the event with TestPoll (no 3 s / 5 s deadline).
    - CLITelemetryShutdownTests :133: new internal `CLIExitPath.init(...clock:)`; GatedClock; asserts recordedSleeps == [testBound]. RED (compile) then GREEN.
    - ResilienceTests :328: new internal `MCPServer.connectAttemptClock` (failConnectAttemptAfterTimeout sleeps on it); GatedClock; asserts recordedSleeps == [hangingConnectTimeout]. RED (compile) then GREEN.
    - Also: SuspendedContextTests (2 x promptResponseBound -> latch event / outcome .cancelled), MCPServerCallTests (promptReturnBound removed; the thrown timedOut names the bound), ShellExecuteTests (doesNotBlockUpperBound removed; sleep of one day + hang guard), JSCInterpreterTests DIAGNOSTIC (< 3 s removed; CancellationError vs InterpreterError, limit of one day + hang guard), ShellHistoryOpsTests (10 s poll -> TestPoll; live run sleep 5 s -> one day), SurfaceRefresherTests (20 s logReadbackDeadline -> TestPoll.deadline), MCPServerCallTests/MCPSessionSweepTests notificationTimeout 5 s -> TestPoll.deadline, SandboxGlobalsFixtures (scriptedRunSettlementSeconds 10 -> TestPoll.deadline; awaitProgress -> TestPoll; elicitation watch sleeps between reads), DropObservingTransportTests and ConcurrencyGateTests `.minutes(1)` -> TestHangGuard.timeLimit.
    - Kept (lower bounds, cannot fail on a busy machine): ShellRunnerTests `sleep 1` >= 900 ms, ScenarioFixtureTests >= delay, MCPServerCallTests elapsed >= inner bound, SuspendedContextTests 600 ms alive window.

    Found and not changed (speed checks on purpose, for a person): SelectionForkPerCallTests asserts second <= first (real clock); ScenarioGrading `nestedRefusalInTime` (refusal <= 5 s, NestedGenerationProbeTests). Not converted: ResilienceTests explicitConnectDuringInFlightReconnectWins depends on real 10 s / 6 s waits; IntegrationPoll deadlines of ShellBackgroundRunner and CLISignalExitTests.

    Root `swift test` (one run): 1881 tests in 154 suites passed, exit 0; only warning is the known SwiftPM "missing creator for mutated node". Integration run of the 28 suites started.
  timestamp: 2026-10-01T21:18:47.322996+00:00
- actor: claude-code
  id: 01m3wp0fk1w93715r286fgp4p0
  text: |-
    ### implement — changed
    - evidence: root `swift test` (one run): 1881 tests in 154 suites passed, exit 0, only the known SwiftPM warning "missing creator for mutated node". Integration (one run, detached): `swift test --package-path IntegrationTests --no-parallel --filter '<the 28 suites whose .timeLimit changed>'`: 46 tests in 28 suites passed after 663.8 s, exit 0; 6 keyed tests skipped by the environment rule (no key set); no web failure, no blocked provider. Log: scratchpad integ-tm4x2hp.log. RED then GREEN for the two new clock seams (CLIExitPath clock, MCPServer.connectAttemptClock). Hang guards: IntegrationHangGuard.timeLimit = 30 min; TestHangGuard.timeLimit = 10 min; TestPoll.deadline = 300 s. Read-schema fix kept (Read.swift, FilesReadTests.swift, BareSessionScenario.swift).
    - not changed, for a person: new card ^kdtrmhv (SelectionForkPerCallTests second <= first; ScenarioGrading nestedRefusalInTime 5 s; ResilienceTests explicitConnectDuringInFlightReconnectWins real waits; IntegrationPoll deadlines).
    - next: /review. The Tests item (full `swift test --package-path IntegrationTests --no-parallel`) stays open: this step ran the 28 changed suites only.
  timestamp: 2026-10-01T21:30:29.345937+00:00
- actor: claude-code
  id: 01m3wqgrdnaexbe0r9cy6rhgps
  text: |-
    ### test - green
    - evidence: root `swift test`: 1881 tests in 154 suites passed after 11.721 s. 0 issues, 0 known issues, 0 skipped. One build-system line "missing creator for mutated node" for mlx-swift_Cmlx.bundle; no compiler warning.
    - evidence: `swift test --package-path IntegrationTests --no-parallel`: 74 tests in 35 suites passed after 685.964 s. 0 failures, 0 issues, 0 known issues. 6 skips, all keyed live providers (braveAPI, tavily, exa, serper, kagi, searxng), allowed by the written exception. The live web test passed.
    - no code change made in this step; no commit; no load gate; no retries.
    - logs: scratchpad root-test.log and integration-test.log
    - next: review
  timestamp: 2026-10-01T21:56:51.253613+00:00
position_column: doing
position_ordinal: '80'
title: Integration tests fail on time limits and a wrong model answer under machine load
---
## What
One run of `swift test --package-path IntegrationTests --no-parallel` on 2026-10-01 (work of ^kghyac5) had 5 failures that are not on a web search path. The load average was about 100 from other sessions. The output is in the scratchpad file `integ2.log` of that session.

- `FilesBareSessionTests`: the model answered "no lines in the file". This is a wrong answer, not a time limit and not a network failure.
- `NestedGenerationProbeTests`: 60 s time limit.
- `NoDescriptionSurfaceDiscoveryTests`: 600 s time limit.
- `OverBudgetSurfaceDiscoveryTests`: 360 s time limit.
- `SearchThenCallTests`: 720 s time limit.

In the run before it, `CLISmokeTests` (600 s) and `AgentSurfaceDiscoveryTests` (300 s) failed on time limits, and they passed in this run. Each model step took 15 s to 3 min under load.

## Decide
- Do these tests fail on a quiet machine? Run the suite one time when the load average is low, and record the result.
- If they pass on a quiet machine: how the real-model tests stay stable under load, without a wider time limit and without a skip, or the card records the decision of a person.
- `FilesBareSessionTests`: is the wrong answer a prompt or tool problem, or a model limit?

Do not skip tests and do not widen time limits without a decision on this card.

## Acceptance Criteria
- [x] The cause of each of the 5 failures is recorded on this card.
- [x] Each failure is fixed, or the card records the decision of a person for it.

## Tests
- [ ] `swift test --package-path IntegrationTests --no-parallel` passes.