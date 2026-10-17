---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m55f4wqqs9nsgavek4m1q54s
  text: 'Research. `performConnectAttempt(factory:timeout:)` starts two unstructured tasks: the attempt and the timeout. The first to resume the `SingleResume` wins. Nothing cancels or awaits the other one. The connect returns at once when the timeout wins. Plan: a new double `HeldConnectTransport`. Its `connect()` opens an arrival gate, records a cancel in a gate, and ends only when the test opens its release gate (a cancel does not end it). The test: one attempt, the timeout on a `GatedClock`. The test waits for the arrival and the armed timeout, opens the clock, and then waits for the first of three events: the connect ended, the loser recorded a cancel, the loser ended. It requires that the connect ended first and that the loser is still open. The teardown releases the loser and waits for its end. Limit: a change that awaits the loser WITHOUT a cancel cannot fail without a hang. Each event that the test can see before the await point also comes before the return in the correct code, and each event after the await point does not come. Thus that case hangs, and the card asks to state it.'
  timestamp: 2026-10-17T17:39:25.559783+00:00
- actor: claude-code
  id: 01m55fpz11jy3n3419bcdm2t3e
  text: |-
    Implementation landed. New double Tests/FoundationModelsMultitoolTests/Support/HeldConnectTransport.swift: its connect opens connectArrival, holds in a task of its own that no cancel reaches, opens connectCancel on a cancel, opens connectEnd when it ends, and ends only after release(). New test ResilienceTests.aLosingConnectAttemptIsNotAwaited: one attempt with its timeout on a GatedClock. The test waits for the armed timeout and the held connect, opens the clock (the timeout wins), and then waits for the first of three events: the connect ended, the loser cancel record, the loser end. It requires that the connect ended, and expects no cancel and no end of the loser, and expects backoffExhausted. The teardown (ensuring) releases the loser and waits for its end on each path. The new helper startAttemptHeld(at:attemptClock:connect:) is shared with orphanStraggler, which had the same wait.

    Mutation check (one time each, reverted, Sources diff is empty after the revert):
    - Cancel and then await the losing attempt in performConnectAttempt: the test failed at once (0.002 s) at the requireOpen: "the connect did not return while the losing attempt held its connect". No hang.
    - Await the losing attempt with no cancel: the test hangs. The test process was still running after 300 s and I stopped it. This is the case that no form of the test can catch without a hang. Each event that the test can see before such an await also comes before the return of the connect as it is now. No event comes after such an await until the loser ends, and only the test can end the loser. The one signal that the await itself makes is a priority escalation of the awaited task, and that depends on the priorities of the tasks, not on the code. Thus the closest form is this test: it catches a cancel of the loser (also with an await after it) and an end of the loser before the return, and it hangs on an await with no cancel.

    Full run: swift test, exit code 0, "Test run with 2459 tests in 214 suites passed", XCTest "Executed 0 tests, with 0 failures", 0 lines of SWIFT TASK CONTINUATION MISUSE.
  timestamp: 2026-10-17T17:49:17.729692+00:00
- actor: claude-code
  id: 01m55fq1jmqdcafay9pyq5bk4s
  text: |-
    ### implement — changed
    - evidence: 2 files. Tests/FoundationModelsMultitoolTests/Support/HeldConnectTransport.swift (new), Tests/FoundationModelsMultitoolTests/ResilienceTests.swift (new test aLosingConnectAttemptIsNotAwaited, shared helper startAttemptHeld). Mutation cancel then await: fails at once. Mutation await with no cancel: hangs, and no form can catch it (reason in the comment above). swift test exit 0, 2459 tests in 214 suites passed, 0 continuation misuse lines.
    - next: review
  timestamp: 2026-10-17T17:49:20.340279+00:00
- actor: claude-code
  id: 01m55fsdg3ch98w27crh1ds8dd
  text: |-
    ### test - green
    - evidence: git diff --stat -- Sources is empty. swift test exit code 0. Swift Testing summary: Test run with 2459 tests in 214 suites passed after 4.410 seconds. SWIFT TASK CONTINUATION MISUSE lines: 0. No test failed. No test was skipped (the word skipped appears only in test names).
    - note: The log has one build tool line, "missing creator for mutated node" for the mlx-swift_Cmlx.bundle path. It comes from the dependency bundle, not from our source or tests.
    - next: review.
  timestamp: 2026-10-17T17:50:38.083574+00:00
- actor: claude-code
  id: 01m55ft5wj9evbc0m8wxymyvkh
  text: |-
    ### commit — changed
    - evidence: f26d697 test: check that a losing MCP connect attempt is not awaited
    - next: review. The test cannot catch the case "await the loser with no cancel"; no form of the test can fail there without a hang.
  timestamp: 2026-10-17T17:51:03.058296+00:00
- actor: claude-code
  id: 01m55g0ahebxxzpw1c424rjfjf
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit 92225d6). 1 finding: Tests/FoundationModelsMultitoolTests/Support/HeldConnectTransport.swift:86 (reuse/reuse). The engine confirmed 1 and refuted 1. The .kanban files are not reviewed because of an ignore rule.
    - next: Put the never-connects send and the empty receive in one shared stub helper. HeldConnectTransport and HangingTransport must both use it. Keep the connect behavior of each double separate. Then run the review again.
  timestamp: 2026-10-17T17:54:24.430590+00:00
- actor: claude-code
  id: 01m55g0vxvz2jfqcphbram6svt
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 2 test files (aLosingConnectAttemptIsNotAwaited; HeldConnectTransport; startAttemptHeld)
    - test: green — swift test, exit 0, 2459 passed, 0 failed, 0 skipped, 0 continuation misuse lines; Sources diff empty
    - commit: 92225d6 (the commit comment names f26d697, the sha before the amend)
    - review: findings — Tests/FoundationModelsMultitoolTests/Support/HeldConnectTransport.swift:86
  timestamp: 2026-10-17T17:54:42.235763+00:00
- actor: claude-code
  id: 01m55g7g9cn35pbjy3znpk5q0p
  text: 'Finding fixed. New file Tests/FoundationModelsMultitoolTests/Support/NeverConnectingTransport.swift: the protocol NeverConnectingTransport (Actor, Transport) and an extension of it. The extension supplies disconnect() (empty), send(_:) (throws MCPError.internalError("\(Self.self) never connects")) and receive() (an empty stream). The message names the conforming type, thus each double keeps its old text and no label parameter is necessary. The pattern is the same as WrappingTransport. HangingTransport and HeldConnectTransport now conform to NeverConnectingTransport, and their own stubs and the import of Foundation.Data are removed. Each double keeps its own connect(). Search: no other test transport in Support has a never-connects send or an empty receive (the wrapping doubles delegate or return a finished stream). Nothing reads the error text. Production code did not change.'
  timestamp: 2026-10-17T17:58:19.692202+00:00
- actor: claude-code
  id: 01m55g7k3bdawebkyxe9chd1a4
  text: |-
    ### implement — changed
    - evidence: 3 files. Tests/FoundationModelsMultitoolTests/Support/NeverConnectingTransport.swift (new, the shared stub), Support/HangingTransport.swift, Support/HeldConnectTransport.swift. No other double had the stub. Findings checked 1/1. swift test one time: exit code 0, "Test run with 2459 tests in 214 suites passed after 4.884 seconds", XCTest "Executed 0 tests, with 0 failures", 0 lines of SWIFT TASK CONTINUATION MISUSE. The one warning is the known mlx-swift_Cmlx.bundle build line.
    - next: review
  timestamp: 2026-10-17T17:58:22.571809+00:00
- actor: claude-code
  id: 01m55gacx4tp3z3w5xcvrbpr3a
  text: |-
    ### test - green
    - evidence: swift test ran one time. Exit code 0. Swift Testing: "Test run with 2459 tests in 214 suites passed after 5.387 seconds." The count of SWIFT TASK CONTINUATION MISUSE lines is 0.
    - note: One build tool message appeared: "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It comes from the dependency bundle, not from project code. No compiler warning came from project code.
    - no code was changed in this step. No test was changed, deleted or skipped.
    - next: review
  timestamp: 2026-10-17T17:59:54.532807+00:00
- actor: claude-code
  id: 01m55gb3bspg8ybmy4st3bxmg4
  text: |-
    ### commit — changed
    - evidence: 461253a test: share one never-connecting transport stub set
    - staged: NeverConnectingTransport.swift (new), HangingTransport.swift, HeldConnectTransport.swift, and the .kanban task files
    - next: review
  timestamp: 2026-10-17T18:00:17.529573+00:00
position_column: doing
position_ordinal: '80'
title: Test that a losing MCP connect attempt is not awaited, in a form that cannot hang
---
Follow-up of ^4vvg00p (owner decision 2026-10-17). The old HangingTransport hang ignored a cancel, so a change that cancels the losing connect attempt and then waits for it would have hung the tests. The new hangUntilCancelled() ends on a cancel, so those tests no longer show such a change.

Add the test "a losing connect attempt is not awaited":
- The losing transport records when its connect ends or is cancelled. It does not end until the test releases it.
- The test asserts that connect returned while the losing attempt is still open (not ended, not cancelled), and it releases the loser in a defer (or an awaited teardown on both paths).
- A future change that awaits the loser must make the test fail at once, not hang. Find the event that makes this possible (for example the loser records a cancel, or the wait for connect also ends on an event of the loser). If no form exists in which a loser that is awaited with no cancel gives a failure and not a hang, say so exactly and give the closest form.

Rule T1. No .timeLimit, sleep, poll or retry. A mutation check: one time, make connect await the loser, show the test fails and does not hang, and revert. One full run. #elicitation-fixes #t1

## Review Findings (2026-10-17 12:51)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/Support/HeldConnectTransport.swift:86` `reuse/reuse` — HeldConnectTransport.send reimplements the send of HangingTransport: both throw an internalError saying the double never connects. The same stub now lives in two doubles, so a later change to the stub must be made twice. Move the never-connects send and the empty receive into a shared test double, or have HeldConnectTransport and HangingTransport both use one stub helper. If the labels must differ, parameterize the label on one helper. Keep the connect behaviour separate, since the held connect does not match HangingTransport's cancel-ending connect.
