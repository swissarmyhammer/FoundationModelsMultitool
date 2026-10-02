---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3x0cprxqxk0jx7t6vae29xy
  text: |-
    Card ^gmhbe7g (iteration 2, not committed yet) did the work of this card. Each item, with the file evidence:

    Do:
    - "Give `WebFetcher` an injected clock": done. `Sources/FoundationModelsMultitool/Capabilities/Web/WebFetcher.swift` has `let timeLimitClock: any Clock<Duration>`, an init parameter that defaults to `ContinuousClock()`, and `load` sleeps on `self.timeLimitClock.sleep(for: timeout)` (not `Task.sleep`). `WebContext.init` passes a `timeLimitClock` parameter through, default `ContinuousClock()`. This is the pattern of `MCPServer.connectAttemptClock`.
    - The session timer: `WebFetcher.prepare` set `URLRequest.timeoutInterval` to the limit, thus a second real timer of 1 second. Now it sets `max(request.timeoutInterval, limit)`. The session timer is a backstop only: it never ends a load before the clock limit, and a limit of 1 second does not start a real 1-second timer. The request default is 60 seconds.
    - "Make `boundTimeoutIsAccepted` use the injected clock": done. `Tests/FoundationModelsMultitoolTests/Support/WebVerbFixture.swift` has `let timeLimitClock = GatedClock()`, given to the `WebContext`. No test opens it. `WebVerbArgumentTests.boundTimeoutIsAccepted` also checks `fixture.timeLimitClock.recordedSleeps == [.seconds(timeout)]`.
    - "Look for other web tests that use a real short time limit": done. `WebStub.makeFetcher` (`Support/WebStubURLProtocol.swift`) now takes `timeLimitClock`, default a closed `GatedClock()`. Thus each stub test (WebFetcher, ProviderFallback, BraveHTML, BraveAPI, SearXNG, WebPageReader, WebRedirectGuard) cannot race the real clock. `WebContextTests.searchChainUsesTheSessionConfiguration` gives `GatedClock()`. The live suites in `IntegrationTests/` keep the real clock, which is correct for a live test.

    Tests:
    - [x] "`boundTimeoutIsAccepted` does not depend on the real clock": satisfied, see above. The only real timer left is the 60-second session backstop, a hang guard far above the stub reply.
    - [x] "A test that proves the time limit still gives the timeout correction, with the injected clock": `WebFetcherTests.hangingRequestTimesOut`. The stub hangs, the test waits until the clock records the sleep, opens the clock, and expects `WebFetchFailure.timeout(url:limit:)` and `recordedSleeps == [shortTimeout]`. The correction text of that failure is checked by `timeoutMessageStatesSeconds`. New test `WebFetcherTests.sessionTimerIsABackstop` checks the session timer (RED with the old line: 1.0 < 60).
    - [x] "Root `swift test` passes": one run, 1886 tests in 154 suites passed.

    I did not move this card.
  timestamp: 2026-10-02T00:31:55.677581+00:00
position_column: todo
position_ordinal: '8280'
title: Remove the real 1-second clock from the web fetch timeout test
---
## What
The root `swift test` run of ^gmhbe7g on 2026-10-02 had one failure: `WebVerbArgumentTests.boundTimeoutIsAccepted` with `timeout: 1`. The result was the correction "The request timed out after 1 second: https://site.example/page". The fetch goes to a `WebStub`, thus no network is used, but `WebFetcher.load` races the request against `Task.sleep(for: timeout)` on the real clock, and it also sets `URLRequest.timeoutInterval`. When the machine is busy, the stubbed reply takes more than 1 second, and the test fails.

The user decision (web.md § "Testing", and ^tm4x2hp) is that no test checks the speed of the machine. This test was not in the list of ^kdtrmhv.

## Do
- Give `WebFetcher` an injected clock (or an event) for the time limit race, in the pattern of `MCPServer.connectAttemptClock` from ^tm4x2hp. Production uses the continuous clock.
- Make `boundTimeoutIsAccepted` use the injected clock, thus a `timeout` of 1 is accepted no matter how slow the machine is.
- Look for other web tests that use a real short time limit (for example the timeout correction tests), and convert them the same way.

## Tests
- [ ] `boundTimeoutIsAccepted` does not depend on the real clock.
- [ ] A test that proves the time limit still gives the timeout correction, with the injected clock.
- [ ] Root `swift test` passes.