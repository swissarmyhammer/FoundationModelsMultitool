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
- actor: claude-code
  id: 01m3cewc8frntkx3zbhmwxr61v
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (b882f11). 1 finding (1 confirmed, 1 refuted). Sources/FoundationModelsMultitool/Capabilities/Web/Search.swift:149
    - next: Add a test that sends mixed-case `freshness` (for example "DAY") and gets the same result as lower case. Then review again.
  timestamp: 2026-09-25T14:18:03.919817+00:00
- actor: claude-code
  id: 01m3cewq60g2wdys4qchnwkfkn
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 files
    - test: green — swift test, 1760 passed
    - commit: b882f11
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Web/Search.swift:149
  timestamp: 2026-09-25T14:18:15.104643+00:00
- actor: claude-code
  id: 01m3ceze50adbts4e2re3z0xt4
  text: |-
    Research for the review finding (Search.swift:149, case-sensitivity-coverage).
    - The cause: a token match that ignores case (`.lowercased()`), with no test that proves the mixed-case spelling gives the same result as the lower-case spelling.
    - Search.swift: one such match, `freshness`. The test `freshnessIsAccepted` already sends "DAY" and "Week", but it does not compare the result with the lower-case result.
    - Fetch.swift: two such matches. `format` (`.lowercased()` before `WebPageFormat(rawValue:)`): the test `formatIsAccepted` sends "RAW" but only checks that there is no correction; it does not prove that the format is raw. The URL scheme (`httpURL`): the test `upperCaseSchemeIsAccepted` sends "HTTPS://" and checks the content against the page text, which is the lower-case result.
    - WebContext.swift: no token match that ignores case. Nothing to change.
    - Plan: add one test for `freshness` that compares the upper-case result with the lower-case result, and one test for `format` that compares the "RAW" content with the "raw" content and with the unchanged HTML body. The tests go in WebVerbArgumentTests.swift, where the verb tests are. WebContextTests.swift tests only the context, and WebVerbFixture.swift is a helper, not a test file.
  timestamp: 2026-09-25T14:19:44.160218+00:00
- actor: claude-code
  id: 01m3cf5dr81fa1kftm7nb1qmtx
  text: |-
    Review finding fixed (Search.swift:149, completeness/case-sensitivity-coverage). Only the test file changed. The production code did not change.
    - New test `upperCaseFreshnessMatchesLowerCase`: it sends `freshness` "day" and "DAY" to one fixture. It checks that the lower-case search gives 1 hit, and that the upper-case result has the same correction, provider, hits, and notes.
    - The same cause in Fetch.swift: `format` is lower-cased before the match, and the old test `formatIsAccepted` ("RAW") only checked that there is no correction. New test `upperCaseFormatMatchesLowerCase`: it fetches one HTML page with "raw" and "RAW". It checks that "RAW" gives no correction, the same content as "raw", and the unchanged HTML body (thus the raw format really took effect, not markdown).
    - The URL scheme in Fetch.swift (`httpURL`) is also lower-cased. The existing test `upperCaseSchemeIsAccepted` already sends "HTTPS://" and checks the content against the page text. Thus it already proves the mixed-case result.
    - WebContext.swift: no token match that ignores case. No change.
    - The HTML body is now the constant `htmlPage`. `fetchResultShape` uses it too, thus the literal is not written two times.
    - The tests go in WebVerbArgumentTests.swift, not in WebContextTests.swift. WebContextTests.swift tests only the context, and WebVerbFixture.swift is a helper.
    - TDD proof: both new tests passed on the current code, because the behavior was already there. To prove that they can fail, I removed `.lowercased()` from Search.swift and Fetch.swift for a short time. Both new tests then failed (the upper-case freshness gave provider "" and no hits; "RAW" gave the format correction). Then I restored the two lines. `git diff` shows no change to the source files.
    - `swift test`: 1762 tests in 140 suites pass (1760 before, plus 2). `swiftlint lint` on WebVerbArgumentTests.swift: 0 violations. The build prints one SwiftPM notice, "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It is from the build system, not from a compiler diagnostic, and it is not related to this change.
  timestamp: 2026-09-25T14:23:00.360032+00:00
- actor: claude-code
  id: 01m3cf5fx980gb2ze5mgknby53
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/WebVerbArgumentTests.swift (new tests upperCaseFreshnessMatchesLowerCase and upperCaseFormatMatchesLowerCase, new constant htmlPage); swift test: 1762 tests in 140 suites pass; finding Search.swift:149 checked
    - next: test, then review
  timestamp: 2026-09-25T14:23:02.569508+00:00
- actor: claude-code
  id: 01m3cfb4ybqf0kzwng2wrqjygw
  text: |-
    ### test — green
    - evidence: command `swift test`. Result: 1762 tests pass. 0 tests fail. 0 tests skip. `swift build --build-tests`: 0 compiler warnings. The build shows one message about the mlx-swift `Cmlx` bundle. This message comes from the SwiftPM build system, not from a compiler check. The message is not new and it does not come from this change. `swiftlint lint` on the changed file (`WebVerbArgumentTests.swift`): 0 violations.
    - next: send the task to the review step.
  timestamp: 2026-09-25T14:26:07.947443+00:00
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
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-25 09:08)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Web/Search.swift:149` `completeness/case-sensitivity-coverage` — The freshness parameter is normalized to lowercase before enum matching (line 149: `.lowercased()`), allowing mixed-case input like "DAY" or "Month" to work. This is intentional but unverified — test files in scope do not exercise non-lowercase input. Add one test case in WebVerbFixture or WebContextTests asserting that mixed-case freshness works, e.g., `try await fixture.search(freshness: "DAY")` produces the same result as lowercase. #web