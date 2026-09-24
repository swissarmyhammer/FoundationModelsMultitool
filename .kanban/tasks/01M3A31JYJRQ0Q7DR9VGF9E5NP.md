---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ahqqqmdg9cnwn7hvzjp80k
  text: |-
    Research:
    - `Providers/` holds only `SearchProviderAdapter.swift`. No Brave HTML adapter exists yet, thus no provider pattern to copy. `FakeSearchAdapter` is the only adapter.
    - No form encoder exists in `Sources/` (no `x-www-form-urlencoded`, no `addingPercentEncoding`). The provider needs its own form body encode.
    - Live check on 2026-09-24 (curl POST to https://html.duckduckgo.com/html/ with a Safari User-Agent): HTTP 200, `text/html; charset=UTF-8`. The `.result__a` links are now direct `https` URLs. No `//duckduckgo.com/l/?uddg=` link was in any page, thus the `uddg` decode test uses hand-written HTML.
    - The query "buy running shoes" gives 2 ad containers (`.result--ad`, links to `https://duckduckgo.com/y.js?...`) and 10 organic `.web-result` containers. This page is the recorded `duckduckgo-results.html`.
    - The `df` parameter works: with `df=d` the page shows `<option value="d" selected>Past Day` and other results; `w`, `m`, `y` also select "Past Week", "Past Month", "Past Year". The recorded page `duckduckgo-results-past-day.html` is this proof, thus the provider supports `.freshness`.
    - The query "swift programming language" (no `df`) gave `https://www.swift.org/` two times, thus duplicates occur in real pages.
  timestamp: 2026-09-24T20:29:28.692840+00:00
- actor: claude-code
  id: 01m3amjr6bj7nxcb2k1zyrmeh9
  text: |-
    ### implement — stuck (agent stopped)
    - evidence: the first implement agent wrote the research note and three fixture pages in `Tests/FoundationModelsMultitoolTests/WebGoldens/` (duckduckgo-challenge.html, duckduckgo-results.html, duckduckgo-results-past-day.html). Then it made no change for about 50 minutes and did not read a status message. The orchestrator stopped it.
    - next: a new implement agent continues from the research note and the fixtures.
  timestamp: 2026-09-24T21:19:11.051056+00:00
- actor: claude-code
  id: 01m3amshdj6c61t4xdew519cet
  text: |-
    Research (second implement agent):
    - The three fixture pages are good. `duckduckgo-results.html` has 2 `.result--ad` containers (links to `duckduckgo.com/y.js`) and 10 organic `.web-result` containers with 10 different direct `https` URLs. Titles and snippets hold HTML entities (`&#x27;`). The challenge page has `.anomaly-modal` and `#challenge-form`, and no `.result`.
    - Gap in the design: `SearchProviderAdapter.parse(_:response:)` gets no query, thus an adapter cannot "stop at count". The chain sends the response of a POST, and the response URL does not hold the form body. Decision: `parse` gets a third parameter `limit: Int?` (the query count, or `nil` for all hits on the page). The chain passes `query.count`. `FakeSearchAdapter` obeys the limit. The `web.md` protocol sketch gets the same change. The Brave HTML task (^w3vpnk0) needs the same limit.
    - SwiftSoup is already a dependency of the library target. `HTMLMarkdown` uses it.
    - No form encoder exists. `URLComponents.queryItems` does not encode `+`, thus the provider encodes the form body with an explicit ASCII unreserved set.
  timestamp: 2026-09-24T21:22:53.490956+00:00
- actor: claude-code
  id: 01m3an8ktp5mxne8wv5kkpr83b
  text: |-
    Implementation landed (TDD).
    - Step 1: the new test `the adapter gets the query count as the limit of its hits` in `ProviderFallbackTests` failed first (3 hits, expected 2). Then `SearchProviderAdapter.parse` got `limit: Int?`, the chain passes `query.count`, and `FakeSearchAdapter` obeys the limit. The `web.md` protocol sketch shows the new parameter. The Brave HTML provider (^w3vpnk0) must use the same `limit` parameter.
    - Step 2: `DuckDuckGoHTMLProviderTests` (19 test cases) failed first with `cannot find 'DuckDuckGoHTMLProvider' in scope`. Then `DuckDuckGoHTMLProvider` made them pass. A mutation check (5 mutations: no ad filter, no limit, no uddg decode, no duplicate check, no challenge selector) made 7 tests fail. The file was then restored.
    - The provider: `POST https://html.duckduckgo.com/html/`, `Content-Type: application/x-www-form-urlencoded`, body `q=<text>[ site:<host>]` and `df=d|w|m|y` for a freshness. It supports `.freshness`, `.site`, and `.count`. The form encoder keeps only the RFC 3986 unreserved ASCII bytes, thus `+` is `%2B` and a space is `%20`.
    - The parse: selector `.result:not(.result--ad)`, title and link from `.result__a`, snippet from `.result__snippet`. A `duckduckgo.com/l/?uddg=` link gives its decoded target. A link that is not an absolute `http` or `https` URL is skipped. A link with a host and no scheme gets `https`. Duplicate URLs are removed before the limit, thus ranks stay 1, 2, 3 with no gap. No hits plus `.anomaly-modal` or `#challenge-form` is `.challenge`; no hits and no such element is `.noResults`.
    - `request` throws `InvalidEndpoint` when the endpoint text is not a URL. Foundation has no `#URL` macro on this toolchain (checked with `swiftc -typecheck`).
    - The provider is not in a chain yet. The WebContext task (^46nr78v) connects `.duckDuckGoHTML` to `DuckDuckGoHTMLProvider`.
  timestamp: 2026-09-24T21:31:07.478100+00:00
- actor: claude-code
  id: 01m3an8tjpjq60kj6hqmpx5ma6
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/DuckDuckGoHTMLProvider.swift (new), Tests/FoundationModelsMultitoolTests/DuckDuckGoHTMLProviderTests.swift (new), Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderAdapter.swift, Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift, Tests/FoundationModelsMultitoolTests/ProviderFallbackTests.swift, Tests/FoundationModelsMultitoolTests/Support/FakeSearchAdapter.swift, web.md; plus the 3 fixture pages of the first agent in Tests/FoundationModelsMultitoolTests/WebGoldens/ (reused with no change). `swift test --filter 'DuckDuckGoHTMLProviderTests|ProviderFallbackTests'`: 35 tests passed. `swift test`: 1647 tests in 131 suites passed, 0 failures, 0 compiler warnings from this code (the one `missing creator for mutated node` line is the mlx-swift bundle note). `swiftlint lint` (default rules, and a strict run with no_magic_numbers, missing_docs, force rules, body length): 0 violations on the 6 Swift files. `swift format lint` with the 7 idiom rules: 0 findings.
    - next: /review
  timestamp: 2026-09-24T21:31:14.390662+00:00
- actor: claude-code
  id: 01m3antd66wnhe93nptfvd8j13
  text: |-
    ### test — green
    - evidence: `swift test` (full clean build after `swift package clean`) — 1647 tests, 131 suites, 0 failures, 0 skipped, 0 warnings in project source.
    - check: no `.disabled` or skip trait in any test file. No skipped test.
    - check: no warning line from any file under `Sources/` or `Tests/`.
    - note: `swiftformat --lint` (tool defaults, no `.swiftformat` file in the repo) finds style items in the changed Web files. The same items are also present in unchanged files, for example `WebPageReader.swift` and `HTMLMarkdown.swift`. This shows the project does not hold swiftformat to its default rules. The agent did not change these items, to keep the same style as the rest of the project.
    - note: `swift build` prints warning lines from the `mlx-swift` package. This package is a pinned, checked-out dependency, not part of this project's own source. The task told the agent not to run `swift package update`. The agent can not change these lines without that command. The agent leaves these lines as a known, out-of-scope item.
    - next: none. The task is ready for the next step.
  timestamp: 2026-09-24T21:40:50.502580+00:00
- actor: claude-code
  id: 01m3ap7m9y75crrwhhqvgdk6ga
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit daf1e81) — 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. The engine reviewed 6 files. It did not review 8 files: 4 `.kanban/` files (from `.reviewignore`), 3 HTML fixture pages and `web.md` (no validator matches these files). The commit renames no file.
    - next: the task moves to done.
  timestamp: 2026-09-24T21:48:03.774400+00:00
- actor: claude-code
  id: 01m3ap82bma5wpk34nk24mvpb4
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files (second agent; the first agent was stopped when it hung)
    - test: green — swift test, 1647 passed
    - commit: daf1e81
    - review: clean — 0 findings (1 refuted); the task is in done
  timestamp: 2026-09-24T21:48:18.164015+00:00
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: done
position_ordinal: ffd580
title: 'Web: add the DuckDuckGo HTML provider (second keyless fallback)'
---
## What
Add the second keyless provider, so a keyless search has a fallback when Brave blocks it. Design: `web.md` § "The provider list".

- Create `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/DuckDuckGoHTMLProvider.swift`, which conforms to `SearchProviderAdapter`:
  - Request: `POST https://html.duckduckgo.com/html/` with the form body `q=<query>` (and `site:<host>` in the query when `site` is set). Supports `.site` and `.count`. Add `.freshness` only if a recorded page proves the `df` parameter works.
  - Parse with SwiftSoup: each `.result` container; title and link from `.result__a`; snippet from `.result__snippet`. A link of the form `//duckduckgo.com/l/?uddg=<encoded>` is decoded to the target URL. Skip ad results. Remove duplicate URLs. Stop at `count`.
  - A page with no results and the known anomaly or challenge text is `.challenge`.
- Record one real results page into `Tests/FoundationModelsMultitoolTests/WebGoldens/duckduckgo-results.html`, and add one hand-written challenge page.

## Acceptance Criteria
- [x] The recorded page gives at least 5 hits with decoded `https` URLs (no `duckduckgo.com/l/` URL in the output).
- [x] Ad results are not in the output.
- [x] The challenge page gives `.challenge`.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/DuckDuckGoHTMLProviderTests.swift`: the request (method, URL, form body), the recorded page, the `uddg` decode, duplicates, the `count` limit, the challenge page.
- [x] Run `swift test --filter DuckDuckGoHTMLProviderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web