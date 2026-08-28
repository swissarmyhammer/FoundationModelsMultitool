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
- actor: claude-code
  id: 01m14gvgk5yds6mhzdb39h34j2
  text: |-
    ### commit — changed
    - evidence: 4 local commits, 24 files total, no push:
      - 316d906 fix(mcp): end the dropped transport's mirror stream with an error (2 files)
      - feda733 fix(tests): release the loopback's gate when a test connect fails (2 files)
      - 9cf7d58 fix(tests): drop the loopback client's stray Last-Event-ID (3 files)
      - 6a53b4a chore(kanban): sync board state (18 files)
    - next: none
  timestamp: 2026-08-28T15:47:13.637333+00:00
- actor: claude-code
  id: 01m14hb6s4gjpf8537m6v8k90w
  text: |
    ### review — findings
    - scope: `review sha HEAD~4..HEAD` — the diffs only. 7 files read, 18 files
      not read because `.reviewignore` holds out `.kanban/`.
    - validators: 7 attempted, 0 failed, 0 skipped. The result is therefore
      trustworthy: no rule was stopped by a stale checkout.
    - evidence: 2 findings, both confirmed, 3 refuted —
      `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:212`
      (`completeness/case-sensitivity-coverage`);
      `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift:221`
      (`swift/fluent-usage`).
    - the production change: the engine confirmed no finding against
      `Sources/FoundationModelsMultitool/Capabilities/MCP/DropObservingTransport.swift`.
      The mirror stream that now ends with `MCPError.connectionClosed` passed
      every validator.
    - the two findings are both in test support. The first asks for a test of a
      header name that is not in the usual case, because
      `withoutResumeHeader` compares without case. The second asks for a label on
      the first parameter of `withoutResumeHeader`.
    - next: `/implement` the two findings, then `/review` again. The card stays in
      `review`.
  timestamp: 2026-08-28T15:55:47.876433+00:00
- actor: claude-code
  id: 01m14hbyt3b6g42jq07cv0fyjm
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files; the true cause found in the swift-sdk HTTPClientTransport (one lastEventID for every SSE stream), plus two more defects: the mirror stream of DropObservingTransport ended with no error and spun a thread for ever, and the process-wide gate of LoopbackHTTPServer was not given back when a connect threw
    - test: green — 30 of 30 clean full swift test runs, 11 to 13 seconds each, 0 warnings; the baseline was 19 of 20. The loopback timeout went DOWN, 120 seconds to 30 seconds; the user CPU of one run fell from about 22.5 seconds to about 16.1 seconds
    - commit: 316d906, feda733, 9cf7d58, 6a53b4a — 24 files
    - review: findings — Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:212, Tests/Support/MCPTestServer/LoopbackHTTPServer.swift:221

    The one production change, the mirror stream that now ends with MCPError.connectionClosed, drew no finding.
  timestamp: 2026-08-28T15:56:12.483774+00:00
- actor: claude-code
  id: 01m14hxc7dwqrgdhfpcepg26ca
  text: |
    ### The two review findings, and how each was answered

    **`swift/fluent-usage`.** `withoutResumeHeader(_:)` is a noun phrase, and its
    first parameter is not a value-preserving conversion, so the rule asks for a
    label. The function is now `withoutResumeHeader(from:)`, and the one call site
    reads `Self.withoutResumeHeader(from: request)`.

    The whole of `LoopbackHTTPServer.swift` was then read for the same cause. It
    holds three more parameters with no label, and each is correct as it stands:
    `handle(_ request:)`, `deliver(_ response:, for url:)` and
    `relayStream(_ stream:)` are imperative verb phrases with a direct object,
    which the finding itself accepts — it offers `removingResumeHeader(_:)` as an
    alternative repair "which reads as a verb with a clear object". Each of
    `init(serving:)`, `loopback(for url:)` and `body(of request:)` already carries
    a label, and `canInit(with:)`, `canonicalRequest(for:)`, `startLoading()` and
    `stopLoading()` are `URLProtocol` overrides whose signature is fixed.

    **`completeness/case-sensitivity-coverage`.** The resume test is now
    parameterized over `resumeHeaderSpellings`, which holds the usual name and the
    same name in lower case. It reuses `connect(to:resumingFrom:)`, which gains one
    parameter with a default so the three other call sites do not move. No sleep
    and no timeout was added: the two cases together run in 0.076 s.

    ### Two facts that were measured before the test was written

    1. **Foundation keeps the case the client spells.** A probe set a header in
       lower case and in mixed case through a `URLSession` with a `URLProtocol`,
       and the protocol read back the spelling the caller wrote. So the spelling
       really reaches `LoopbackHTTPServer.handle(_:)`, and the test is not empty.
    2. **The sdk reads the header without case too.**
       `HTTPRequest.header(_:)` in `HTTPServerTypes.swift` of the swift-sdk
       lowercases both sides. A lower-case name the loopback let through would
       therefore reach `handleResumeRequest` exactly as the usual name does. This
       is what makes the new case load-bearing rather than decorative.

    ### The red that was watched

    `caseInsensitiveCompare` was temporarily replaced by `==` in the filter. The
    run then reported the usual spelling PASSED and `last-event-id` FAILED with
    "the standalone SSE stream never held within 10.0 seconds" — the loopback let
    the lower-case header through, the sdk took its resume path, and no standalone
    stream opened. The filter was put back and both cases passed in 0.076 s.
  timestamp: 2026-08-28T16:05:43.277145+00:00
- actor: claude-code
  id: 01m14hy3fgmbphd6yxg9s97jq1
  text: |
    ### implement — changed
    - evidence: 2 files —
      `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift`;
      `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`.
    - findings: both of the two are now `- [x]`.
      `swift/fluent-usage` — `withoutResumeHeader(_:)` becomes
      `withoutResumeHeader(from:)`. `completeness/case-sensitivity-coverage` — the
      resume test takes `arguments: resumeHeaderSpellings`, which holds
      `Last-Event-ID` and `last-event-id`.
    - runs: 10 of 10 clean full `swift test` runs, 11.5 to 12.6 seconds of wall
      clock each. The baseline was 30 of 30 at 11 to 13 seconds, so neither number
      moved. `swift build --build-tests` is clean; the one warning of each run is
      the vendored `mlx-swift_Cmlx.bundle`, which is out of scope.
    - speed: the new case costs nothing that can be measured — the whole resume
      test, both spellings, runs in 0.076 s. No sleep and no timeout was added.
    - next: `/review`.
  timestamp: 2026-08-28T16:06:07.088032+00:00
- actor: claude-code
  id: 01m14hzhp5hwrsh4wstkkwz9v0
  text: |-
    ### commit — changed
    - evidence: 9432639 test: check the resume header name without case, rename a helper (4 files changed, 179 insertions(+), 12 deletions(-))
    - next: none
  timestamp: 2026-08-28T16:06:54.405360+00:00
- actor: claude-code
  id: 01m14j97yp5tdafsgbvkhsmx3c
  text: |
    ### review — findings
    - scope: `review sha HEAD~1..HEAD` (commit 9432639), diffs only. 2 files reviewed, 2 files not reviewed (`.kanban/`, an ignore rule).
    - validators: 7 attempted, 0 failed, 0 skipped. The result is complete.
    - prior findings: the two items of the 2026-08-28 10:47 section are both checked.
    - evidence: 1 new finding — `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:151` `swift/fluent-usage`. The name `asking` does not make a grammatical phrase with its parameters.
    - next: give the helper a name that reads correctly at the call site, for example `addingResumeHeader`. Then run the review again.
  timestamp: 2026-08-28T16:12:12.118618+00:00
- actor: claude-code
  id: 01m14j9zmw7wdmd75xv3pva9te
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 2 files, both prior findings answered
    - test: green — 10 of 10 clean swift test runs, 11.5 to 12.6 seconds each; no regression of the rate or the time
    - commit: 9432639 — 4 files changed
    - review: findings — Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:151

    Note for the next iteration: this is the SECOND finding of the rule swift/fluent-usage in this one file. Iteration 1 raised it at line 221 of LoopbackHTTPServer.swift, and this iteration raises it at line 151 of LoopbackHTTPServerTests.swift. The next fix must sweep every helper of both files, and not the one line named.
  timestamp: 2026-08-28T16:12:36.380028+00:00
- actor: claude-code
  id: 01m14jrsyedykpy4174y2rgh48
  text: |
    ### The full sweep of `swift/fluent-usage` over both files

    The rule fired twice on this pair, so this pass reads the shipped rule body
    (`get validator swift`, rule `fluent-usage`, version 0.18.1) and judges EVERY
    declaration of both files against it, and not the one line named. The verdict
    of each declaration is below.

    These are the parts of the rule the verdicts use:

    - A name makes a grammatical phrase at the call site. Read the call aloud.
    - The preposition goes on the argument label, and not on the base name.
    - The first label goes off only for a conversion that keeps the value.
    - An operation with no side effect is a noun phrase; an operation with a side
      effect is an imperative verb phrase. A non-mutating form of a verb takes
      `ed` or `ing`.

    **`Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift`**

    | Declaration | Call site | Verdict |
    | --- | --- | --- |
    | `NotificationCounter.increment()` | `counter.increment()` | Passes. An imperative verb, and the call has a side effect. |
    | `Connection.close()` | `connection.close()` | Passes. Same shape. |
    | `Connection.init(loopback:client:)`, which the compiler makes | `Connection(loopback: loopback, client: client)` | Passes. Noun labels of an initializer, as in `Color(red:green:blue:)`. |
    | `connect(to:capabilities:resumingFrom:resumeHeaderNamed:)` | `connect(to: scripted, capabilities: Self.elicitingCapabilities)` | **Fails**, and it was not the line the finding named. `capabilities:` is a bare noun after the verb — the shape the rule refuses as `x.subviews(color: c)`. `resumeHeaderNamed:` had no word to join it to the verb. Now `connect(to:advertising:resumingFrom:sendingResumeHeaderNamed:)`, which reads "connect to scripted, advertising the eliciting capabilities" and "connect to scripted, resuming from the id of no stream, sending the resume header named last-event-id". |
    | `asking(to:resumeFrom:headerNamed:)` | `Self.asking(to: $0, resumeFrom: lastEventID, headerNamed: headerName)` | **Fails** — the finding of 11:07. The call has no side effect and returns a new request, so the rule asks for the `ing` form of the verb. Now `addingResumeHeader(to:resumingFrom:named:)`, which reads "adding the resume header to the request, resuming from the id, named last-event-id". The local `var asking` becomes `var carrying`. |
    | `initializeListAndCallEcho()` | none | Passes. The framework calls it; there is no call site to read. |
    | `elicitEchoRoundTrip()` | none | Passes. Same. |
    | `toolListChangedOverEventStream()` | none | Passes. Same. |
    | `aResumeRequestStillGetsTheStandaloneStream(headerName:)` | none | Passes. The framework supplies the argument from `arguments:`. |
    | `toolsListOverEachTransport(kind:)` | none | Passes. Same. |

    **`Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`**

    | Declaration | Call site | Verdict |
    | --- | --- | --- |
    | `init(serving:)` | `LoopbackHTTPServer(serving: scripted)` | Passes. |
    | `start()` | `loopback.start()` | Passes. An imperative verb with a side effect. |
    | `stop()` | `loopback.stop()` | Passes. Same. |
    | `endpoint` | a property | Passes. A noun, and the read has no side effect. |
    | `loopback(for:)` | `LoopbackHTTPServer.loopback(for: request.url)` | Passes. A noun phrase with its preposition, and no side effect. |
    | `handle(_:)` | `loopback.handle(httpRequest)` | Passes. A verb with a direct object, which the rule permits with no label, as in `x.append(y)`. |
    | `withoutResumeHeader(from:)` | `Self.withoutResumeHeader(from: request)` | **Fails**, and it was not the line the finding named. "without resume header from request" starts with a preposition and has no head. Now `removingResumeHeader(from:)` — "removing the resume header from the request", the `ing` form the rule asks of a call with no side effect, and the alternative the 10:47 finding itself offered. It also makes a pair with `addingResumeHeader(to:)` of the test file. |
    | `body(of:)` | `Self.body(of: request)` | Passes. A noun phrase with its preposition. |
    | `deliver(_:for:)` | `self.deliver(response, for: url)` | Passes. "deliver the response for the url" — a verb, a direct object, and a preposition on the second label. |
    | `relayStream(_:)` | `relayStream(stream)` | Passes. "relay stream" is a verb with its object. The name cannot become `relay(_:)`: the class holds a stored property `relay`, and Swift refuses the two names in one type. |
    | `canInit(with:)` | the loader | Cannot change. A `URLProtocol` override: the signature is fixed by the superclass. |
    | `canonicalRequest(for:)` | the loader | Cannot change. Same. |
    | `startLoading()` | the loader | Cannot change. Same. |
    | `stopLoading()` | the loader | Cannot change. Same. |

    Three declarations were corrected: two the review had not named, and the one
    it did. Every other declaration passes, or has a signature the superclass
    fixes.

    ### One more site of the same cause, in a third file

    `ScriptedServerSelfTests.connect(to:capabilities:)` carries the same bare
    `capabilities:` label. That file is not one of the two this card names, and no
    review raised it because every review of this card read the diff only. It is
    now task `^5h9cf3p`.
  timestamp: 2026-08-28T16:20:42.062445+00:00
- actor: claude-code
  id: 01m14js4xvxhep6xh0h3vqnywk
  text: |
    ### implement — changed
    - evidence: 2 files, 12 insertions and 12 deletions —
      `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift`;
      `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`.
    - findings: the one item of the 2026-08-28 11:07 section is now `- [x]`.
    - renames: `asking(to:resumeFrom:headerNamed:)` becomes
      `addingResumeHeader(to:resumingFrom:named:)`;
      `connect(to:capabilities:resumingFrom:resumeHeaderNamed:)` becomes
      `connect(to:advertising:resumingFrom:sendingResumeHeaderNamed:)`;
      `withoutResumeHeader(from:)` becomes `removingResumeHeader(from:)`; the
      local `var asking` becomes `var carrying`. The sweep comment above lists
      every declaration of both files and the verdict for each.
    - build: `swift build --build-tests` complete in 10.3 s. The one warning is
      the vendored `mlx-swift_Cmlx.bundle`, which is out of scope.
    - runs: 10 of 10 clean full `swift test` runs. 1310 tests in 100 suites, and
      one warning of each run, which is the vendored bundle. Wall clock 11.6 to
      13.0 s: the first run after the build took 12.98 s, and the other nine took
      11.6 to 12.1 s. The figure to hold was 10 of 10 at 11.5 to 12.6 s.
    - speed: nothing new to run. This pass renames only. The resume test, both
      spellings, still runs in 0.062 s, and the whole `LoopbackHTTPServer` suite
      in 0.114 s.
    - new work: `^5h9cf3p` — the same bare `capabilities:` label in
      `ScriptedServerSelfTests.swift`, which is a third file and out of the scope
      of this card.
    - next: `/review`.
  timestamp: 2026-08-28T16:20:53.307977+00:00
- actor: claude-code
  id: 01m14jtgx6n59ggstgzxdede57
  text: |-
    ### commit — changed
    - evidence: be6ea1f 6 files changed, 195 insertions(+), 13 deletions(-)
    - next: none
  timestamp: 2026-08-28T16:21:38.342992+00:00
- actor: claude-code
  id: 01m14jzcy77zmknpa0zf13x3xh
  text: |-
    ### review — clean

    - evidence: 0 findings. The engine attempted 7 validators. 0 validators failed and 0 validators were skipped. Scope: `review sha HEAD~1..HEAD`, which is commit be6ea1f. The engine read 2 Swift files. It did not read 4 files in `.kanban/`, because an ignore rule excludes them.
    - The rule `swift/fluent-usage` did not report an item on these two files. This is the third review of this pair of files. The rule reported an item in the two reviews before this one.
    - The commit changes no file name. It changes only the names of three helper functions. Thus the review read the two Swift files fully.
    - All items in the two `## Review Findings` sections are complete. The task has 7 complete items and 0 incomplete items.
    - next: none. The task moves to `done`.
  timestamp: 2026-08-28T16:24:18.119460+00:00
- actor: claude-code
  id: 01m14k07zvc51xdhf46z6xvagz
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 2 files; all 25 declarations of both files judged against the shipped rule body, 3 names corrected
    - test: green — 10 of 10 clean swift test runs, 1310 tests in 100 suites, 11.6 to 13.0 seconds each
    - commit: be6ea1f — 6 files changed
    - review: clean — 0 findings, 7 validators attempted, 0 failed, 0 skipped; all 3 prior finding items checked; task moved to done

    The rule swift/fluent-usage did not fire a third time, thus the loop guardrail was never reached.
  timestamp: 2026-08-28T16:24:45.819393+00:00
position_column: done
position_ordinal: ffa180
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
Read the doc comment of `LoopbackHTTPServerTests` first.

## Review Findings (2026-08-28 10:47)

> Scope: `review sha HEAD~4..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 18 not reviewed.

> 18 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 18 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:212` `completeness/case-sensitivity-coverage` — The `withoutResumeHeader()` function in LoopbackHTTPServer.swift (line 221-224) uses `caseInsensitiveCompare()` to match the Last-Event-ID header, which is correct for HTTP headers. However, the test `aResumeRequestStillGetsTheStandaloneStream()` exercises only the canonical case "Last-Event-ID" and does not verify that non-canonical spellings (e.g., "last-event-id", "Last-Event-Id") are also filtered. Add one assertion or test variant that sends the Last-Event-ID header with a non-canonical case (e.g., lowercase "last-event-id" or mixed case "Last-Event-Id") and verify that the server-initiated messages still arrive, proving the filter handles all case variations.
- [x] `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift:221` `swift/fluent-usage` — The first parameter `request` is unlabeled, but should only be unlabeled for value-preserving conversions (e.g., `Int64(someUInt32)`). Since this function transforms the request by filtering headers rather than preserving it unchanged in a different type, the parameter needs a label for clarity at the call site. Add a label to the first parameter: `private static func withoutResumeHeader(from request: HTTPRequest) -> HTTPRequest` so the call reads as `withoutResumeHeader(from: request)`, or alternatively rename to `removingResumeHeader(_ request: HTTPRequest)` which reads as a verb with a clear object.

## Review Findings (2026-08-28 11:07)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift:151` `swift/fluent-usage` — The function name `asking` does not form a grammatical phrase with its parameters. Reading the call `asking(to: request, resumeFrom: id, headerNamed: name)` aloud as "asking to [request] resumeFrom [id]..." is unnatural English; prepositions like `to` typically follow verbs that form idiomatic phrases (e.g., `insert(at:)`, `removeValue(forKey:)`), but "asking to [object]" is not a standard English phrase structure. Rename the function to better describe its action. Suggested names: `addingResumeHeader`, `withResumeHeader`, or `requestWithResumeHeader`, which form clearer phrases: "adding resume header to [request]" or "with resume header [request] resumeFrom [id]". #eventplan