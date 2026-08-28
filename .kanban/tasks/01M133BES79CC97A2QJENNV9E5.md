---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m14c1w2xmzq2pexh0zz7pdxj
  text: |
    ### Research — the cause is found, and it is in production code

    **A deterministic reproduction.** `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` holds the
    cooperative pool to one thread. With it, `swift test --filter LoopbackHTTPServer`
    alone fails 2 of 2 attempts, with exactly the two failures this card names:

    - "a server-initiated elicitation/create reaches the client…" — `NSURLErrorTimedOut`
      (-1001) after 120.5 s;
    - "notifications/tools/list_changed reaches the client over the loopback SSE
      stream" — the 10 s `TestPoll` deadline.

    Without the variable, that same filtered run passed 20 of 20. So the load of the
    full run is not a coincidence: it is the pool.

    **What holds the pool.** A `sample` of the stalled process shows one task that
    spins hot, and never suspends: 960 of 1679 samples in `Client.connect(transport:)`
    calling `DropObservingTransport.receive()` again and again, each call returning at
    once from `AsyncThrowingStream._Storage.next`.

    **Why it spins.** The message loop of `MCP.Client` is
    `repeat { let stream = await connection.receive(); for try await data in stream {…} }
    while true`. It leaves that loop on two conditions only: `Task.isCancelled`, or the
    stream ends with a THROW (the `catch` breaks). A stream that ends WITHOUT a throw
    sends the loop straight back to `receive()`.

    `DropObservingTransport.receive()`
    (`Sources/FoundationModelsMultitool/Capabilities/MCP/DropObservingTransport.swift`)
    returns the mirror stream that `mirror(_:)` built. When the wrapped receive stream
    ends normally — a transport drop, which is the very case this wrapper exists to
    report — `mirror(_:)` calls `continuation.finish()`. The mirror is now a finished
    stream that `receive()` keeps handing back, and `handleTransportDrop(generation:)`
    does not disconnect the client. So the loop spins on one cooperative-pool thread
    for the rest of the process.

    **Why the loopback is what fails.** Every drop test of the run leaves one more
    spinning loop behind. The relay of `LoopbackHTTPServer` and the SSE read of
    `HTTPClientTransport` are ordinary tasks on that same pool, so a server-to-client
    message waits behind the spinners. That is the stall this card measured.

    **This is a defect in this repository's production code, not in the test support.**
    In a shipped host, an MCP server process that dies leaves `MCPServer` burning a full
    core for the life of the host.
  timestamp: 2026-08-28T14:23:19.133051+00:00
- actor: claude-code
  id: 01m14ghj2m8980c8yn5cy0n68y
  text: |
    ### The first diagnosis was wrong, and what replaced it

    The earlier comment on this card named a hot spin in `DropObservingTransport`
    as the cause. That spin is real, and it is repaired here, but it is NOT the
    cause of this card's flake: with it removed the loopback still timed out on 2
    of 5 runs. Two things had misled that measurement, and the next agent should
    know both:

    1. **The samples read the wrong process.** `pgrep -f
       FoundationModelsMultitoolTests.xctest` matched two LEAKED
       `swiftpm-testing-helper` processes from an earlier session, each spinning at
       100% CPU for 14 hours. `pgrep -n` (newest) is what reads the live run. Those
       two leaks were themselves the proof that the spin persists after a run ends,
       so they were worth finding — they were killed, and none has appeared since.
    2. **`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` is a trap here.** It reproduces
       both failures 2 of 2 on the filtered suite, which looks decisive. It is not:
       a sample of a strict-pool stall shows the runtime idle with NO cooperative
       thread at all, and the filtered suite uses no `DropObservingTransport` at
       all. Use it to reproduce, never to conclude.

    **What did work.** Temporary `stderr` tracing in `LoopbackHTTPServer.handle(_:)`
    and in `LoopbackURLProtocol` — every request method, every response status,
    every relayed chunk with its SSE `id:` line — then `catch.sh`, a loop that runs
    `swift test` until one run passes 25 seconds. Run 24 of 30 stalled, and the
    trace named the fault at once: in every clean run the standalone `GET` carries
    `id: _GET_stream_2`, and in the red run the elicitation loopback's `GET`
    carries `id: 581A840E-…_6` — a `POST` request's stream. The tracing is removed.

    ### Two more defects the work uncovered, both repaired here

    **A hot spin that burns a core for the life of the process.** The message loop
    of `MCP.Client` is `repeat { for try await data in await connection.receive() }
    while true`, and it leaves that loop on a cancel or a THROW only.
    `DropObservingTransport.mirror(_:)` ended its mirror with a plain
    `continuation.finish()` when the wrapped stream ended, and
    `handleTransportDrop(generation:)` never disconnects the client, so after every
    transport drop the loop spun on one cooperative-pool thread for ever. This is
    production code: a shipped host whose MCP server process dies burns a full core
    until the host exits. The mirror now ends with `MCPError.connectionClosed`.
    Measured: user CPU of one `swift test` run fell from about 22.5 s to about
    16.1 s.

    **A gate nobody gave back turns one failure into a whole-run hang.**
    `LoopbackHTTPServer.start()` takes the one process-wide gate, and neither
    `LoopbackHTTPServerTests.connect(to:)` nor `MCPTestSupport` gave it back when
    the connect threw after the start. The new resume test found this the hard way:
    one 10-second failure became a `swift test` that ran past 900 seconds. Both
    paths now stop the loopback before they rethrow.

    ### The timeout

    `requestTimeout` goes from 120 seconds to 30, and no timeout was raised. A
    loopback reaches no network, so this number decides only how long a stuck run
    takes to report: a red run now reports in about 31 seconds instead of 121. 30
    is three times the `TestPoll` deadline and thirty times a whole green run.
  timestamp: 2026-08-28T15:41:47.476420+00:00
- actor: claude-code
  id: 01m14ghya0wy429syjx012a96g
  text: |
    ### implement — changed
    - evidence: 7 files. `Sources/FoundationModelsMultitool/Capabilities/MCP/DropObservingTransport.swift`;
      `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`;
      `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift`;
      `Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift`;
      `Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift`;
      `Tests/FoundationModelsMultitoolTests/Support/LoopbackClosingTransport.swift`;
      new `Tests/FoundationModelsMultitoolTests/DropObservingTransportTests.swift`.
    - cause: `HTTPClientTransport` of the sdk keeps one `lastEventID` for every SSE
      stream, so the standalone `GET` asks to resume a `POST` request's stream;
      `StatefulHTTPServerTransport` binds that `GET` to the `POST` stream, the
      session keeps no standalone stream, and every server-initiated message is
      stored for a replay that never comes. `LoopbackHTTPServer.handle(_:)` now
      drops `Last-Event-ID`.
    - tests: 4 new cases. One is the repair of this card ("a client that asks to
      resume a stream still gets the standalone SSE stream"); three read how
      `DropObservingTransport` ends its mirrored stream. Each was watched red
      first.
    - runs: 30 of 30 clean full `swift test` runs, 11 to 13 seconds each. The
      baseline tree, measured on the same quiet machine, was 19 of 20 plus a
      further red in a 5-run batch.
    - speed: a green run stays about 12 s of wall clock (12 s before). User CPU
      falls from about 22.5 s to about 16.1 s, and the `LoopbackHTTPServer` suite
      from about 6 s to 0.09 s. A red run would now report in about 31 s, not 121.
    - next: `/review`.
  timestamp: 2026-08-28T15:42:00.000813+00:00
position_column: doing
position_ordinal: '80'
title: The HTTP-loopback elicitation tests time out on about one full swift test run in six
---
## What

`swift test` at the root fails intermittently. Two tests carry the failure,
and both drive an elicitation over the in-process HTTP loopback:

- `LoopbackHTTPServerTests.elicitEchoRoundTrip` — "a server-initiated
  elicitation/create reaches the client, and the answer returns to the tool".
- `MCPElicitationTests` — "a runCode snippet suspends on the elicitation and
  returns the mailbox answer over the HTTP loopback".

The first fails with a `URLSession` request timeout, not an assertion:

```
Caught error: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
NSErrorFailingURLStringKey=http://loopback-<uuid>/mcp
```

The test then reports after 120 seconds, and the whole run reports after 121
seconds. A clean run of the same suite takes about 6 seconds, so a red run
takes 20 times the time of a green one.

## The measurement

Made on 2026-08-27, with `swift test` at the root, on an Apple silicon
machine: about one run in six was red, with no working change.

## The cause

The premise this card was written on — a loaded cooperative thread pool
delays the message — is wrong, and the doc comments that carried it are
corrected. A `sample` of a stalled process shows the WHOLE process idle: the
main thread and the CFNetwork thread wait on `mach_msg`, no cooperative thread
exists, and nothing is runnable. The message is dropped, and not delayed.

A trace of every loopback request states where it goes. `HTTPClientTransport`
of the sdk keeps ONE `lastEventID` for every SSE stream it reads, the response
stream of a `POST` included. The `Last-Event-ID` it sends on the standalone
`GET` is therefore the id of the last event of ANY stream, usually an event of
a `POST` response stream. `StatefulHTTPServerTransport.handleGet` then takes
its resume path and binds the new `GET` to
`requestSSEContinuations[thatRequestID]` instead of to
`standaloneSSEContinuation`. The session now has no standalone stream, so
`routeServerInitiatedMessage` stores every `elicitation/create` and every
notification "for replay" and delivers none of them. The tool call never
finishes and the `POST` fails on the request timeout.

Whether it happens is a race: the `GET` goes out as soon as the session id is
read from the initialize RESPONSE HEADERS, while the body of that same
response is still being parsed into `lastEventID`.

The defect stands in the sdk, which this package consumes as a released
dependency and cannot patch. `LoopbackHTTPServer.handle(_:)` therefore drops
`Last-Event-ID` before it routes: a loopback lives for one test and its
session never outlives a disconnect, so replay has nothing to give it.

## Acceptance Criteria

- [x] Find why the server-to-client message stalls. Stated above: the stall is
      in neither `LoopbackHTTPServer`, the SSE read of `HTTPClientTransport`,
      nor the pool. `HTTPClientTransport` asks to resume the wrong stream, and
      `StatefulHTTPServerTransport` grants it, so the message reaches nothing.
- [x] Remove the cause. No timeout was raised, and the two suites were not
      made serial with each other. The wording of this line named the two
      repairs a pool stall would need; the cause was a dropped message, so
      neither applies.
- [x] Keep both tests in the unit target. Add no environment variable and no
      skip.

## Tests

- [x] 30 consecutive full `swift test` runs, each green.

## Workflow
Read the doc comment of `LoopbackHTTPServerTests` first. #eventplan