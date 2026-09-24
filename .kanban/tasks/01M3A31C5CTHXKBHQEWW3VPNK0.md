---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3arw42hrrr9dfrxvtt9bj1g
  text: |-
    Research done.
    - The adapter pattern is `DuckDuckGoHTMLProvider`: `request` and `parse` are pure; `parse` uses `SearchProviderSupport.reading`, `rankedHits`, and `webURL(of:)`. The chain checks 401/403/429/5xx before `parse`, thus `parse` does not read the status.
    - `brave.rs` takes the URL from the first `a[href]` that starts with `http` in the container (not the parent of `.title`). A `.title` title is kept also when the URL comes from the fallback loop. An entry with no title or no URL is skipped before the duplicate check.
    - The chain test for "goes to the next provider" can use `WebStub` with the real Brave request URL as the route key, and a `FakeSearchAdapter` as the second provider.
    - `WebFetcher` keeps a `User-Agent` that the provider request sets (web.md, step 3).
  timestamp: 2026-09-24T22:34:12.433029+00:00
- actor: claude-code
  id: 01m3ascwzn1d2vchkhd1at0pf0
  text: |-
    Implementation landed (TDD: the test file failed first with "cannot find 'BraveHTMLProvider' in scope", then passed).
    - `BraveHTMLProvider` follows the `DuckDuckGoHTMLProvider` pattern. The URL is the first `a[href]` whose href has an explicit `http` or `https` scheme (in any case). Thus `/path`, `//host/path`, and `ftp:` are skipped, as in `brave.rs`.
    - Freshness: live requests with `tf=pd|pw|pm|py` (2026-09-24) each gave a page whose time filter shows "Past day", "Past week", "Past month", "Past year", with fewer results (2, 3, 16, 18 containers). The past-day page is recorded as `WebGoldens/brave-results-past-day.html`. Thus `supports` is `[.freshness, .site, .count]`.
    - Challenge: no real Brave challenge page was recorded. The markers are a `form[action*=captcha]` or the word "captcha" in the body text (in any case). A real results page holds "Switch to traditional captcha" in a script, thus script text is not a marker, and the marker check runs only when the page has no `[data-pos]`. A test covers this.
    - Shared code: `SearchProviderSupport.getRequest(to:items:accepting:)` (`jsonGetRequest` now calls it), and `SearchQuery.textWithSiteTerm`.
    - The ported Rust 429/503 tests and the happy-path test run through `WebSearchChain` with a `WebStub`. The Rust "default count 10" test runs with an explicit limit of 10, because in this design `nil` is all hits.
    - The recorded page gives 21 hits. It has no `.snippet-description`, thus each real snippet is empty. New task: "Web: read the snippet of the current Brave results markup".
    - The DuckDuckGo and Brave API adapters keep their own copy of the `site:` expression. New task: "Web: use SearchQuery.textWithSiteTerm in DuckDuckGoHTMLProvider and BraveAPIProvider".
    - The ported fixtures are in an extension of the suite in the same file, to keep the struct body under the swiftlint limit of 250 lines.
  timestamp: 2026-09-24T22:43:22.229295+00:00
- actor: claude-code
  id: 01m3asd0p8g0fhy35pa2dw3z07
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift (new), Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderSupport.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderAdapter.swift, Tests/FoundationModelsMultitoolTests/BraveHTMLProviderTests.swift (new), Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results.html (new, recorded), Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results-past-day.html (new, recorded), Tests/FoundationModelsMultitoolTests/WebGoldens/brave-challenge.html (new, hand-written). `swift test --filter BraveHTMLProviderTests`: 27 tests passed. `swift test`: 1701 tests in 134 suites passed, 0 failures. `swiftlint lint` on the changed Swift files: 0 violations.
    - next: /review
  timestamp: 2026-09-24T22:43:26.024078+00:00
- actor: claude-code
  id: 01m3asg1td72f9zcq9qspmy1t9
  text: |-
    ### test — green
    - evidence: swift test — 1701 tests, 134 suites, passed, 0 failed, 0 skipped; no compiler warnings in build output
    - next: ready for review
  timestamp: 2026-09-24T22:45:05.485201+00:00
- actor: claude-code
  id: 01m3asz70m9jtqfda2dkxvtqty
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (fb11807). 1 finding (1 confirmed, 1 refuted): Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift:82 swift/doc-parameter-naming.
    - next: Correct the doc comment. It must not name the external label `key` for the parameter with the internal name `_`. Remove this cause from all of BraveHTMLProvider.swift. Then run the review again. The task stays in review.
  timestamp: 2026-09-24T22:53:22.324305+00:00
- actor: claude-code
  id: 01m3aszpkwd3ytyv5s3nxmg3df
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files
    - test: green — swift test, 1701 passed
    - commit: fb11807
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift:82
  timestamp: 2026-09-24T22:53:38.300599+00:00
- actor: claude-code
  id: 01m3at5a8th235saqya47vs99k
  text: |-
    Fix of finding `swift/doc-parameter-naming` done.
    - Cause: a `- Parameters:` entry names the external label of a parameter whose internal name is `_`. In BraveHTMLProvider.swift, the cause occurs two times: `key` of `request(for:key:)` and `response` of `parse(_:response:limit:)`.
    - The same cause occurs two times in DuckDuckGoHTMLProvider.swift, at the same two functions. These are fixed also.
    - Fix: remove the entry for each `_` parameter, and put the fact ("The provider has no key and does not read the key value." / "The provider does not read the response.") in the summary text. The rule lets the prose use the external label. `request` now has only one entry, thus it uses the `- Parameter query:` form.
    - The other files in Providers/ (BraveAPIProvider, TavilyProvider, ExaProvider, SearchProviderAdapter, SearchProviderSupport) document `key` and `response` where these names are the internal names. They do not have this cause.
    - No test was added: the change is to doc comments only, and no behavior changed.
  timestamp: 2026-09-24T22:56:42.266431+00:00
- actor: claude-code
  id: 01m3at5chpd6a5e79bpw6j48f3
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Providers/DuckDuckGoHTMLProvider.swift. `swift test`: 1701 tests in 134 suites passed, 0 failures, no compiler warnings. `swiftlint lint` on the two files: 0 violations. Finding 1 of 1 is checked.
    - next: /review
  timestamp: 2026-09-24T22:56:44.598827+00:00
- actor: claude-code
  id: 01m3atg3e9bzcjn6kds3v8ha0a
  text: |-
    ### test — green
    - evidence: `swift build` first showed a warning about a mutated node for `mlx-swift_Cmlx.bundle`. This warning came from old build files, not from our code. `swift package clean` (not `swift package update`) removed the old build files. After this, `swift build` gave 0 warnings. `swift test` ran 1701 tests in 134 suites. All tests passed. 0 failures. 0 skips. 0 warnings.
    - next: ready for review
  timestamp: 2026-09-24T23:02:35.721991+00:00
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: doing
position_ordinal: '8180'
title: 'Web: port the Brave HTML provider from brave.rs'
---
## What
Port the keyless search path of swissarmyhammer. Source: `../swissarmyhammer/crates/swissarmyhammer-web/src/search/brave.rs` (request at `:53-107`, parse at `:116-240`). Design: `web.md` § "What we copy".

- Create `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift`, which conforms to `SearchProviderAdapter`:
  - Request: `GET https://search.brave.com/search?q=<percent-encoded>&source=web`, `Accept: text/html`, the desktop browser `User-Agent` of `brave.rs:55`. When `site` is set, add `site:<host>` to the query text. Supports `.site` and `.count`. Examine whether Brave takes a time filter parameter; add `.freshness` only if a recorded page proves that it works.
  - Parse with SwiftSoup: containers `[data-pos]`; title `a .title`, else the text of the first `http` anchor; URL the first `a[href]` that starts with `http`; snippet `.snippet-description`, else the first `<p>` with more than 20 characters; skip an entry with no title or no URL; remove duplicate URLs; decode entities; stop at `count`. No entries is `.noResults`.
  - A 200 page with no `[data-pos]` and a challenge marker (a captcha form or the known challenge text) is `.challenge`, not `.noResults`.
- Record one real Brave results page into `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results.html`, and add small hand-written pages for each fallback rule (port the fixtures of `brave.rs:283-660`) and one challenge page.

## Acceptance Criteria
- [x] The recorded page gives at least 5 hits, each with an `https` URL and a non-empty title.
- [x] Each ported fixture of `brave.rs` gives the same result as the Rust test.
- [x] The challenge page gives `.challenge`, and the chain goes to the next provider.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/BraveHTMLProviderTests.swift`: the request (URL, headers, the `site:` form), the recorded page, each fallback fixture, duplicates, the `count` limit, entity decode, the challenge page.
- [x] Run `swift test --filter BraveHTMLProviderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-24 17:45)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 11 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-challenge.html` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results-past-day.html` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results.html` — no validator matches this file

- [x] `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift:82` `swift/doc-parameter-naming` — The doc comment names the external parameter label `key` instead of the internal parameter name `_`. Documentation must name the internal (local) parameter name, never the external label, as Swift-DocC and Xcode resolve documentation against internal names. Either document the parameter as `- Parameter _:` (uncommon for ignored parameters) or omit it entirely, since the internal name is intentionally `_` to indicate the parameter is unused. #web