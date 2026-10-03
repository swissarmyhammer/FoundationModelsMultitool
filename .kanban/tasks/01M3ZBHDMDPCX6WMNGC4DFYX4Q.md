---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m40r1z476w2pptvnx0pwv3az
  text: |-
    ### Decision of the user — the stable check (2026-10-03)
    - The user accepted this check for the pages of the goal snippet:
      - each fetched page has a valid URL and a title, and its fetch did not fail;
      - at least one of the pages has content.
    - A page with empty content (for example a page that JavaScript draws, whose text is only inside `<noscript>`) passes with those checks. It proves that the fetch reached the page and that the converter worked, as a recognized block does for a search.
    - A transport error, a failed fetch, a page with no URL or no title, or no page with content fails the test.
    - A blocked search still goes through `BlockedProviderRule`.
    - No retry, no skip, no known-issue mark, no wider deadline.
    - The keyed web tests that skip when no API key is set stay as they are (the user answered "yea" to the question whether they stay).
  timestamp: 2026-10-03T11:23:12.903321+00:00
- actor: claude-code
  id: 01m40rd0zhh5h7gb2fembwnqk0
  text: |-
    ### Research (implement)
    - The goal snippet maps each fetch to `{ url, title, head }`. A failed fetch gives a `FetchResult` with a `correction`, the requested URL, status 0, title `nil`, and empty content (`Fetch.swift`, `corrective(_:url:)`). The map drops the `correction`, thus the test cannot see a failed fetch. Without it, a failed fetch looks the same as a page with no title.
    - Plan: the snippet also returns `correction: p.correction` for each page. `WebPageHead` (shared with the unit suite `WebRunCodeTests`) gets an optional `correction` with the default `nil`, thus the unit suite does not change.
    - Plan: a new helper `Web/Support/FetchedPagesRule.swift` holds the check, with the same shape as `BlockedProviderRule`: a pure function that gives the failures, and an `expect` function that records them. A new offline suite `Web/FetchedPagesRuleTests.swift` checks it with no network.
    - The count check `1...3` goes out of the test: the decision of the user does not include it. "At least one page has content" fails an empty list.
  timestamp: 2026-10-03T11:29:15.249709+00:00
- actor: claude-code
  id: 01m40sekh0nvv3058q0akjgg65
  text: |-
    ### Implementation landed
    - New helper `IntegrationTests/.../Web/Support/FetchedPagesRule.swift`: `failures(of:)` gives the failures of the pages (`fetchFailed`, `invalidURL`, `noTitle`, `noPageWithContent`), and `expectPages(_:output:)` records one issue for each failure.
    - New offline suite `Web/FetchedPagesRuleTests.swift` (8 tests, no network). RED first: with a stub that gave no failure, 7 of 8 tests failed on their assertions. GREEN: 8 of 8 pass.
    - `WebRunCodeLiveTests`: the snippet also returns `correction: p.correction` for each page, thus a failed fetch is visible. The pages go through `FetchedPagesRule`. The block still goes through `BlockedProviderRule`. The old count check `1...3` and the check "each page has content" are removed, as the decision of the user says.
    - `Tests/Support/MultitoolTestSupport/WebPageHead.swift`: an optional `correction` (`var`, thus the memberwise init and the unit suite `WebRunCodeTests` do not change).
    - web.md: the `WebRunCodeLiveTests` row states the check, a new `FetchedPagesRuleTests` row, and the Level 2 filter has `FetchedPagesRuleTests`.
    - Local live run: `WebRunCodeLiveTests` took the **results** branch (1 search and 3 fetch dispatches in the log, no `LIVE-SEARCH` block line), and it passed. Thus the search providers did not block this network on 2026-10-03.
    - No retry, no skip, no known-issue mark, no wider deadline, no score.
  timestamp: 2026-10-03T11:47:35.584882+00:00
- actor: claude-code
  id: 01m40sepsxcxzn5x6mtj8t66bh
  text: |-
    ### implement — changed
    - evidence: 5 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/WebRunCodeLiveTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/FetchedPagesRule.swift (new), IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/FetchedPagesRuleTests.swift (new), Tests/Support/MultitoolTestSupport/WebPageHead.swift, web.md. `swift test --package-path IntegrationTests --no-parallel --filter "FetchedPagesRuleTests|WebRunCodeLiveTests"`: 9 tests in 2 suites passed (live test took the results branch). Root `swift test`: 1895 tests in 155 suites passed.
    - next: /review. The CI box stays open: it needs a pushed commit and a real CI run that gives results.
  timestamp: 2026-10-03T11:47:38.941147+00:00
- actor: claude-code
  id: 01m40svwdeyg95g0fh2sx7t9xk
  text: |-
    ### test - green
    - evidence: root `swift test`: 1895 tests in 155 suites passed, 0 failed, 0 skipped. No warning from package sources. The only warning is "missing creator for mutated node" for mlx-swift_Cmlx.bundle, from the build system, not from package sources.
    - evidence: `swift build --build-tests --package-path IntegrationTests`: build complete, 0 errors, 0 warnings from IntegrationTests sources (same build-system warning only).
    - evidence: offline `FetchedPagesRuleTests|BlockedProviderRuleTests`: 23 tests in 2 suites passed.
    - evidence: live web group, one run, `--no-parallel`: 32 tests in 10 suites passed. 6 keyed tests skipped because no API key is set (braveAPI, tavily, exa, serper, kagi, searxng). This is the existing rule.
    - LIVE-SEARCH outcomes: results from duckDuckGoHTML (10 hits) in 2 DuckDuckGoHTMLLive tests. Block in 5 searches: 2 BraveHTMLLive (braveHTML HTTP 429), KeyedFallbackLive (braveAPI key refused HTTP 422, braveHTML HTTP 429), KeylessChainLive (braveHTML HTTP 429, duckDuckGoHTML challenge page), WebRunCodeLive (same two blocks).
    - note: WebRunCodeLive passed on the recognized block. The new page check (FetchedPagesRule on fetched pages) did not run against live pages in this run. Offline FetchedPagesRuleTests cover the rule. The open criterion (a real CI run that gives results) stays open.
    - next: review.
  timestamp: 2026-10-03T11:54:50.670762+00:00
- actor: claude-code
  id: 01m40swta1k2xz4b449784ztxq
  text: |-
    ### commit — changed
    - evidence: this commit — test(integration): check fetched pages in the live web test with FetchedPagesRule. It holds 5 source files (WebRunCodeLiveTests.swift, Web/Support/FetchedPagesRule.swift, Web/FetchedPagesRuleTests.swift, WebPageHead.swift, web.md) and the .kanban files of ^4dfyx4q and ^vn1899e. Local commit only, not pushed.
    - next: review. The CI box stays open: it needs a pushed commit and a real CI run that gives results.
  timestamp: 2026-10-03T11:55:21.281878+00:00
position_column: doing
position_ordinal: '80'
title: 'WebRunCodeLiveTests: a search hit that renders with JavaScript gives a page with no content and fails the test'
---
## Problem

In CI run 37061505863 (commit e2d35ff), `WebRunCodeLiveTests` ("the goal snippet returns 1 to 3 pages...") did not fail on a provider block. The keyless search gave results. Two of the fetched pages had an empty `head`:

- `https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/`
- `https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency`

Both are pages that render with JavaScript. The DocC page is an HTML shell: its only text is in `<noscript>`, and `HTMLMarkdown` removes `noscript` (web.md § "HTML to markdown"). Thus `fetch` gives an empty `content`, and the check `!page.head.isEmpty` fails. web.md § "Out of scope" puts a headless browser and JavaScript execution out of scope.

Card `^vn1899e` (the blocked provider rule) does not change this: an empty page is not a block, so it stays a failure. When the keyless search gives results in CI, this test can fail again, and the CI criterion of `^vn1899e` can stay red.

## What to decide

The assertion rule of web.md permits only facts that are stable for years. The test now asserts that each of the top 3 hits of a live search for "swift structured concurrency" has content. The search rank and the render method of those hits are not stable. A person must decide the correct stable fact (for example: at least one page has content, or a different query, or a different check). Do not add a retry, a skip, a known-issue mark, or a wider deadline.

## Acceptance criteria

- [x] The user decides the stable check for the pages of the goal snippet.
- [x] `WebRunCodeLiveTests` asserts only that stable check on results, and still uses `BlockedProviderRule` for a block.
- [x] web.md (the `WebRunCodeLiveTests` row) states the check.
- [ ] The live web suites pass in a real CI run that gives results (record the run id).
#ci