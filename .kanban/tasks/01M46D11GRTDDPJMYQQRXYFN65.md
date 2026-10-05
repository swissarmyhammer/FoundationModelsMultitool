---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m46f401bvq54tdam89xgj71t
  text: |-
    Research (implement step):
    - The real service did not give the no-results page. Two POSTs to https://html.duckduckgo.com/html/ with packageUserAgent and the task query (30 s apart) gave HTTP 202 and the anomaly form (a challenge page, 46 matches of anomaly-modal/challenge-form). Thus duckduckgo-no-results.html is made from duckduckgo-results.html: the head and the search form are kept (the title and the q value hold the task query), each result container (ads and organic) and the "Next" nav-link form are removed, and the #links.results container is empty. The test doc comment tells this.
    - WebStub routes by the URL only. The DuckDuckGo request is a POST to one fixed URL, so the exact query and the relaxed query have the same URL. To read the form body in the URLProtocol, the stub must read httpBodyStream. LoopbackURLProtocol.body(of:) (MCPTestServer) already does this, but it is private and outside this change, and the duplication rule forbids a copy and forbids an edit of the counterpart. Thus the chain test uses a test-only adapter that wraps DuckDuckGoHTMLProvider: it sends the real POST and parses with the real provider, but it sets the URL of each request from the query text. The stub then gives the no-results page to the URL of the exact query and the results page to the URL of the relaxed query.
    - SkippedProvider keeps only the reason text now. To find .noResults, it will keep the ProviderSkip value and make the reason from it.
    - web.md § "Fallback" is the spec of the chain. It gets one paragraph about the relaxed second run.
  timestamp: 2026-10-05T16:42:28.779872+00:00
- actor: claude-code
  id: 01m46fhexx556qcs66wd5yt9w7
  text: |-
    Implementation landed (TDD: RED watched with a stub relaxedText that gave back the text; 14 new tests failed for the missing feature, then GREEN).
    - WebSearchChain.search now calls run(query) (one pass over the providers, returns ChainRun .hits or .allFailed). On .allFailed, relaxedSearch runs one more pass only when a SkippedProvider gaveNoResults, and the relaxed text is not empty and is not equal to query.text. Hits of that pass get the note "No results for the exact query; these are the results for: <relaxed>" first, then the notes of that pass; all notes are redacted. Else the correction of the exact query is returned.
    - WebSearchChain.relaxedText(of:) is one static function with its own doc comment. Decisions to know: the value after site:/intitle:/inurl:/filetype: stays as a word (only the operator goes); the operator match is case-insensitive (test with SITE: and InTitle:); OR/AND are removed only in upper case, because lower case "or"/"and" are normal words (test); typographic single quote marks stay, because the right single quote is also the apostrophe.
    - SkippedProvider now keeps the ProviderSkip value, not the reason text, so the chain can find .provider(.noResults).
    - Test seam: Tests/.../Support/QueryRoutedAdapter.swift wraps an adapter and sets the request URL from the query text, so the WebStub gives one reply to the exact query and another to the relaxed query.
    - web.md § "Fallback" has one new paragraph about the relaxed run.
    - Integration tests: the live queries are plain text (for example "swift programming language"), so their relaxed text is the same and no live test changes behavior. The integration package was not run in this step.
  timestamp: 2026-10-05T16:49:50.013992+00:00
- actor: claude-code
  id: 01m46fhk72qqgs4x6qhmnfjz5p
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift, Tests/FoundationModelsMultitoolTests/RelaxedQueryTests.swift (new), Tests/FoundationModelsMultitoolTests/Support/QueryRoutedAdapter.swift (new), Tests/FoundationModelsMultitoolTests/WebGoldens/duckduckgo-no-results.html (new, made from duckduckgo-results.html because the real service gave HTTP 202 and a challenge page two times), Tests/FoundationModelsMultitoolTests/ProviderFallbackTests.swift, Tests/FoundationModelsMultitoolTests/DuckDuckGoHTMLProviderTests.swift, Tests/FoundationModelsMultitoolTests/Support/FakeSearchAdapter.swift, web.md. Commands: `swift test --filter "RelaxedQueryTests|ProviderFallbackTests|DuckDuckGoHTMLProviderTests"` RED 14 failing tests (18 issues) of 51, then GREEN 51/51; `swift build --build-tests` complete; `swift test` 1829 tests in 152 suites passed, 0 failures. The one warning ("missing creator for mutated node" on the mlx-swift_Cmlx bundle) comes from the dependency build, not from this change.
    - next: /review
  timestamp: 2026-10-05T16:49:54.402105+00:00
- actor: claude-code
  id: 01m46fmav3ch3cnpedsha3772m
  text: |-
    ### test — green
    - evidence: swift test — 1829 tests in 152 suites passed, 0 failed, 0 skipped; cd IntegrationTests && swift build --build-tests — Build complete, 0 errors. Only warning: known mlx-swift "missing creator for mutated node" (dependency).
    - next: review
  timestamp: 2026-10-05T16:51:24.131345+00:00
- actor: claude-code
  id: 01m46fn46cs4kqsqvs1cwnpeqp
  text: |-
    ### commit — changed
    - evidence: 9a10746 fix: run the web search chain again with a relaxed query
    - next: test and review
  timestamp: 2026-10-05T16:51:50.092508+00:00
- actor: claude-code
  id: 01m46fy05yfjfs7vngbhre1967
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit b0771ed; the commit comment above names 9a10746, which the amend changed to b0771ed). Counts: findings 0, confirmed 0, refuted 0, attempted 7, failed 0, skipped 0. 6 files reviewed. Not reviewed: 4 .kanban files (.reviewignore); duckduckgo-no-results.html and web.md (no validator matches). No renamed files in git diff -M, thus no file-scoped review was necessary. No earlier Review Findings section.
    - next: none — task moved to done
  timestamp: 2026-10-05T16:56:40.894555+00:00
- actor: claude-code
  id: 01m46fyh89rw9myms8yae4401m
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files (WebSearchChain.swift, RelaxedQueryTests.swift, QueryRoutedAdapter.swift, duckduckgo-no-results.html, ProviderFallbackTests.swift, DuckDuckGoHTMLProviderTests.swift, FakeSearchAdapter.swift, web.md)
    - test: green — swift test, 1829 passed in 152 suites; IntegrationTests build complete
    - commit: b0771ed
    - review: clean — 0 findings, 7 of 7 checks ran
  timestamp: 2026-10-05T16:56:58.377903+00:00
position_column: done
position_ordinal: ffffa780
title: 'Web search: run the chain again with a relaxed query when no provider has results'
---
## Problem

A SWE-bench run (16 django instances, model mlx-community/Qwen3.8-27B-mxfp4, reported by the FoundationModelsACPAgent session) sent this query two times:

`Django ticket "Add model class to app_list context" Raffaele Salmaso`

Each time the result was: `No search provider gave results. braveHTML: blocked (HTTP 429). duckDuckGoHTML: no results.`

The peer session sent the same POST to `html.duckduckgo.com/html/` with `packageUserAgent`. The result was HTTP 200 and 0 `.result__a`. A simple query (`django admin app_list model class`) gave HTTP 200 and 10 `.result__a`. Thus the provider is correct, and the query is too narrow. The model did not make the query wider. It stopped searching.

## Where

- `Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift`, `search(_:)` (lines 68-84). The loop collects `SkippedProvider` values, then returns `.correction`.
- `ProviderSkip.provider(.noResults)` is the failure to look for. `ProviderFailure` is in `Providers/SearchProviderAdapter.swift`.
- `SearchQuery` (`Providers/SearchProviderAdapter.swift:80`) has `text`, `site`, and other fields. `textWithSiteTerm` adds `site:` from the `site` field. Do not remove the `site` field. Remove only operators that the model typed in `text`.

## Fix

1. When every provider fails, and one or more failures is `.noResults`, make a relaxed text from `query.text`:
   - Remove the quote marks (`"` and the typographic quote marks).
   - Remove the search operators in the text: `site:`, `intitle:`, `inurl:`, `filetype:`, a leading `-` or `+` on a word, and `OR`/`AND` as words.
   - Collapse the whitespace.
2. If the relaxed text is empty, or is equal to `query.text`, do not run again. Return the correction as before.
3. Else run the chain one more time with a copy of the query that has the relaxed text. Run it only one time (no loop).
4. If the second run gives hits, add this note first in `notes`: `No results for the exact query; these are the results for: <relaxed>`. Keep the skip notes of the second run after it. Redact the keys in the note as the other notes are redacted.
5. If the second run fails too, return the correction of the first run (the correction of the exact query). Task "Web search: the correction tells the model what to do" adds the next step to that text.

Put the relax function in one static function with its own doc comment, so a test can call it directly.

## Tests

- Add a recorded DuckDuckGo page with no results: `Tests/FoundationModelsMultitoolTests/WebGoldens/duckduckgo-no-results.html` (the HTML page for 0 `.result__a`). Record it from the real service with `packageUserAgent`, for the query above.
- Chain test (pattern of `ProviderFallbackTests.swift` and `DuckDuckGoHTMLProviderTests.swift`, with `WebStub`): the exact query gets the no-results page; the relaxed query gets `duckduckgo-results.html`. Expect `.hits` and the note as the first note.
- Test: the relaxed text equals the exact text (no quote marks, no operators) → no second request, and the correction is the same as before.
- Test: all providers fail with no `.noResults` (for example HTTP 429 and a challenge page) → no second request.
- Unit tests of the relax function: quote marks, each operator, a word with `-`, whitespace.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- The second run occurs only for the cause above, and only one time. #web #defect