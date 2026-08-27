---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m12k9dcj3734t5ag4tdzm0jp
  text: |-
    ### Research and discoveries

    - `ShellState` has no `close()` and no `deinit`. The shell store is released with the session by ARC. No host in this package calls `RoutedSession.close()`, thus there is no code hook for step 2 to wire into. The pool is the MCP side of that release: the host holds `builder.serverPool` and calls `shutdownAll()` after `RoutedSession.close()`. The doc comments of `MCPServerPool` and `Builder.serverPool` state this route.
    - The first test run (red) showed two gaps that the design did not show:
      1. `MCPServer.call` started the `notifications/cancelled` in a detached `Task` from its `onCancel` handler. A `disconnect()` that ran first failed the call as `.lost` before that task ran, and the notice never reached the wire. Fix: `CancellationNotices` holds each notice task, and `disconnect()` drains the ledger before it tears the client down.
      2. In the parked shape, the cancellation of the `runCode` run reached the inner `tools.*` call only on the next poll of the JS promise pump (20 ms). The sweep returned before that, and the pool closed the transport first. Fix: `InFlightInnerCalls` holds each inner call of one `runCode` invocation in a task, and the cancellation handler of `MultiTool.run` cancels every one of them at once, in the same `cancel()`.
    - The second fix made a cancelled call able to finish with a value or a repairable error before the watchdog read the flag (`HardeningTests` and `SuspendedContextTests` went red). `MultiTool.runCapturingOutcome` now answers `CancellationError` for a cancelled call whatever the snippet did, which is what `call(arguments:)` documents.
    - The order "advisory cancel, then the terminal `.cancelled`" of the parked shape is not fixed by this package: Router's cooperative canceler returns at once and `SessionMailbox.sweep()` synthesizes the terminal, while the notice goes out from its own task. The tests assert the two orders this package fixes: the advisory cancel is on the wire before the transport closes, and the terminal `.cancelled` is recorded before the transport closes. The header of `MCPSessionSweepTests` states this.
    - The `SurfaceRefresher` of `^7vn4nk5` does not exist. The hook is the `Stoppable` protocol and `MCPServerPool.attach(_:)`; `shutdownAll()` stops the attachment first.
    - New shared test support: `WireRecordingTransport` (Support), `ProcessLiveness` (Support, and `StdioServerProcessTests` now reads it), `SessionMount` (Fixtures), and `MCPTestSupport.connectedRecordingMCPServer(to:name:)`.
    - The repository holds no `.swift-format` configuration file, thus no formatter ran.
  timestamp: 2026-08-27T21:51:17.394464+00:00
- actor: claude-code
  id: 01m12k9tshp9pmjppqdcgwwjnf
  text: |-
    ### implement — changed
    - evidence: 13 files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift (new), Sources/FoundationModelsMultitool/Capabilities/MCP/CancellationNotices.swift (new), Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Connection.swift, Sources/FoundationModelsMultitool/Invocation/InFlightInnerCalls.swift (new), Sources/FoundationModelsMultitool/MultiTool.swift, Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift, Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift (new), Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift (new), Tests/FoundationModelsMultitoolTests/Support/ProcessLiveness.swift (new), Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift, Tests/FoundationModelsMultitoolTests/Fixtures/SessionMountFixtures.swift (new), Tests/FoundationModelsMultitoolTests/StdioServerProcessTests.swift. `swift build --build-tests` clean; `swift test`: 1282 tests in 97 suites passed, 0 warnings; `swift test --filter MCPSessionSweepTests`: 5 of 5 passed, 5 runs in a row.
    - next: /test, then /commit, then /review.
  timestamp: 2026-08-27T21:51:31.121177+00:00
- actor: claude-code
  id: 01m12kmebf7mx2se4gepa0a63g
  text: |-
    ### commit — changed
    - evidence: 93b75f1 feat(mcp): stop MCP calls and server processes at session teardown (16 files changed, 944 insertions(+), 48 deletions(-))
    - next: /review
  timestamp: 2026-08-27T21:57:18.831612+00:00
- actor: claude-code
  id: 01m12ma3g1cgrcr3c80k634rdv
  text: |-
    ### review — findings
    - evidence: 4 findings — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift:80, Sources/FoundationModelsMultitool/Invocation/InFlightInnerCalls.swift:51, Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:186, Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift:83
    - next: Correct the four findings. Three are `swift/fluent-usage`: give a label to the first argument of `attach()`, `expectOrder()`, and `mark()`. One is `duplication`: the key generation code in `InFlightInnerCalls` is the same as in `CancellationNotices`; put it in one shared helper. Remove each cause from the full file, not only the line in the finding. Then do the review again.
  timestamp: 2026-08-27T22:09:08.609671+00:00
- actor: claude-code
  id: 01m12mastfh54x1bmypsxvjtag
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 files
    - test: green — swift test, 1282 tests in 97 suites passed, 0 warnings
    - commit: 93b75f1 — 16 files changed, 944 insertions, 48 deletions
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift:80, Sources/FoundationModelsMultitool/Invocation/InFlightInnerCalls.swift:51, Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:186, Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift:83
  timestamp: 2026-08-27T22:09:31.471158+00:00
- actor: claude-code
  id: 01m12ms32k9pdwpcpz1v8exf9x
  text: |-
    ### The four findings, and what each correction did

    **The three `swift/fluent-usage` findings share one cause**: a first argument with no label on a method that makes a side effect. Each of the three files was swept in full for that cause, and each file holds exactly one instance of it.

    - `MCPServerPool.swift` — `attach(_ attachment:)` becomes `attach(attachment:)`. This agrees with the two other recording methods of the same actor, `add(server:)` and `add(process:)`. The sweep of the full file found no other method with an unlabelled first argument that makes a side effect: `add(server:)`, `add(process:)` and `shutdownAll()` are all correct as they stand.
    - `WireRecordingTransport.swift` — `mark(_ label:)` becomes `mark(as label:)`, the first form the finding names. The sweep of the full file found two more methods with an unlabelled first argument, and neither is an instance of this cause: `send(_ data:)` is a requirement of the `Transport` protocol, thus its signature is not free, and `holds(_ entry:)` makes no side effect — it is a Boolean assertion about the receiver (`wire.holds(entry)`), which the naming rule permits.
    - `MCPSessionSweepTests.swift` — `expectOrder(_ first:before:on:)` becomes `expectOrder(of first:before:on:)`. The finding asks for a preposition that agrees with the sibling helpers `waitForTheCall(on:)` and `expectServerReceivedTheCancel(from:)`. `of:` is that preposition, and it makes the call read as a phrase: "expect order of the cancel, before disconnected, on the wire". The sweep of the full file found no other method with an unlabelled first argument.

    **The `duplication` finding.** The key generation of `InFlightInnerCalls` and `CancellationNotices` is now in one type, `SequentialKeys`, in `Sources/FoundationModelsMultitool/Invocation/SequentialKeys.swift`. Both halves of the duplicate were written by this change, thus this is a changed-set duplicate: one shared type is extracted and both sites call it, and no copy stays. Each class holds `private let keys = SequentialKeys()` and takes its key with `keys.take()`. `SequentialKeys` is a `final class` over a `Mutex`, and not an actor, for the reason both callers already state: each takes its key from code that cannot `await` — a synchronous `onCancel` handler, or an `AsyncHostFunction` body the promise pump starts on whatever thread it likes.

    ### What did not change, and why

    `CancellationNotices.track(_:)` and `InFlightInnerCalls.running(_:)` keep their unlabelled first argument. No finding names either one; both take a trailing closure, which is the shape of the sibling scoping helpers of this codebase (`lostRuns.noting { ... }`, `ledger.recording { ... }`); and both lines stand unchanged by this correction, thus they are outside it.
  timestamp: 2026-08-27T22:17:19.699509+00:00
- actor: claude-code
  id: 01m12ms98hz11hp5vh1kzpx90c
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Invocation/SequentialKeys.swift (new), Sources/FoundationModelsMultitool/Invocation/InFlightInnerCalls.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/CancellationNotices.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift, Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift, Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift. `swift build --build-tests` clean, 0 warnings; `swift test`: 1282 tests in 97 suites passed, 0 failures and 0 warnings. All 4 review findings are corrected and checked.
    - next: /review
  timestamp: 2026-08-27T22:17:26.033226+00:00
- actor: claude-code
  id: 01m12myxvcme0nrw4t55cy6rdt
  text: |-
    ### commit — changed
    - evidence: 0ab1135 refactor: fix argument labels and remove a duplicate counter — 8 files changed, 121 insertions(+), 23 deletions(-)
    - next: none, local commit only, not pushed
  timestamp: 2026-08-27T22:20:30.956530+00:00
- actor: claude-code
  id: 01m12n5mdbm6bgkzxb7zy5zht3
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 0ab1135) — 0 findings, 0 confirmed, 0 refuted. 6 files reviewed, 2 files not reviewed because an ignore rule excludes `.kanban/`. All 4 findings of the section `## Review Findings (2026-08-27 16:57)` are checked.
    - next: none. The task moves to `done`.
  timestamp: 2026-08-27T22:24:10.667621+00:00
- actor: claude-code
  id: 01m12n642sdtb7jhqzdd83795w
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 6 files, the four findings answered, SequentialKeys extracted
    - test: green — swift test, 1282 passed, 0 failed, 0 skipped, 97 suites
    - commit: 0ab1135 — 8 files changed
    - review: clean — 0 new findings, 4 of 4 prior findings checked; task moved to done
  timestamp: 2026-08-27T22:24:26.713504+00:00
depends_on:
- 01M112EG33CSGN466M9BHVD8C0
- 01M112DXH2AS8Z8VNYAD9QXVY4
position_column: done
position_ordinal: ff9d80
title: Session teardown sweep for MCP calls and server subprocesses
---
## What
eventplan.md § "Background tools and the completion token": "Session teardown does one deterministic sweep of the mailbox. ... MCP requests get the advisory cancel and post `.cancelled` before the transport closes." And § "Consolidation of the siblings": "To kill a server subprocess is a host-level act on each in-flight call that it carries. It is not a run cancellation."

Shell already has its sweep (`ShellSessionSweepTests.swift`). Give MCP the same, in two steps that keep their order.

- Step 1 — in-flight calls, two shapes:
  - Inside a parked `runCode` run: the session sweep cancels the run; Task cancellation reaches `MCPServer.call`, which sends `notifications/cancelled` and throws; the run's terminal `.cancelled` posts through the engine.
  - Mounted natively on a `RoutedSession` (a plain run-to-completion call, never parked): the sweep cancels the session's in-flight turn task; the same cancellation reaches `MCPServer.call` the same way. No run-plane entry exists; the advisory cancel still goes out before the transport closes. State this shape in the header, because eventplan.md speaks of "MCP requests" without the distinction.
  This task adds the tests that prove the order for both shapes: the advisory cancel is on the wire BEFORE the transport closes.
- Step 2 — server subprocesses. Add `MCPServerPool` in `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift`, recorded by `withMCP(servers:)`, with `public func shutdownAll() async`: `disconnect()` on each server and `shutdown()` on each `StdioServerProcess`, and `stop()` on the `SurfaceRefresher` if one is attached. A host calls it after the session sweep. Servers are infrastructure with session lifetime; they get no `completionToken`.
- Wire step 2 where the shell store closes at session end (see how `ShellState` is released at teardown, and follow the same route).
- The crash edge (no teardown ran) needs no code here: Router's restoration marks journaled runs with no terminal event as `.lost`.

## Acceptance Criteria
- [x] Parked shape: at session end with a `runCode` run that awaits a slow `ScriptedTool`, the server receives `notifications/cancelled` for that request, then the terminal event for the run is `.cancelled`, then the transport closes. The recorded order is asserted.
- [x] Native shape: at session end with an `MCPTool` mounted directly on a `RoutedSession` and a slow call in flight, the server receives `notifications/cancelled`, then the transport closes.
- [x] `shutdownAll()` ends each server subprocess, and `ProcessRegistry.global` no longer holds it.
- [x] A session with no MCP servers is unchanged.
- [x] `swift build` succeeds.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift` in the pattern of `ShellSessionSweepTests.swift`, with the criteria above. Use `ScriptedServer` over a recording in-memory transport for the two order cases, and `mcp-test-server` over stdio for the subprocess case.
- [x] `swift test --filter MCPSessionSweepTests` passes.

## Workflow
- Use `/tdd` — write the order tests first, then implement the pool and its shutdown.

## Review Findings (2026-08-27 16:57)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 14 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift:80` `swift/fluent-usage` — The first argument label is omitted with underscore (`_`), but this is only permitted for value-preserving conversions per fluent-usage guidance. The `attach()` method is not a value-preserving conversion; it performs a side effect (modifying state), so the first argument should be labeled. Add a label to the first argument: `public func attach(attachment: any Stoppable)` or use a preposition if clarification is needed (e.g., `attach(to: attachment)`).
- [x] `Sources/FoundationModelsMultitool/Invocation/InFlightInnerCalls.swift:51` `duplication/duplication` — Key generation logic (lines 51–54) is byte-for-byte identical to CancellationNotices.swift:41–44. The counter-increment logic could drift out of sync if one class is updated and the other is not. Extract into a shared private helper method (e.g., `private func nextSequentialKey() -> Int`) or a common base class. Both CancellationNotices and InFlightInnerCalls would then call this instead of repeating the pattern.
- [x] `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:186` `swift/fluent-usage` — The first argument label is omitted with underscore, but this is only permitted for value-preserving conversions. The `expectOrder()` function is not a value-preserving conversion; it performs an assertion operation. Additionally, this is inconsistent with sibling helper functions in the same test file (`waitForTheCall(on:)` at line 173 and `expectServerReceivedTheCancel(from:)` at line 199) which both label their first parameters with prepositions. Add a label to the first argument with a preposition: `first first:` or better yet `comparing first:` to clarify intent and match the pattern of other helper functions.
- [x] `Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift:83` `swift/fluent-usage` — The first argument label is omitted with underscore, but this is only permitted for value-preserving conversions. The `mark()` method performs a side effect (appending to the ledger) and is not a value-preserving conversion, so the first argument should be labeled. Add a label to the first argument: `func mark(as label: String)` or `func mark(with label: String)` for clarity. #eventplan #phase-4