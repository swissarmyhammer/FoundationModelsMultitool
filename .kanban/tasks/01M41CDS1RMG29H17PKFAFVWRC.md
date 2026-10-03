---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41v39kzpvg6n14s49e57nbx
  text: |-
    ### Research and implementation
    - FoundationModelsExtras resolves at 130eb40 (the pushed form of e7e09a6). Before the change, 3 of the 4 tests failed fast (MCPServerCallTests progress case, RunBindingTests, HostAndEmitterTests). The LostCallTests failure (about 320 s wait) is recorded on this card; it was not run red again.
    - Extras facts that make a read with no wait correct: `ToolRun.settle` awaits `RunEventFunnel.settleRun(with:)`, and that awaits `enqueue(terminal).value`. Thus the terminal event is on the sink of the mounted run before the call returns or throws. Note: `settleRun` drops a `.succeeded` terminal when the run posted no event before. A `.lost` or `.failed` terminal always goes.
    - MCPServerCallTests `progressThenExactlyOneCompleted` and LostCallTests `aTransportDroppedBeforeTheCallThrowsLost` now mount with `postingTo: RecordingEventSink()` and read `sink.events` one time after the call. LostCallTests no longer opens the session event stream and no longer waits for a deadline: it runs in 0.069 s.
    - RunBindingTests now expects the progress details `alpha ran`, `beta ran`, and the inner terminal details `alpha-result`, `beta-result`. HostAndEmitterTests now expects `[recorder ran, recorder-result]` in order (new file constant `recorderResult`; `renderedRecorderResult` is built from it).
    - `MCPCallProbe.mountedRunToCompletion` now takes a sink that is not optional: each caller passes one, so the branch with no sink was dead. Its doc states why the mount with no sink is not used.
    - `settledEvents(on:count:deadline:)` in StubRouterFixtures.swift had no caller left; deleted.
    - LostCallTests: the two `guard case .lost? ... return` in tests became `#expect(Self.isLost(thrown), ...)` (swift optionals rule: never `guard` in a test). New private helper `isLost(_:)`.
    - Discovered: `noAutoRetryAfterReconnectEvenForIdempotentHintedTool` sleeps `autoRetryGraceWindow` (300 ms) to learn that no retry came. Not in the scope of the four tests; filed as ^2v197d8.
    - Stale doc, not changed (out of scope): the doc of `recordedOperationEvents(of:ofKind:)` says that nothing public of Router accepts an `OperationEventSink`, but `ToolContext.mount(_:op:as:postingTo:)` is public.
  timestamp: 2026-10-03T21:35:36.575510+00:00
- actor: claude-code
  id: 01m41v3cgqfmbvswaqr0q2r6t5
  text: |-
    ### implement — changed
    - evidence: 6 files — Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift, LostCallTests.swift, RunBindingTests.swift, HostAndEmitterTests.swift, Support/MCPCallProbeTool.swift, Fixtures/StubRouterFixtures.swift. `swift build --build-tests` clean (no warning in Sources or Tests). `swift test --filter 'MCPServerCallTests|LostCallTests|RunBindingTests|HostAndEmitterTests|InnerTerminalEventTests'`: 23 tests in 5 suites passed. `swift test`: 1808 tests in 151 suites passed, 0 failed, 0 skipped. No library code changed; no clock added.
    - next: /review. Follow-up ^2v197d8 (300 ms grace window in the no-auto-retry test).
  timestamp: 2026-10-03T21:35:39.543693+00:00
- actor: claude-code
  id: 01m41vfpc4wegenmzcsqem24bx
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 3202bf5). 0 findings (0 confirmed, 0 refuted; 7 attempted, 0 failed). 6 Swift test files reviewed. 6 `.kanban/` files not reviewed (.reviewignore). The commit renames no file, so no file-scoped review was necessary. The task has no earlier review findings.
    - next: none. Task moved to done.
  timestamp: 2026-10-03T21:42:22.852871+00:00
- actor: claude-code
  id: 01m41vg95593az8kvsebt68h4c
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 test files
    - test: green — swift test 1808 tests in 151 suites passed; Extras at 130eb40
    - commit: 3202bf5
    - review: clean — 0 findings
  timestamp: 2026-10-03T21:42:42.085784+00:00
depends_on: []
position_column: done
position_ordinal: ffffa380
title: Update four tests that read an inner terminal through the mount sink, after the Extras fix e7e09a6
---
## What
FoundationModelsExtras commit e7e09a6 (local, not pushed yet; task ^1ch4dhb) changes `MountedRunUpstreamSink`. A synchronous call that `ToolContext.mount(_:op:as:)` mounted now sends its terminal event to the mounting run as a `.progress` event with the same detail. Before, it went up as a `.completed` event of the mounting run.

Four tests in this package read the inner terminal through the mount sink of the captured stub-run context (`makeStubRun().context`). With the local Extras (`swift package edit`), they fail:
- `MCPServerCallTests` "a mounted call posts its progress events then exactly one completed, in that order" — `kinds.last == .completed` and `events.last?.outcome == .succeeded` fail.
- `LostCallTests` "a transport dropped before the call throws lost, and the run posts exactly one completed event with outcome lost" — no `runSettled` event comes; the test waits about 320 seconds, then `completed.count` and `.lost` fail.
- `RunBindingTests` "two parallel inner calls under Promise.all carry distinct completion tokens and post to the same session" — the progress details now also hold the details of the two inner terminals.
- `HostAndEmitterTests` "runCode casts to ForkableTool off an any Tool existential, and the erased forked() return downcasts and serves the registry" — the same cause.

These tests pin the old route, which is the defect of ^1ch4dhb: an inner terminal took the place of the terminal of the mounting run.

Subtasks:
- [x] After the user pushes FoundationModelsExtras and runs `swift package update` here, read the inner terminal in MCPServerCallTests and LostCallTests from a sink of the inner run itself (`mount(_:op:as:postingTo:)`, as `concurrentCallsAreDistinguishableByCorrelationID` does), so that each test keeps its intent: the inner run gives its progress events and then exactly one terminal event.
- [x] In RunBindingTests and HostAndEmitterTests, expect the progress details of the inner tools and the details of the inner terminals, or filter to the details that the tools posted.

## Acceptance Criteria
- [x] The four tests pass against FoundationModelsExtras with e7e09a6.
- [x] No test waits for a deadline to learn that an event did not come.

## Tests
- [x] `swift test --filter 'MCPServerCallTests|LostCallTests|RunBindingTests|HostAndEmitterTests|InnerTerminalEventTests'` passes. `swift test` passes. #defect #extras #timeouts