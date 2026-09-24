---
assignees:
- claude-code
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: todo
position_ordinal: '8780'
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
- [ ] The recorded page gives at least 5 hits with decoded `https` URLs (no `duckduckgo.com/l/` URL in the output).
- [ ] Ad results are not in the output.
- [ ] The challenge page gives `.challenge`.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/DuckDuckGoHTMLProviderTests.swift`: the request (method, URL, form body), the recorded page, the `uddg` decode, duplicates, the `count` limit, the challenge page.
- [ ] Run `swift test --filter DuckDuckGoHTMLProviderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web