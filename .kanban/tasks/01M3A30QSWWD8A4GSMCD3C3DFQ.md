---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ac3ztw8z7ye45e7a2xgq26
  text: |-
    Research done.
    - `WebFetcher.load(_:timeout:guarded:)` gives `FetchedBody` (final URL, status, lower-case media type, charset, bytes, `truncated`). `decodeText(_:)` decodes each text type and gives `.notText` for other types. A non-2xx status is a body, not a failure.
    - `HTMLMarkdown.convert(html:baseURL:format:)` throws (SwiftSoup) and gives `ConvertedPage(title:text:)`. `WebTextFormat` has `.markdown` and `.text` only.
    - `WebStub.makeFetcher()` gives a fetcher on the stub session with `PublicHostResolver`. The stub records each request, also each redirect hop.
    - The project counts text in `Character` units (`String.count`). The reader uses the same unit for `offset`, `maxCharacters`, and `totalCharacters`.
    - `WebFetchFailure` has no case for a page that the converter cannot parse. Plan: add `case unconvertible(url:reason:)` with a correction, so a SwiftSoup error does not go silent.
    - Plan for the cache: an ordered list of at most 16 entries. Each entry holds one page and the set of its keys (URL text + format): the requested URL and the final URL. A hit moves the entry to the end. An insert merges each old entry that shares a key.
  timestamp: 2026-09-24T18:51:18.748725+00:00
- actor: claude-code
  id: 01m3acgwqfqf3pf2az5xcw0m5y
  text: |-
    Implementation landed (TDD: the suite failed first on a stub `read`, then passed).
    - New `WebPageReader.swift` (308 lines): `WebPageFormat`, `PageWindow`, `actor WebPageReader`. There are also three file-private types: `ConvertedWebPage`, `WebPageCacheKey`, and `WebPageCache` (an ordered list, least recently used first).
    - `WebFetcher.swift`: new case `WebFetchFailure.unconvertible(url:reason:)`. The correction is "The page at <url> could not be converted: <reason>". It is for a SwiftSoup error. Before, that error had no failure case.
    - When an insert shares a key with an old entry, the old entry goes away and the new entry keeps its keys. Thus two URLs that redirect to one page use one cache slot. A mutation check proved it: with no key merge, the test `sharedFinalURLIsOneEntry` fails.
    - Decisions: `.raw` gives `title == nil`. A failed load goes into no cache entry. `offset < 0` and `maxCharacters <= 0` are `precondition` failures, because the `Fetch` tool checks the bounds first (web.md step 1).
    - Known limit, not in scope: two reads of the same URL that run at the same time both load (actor reentrancy). Reads one after the other load one time.
    - `swiftlint lint` on the two new files: 0 findings. `swift test`: 1611 tests in 129 suites passed. The one build warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from the SwiftPM build graph of the mlx dependency, not from this change.
  timestamp: 2026-09-24T18:58:21.551707+00:00
- actor: claude-code
  id: 01m3acgz3dttjak0f9xfgbw5cb
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebPageReader.swift (new), Sources/FoundationModelsMultitool/Capabilities/Web/WebFetcher.swift (new `unconvertible` failure case), Tests/FoundationModelsMultitoolTests/WebPageReaderTests.swift (new, 16 tests). `swift test --filter WebPageReaderTests`: 16 passed. `swift test`: 1611 tests passed. `swiftlint lint` on the new files: 0 findings.
    - next: /review
  timestamp: 2026-09-24T18:58:23.981209+00:00
- actor: claude-code
  id: 01m3acvhsmbc05pek9hd2rg92h
  text: |-
    ### test — green
    - Evidence: `swift package clean && swift build` — build is OK. 0 warnings in project code. (4 warnings are from the mlx-swift C++ vendor code, not our code.)
    - Evidence: `swift test` — 1611 tests pass. 0 tests fail. 0 tests skip. 129 suites pass.
    - The WebPageReader suite passes.
    - No test has a skip mark or a disable mark.
    - next: none.
  timestamp: 2026-09-24T19:04:10.804530+00:00
depends_on:
- 01M3A30EJ2DG162C1F2CXZXYQ1
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: doing
position_ordinal: '80'
title: 'Web: add page conversion, windows, and the page cache'
---
## What
Join the fetch engine and the converter into one page reader, and add windows and the session cache. Design: `web.md` § "Fetch / The pipeline", step 7, and the page cache paragraph after it.

- Create `Sources/FoundationModelsMultitool/Capabilities/Web/WebPageReader.swift`:
  - `actor WebPageReader` made from a `WebFetcher`.
  - `func read(url: URL, format: WebPageFormat, offset: Int, maxCharacters: Int, timeout: Duration) async -> Result<PageWindow, WebFetchFailure>`. `WebPageFormat` is `.markdown`, `.text`, or `.raw`.
  - HTML (`text/html`, `application/xhtml+xml`) goes through `HTMLMarkdown.convert`; `.raw` gives the decoded body with no change; other text types are used as is.
  - `PageWindow`: final URL, status, content type, title, content (the window), `totalCharacters`, `nextOffset` (`nil` at the end), and `truncated` from the fetch.
  - Cache: at most 16 converted pages, least recently used goes first. Store each entry under the requested URL and under the final URL, each with the format, so a second window of a URL that redirects makes no new request.
  - `internal var networkLoadCount: Int` counts the loads that went to the `WebFetcher`. The live tests read it with `@testable import`.
  - An `offset` at or past the end gives an empty `content` and `nextOffset == nil`.

## Acceptance Criteria
- [x] Windows cover the whole page with no gap and no overlap: joining the windows from `offset` 0 through each `nextOffset` gives the full text.
- [x] A second window of the same page makes no new request (the stub records one request, and `networkLoadCount == 1`).
- [x] A second window of `http://a.test/` that redirects to `https://a.test/` makes no new request.
- [x] The seventeenth distinct page removes the least recently used page from the cache.
- [x] `.raw` of an HTML page gives the HTML; a truncated body sets `truncated` on the window.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/WebPageReaderTests.swift` with `WebStubURLProtocol`: windowing, cache hit, cache hit after a redirect, eviction, formats, the offset past the end, the non-2xx page with its body, `truncated`, `networkLoadCount`.
- [x] Run `swift test --filter WebPageReaderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web