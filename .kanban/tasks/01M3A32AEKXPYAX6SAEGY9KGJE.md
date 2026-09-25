---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3c9rpdbcpbb8y3r1wfappqq
  text: |-
    Research (2026-09-25). Results of the documentation check:

    - Kagi: the current reference is the OpenAPI spec of API v1 (https://kagi.com/api/docs, spec at https://redocly-api-docs.kagi.com/api/docs/_bundle/openapi.yaml). It gives `POST https://kagi.com/api/v1/search`, security `http bearer` (`Authorization: Bearer <key>`), a JSON body with `query` (required), `limit` (1...1024), `filters.after` (a date), and `lens.sites_included`. The response is `{meta, data: {search: [...], related_search: [...], ...}}`. Each entry has `url`, `title`, `snippet`, `time`. There is no `data[]` list with `t: 0/1` in v1. The spec documents no v0 GET endpoint. Thus the card text (`GET /api/v0/search`, `Bot <key>`, `data[]` type 0) is out of date, and the adapter follows the v1 spec, as the card tells. The related searches are in `data.related_search`, and the adapter does not read them. The example titles and snippets hold HTML entities (`&amp;`, `&#39;`), thus the adapter decodes them the same as Brave.
    - Serper: the documentation site does not answer (docs.serper.dev has no DNS, serper.dev shows only a cookie banner). Other sources agree: `POST https://google.serper.dev/search`, header `X-API-KEY`, JSON body `q`, `num` (1...100, default 10), `tbs` (`qdr:h`, `qdr:d`, `qdr:w`, `qdr:m`, `qdr:y`), `gl`, `hl`, `page`. Response `organic[]` with `title`, `link`, `snippet`, `position`; also `relatedSearches`, `peopleAlsoAsk`. No site field, thus the adapter adds a `site:` term to `q`.
    - SearXNG: https://docs.searxng.org/dev/search_api.html gives `GET /search` with `q`, `format=json`, `time_range`. The source (`searx/webadapter.py`) accepts `day`, `week`, `month`, `year`. No count field, thus the count is the limit of the parse (the same as braveHTML and duckDuckGoHTML).
    - No production code maps a `WebSearchProvider` to an adapter yet; the chain gets `(provider, adapter)` pairs. Thus `SearXNGProvider` takes the base URL in its initializer.
    - `ProviderFallbackTests.swift` has 369 lines, thus the SearXNG chain test goes in a new `SearXNGChainTests.swift`.
    - Plan: move the calendar step of an age limit from `ExaProvider` to `SearchProviderSupport` (Kagi uses it for `filters.after`), and move the HTML text step of `BraveAPIProvider` to `SearchProviderSupport` (Kagi uses it too).
  timestamp: 2026-09-25T12:48:40.363690+00:00
- actor: claude-code
  id: 01m3ca8y3e5gwwv3brt05dnw1b
  text: |-
    Implementation landed (TDD: the tests failed first with "cannot find type", then with stub adapters: "serper needs an API key", ".noResults", "the endpoint is not a URL").

    What changed:
    - New adapters `SerperProvider`, `KagiProvider` (API v1, Bearer), `SearXNGProvider` (`isHostConfiguration = true`, base URL in `init(base:)`).
    - `SearchProviderSupport` now holds `text(ofHTML:)` (moved from `BraveAPIProvider`), `startDate(of:before:)` and `InvalidStartDate` (moved from `ExaProvider`), because Kagi uses both. Brave and Exa call the shared steps.
    - `KeyedProviderCase`: rows `serper`, `kagi`, `searxng`; `keyed` (5 rows) and `all` (6 rows); field `isHostConfiguration`. `KeyedProviderTests`: the key tests run over `keyed`; the other tests run over `all`.
    - New `ProviderRequestReading` test helper (query items, JSON body); `KeyedProviderRequestTests` uses it.
    - New suites `SerperKagiRequestTests`, `SearXNGRequestTests`, `SearXNGChainTests`.
    - Fixtures `serper-results.json`, `kagi-results.json`, `searxng-results.json`, written from the documentation (the user decision on ^p1t98nj covers this; no key is set here).
    - `web.md`: the Kagi row and the enum comment now show `POST /api/v1/search` and `Bearer`.

    Discoveries:
    - Kagi has no `year` value for `lens.time_relative`, thus the adapter sends `filters.after` (a `date`) from the time of the request, the same method as Exa.
    - Kagi example titles hold `&amp;` and `&#39;`, thus the adapter decodes the entities.
    - SearXNG `time_range` accepts `week` in `searx/webadapter.py`, but the documentation page lists only `day`, `month`, `year`.
    - The `files` tool `replace_all` edit replaced only the first match two times. Use one edit for each match.
    - `swift build` prints `warning: missing creator for mutated node` for the `mlx-swift_Cmlx.bundle` of the dependency. It is not from the changed files.

    Open for a later task: no production code maps a `WebSearchProvider` case to its adapter yet (the chain takes `(provider, adapter)` pairs). The capability task must map `.serper`, `.kagi`, `.searxng(url)` to these adapters.
  timestamp: 2026-09-25T12:57:32.526495+00:00
- actor: claude-code
  id: 01m3ca958fxhy2cj7gwrctz47r
  text: |-
    ### implement — changed
    - evidence: 20 files — new: Providers/SerperProvider.swift, Providers/KagiProvider.swift, Providers/SearXNGProvider.swift, Tests/SerperKagiRequestTests.swift, Tests/SearXNGRequestTests.swift, Tests/SearXNGChainTests.swift, Tests/Support/ProviderRequestReading.swift, WebGoldens/serper-results.json, WebGoldens/kagi-results.json, WebGoldens/searxng-results.json; changed: Providers/SearchProviderSupport.swift, Providers/BraveAPIProvider.swift, Providers/ExaProvider.swift, Tests/KeyedProviderTests.swift, Tests/KeyedProviderRequestTests.swift, Tests/Support/KeyedProviderCase.swift, web.md (and the two kanban files of this card). `swift test --filter "KeyedProviderTests|ProviderFallbackTests|SearXNGChainTests"`: 34 tests in 3 suites passed. `swift test`: 1725 tests in 137 suites passed. `swiftlint lint` on each changed Swift file: no violations.
    - next: /review
  timestamp: 2026-09-25T12:57:39.855774+00:00
- actor: claude-code
  id: 01m3cag0e9862svn2syj7hdt9r
  text: |-
    ### test — green
    - evidence: swift package clean; swift test — 1725 tests, 137 suites, 0 failures, 0 skipped. No warning in Sources or Tests. Five warnings remain, all from the vendored mlx-swift dependency (four C++17 extension warnings under .build/checkouts/mlx-swift, plus one SwiftPM build-graph note about its Cmlx.bundle resource copy). That code is not part of this repo, is git-ignored, and swift package update did not run, so no edit to it can persist.
    - next: none. The task is clear for the next step.
  timestamp: 2026-09-25T13:01:24.297316+00:00
- actor: claude-code
  id: 01m3cb4ed9rr8wcm81938npbwe
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (628900f). 3 findings (3 confirmed, 1 refuted). SearXNGProvider.swift:124, SerperProvider.swift:119, KeyedProviderTests.swift:95.
    - next: Do the 3 open items in the "Review Findings (2026-09-25 08:02)" section. Then do the review again. The task stays in review.
  timestamp: 2026-09-25T13:12:33.961827+00:00
- actor: claude-code
  id: 01m3cb4v7tbes2484eav3ntnar
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 20 files
    - test: green — swift test, 1725 passed
    - commit: 628900f
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearXNGProvider.swift:124, Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SerperProvider.swift:119, Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift:95
  timestamp: 2026-09-25T13:12:47.098434+00:00
- actor: claude-code
  id: 01m3cbhfb30ntd5mefvq6rg1es
  text: |-
    Review findings done (implement pass 2). The task is in doing.

    Finding 1 and 2 (`duplication/duplication`, SearXNGProvider.swift:124 and SerperProvider.swift:119): the cause is one `switch` over `SearchFreshness` for each provider, with only the return values different. The same cause was in 7 places in `Providers/`: SearXNG, Serper, Tavily, DuckDuckGoHTML, BraveAPI, BraveHTML (`private extension SearchFreshness` in each), and the `calendarStep` of `SearchProviderSupport` (Exa and Kagi use it).
    - New shared type `SearchFreshnessValues<Value: Sendable>` in `SearchProviderAdapter.swift`, beside `SearchFreshness`. It has one field for each age limit and one exhaustive `switch` in `value(for:)`. The compiler checks that each table has all four values.
    - Each provider now keeps one `private static let` table of its own documented values and calls `value(for:)`. All 7 `switch` copies are deleted.
    - `SearchProviderSupport.startDate(of:before:)` now reads `ageLimitUnits` (a `SearchFreshnessValues<Calendar.Component>`) and the named constant `ageLimitUnitCount = 1`.
    - TDD: new `SearchFreshnessValuesTests.swift`. It failed first with "cannot find 'SearchFreshnessValues' in scope", then passed. The existing freshness tests of each provider (Brave API, Brave HTML, DuckDuckGo, Tavily, Serper, SearXNG, Exa, Kagi) cover the table values and stay green.

    Finding 3 (`completeness/public-output-contract`, KeyedProviderTests.swift:95): Serper and Kagi now declare `let isHostConfiguration = false`. The same cause (an adapter that gets the value from the protocol default and does not declare it) was in Tavily, Exa, BraveAPI, BraveHTML, and DuckDuckGoHTML. Each of them now declares `let isHostConfiguration = false`. The protocol default (`extension SearchProviderAdapter { var isHostConfiguration: Bool { false } }`) had no user after that, thus it is deleted as dead code. The compiler now makes each new adapter declare the value. The protocol doc comment tells this.

    Discovery: the finding said that Serper and Kagi "will fail this assertion". That was not true before this change, because the protocol default gave `false`. The fix makes the declaration explicit in all adapters.

    Discovery: the `kanban` `move task` and `update task` ops return the whole board (about 69000 characters). Read the task file under `.kanban/tasks/` to verify the change.
  timestamp: 2026-09-25T13:19:40.899398+00:00
- actor: claude-code
  id: 01m3cbhk9bdshx399dmjdx7479
  text: |-
    ### implement — changed
    - evidence: 11 files — changed: Providers/SearchProviderAdapter.swift, Providers/SearchProviderSupport.swift, Providers/SearXNGProvider.swift, Providers/SerperProvider.swift, Providers/KagiProvider.swift, Providers/TavilyProvider.swift, Providers/ExaProvider.swift, Providers/BraveAPIProvider.swift, Providers/BraveHTMLProvider.swift, Providers/DuckDuckGoHTMLProvider.swift; new: Tests/FoundationModelsMultitoolTests/SearchFreshnessValuesTests.swift (and the two kanban files of this card). 3 of 3 review findings checked. `swift test --filter "KeyedProvider|ProviderFallback|SearXNG|SerperKagi|BraveHTML|DuckDuckGo|SearchFreshnessValues"`: 114 tests in 9 suites passed. `swift test`: 1726 tests in 138 suites passed. `swiftlint lint` on each Swift file of Providers/ and the new test: no violations. The one build warning is the known `missing creator for mutated node` note of the mlx-swift dependency.
    - next: /review
  timestamp: 2026-09-25T13:19:44.939263+00:00
- actor: claude-code
  id: 01m3cc3v9qf8yw2zv9wxv78aq7
  text: |-
    ### test — green
    - evidence: swift package clean; swift test — 1726 tests, 138 suites, 0 failures, 0 skipped. swiftlint lint on the repo — no violations (only a tool-version note: installed 0.65.1, config pins 0.48.0). 5 warnings remain, all from the vendored mlx-swift dependency under .build/checkouts (4 C++17 extension notes plus 1 SwiftPM build-graph note about its Cmlx.bundle resource copy). That code is not part of this repo, is git-ignored, and swift package update did not run, so no fix to it can stay. No warning is in Sources or Tests of this repo.
    - next: none. The task is ready for the next step.
  timestamp: 2026-09-25T13:29:42.967622+00:00
depends_on:
- 01M3A31T6MJJSGKHPG7P1T98NJ
position_column: doing
position_ordinal: '80'
title: 'Web: add the Serper, Kagi, and SearXNG providers'
---
## What
Add the other three providers of decision 4. Design: `web.md` § "The provider list". FIRST examine the current API documentation of each provider (WebFetch) and correct the endpoint, auth, request fields, and response fields that `web.md` gives from memory. Record the documentation URL in a doc comment on each adapter.

- `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SerperProvider.swift`: `POST https://google.serper.dev/search`, header `X-API-KEY`, JSON body `q`, `num` (and the time filter the docs give); parse `organic[].{title,link,snippet}`.
- `.../Providers/KagiProvider.swift`: `GET https://kagi.com/api/v0/search?q=&limit=`, `Authorization: Bot <key>`; parse the search result entries of `data[]` (type 0 only) with `title`, `url`, `snippet`.
- `.../Providers/SearXNGProvider.swift`: `GET <base>/search?q=&format=json` (and `time_range` for freshness); no key; parse `results[].{title,url,content}`. Set `isHostConfiguration = true`, so the chain sends the request with `guarded: false` (`web.md` § "Security"). Redirect hops and the result URLs a snippet fetches stay guarded.
- The same error mapping as the previous task. Declare only the features each adapter really sends.
- Record one real JSON response for each (for SearXNG, a response from any public instance with JSON on, or a hand-written response in the documented shape) into `Tests/FoundationModelsMultitoolTests/WebGoldens/`.

Note (2026-09-25): The documentation check changed the Kagi request. The current Kagi API is version 1: `POST https://kagi.com/api/v1/search`, `Authorization: Bearer <key>`, a JSON body, and `data.search[]` / `data.related_search[]` in the response. The adapter follows version 1, and `web.md` now shows it. No API key is set in this environment, thus the three JSON fixtures are written from the documentation of each provider. The decision of the user on ^p1t98nj (2026-09-25: fixtures from the provider documentation in place of real recorded responses) covers this card.

## Acceptance Criteria
- [x] Each adapter builds the documented request, and the key appears only in the auth header.
- [x] Each recorded response parses to hits with URLs and titles; Kagi related-search entries are not hits.
- [x] A chain with `[.searxng(URL(string: "http://127.0.0.1:8888")!)]` and a stub for that address sends the search request and returns hits (the host configuration is not refused by the guard).

## Tests
- [x] Extend `Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift` with these three adapters in the same parameterized suite.
- [x] Add to `ProviderFallbackTests.swift` (or a new `SearXNGChainTests.swift`) the stubbed SearXNG search at `http://127.0.0.1:8888` that returns hits.
- [x] Run `swift test --filter "KeyedProviderTests|ProviderFallbackTests|SearXNGChainTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-25 08:02)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 13 file(s) reviewed, 8 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 4 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/kagi-results.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/searxng-results.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/serper-results.json` — no validator matches this file
> - `web.md` — no validator matches this file

- [x] `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearXNGProvider.swift:124` `duplication/duplication` — The searxngTimeRange property contains the same switch/case structure as SerperProvider.serperTimeFilter, differing only in return values for each case. This is a changed-set duplicate—two blocks pasted into two new files in the same change with identical form and different values only. This pattern should be one function with an argument, not two copies. Extract a shared helper—either a mapping dictionary per API or a generic function that accepts a mapping parameter—so both properties delegate to one implementation. Example: create a method on SearchFreshness that accepts the case-value mapping as an argument, or extract static dictionaries per provider that both properties query.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SerperProvider.swift:119` `duplication/duplication` — The serperTimeFilter property contains the same switch/case structure as SearXNGProvider.searxngTimeRange, differing only in return values for each case. This is a changed-set duplicate—two blocks pasted into two new files in the same change with identical form and different values only. This pattern should be one function with an argument, not two copies. Extract a shared helper—either a mapping dictionary per API or a generic function that accepts a mapping parameter—so both properties delegate to one implementation. Example: create a method on SearchFreshness that accepts the case-value mapping as an argument, or extract static dictionaries per provider that both properties query.
- [x] `Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift:95` `completeness/public-output-contract` — The test at line 95 asserts that all adapters in KeyedProviderCase.all have an isHostConfiguration property, matching a KeyedProviderCase property of the same name. SearXNGProvider implements this property (line 47: `let isHostConfiguration = true`), but SerperProvider and KagiProvider do not—both providers will fail this assertion when the test runs. Add `let isHostConfiguration = false` to both SerperProvider and KagiProvider struct definitions (they have fixed endpoints, unlike SearXNG which requires host configuration). The property should appear with the other properties near the name and supports declarations. #web