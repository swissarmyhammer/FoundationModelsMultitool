---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
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