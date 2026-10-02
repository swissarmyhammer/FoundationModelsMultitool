---
assignees:
- claude-code
position_column: todo
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

- [ ] The user decides the stable check for the pages of the goal snippet.
- [ ] `WebRunCodeLiveTests` asserts only that stable check on results, and still uses `BlockedProviderRule` for a block.
- [ ] web.md (the `WebRunCodeLiveTests` row) states the check.
- [ ] The live web suites pass in a real CI run that gives results (record the run id).

#ci