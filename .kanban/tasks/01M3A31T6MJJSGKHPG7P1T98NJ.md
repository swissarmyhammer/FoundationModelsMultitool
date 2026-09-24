---
assignees:
- claude-code
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: todo
position_ordinal: '8880'
title: 'Web: add the Brave API, Tavily, and Exa keyed providers'
---
## What
Add three of the six keyed providers (decision 4). Design: `web.md` § "The provider list". That table comes from memory. FIRST examine the current API documentation of each provider (WebFetch) and correct the endpoint, the auth header, the request fields, and the response fields. Record the documentation URL in a doc comment on each adapter.

- `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveAPIProvider.swift`: `GET https://api.search.brave.com/res/v1/web/search?q=&count=`, header `X-Subscription-Token`; `freshness` maps to `pd`/`pw`/`pm`/`py`; parse `web.results[].{title,url,description}`.
- `.../Providers/TavilyProvider.swift`: `POST https://api.tavily.com/search`, `Authorization: Bearer <key>`, JSON body with `query` and `max_results` (and the time range field if the docs have one); parse `results[].{title,url,content}`.
- `.../Providers/ExaProvider.swift`: `POST https://api.exa.ai/search`, header `x-api-key`, JSON body with `query` and `numResults`; parse `results[].{title,url}` and the snippet field the docs give.
- Each adapter maps 401/403 to `.badKey`, 429 to `.rateLimited`, 5xx to `.serverError`, an empty list to `.noResults`. Each declares only the `SearchFeature` values it really sends.
- Record one real JSON response for each into `Tests/FoundationModelsMultitoolTests/WebGoldens/` (remove any account data from it).

## Acceptance Criteria
- [ ] Each adapter builds the documented request: method, URL, auth header, body.
- [ ] The key appears in the auth header and in no other part of the request (URL, body).
- [ ] Each recorded response parses to hits with `https` URLs and titles.
- [ ] Each error status maps to the documented `ProviderFailure`.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift` with one parameterized suite over these three adapters (the next task adds the other three): request shape, key placement, parse of the recorded response, error mapping.
- [ ] Run `swift test --filter KeyedProviderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web