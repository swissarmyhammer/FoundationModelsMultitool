---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ccgfpfq9h8yh7nmb8y3a5c
  text: |-
    Research done. Facts:
    - `WebSearchChain(providers:fetcher:environment:)` takes (provider, adapter) pairs. `WebPageReader(fetcher:)` is an actor. `WebFetcher(sessionConfiguration:policy:addressGuard:)`.
    - `WebAddressGuard(resolver:)` uses `SystemHostResolver` by default. That calls `getaddrinfo`. Thus WebContext gets an internal `resolver` parameter (default `SystemHostResolver()`), so tests use `PublicHostResolver` and no network.
    - `WebHit` is in `Providers/SearchProviderAdapter.swift` and is not `@Generable`. `SearchResult.results: [WebHit]` needs it to be `@Generable`. Plan: add `@Generable` to `WebHit` in place.
    - `PageWindow.truncated` gives the truncation fact. `WebFetchPolicy.maxBytes` gives `<n>`. `WebFetchPolicy.defaultFetchTimeout` (30) is the default `timeout`.
    - Adapters: `BraveHTMLProvider()`, `DuckDuckGoHTMLProvider()`, `BraveAPIProvider()`, `TavilyProvider()`, `ExaProvider()`, `SerperProvider()`, `KagiProvider()`, `SearXNGProvider(base:)`.
  timestamp: 2026-09-25T13:36:37.071875+00:00
- actor: claude-code
  id: 01m3cdawyc2d8phy6fm5tv1dcc
  text: |-
    Implementation landed (TDD: each test file failed first on missing types, then went green).
    - New: `Web/WebContext.swift` (one fetcher, reader, chain; `WebSearchProvider.searchAdapter` maps each case, exhaustive switch). `WebContext.init` has an internal `resolver:` parameter (default `SystemHostResolver()`) so tests use `PublicHostResolver` and no DNS lookup.
    - New: `Web/Search.swift`, `Web/Fetch.swift`. Both are plain `Tool`, no `BackgroundTool`.
    - Reuse: Read's private `BoundSpec` moved to `Files/BoundParameter.swift` (shared). It now also takes `maximum: nil` for a range with no upper end (`offset` ≥ 0 gives "... must be a character offset of 0 or more."). Read messages do not change (FilesReadTests and CorrectiveVocabularyTests green).
    - Reuse: GlobEngine's private `Rejection` became the shared `CorrectiveRejection` in `CorrectiveResult.swift`. GlobEngine keeps a private typealias to it.
    - Changed: `WebHit` is now `@Generable` (needed by `SearchResult.results`). `SearchFreshness` is `CaseIterable`. `WebPageFormat` has `String` raw values and is `CaseIterable`. The correction lists come from those cases.
    - Discovery: when `count` is omitted, the verb sends `count: nil` to the chain (thus no false "count is not supported" note), and it cuts the hits to 10 itself.
    - Discovery: `Tests/.../Fixtures/BuilderSurfaceFixtures.swift` declares a test-module `SearchArguments`. It shadows the library type in the test target. The web tests do not name the type (they use `.init(...)`).
    - Discovery: `WebStub` routes by the exact URL text; a request to `HTTPS://...` keeps the upper-case scheme.
    - Tests: `WebVerbArgumentTests.swift`, `WebContextTests.swift`, `Support/WebVerbFixture.swift`. `swift test --filter 'WebVerbArgument|WebContext'` 34 tests pass. `swift test` 1760 tests in 140 suites pass. `swiftlint lint` on the new and changed web files: 0 warnings (the old warnings in GlobEngine.swift and Read.swift are on lines this change did not touch).
    - No ARCHITECTURE.md exists.
  timestamp: 2026-09-25T13:51:02.604535+00:00
- actor: claude-code
  id: 01m3cdb0v25955zga3fzy91c1j
  text: |-
    ### implement — changed
    - evidence: 12 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebContext.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Search.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Fetch.swift, Sources/FoundationModelsMultitool/Capabilities/Files/BoundParameter.swift, Sources/FoundationModelsMultitool/Capabilities/Files/CorrectiveResult.swift, Sources/FoundationModelsMultitool/Capabilities/Files/GlobEngine.swift, Sources/FoundationModelsMultitool/Capabilities/Files/Read.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderAdapter.swift, Sources/FoundationModelsMultitool/Capabilities/Web/WebPageReader.swift, Tests/FoundationModelsMultitoolTests/WebVerbArgumentTests.swift, Tests/FoundationModelsMultitoolTests/WebContextTests.swift, Tests/FoundationModelsMultitoolTests/Support/WebVerbFixture.swift; swift test: 1760 tests in 140 suites pass
    - next: review
  timestamp: 2026-09-25T13:51:06.594164+00:00
- actor: claude-code
  id: 01m3ce8cq3ht0mm8qeq577ryke
  text: |-
    ### test — green
    - evidence: command `swift test`. Result: 1760 tests pass. 0 tests fail. 0 tests skip. 0 build warnings.
    - next: send the task to the review step.
  timestamp: 2026-09-25T14:07:09.027457+00:00
depends_on:
- 01M3A30QSWWD8A4GSMCD3C3DFQ
- 01M3A31C5CTHXKBHQEWW3VPNK0
- 01M3A31JYJRQ0Q7DR9VGF9E5NP
- 01M3A31T6MJJSGKHPG7P1T98NJ
- 01M3A32AEKXPYAX6SAEGY9KGJE
position_column: doing
position_ordinal: '80'
title: 'Web: add WebContext and the search and fetch verbs'
---
## What
Add the two verbs as plain `FoundationModels.Tool` conformers over one shared context. Design: `web.md` § "The surface" and § "Corrections, not throws". Decisions 2 and 3: `search` never fetches pages; both verbs are synchronous (no `BackgroundTool`). The next task mounts them (`WebCapability`, `withWeb`).

- `Sources/FoundationModelsMultitool/Capabilities/Web/WebContext.swift`: `final class WebContext` holds one `WebFetcher`, one `WebPageReader`, and one `WebSearchChain`, all made from a `WebConfiguration` and a `URLSessionConfiguration`. It maps each `WebSearchProvider` case to its adapter.
- `.../Web/Search.swift`: `@Generable SearchArguments` (`query`, `count`, `freshness`, `site`), `@Generable SearchResult` (`provider`, `results: [WebHit]`, `notes`, `correction`), `struct Search: Tool` with `name = "search"`. Checks:
  - `query` trimmed, 1 to 500 characters.
  - `count` 1 to 20 (default 10).
  - `freshness` `day|week|month|year` through `EnumParameter` (`Capabilities/Files/EnumParameter.swift:51`).
  - `site` must be one host name: no scheme, no path, no space, only letters, digits, `-` and `.`. Else the correction ``The `site` parameter must be one host name, for example developer.apple.com: <value>``.
- `.../Web/Fetch.swift`: `@Generable FetchArguments` (`url`, `format`, `offset`, `maxCharacters`, `timeout`), `@Generable FetchResult` (`url`, `status`, `contentType`, `title`, `content`, `totalCharacters`, `nextOffset`, `notes`, `correction`), `struct Fetch: Tool` with `name = "fetch"`. Checks:
  - `url` must parse as an absolute `http` or `https` URL. Else the correction ``The `url` parameter must be an absolute http or https URL: <value>``.
  - `maxCharacters` 500 to 200000 (default 20000); `timeout` 1 to 120 (default 30); `offset` ≥ 0; `format` `markdown|text|raw`.
  - When the page download stopped at the byte limit, `notes` has `The download stopped at <n> bytes. The page is not complete.`
- The `description` of each verb tells the model when to use it, that `search` then `fetch` in one snippet is the normal pattern, and that `Promise.all` fetches pages in parallel.

## Acceptance Criteria
- [x] Each bad argument of both verbs gives the documented `correction` and does not throw.
- [x] A failed search or fetch gives a `correction`; a non-2xx page is a normal result with `status` and content.
- [x] A body larger than the byte limit gives a result with the truncation note in `notes`.
- [x] Neither verb conforms to `BackgroundTool`.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/WebVerbArgumentTests.swift` with `WebStubURLProtocol`: each bound and enum value of both verbs (including `url` `ftp://x` and `site` `https://apple.com/x`), a stubbed search result shape, a stubbed fetch result shape, the truncation note.
- [x] Run `swift test --filter WebVerbArgumentTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web