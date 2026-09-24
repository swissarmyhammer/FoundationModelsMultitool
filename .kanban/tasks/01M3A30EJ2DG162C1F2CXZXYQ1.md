---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3aacf03bj7sgg4v0e0k068r
  text: |-
    Research done. Discoveries:
    - `WebAddressGuard.check(_:)` is async and gives `WebGuardRefusal?`. `WebGuardRefusal` conforms to `CorrectiveFailure` (Files/CorrectiveResult.swift). `WebFetchPolicy` (WebConfiguration.swift) already has `maxBytes`, `userAgent`, `maxRedirects` (10).
    - A probe script showed that `URLSessionConfiguration.httpAdditionalHeaders` reach the `request` of a custom `URLProtocol`, also on each redirect hop. Thus the stub can find its own table from a header that the stub configuration adds. Each test then has its own table, and Swift Testing can run the tests in parallel.
    - A task delegate given to `URLSession.bytes(for:delegate:)` gets `willPerformHTTPRedirection`. A `nil` return does not fail the task: the 3xx response comes back as the final response. Thus the fetcher must keep the refusal in the delegate and look at it after the call.
    - The swiftlint rule `no_unchecked_sendable` needs `// swiftlint:disable:next no_unchecked_sendable` plus the invariant on a `@unchecked Sendable` class. `LoopbackURLProtocol` does not have this directive.
    - `no_magic_numbers` also reads test files. Tests must name their numeric values.
  timestamp: 2026-09-24T18:20:59.267779+00:00
- actor: claude-code
  id: 01m3ab4pbca6adwqw7xzx4926b
  text: |-
    Implementation done (TDD: a skeleton WebFetcher made the 22 new tests compile and fail, then the code made them pass).

    What changed:
    - New `WebFetcher.swift` (358 lines): `FetchedBody`, `WebFetchFailure` (refused, tooManyRedirects, timeout, network, notText), `WebFetcher` with `load(_:timeout:guarded:)` and `decodeText(_:)`. The timeout is a task-group race over the whole load (guard, hops, body). `URLError.timedOut` also gives the timeout failure.
    - `RedirectCheck` (the `willPerformHTTPRedirection` hook) is in `WebAddressGuard.swift`, not in `WebFetcher.swift`. Reason: `WebFetcher.swift` went past the 400-line limit, and web.md § "Files to add or change" puts the "redirect hook" in `WebAddressGuard.swift`. The reviewer must know that this differs from the card text.
    - New `Support/WebStubURLProtocol.swift`: `WebStub` (table keyed by the exact URL text, a record of each request with its headers), `WebStubReply` (respond, redirect(location:), fail, hang), `WebStubURLProtocol`, `PublicHostResolver`.

    What did not work, and why:
    - A refused hop that returns `nil` from the redirect delegate does NOT end the task with a custom `URLProtocol`: the session waits for a body that the stub never sends, and the load hangs until the timeout. Fix: `RedirectCheck` also calls `task.cancel()`, and the fetcher gives the recorded refusal in place of the cancel error.
    - `HTTPURLResponse.mimeType` gave a text type for a response with NO `Content-Type` header (it guesses from the body). The fetcher now reads the `Content-Type` header itself; no header gives `application/octet-stream`.
    - A first cookie test (a `Set-Cookie` response, then a second request with no `Cookie`) passed with the cookie settings removed, so it could not fail. It is replaced by a test that reads `fetcher.session.configuration` (thus `session` is internal).
    - `@unchecked Sendable` on the stub protocol is not necessary: the build has no warning without it, thus no `no_unchecked_sendable` directive is necessary. Plain `swiftlint lint` reports the words after a `disable:next` directive as unknown rules, thus a reason cannot go on the directive line.

    Checks: `swift test --filter "WebRedirectGuardTests|WebFetcherTests"`: 22 tests pass. `swift test`: 1595 tests in 128 suites pass, no build warnings. `swiftlint lint` on the 5 files: 0 findings. A swiftlint run with `no_magic_numbers` (allowed 0, 1, -1, 100), `missing_docs`, and the force rules: 0 findings.
  timestamp: 2026-09-24T18:34:13.228525+00:00
- actor: claude-code
  id: 01m3ab4tp4ptqreke1z249msvm
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebFetcher.swift (new), Sources/FoundationModelsMultitool/Capabilities/Web/WebAddressGuard.swift (+ RedirectCheck), Tests/FoundationModelsMultitoolTests/Support/WebStubURLProtocol.swift (new), Tests/FoundationModelsMultitoolTests/WebFetcherTests.swift (new), Tests/FoundationModelsMultitoolTests/WebRedirectGuardTests.swift (new); `swift test` 1595 tests pass; `swiftlint lint` 0 findings
    - next: review
  timestamp: 2026-09-24T18:34:17.668833+00:00
- actor: claude-code
  id: 01m3abm2p8gdxjzfdk3k3rgpc3
  text: |-
    ### test — green

    - evidence: `swift test` — 1595 tests, 128 suites, all passed, 0 failed, 0 skipped, 0 compiler warnings. `swift test --filter "WebRedirectGuardTests|WebFetcherTests"` — 22 tests, 2 suites, all passed.
    - checks done: full build with the touched files recompiled (no compiler warning in `WebFetcher.swift`, `WebAddressGuard.swift`, `WebStubURLProtocol.swift`, `WebFetcherTests.swift`, `WebRedirectGuardTests.swift`). The one build-system line about `mlx-swift_Cmlx.bundle` is present on the base commit too, so it is not from this task.
    - format and lint: `swiftformat` (with the four stated options) and `swiftlint` gave opposite answers on the same lines — `swiftformat` wants a trailing comma and a brace on its own line after a wrapped return type; `swiftlint`'s default rules want no trailing comma and the brace on the declaration line. The repo has no `.swiftformat` and no `.swiftlint.yml`, and `swiftformat` is the tool the project guidelines give named options for, so its output stands. `PathGuard.swift`, already on `main`, uses the same wrapped-brace form, which matches this choice.
    - one line of `swiftformat`'s repair touched code this task did not write: it added a trailing comma to the `blockedHosts` array in `WebAddressGuard.swift`, a line already on `main` before this task. That comma is removed, so the diff of this task holds only lines this task changed.
    - no commit made.
    - next: ready for review.
  timestamp: 2026-09-24T18:42:37.384528+00:00
depends_on:
- 01M3A2ZFR1FPVNM9TSWT37RFZ1
- 01M3A300ZZK58WVM6CX354ETCQ
position_column: doing
position_ordinal: '80'
title: 'Web: add the guarded fetch engine (redirects, byte limit, content types)'
---
## What
Add the HTTP layer that each network request of the web capability goes through. Design: `web.md` § "Fetch / The pipeline", steps 2 to 6, and § "Security" (the SearXNG rule).

- Create `Sources/FoundationModelsMultitool/Capabilities/Web/WebFetcher.swift`:
  - `final class WebFetcher: Sendable`, made from a `URLSessionConfiguration`, a `WebFetchPolicy`, and a `WebAddressGuard`. It makes one `URLSession` with no cookies and no URL cache (`httpShouldSetCookies = false`, `urlCache = nil`).
  - `User-Agent`: when the request has no `User-Agent` header, set the one of the policy. A request that sets its own `User-Agent` keeps it (the Brave HTML request needs its browser `User-Agent`).
  - `func load(_ request: URLRequest, timeout: Duration, guarded: Bool = true) async -> Result<FetchedBody, WebFetchFailure>`. When `guarded` is `true`, check the URL with the guard before the request. `guarded: false` is only for host configuration (the SearXNG base URL); the redirect hops of that request are still checked.
  - In `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)`, check each hop with the guard and stop after `maxRedirects` hops.
  - Read the body with `URLSession.bytes(for:)` and stop at `maxBytes` (set `truncated = true`).
  - `FetchedBody`: final URL, status, content type, charset, bytes, `truncated`.
  - `WebFetchFailure`: guard refusal, too many redirects, timeout, network failure. Each has a `correctiveMessage` (for example `The request timed out after 30 seconds: <url>`).
  - `func decodeText(_ body: FetchedBody) -> Result<String, WebFetchFailure>`: accept `text/*`, `application/json`, `application/xml`, `+json`, `+xml`, `application/xhtml+xml`; decode with the charset, else UTF-8; any other type is the failure `The content type is not text: <type>. fetch reads text, HTML, JSON, and XML.`
- Create `Tests/FoundationModelsMultitoolTests/Support/WebStubURLProtocol.swift`: a `URLProtocol` subclass that answers from a table (URL pattern → status, headers, body, optional redirect) and records each request with its headers. Tests give it through `URLSessionConfiguration.ephemeral.protocolClasses`, the same method as `LoopbackHTTPServer` (`Tests/Support/MCPTestServer/LoopbackHTTPServer.swift:150`).

## Acceptance Criteria
- [x] A redirect to `http://127.0.0.1/` is refused before a request goes to that address.
- [x] The eleventh redirect hop is refused.
- [x] A body larger than `maxBytes` stops at the limit and is marked truncated.
- [x] A non-2xx status is a normal result, not a failure.
- [x] A PDF content type gives the content-type failure; a JSON body decodes as text; a `charset=iso-8859-1` body decodes correctly.
- [x] A request with no `User-Agent` sends the policy `User-Agent`; a request with its own `User-Agent` keeps it (the stub records both).
- [x] With `guarded: false`, a request to `http://127.0.0.1:8888/search` is sent; a redirect from it to `http://169.254.169.254/` is still refused.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/WebRedirectGuardTests.swift` (private-address redirect, hop limit, redirect from an unguarded request).
- [x] Create `Tests/FoundationModelsMultitoolTests/WebFetcherTests.swift` (byte limit, status, content types, charset, timeout failure, both `User-Agent` cases, the unguarded request).
- [x] Run `swift test --filter "WebRedirectGuardTests|WebFetcherTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web