---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3x2edszkvdrdsz5gv4wsez9
  text: |-
    ### Decision of a person — recorded for each item

    The user decided this for all items: "we should also not be load testing" and "no test checks the speed of the machine". The decision is recorded on ^tm4x2hp. The rule is in web.md, section "Testing". Thus no item stays as a real-clock speed check. Each item gets this decision:

    - `SelectionForkPerCallTests` `second <= first`: CONVERT. Do not compare two real durations. Assert the mechanism that the second call saves (fork reuse, model load count, cached prefix, or fewer turns) with a count or a recorded event.
    - `ScenarioGrading.nestedRefusalInTime` (`integrationNestedRefusalTimeLimit`, 5 s real clock) in `NestedGenerationProbeTests`: CONVERT. Assert by order of events or by outcome: the refusal `waitInsideOpenSubmission` comes before the outer turn ends, and the nested call is not queued. No real-time bound. The `.timeLimit` hang guard stays.
    - `ResilienceTests.explicitConnectDuringInFlightReconnectWins`: CONVERT. Gate it with `MCPServer.connectAttemptClock` and `GatedClock` (pattern of 05aed3a). Replace the 6 s sleep with a wait for an event.
    - `ShellBackgroundRunner` (`IntegrationPoll`) and `CLISignalExitTests` (`TestPoll`) short real deadlines: CONVERT. A poll deadline is a hang guard only. Use one shared hang-guard poll deadline (as `TestPoll.deadline`, 300 s since 05aed3a), defined one time, or wait for the event directly.
    - Also: search the root and integration tests again for other real-clock speed checks of the same kind, and convert them the same way.
  timestamp: 2026-10-02T01:07:49.183545+00:00
- actor: claude-code
  id: 01m3x3701wb2bj34b9sm09tf5j
  text: |-
    Progress (implement):
    - nestedRefusalInTime -> nestedRefusalAtOnce. The probe tool reads the generation queue of the model at the refusal (`GenerationQueueReading`: isRunning, waitingCount). The check holds when the outer submission still runs and no job waits. `integrationNestedRefusalTimeLimit` and its seconds constant are deleted. ScenarioGradingTests: red (compile) then green, 16 tests.
    - SelectionForkPerCallTests: the `second <= first` check and the `Date()` timing are deleted. The mechanism (one cached root for both calls, one forked child per call) stays asserted by the counts on the recorded transcript.
    - ResilienceTests.explicitConnectDuringInFlightReconnectWins: attempt timeout on a GatedClock, queue bounds on a second GatedClock. New `GatedClock.open(sleepsOf:)` ends only the straggler bound, so the explicit connect cannot race its own disconnect. The 6 s sleep is replaced by `await reconnect.value` after the attempt clock opens. Test time went from about 11 s to 0.06 s.
    - Same file, same kind: `makeServer` default attempt clock is now a GatedClock that no test opens. The late-resolving tests use ManualClock for the attempt (the timeout must fire). freshAttemptWaits... uses two GatedClocks and an event wait instead of the 800 ms sleep. The factory test waits for the dispose event instead of a 200 ms sleep before a positive check.
    - Discovery: `GatedClock.open()` alone was not safe for the explicit-connect test. It ends the 500 ms disconnect bound and the 5 s straggler bound together, so the fresh `client.connect` could run before the queued `client.disconnect`. That is why `open(sleepsOf:)` was added.
    - ResilienceTests + ScenarioGradingTests: 29 tests, all pass.
  timestamp: 2026-10-02T01:21:14.300357+00:00
- actor: claude-code
  id: 01m3x5n1xrhmcjg4vj7nefttap
  text: |-
    Step: implement. Outcome: changed. Not committed.

    Each item is converted. No test checks the speed of the machine now.
    - SelectionForkPerCallTests: the `second <= first` check on two real durations is removed. The counts assert the mechanism: one cached root session, and one fork for each call.
    - nestedRefusalInTime: replaced by `nestedRefusalAtOnce`. The tool reads the generation queue at the refusal. "At once" means the queue runs the outer submission and no job waits (`isRunning == true`, `waitingCount == 0`). `integrationNestedRefusalTimeLimit` is removed. The `.timeLimit` hang guard stays.
    - ResilienceTests.explicitConnectDuringInFlightReconnectWins: the attempt clock and the queue clock are `GatedClock`s. The 6 s sleep is replaced by waits for events. New `GatedClock.open(sleepsOf:)` ends only the straggler bound.
    - ShellBackgroundRunner and CLISignalExitTests: the short deadlines are removed. `IntegrationPoll.deadline` (20 min) is the one shared hang-guard deadline. CLISignalExitTests uses `TestPoll.deadline`.

    More items found and fixed the same way:
    - ResilienceTests: the late attempt tests, the factory test and the straggler test open the timeout only after the gated step is in flight (new `GatedConnectTransport.connectWasCalled`, `GatedTransportFactory.makeWasCalled`). This fixed a race that a full parallel run showed.
    - ScenarioRunner: the 8 min and 12 min mail-answer deadlines now use `IntegrationPoll.deadline`.
    - CLITelemetryShutdownTests: the exit paths use a `GatedClock` for the flush bound.
    - MultiToolExecutionTests and JSCInterpreterTests: the `Promise.all` concurrency tests meet at the existing `Rendezvous`, not at an overlap of two real windows. The watchdog tests have no duration bound now.
    - StubRouterFixtures.settledEvents and ScriptedServerSelfTests use `TestPoll.deadline`.

    Follow-up cards (need a production clock seam): ^3np5yzj (JSC watchdog), ^zbhjc99 (MCPTestSupport connect clock), ^pfvdg5b (other short windows).

    Tests (each run once):
    - `swift test --filter` on the affected root suites: 142 tests in 9 suites passed. After the race fix: 90 tests in 4 suites passed.
    - Root `swift test`: 1888 tests in 155 suites passed. (The first run before the race fix failed in one test.)
    - Integration, detached: 7 tests in 6 suites passed.

    Ready for /review.
  timestamp: 2026-10-02T02:03:52.120320+00:00
- actor: claude-code
  id: 01m3x6v0q23pdkw6avh0p2p1hc
  text: |-
    ### test - green (with the accepted web exceptions)
    - root: `swift test` one run, exit 0. 1888 tests in 155 suites passed. 0 issues, 0 known issues, 0 skipped. 0 warnings from repo code (only dependency cache and Metal C++17 notes).
    - integration: `swift test --package-path IntegrationTests --no-parallel` one run. 74 tests in 35 suites, 15 issues (5 known issues), 6 skipped.
    - skipped (6, keyed live provider exception): braveAPI, tavily, exa, serper, kagi, searxng (key or URL not set).
    - known issues (5, blocked provider rule): BraveHTMLLiveTests 2, DuckDuckGoHTMLLiveTests 2, KeyedFallbackLiveTests 1.
    - web failures where no provider gave results (braveHTML blocked HTTP 429, duckDuckGoHTML blocked by challenge page; accepted on ^kghyac5), 4 tests, 10 issues: DuckDuckGoHTMLLiveTests "a site search for developer.apple.com gives only hits under apple.com" (1); KeyedFallbackLiveTests "a braveAPI key that is not valid gives the refused-key note..." (4); KeylessChainLiveTests "the keyless chain gives hits..." (3); WebRunCodeLiveTests "the goal snippet returns 1 to 3 pages..." (2, empty result decode).
    - other failures: none. No code changed, no rerun.
    - next: review.
  timestamp: 2026-10-02T02:24:36.066686+00:00
position_column: doing
position_ordinal: '80'
title: Remaining real-clock time checks after the "no load testing" decision
---
## What
Card ^tm4x2hp applied the user decision "no test checks the speed of the machine" to the root tests and to each integration `.timeLimit`. These real-clock time checks stay, and a person must decide each one:

- `IntegrationTests/.../SelectionForkPerCallTests.swift`: asserts `second <= first` on two real durations. It is a speed check on purpose (a measurement of the second call).
- `Tests/Support/ScenarioGrading/ScenarioGrading.swift` check `nestedRefusalInTime`: the refusal of a nested generation must come in `integrationNestedRefusalTimeLimit` (5 s, real clock), in `NestedGenerationProbeTests`. A refusal at once is the defect it finds. A busy machine can make it fail.
- `Tests/FoundationModelsMultitoolTests/ResilienceTests.swift` `explicitConnectDuringInFlightReconnectWins`: depends on a real 10 s per-attempt timeout and a 6 s sleep. `MCPServer.connectAttemptClock` (new in ^tm4x2hp) can gate it.
- `IntegrationTests/.../Support/ShellBackgroundRunner.swift` and `CLISignalExitTests.swift`: `IntegrationPoll` / `TestPoll` waits with their own short real deadlines.

## Decide
- For each item: convert it to an injected clock or an event, or keep it with a written decision.

## Acceptance Criteria
- [ ] Each item above is converted, or the card records the decision of a person for it.

## Tests
- [ ] Root `swift test` passes.