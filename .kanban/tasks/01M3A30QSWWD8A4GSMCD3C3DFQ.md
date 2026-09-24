---
assignees:
- claude-code
depends_on:
- 01M3A30EJ2DG162C1F2CXZXYQ1
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: todo
position_ordinal: '8480'
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
- [ ] Windows cover the whole page with no gap and no overlap: joining the windows from `offset` 0 through each `nextOffset` gives the full text.
- [ ] A second window of the same page makes no new request (the stub records one request, and `networkLoadCount == 1`).
- [ ] A second window of `http://a.test/` that redirects to `https://a.test/` makes no new request.
- [ ] The seventeenth distinct page removes the least recently used page from the cache.
- [ ] `.raw` of an HTML page gives the HTML; a truncated body sets `truncated` on the window.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebPageReaderTests.swift` with `WebStubURLProtocol`: windowing, cache hit, cache hit after a redirect, eviction, formats, the offset past the end, the non-2xx page with its body, `truncated`, `networkLoadCount`.
- [ ] Run `swift test --filter WebPageReaderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web