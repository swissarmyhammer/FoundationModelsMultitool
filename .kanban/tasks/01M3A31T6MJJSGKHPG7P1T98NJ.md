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
- actor: claude-code
  id: 01m3c6qywpx8yrq458wz8kmkfm
  text: |-
    ### decision — 2026-09-25
    - The user accepts the JSON fixtures from the provider documentation for this card. The item "Record one real JSON response for each" is replaced by these fixtures. The keyed live tests (KeyedProviderLiveTests) test the real services when the keys are in CI.
    - next: review commit ac2e9b4.
  timestamp: 2026-09-25T11:55:50.550955+00:00
- actor: claude-code
  id: 01m3c7aa012qyb2q6bnh33w3gd
  text: |-
    ### review — findings
    - evidence: `review sha ac2e9b4~1..ac2e9b4` — 1 finding (1 confirmed, 0 refuted). Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderSupport.swift:254 `completeness/case-sensitivity-coverage`.
    - note: The user accepted the JSON fixtures from the provider documentation on 2026-09-25. Thus the missing live recordings are not a finding. The engine did not examine the three JSON files in `WebGoldens/`, because no validator matches them.
    - next: Add a test with an uppercase-scheme URL (for example `HTTPS://example.com`) to KeyedProviderTests. Then run /finish ^p1t98nj again. The task stays in `review`.
  timestamp: 2026-09-25T12:05:51.745311+00:00
- actor: claude-code
  id: 01m3c7ath5xm59r591zsp69d8e
  text: |-
    ### finish iteration 2 — findings
    - implement: no work (the user accepted the documentation fixtures)
    - test: green on ac2e9b4 (1674 passed)
    - commit: ac2e9b4 (no new commit)
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderSupport.swift:254
  timestamp: 2026-09-25T12:06:08.677944+00:00
- actor: claude-code
  id: 01m3c7m4w2qqkqwdyq65gdy002
  text: |-
    Finding fixed (TDD): `completeness/case-sensitivity-coverage` at SearchProviderSupport.swift `webURL`.

    - New test in `KeyedProviderTests.swift`: "a result with an upper-case URL scheme gives the same hit as the lower-case URL". It runs over the 3 adapters. It parses a body with `HTTPS://good.example/page` and a body with `https://good.example/page`. It makes the URL of each upper-case hit lower case, and then it expects the same hits: the same rank, title, snippet, and URL.
    - RED: I removed `.lowercased()` from the scheme check in `webURL(of components:)` for a short time. The new test failed for each provider with `.noResults`. Then I put `.lowercased()` back. The production source has no change.
    - GREEN: `swift test --filter KeyedProviderTests` passes, with 12 tests. `swift test` passes, with 1702 tests in 134 suites, 0 failures. `swiftlint lint` on the test file gives 0 findings.
    - Other case-insensitive checks in SearchProviderSupport.swift: the `.lowercased()` scheme check is the only one. `webURL(of text:)` sends its value to that check. The `defaultScheme` step and the host check do not compare case. `unreservedBytes` and the `%02X` format follow RFC 3986 exactly and do not compare text without case. Thus the one new test covers the full gap.
    - Discovery: `URLComponents` keeps the scheme as the provider wrote it. Thus a hit URL can start with `HTTPS://`, and `rankedHits` sees `HTTPS://a` and `https://a` as two different URLs. The test does not lock the spelling of the scheme, so a later scheme normalization does not break it.
    - Card: the user accepted the documentation JSON fixtures on 2026-09-25. I added a note to the recording item. I checked the 4 Acceptance Criteria items and the 2 Tests items, because the committed work (ac2e9b4) meets them.
  timestamp: 2026-09-25T12:11:14.178791+00:00
- actor: claude-code
  id: 01m3c7m77mqrkprjvg21h0h0fz
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift (+17 lines, 1 new parameterized test). RED by mutation (without `.lowercased()`: 3 failures, `.noResults`). GREEN: `swift test --filter KeyedProviderTests` 12 tests pass; `swift test` 1702 tests in 134 suites pass, 0 failures; swiftlint 0 findings.
    - next: run /test, then /commit, then /review. The task stays in `doing`.
  timestamp: 2026-09-25T12:11:16.596094+00:00
- actor: claude-code
  id: 01m3c8m5emn0evdjcnbzcsy4an
  text: |-
    ### test — green
    - evidence: `swift test` (2 runs) — 1702 tests in 134 suites passed, 0 failed, 0 skipped. `swiftlint lint --quiet` — 0 findings. `sah diagnostics check working` — 0 errors, 0 warnings.
    - note: each run prints one line — \"warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)\". This line is from the build system, about the vendored mlx-swift dependency's bundle under `.build/`, not from project source in `Sources/` or `Tests/`. It is not a compiler warning and not a lint finding. No source edit in this repo can remove it, and the launching order said not to run `swift package update`.
    - note: `swiftlint lint --quiet` also prints \"warning: Currently running SwiftLint 0.65.1 but configuration specified version 0.48.0.\" This is a tool self-check about the installed SwiftLint version, not a rule finding. Lint findings count is 0.
    - next: none. All tests pass. The build has zero project-source warnings and zero lint findings. Iteration 3 of this task is ready for the next step in the pipeline.
  timestamp: 2026-09-25T12:28:43.348073+00:00
- actor: claude-code
  id: 01m3c8ts37xhmcpfzschb84my9
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit e511883) — 0 findings (0 confirmed, 0 refuted). 1 file reviewed: Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift. 6 `.kanban/` files not reviewed (ignore rule).
    - prior finding: SearchProviderSupport.swift:254 `completeness/case-sensitivity-coverage` is fixed. The new parameterized test "a result with an upper-case URL scheme gives the same hit as the lower-case URL" parses `HTTPS://good.example/page` for each of the 3 adapters and compares the hits with the lower-case URL hits. The item is checked.
    - note: The user accepted the JSON fixtures from the provider documentation on 2026-09-25. Thus the missing live recordings are not a finding.
    - next: none. All prior findings are checked, and this pass has 0 new findings. The task moves to `done`.
  timestamp: 2026-09-25T12:32:20.071723+00:00
- actor: claude-code
  id: 01m3c8v4zh85536c4w3vgp9b5d
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 1 file (uppercase scheme test)
    - test: green — swift test, 1702 passed
    - commit: e511883
    - review: clean — 0 findings; prior finding checked; the task is in done
  timestamp: 2026-09-25T12:32:32.241531+00:00
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: done
position_ordinal: ffd980
title: 'Web: add the Brave API, Tavily, and Exa keyed providers'
---
## What
Add three of the six keyed providers (decision 4). Design: `web.md` § "The provider list". That table comes from memory. FIRST examine the current API documentation of each provider (WebFetch) and correct the endpoint, the auth header, the request fields, and the response fields. Record the documentation URL in a doc comment on each adapter.

- `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveAPIProvider.swift`: `GET https://api.search.brave.com/res/v1/web/search?q=&count=`, header `X-Subscription-Token`; `freshness` maps to `pd`/`pw`/`pm`/`py`; parse `web.results[].{title,url,description}`.
- `.../Providers/TavilyProvider.swift`: `POST https://api.tavily.com/search`, `Authorization: Bearer <key>`, JSON body with `query` and `max_results` (and the time range field if the docs have one); parse `results[].{title,url,content}`.
- `.../Providers/ExaProvider.swift`: `POST https://api.exa.ai/search`, header `x-api-key`, JSON body with `query` and `numResults`; parse `results[].{title,url}` and the snippet field the docs give.
- Each adapter maps 401/403 to `.badKey`, 429 to `.rateLimited`, 5xx to `.serverError`, an empty list to `.noResults`. Each declares only the `SearchFeature` values it really sends.
- Record one real JSON response for each into `Tests/FoundationModelsMultitoolTests/WebGoldens/` (remove any account data from it). Note (2026-09-25): the user accepted the JSON fixtures from the provider documentation for this item (see the decision comment). The keyed live tests (KeyedProviderLiveTests) test the real services when the keys are in CI.

## Acceptance Criteria
- [x] Each adapter builds the documented request: method, URL, auth header, body.
- [x] The key appears in the auth header and in no other part of the request (URL, body).
- [x] Each recorded response parses to hits with `https` URLs and titles.
- [x] Each error status maps to the documented `ProviderFailure`.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift` with one parameterized suite over these three adapters (the next task adds the other three): request shape, key placement, parse of the recorded response, error mapping.
- [x] Run `swift test --filter KeyedProviderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-25 06:56)

> Scope: `review sha ac2e9b4~1..ac2e9b4` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 7 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-api-results.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/exa-results.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/tavily-results.json` — no validator matches this file

- [x] `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderSupport.swift:254` `completeness/case-sensitivity-coverage` — The scheme is normalized via `.lowercased()` before comparison against `webSchemes`, correctly handling case-insensitivity (URL schemes are case-insensitive per RFC 3986), but no test exercises the non-canonical form (uppercase schemes like 'HTTPS://'). Add one test case to KeyedProviderTests that includes a FixtureResult with an uppercase-scheme URL (e.g., 'HTTPS://example.com') and verifies it is accepted and ranked the same as the lowercase equivalent, confirming the case-insensitive contract. #web