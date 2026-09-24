---
assignees:
- claude-code
depends_on:
- 01M3A31T6MJJSGKHPG7P1T98NJ
position_column: todo
position_ordinal: '8980'
title: 'Web: add the Serper, Kagi, and SearXNG providers'
---
## What
Add the other three providers of decision 4. Design: `web.md` § "The provider list". FIRST examine the current API documentation of each provider (WebFetch) and correct the endpoint, auth, request fields, and response fields that `web.md` gives from memory. Record the documentation URL in a doc comment on each adapter.

- `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SerperProvider.swift`: `POST https://google.serper.dev/search`, header `X-API-KEY`, JSON body `q`, `num` (and the time filter the docs give); parse `organic[].{title,link,snippet}`.
- `.../Providers/KagiProvider.swift`: `GET https://kagi.com/api/v0/search?q=&limit=`, `Authorization: Bot <key>`; parse the search result entries of `data[]` (type 0 only) with `title`, `url`, `snippet`.
- `.../Providers/SearXNGProvider.swift`: `GET <base>/search?q=&format=json` (and `time_range` for freshness); no key; parse `results[].{title,url,content}`. Set `isHostConfiguration = true`, so the chain sends the request with `guarded: false` (`web.md` § "Security"). Redirect hops and the result URLs a snippet fetches stay guarded.
- The same error mapping as the previous task. Declare only the features each adapter really sends.
- Record one real JSON response for each (for SearXNG, a response from any public instance with JSON on, or a hand-written response in the documented shape) into `Tests/FoundationModelsMultitoolTests/WebGoldens/`.

## Acceptance Criteria
- [ ] Each adapter builds the documented request, and the key appears only in the auth header.
- [ ] Each recorded response parses to hits with URLs and titles; Kagi related-search entries are not hits.
- [ ] A chain with `[.searxng(URL(string: "http://127.0.0.1:8888")!)]` and a stub for that address sends the search request and returns hits (the host configuration is not refused by the guard).

## Tests
- [ ] Extend `Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift` with these three adapters in the same parameterized suite.
- [ ] Add to `ProviderFallbackTests.swift` (or a new `SearXNGChainTests.swift`) the stubbed SearXNG search at `http://127.0.0.1:8888` that returns hits.
- [ ] Run `swift test --filter "KeyedProviderTests|ProviderFallbackTests|SearXNGChainTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web