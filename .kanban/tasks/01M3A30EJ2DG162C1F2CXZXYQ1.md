---
assignees:
- claude-code
depends_on:
- 01M3A2ZFR1FPVNM9TSWT37RFZ1
- 01M3A300ZZK58WVM6CX354ETCQ
position_column: todo
position_ordinal: '8380'
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
- [ ] A redirect to `http://127.0.0.1/` is refused before a request goes to that address.
- [ ] The eleventh redirect hop is refused.
- [ ] A body larger than `maxBytes` stops at the limit and is marked truncated.
- [ ] A non-2xx status is a normal result, not a failure.
- [ ] A PDF content type gives the content-type failure; a JSON body decodes as text; a `charset=iso-8859-1` body decodes correctly.
- [ ] A request with no `User-Agent` sends the policy `User-Agent`; a request with its own `User-Agent` keeps it (the stub records both).
- [ ] With `guarded: false`, a request to `http://127.0.0.1:8888/search` is sent; a redirect from it to `http://169.254.169.254/` is still refused.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebRedirectGuardTests.swift` (private-address redirect, hop limit, redirect from an unguarded request).
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebFetcherTests.swift` (byte limit, status, content types, charset, timeout failure, both `User-Agent` cases, the unguarded request).
- [ ] Run `swift test --filter "WebRedirectGuardTests|WebFetcherTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web