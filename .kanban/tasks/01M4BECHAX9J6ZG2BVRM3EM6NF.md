---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4bf1zyv9a2z9nc92tw79g4z
  text: |-
    ### test - what I found and changed
    - Cause confirmed in Router commit c30d1d41. The run journal writes the first progress event of a run as its own row. Each next progress event of the same run goes into an open row in memory. The open row is written only when a different entry comes, or when `RoutedSession.close()` runs. Each event stays whole as one segment in the row, so no event is lost and none is joined.
    - The fixture `CollectingTranscriptRecorder.operationEvents` already reads every segment of every row. The tests read while the session was open, so the open row was not yet written. This is why they saw 1 progress event, or 1 of 3.
    - Router behavior is correct. Production code is not changed.
    - Fix: new fixture `settledOperationEvents(of:ofKind:)` in Tests/FoundationModelsMultitoolTests/Fixtures/StubRouterFixtures.swift. It closes the session, then reads the recorder. The read returns every progress event in post order. The doc comment of `recordedOperationEvents(of:ofKind:correlatedTo:)` now says that a read while the session is open sees only the first progress event of a run.
    - Tests changed to read with `settledOperationEvents`. Each keeps its full assertion on content and order. No assertion expects fewer events.
      - SandboxGlobalsTests: "notify() and progress() reach the session's sink on the run's own correlation" (still expects ["starting the sweep", "half way"], and the correlation check on all events)
      - SandboxGlobalsTests: "a long snippet loop's notices reach the sink in the order the snippet enqueued them" (still expects step 1 to step 4, then finished)
      - HostAndEmitterTests: "runCode casts to ForkableTool ..." (still expects [recorder ran, recorder-result])
      - RunBindingTests: "two parallel inner calls under Promise.all ..." (still expects the 4 details)
      - MCPServerCallTests: "a progress notification during a call reaches ToolContext.progress ..." (still expects 3 events on the run's correlation)
      - FileChangeEventAbsenceTests: "a notify() beside a write ..." (still expects 1 notice and 1 change set, in the run's correlation). The 300 s poll is gone: close() writes the row before it returns, so no wait is needed.
    - Result: the 5 suites pass (56 tests). Full `swift test`: 2238 tests in 194 suites, 0 failures. FileChangeEventAbsenceTests now takes 0.1 s, not 307 s.
  timestamp: 2026-10-07T15:17:35.323449+00:00
position_column: todo
position_ordinal: '8380'
title: 'tests: six progress-event tests fail after Router c30d1d41 merges progress rows'
---
## Problem

After `swift package update` (2026-10-07), Router resolves at main `6bdf9ae7`. Router commit `c30d1d41` (card `^zze1067` in Router) merges consecutive progress events of one operation into one journal row. The open row stays in memory until a different event, a different entry or `close()` writes it.

The test fixture `recordedOperationEvents` (Tests/FoundationModelsMultitoolTests/Fixtures/StubRouterFixtures.swift) reads the journal through `CollectingTranscriptRecorder`. Thus a test that reads more than one progress event while the run is open now sees fewer events.

These tests fail on `HEAD` with no local change (checked with `git stash` during the work on `^2ny3k6k`):

- SandboxGlobalsTests: "notify() and progress() reach the session's sink on the run's own correlation"
- SandboxGlobalsTests: "a long snippet loop's notices reach the sink in the order the snippet enqueued them"
- HostAndEmitterTests: "runCode casts to ForkableTool off an any Tool existential, and the erased forked() return downcasts and serves the registry"
- RunBindingTests: "two parallel inner calls under Promise.all carry distinct completion tokens and post to the same session"
- MCPServerCallTests: "a progress notification during a call reaches ToolContext.progress with the run's correlationID" (1 of 3 events seen)
- FileChangeEventAbsenceTests: "a notify() beside a write posts a plain-text progress event the envelope tells apart" (waits 300 s on the poll, then fails). This one was not run on the stashed tree; it reads progress events the same way.

## Work

1. Read how Router c30d1d41 writes a merged row (segments of one row, and when the open row is written).
2. Make the fixture read every progress event the session posted, merged row or not, or read the events at a point where the open row is written.
3. Do not change a test to expect fewer events than the code posts.

## Acceptance

- The six tests pass. `swift build --build-tests` and `swift test` pass with no new warnings. #tests