---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3apfj7ms77pcax04vjxawmv
  text: |-
    Research (API documentation examined with WebFetch, 2026-09-24):

    - Brave: `GET https://api.search.brave.com/res/v1/web/search`. Header `X-Subscription-Token`. Query `q`, `count` (1 to 20, default 20), `freshness` (`pd`, `pw`, `pm`, `py`). The `site:` operator in `q` is supported. The `web` object is optional (it is absent when there are no web results). `web.results[].title` and `url` are required, `description` can be null and holds `<strong>` markup. Documented errors: 404, 422, 429. Docs: https://api-dashboard.search.brave.com/api-reference/web/search/get
    - Tavily: `POST https://api.tavily.com/search`. Header `Authorization: Bearer <key>`. Body `query`, `max_results` (0 to 20, default 10), `time_range` (`day`, `week`, `month`, `year`), `include_domains`. Response `results[].{title,url,content,score,...}`. Documented errors: 400, 401, 422, 429, 432 (plan limit), 433 (pay-as-you-go limit), 500. Docs: https://docs.tavily.com/documentation/api-reference/endpoint/search
    - Exa: `POST https://api.exa.ai/search`. Header `x-api-key`. Body `query`, `numResults` (1 to 100, default 10), `includeDomains`, `startPublishedDate` (ISO 8601), `contents.highlights`. `text` and `highlights` are NOT in the response unless `contents` asks for them. The snippet field is `highlights[]`. Documented errors: 400, 401, 402 (credits), 403, 429, 500, 503, 504. Docs: https://exa.ai/docs/reference/search and https://exa.ai/docs/reference/error-codes

    Discoveries:
    - No key for these providers is set in this environment, and the launching agent says: no real network and no real keys. Thus a live JSON response cannot be recorded here.
    - `DuckDuckGoHTMLProvider` keeps its `InvalidEndpoint` error, its percent encoder, and its `webURL` check private. The keyed adapters need the same three.
    - The chain maps 401, 403, 429 and 5xx before `parse`. A status that the chain does not map (for example Tavily 432, Exa 402) reaches `parse` with an error body.
  timestamp: 2026-09-24T21:52:23.796842+00:00
- actor: claude-code
  id: 01m3aq10jtszxjwjp3g2a7azpk
  text: |-
    Implementation landed (TDD: the build failed with no adapters, then the tests went green; a mutation that removed the count maximum made the 3 count tests fail, then it was restored).

    - New `Providers/SearchProviderSupport.swift` holds the shared steps: `endpointURL`, `requiredKey`, `clampedCount`, `percentEncoded`, `jsonGetRequest`, `jsonPostRequest`, `decodedBody` (status first: 401/403 -> `.badKey`, 429 -> `.rateLimited`, 5xx -> `.serverError`, another non-2xx status -> `.parse("the service answered HTTP <status>")`), `reading`, `checkedHits` (skips a result with no title or no http/https URL with a host, removes duplicate URLs, empty -> `.noResults`), `rankedHits`, `webURL`. Also the types `InvalidProviderEndpoint`, `MissingProviderKey`, `ProviderResult`.
    - `DuckDuckGoHTMLProvider` now uses these shared steps. Its private copies of the percent encoder, the `webURL` check, the hit rank, `reading`, `PageResult`, and `InvalidEndpoint` are removed. Its 13 tests still pass.
    - `BraveAPIProvider`: GET with `q` (plus `site:<host>`), `count` in 1...20, `freshness` pd/pw/pm/py; key in `X-Subscription-Token`. The description is read as HTML (SwiftSoup) to remove the `<strong>` markup. A response with no `web` object gives `.noResults`.
    - `TavilyProvider`: POST JSON `query`, `max_results` in 1...20, `time_range`, `include_domains`; key in `Authorization: Bearer <key>`. Snippet = `content`.
    - `ExaProvider`: POST JSON `query`, `numResults` in 1...100, `includeDomains`, `startPublishedDate` (the time of the request less the age limit, in UTC; the clock is injected), `contents.highlights: true`; key in `x-api-key`. Snippet = the highlights joined with a space.
    - Each adapter declares `[.freshness, .site, .count]`, because each one sends all three fields.
    - Tests: `KeyedProviderTests.swift` (one parameterized suite over the 3 adapters), `KeyedProviderRequestTests.swift` (the documented field names and values of each provider), `Support/KeyedProviderCase.swift` (the table of rows). `swift test --filter KeyedProvider`: 27 tests pass. `swift test`: 1674 tests in 133 suites pass, 0 warnings. `swiftlint lint` on the new and changed files: 0 findings, and also 0 findings with `no_magic_numbers` and `missing_docs` on.
    - The web.md provider table is correct for these three providers. It needs no change.
  timestamp: 2026-09-24T22:01:55.546374+00:00
- actor: claude-code
  id: 01m3aq1879rs58rhkjs7hk1ze9
  text: |-
    BLOCKER — one card item is not done: "Record one real JSON response for each into `Tests/FoundationModelsMultitoolTests/WebGoldens/`".

    Why: a live recording needs a real key and the real network. No key for Brave, Tavily, or Exa is set in this environment (`BRAVE_SEARCH_API_KEY`, `BRAVE_API_KEY`, `TAVILY_API_KEY`, `EXA_API_KEY` are all unset). Also, the launching agent told this step: "Tests use no real network and no real keys." The card and that order conflict, so I did not decide this myself.

    What is in place now: `brave-api-results.json`, `tavily-results.json`, and `exa-results.json` are in `WebGoldens/`. I wrote them in the response schema of the current API documentation (the same fields, nesting, null values, and markup, for example Brave `<strong>` descriptions and a null description, Exa empty `highlights`). They hold no account data. They are NOT live recordings.

    A person must decide one of these:
    1. Supply keys, and allow one live call for each provider. Then replace the three files with real responses (remove the request ids), and update `firstHit` and `goldenHitCount` in `Tests/FoundationModelsMultitoolTests/Support/KeyedProviderCase.swift`.
    2. Accept the documentation-schema fixtures for this card. The later `KeyedProviderLiveTests` card then checks the real service.
  timestamp: 2026-09-24T22:02:03.369909+00:00
- actor: claude-code
  id: 01m3aq1ebrvm1z7eq1d3cet6c1
  text: |-
    ### implement — stuck
    - evidence: 11 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/{SearchProviderSupport,BraveAPIProvider,TavilyProvider,ExaProvider}.swift (new), Sources/FoundationModelsMultitool/Capabilities/Web/Providers/DuckDuckGoHTMLProvider.swift (changed), Tests/FoundationModelsMultitoolTests/{KeyedProviderTests,KeyedProviderRequestTests}.swift, Tests/FoundationModelsMultitoolTests/Support/KeyedProviderCase.swift, Tests/FoundationModelsMultitoolTests/WebGoldens/{brave-api-results,tavily-results,exa-results}.json. `swift test --filter KeyedProvider`: 27 tests pass. `swift test`: 1674 tests in 133 suites pass, 0 warnings. swiftlint: 0 findings.
    - gap: "Record one real JSON response for each" is not done. The fixtures follow the documented schema, but they are not live recordings. No key is set, and the launching agent said no real network and no real keys. See the BLOCKER comment.
    - next: a person decides (supply keys and record, or accept the schema fixtures). Then run /review. The task stays in `doing`.
  timestamp: 2026-09-24T22:02:09.656718+00:00
- actor: claude-code
  id: 01m3aqxnq31maryw0s93djb1re
  text: |-
    ### test — green
    - evidence: `swift test` — 1674 tests in 133 suites passed, 0 failed, 0 skipped. `swift build` — build complete, 0 failures. No compiler warning in project source. `swiftlint lint --quiet` — 0 findings.
    - note: both runs print one line — "warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)". This line comes from the build system, about the vendored mlx-swift dependency's bundle under `.build/`, not from project source in `Sources/` or `Tests/`. No source change can remove it, and it is present with no edits made in this step.
    - note: `swiftformat --lint` with the four stated flags reports format changes on 312 of 357 files across the whole repo, old and new files alike, this step made no source edits. A fix at this scope is not part of the test step. The `/review` code-hygiene check will judge the diff.
    - next: none. The test step is done. The BLOCKER from the implement step (live JSON goldens for the keyed providers need real keys) is still open and is not a test-step matter.
  timestamp: 2026-09-24T22:17:34.691424+00:00
- actor: claude-code
  id: 01m3aqywmkpfm6ppz80vve0j00
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — code complete (11 files); the item "Record one real JSON response for each" is not done. No API key is set, so no live recording is possible. The three JSON fixtures follow the provider documentation.
    - test: green — swift test, 1674 passed
    - commit: ac2e9b4 (checkpoint)
    - review: not run
    - decision for a person: (1) supply keys and allow one live call per provider to record the fixtures, or (2) accept the documentation fixtures for this card, because the keyed live tests cover the real services. Then run /finish ^p1t98nj.
  timestamp: 2026-09-24T22:18:14.547511+00:00
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: doing
position_ordinal: '80'
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