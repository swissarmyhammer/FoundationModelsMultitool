---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3a6dafr6fqa8v3b706ywc58
  text: |-
    Research:
    - The current SwiftSoup release is 2.13.9 (git ls-remote, 2026-09-24). Package.swift uses `from: "2.13.9"`, as the card says "use the current release". `swift package resolve` gets 2.13.9.
    - No `WebTextFormat`, `ConvertedPage` or `HTMLMarkdown` exists yet. `Capabilities/Web/` holds `KeyRedaction.swift` and `WebConfiguration.swift` only.
    - SwiftSoup API: `SwiftSoup.parse(html, baseUri)`, `Element.select(css)`, `Node.remove()`, `Node.absUrl("href")` (resolves against the base URI and against a `<base href>`), `Document.title()`, `TextNode.getWholeText()`.
    - Package.resolved is git-ignored. A new dependency changes no tracked lock file.
    - Decisions for the parts the card does not state: the title comes from the DOM after the removal step; `.text` keeps the numbers of an ordered list and has no bullet for an unordered list; `.text` separates table cells with a tab; the output ends with one newline.
  timestamp: 2026-09-24T17:11:33.112523+00:00
- actor: claude-code
  id: 01m3a6z888878gcdqw9fjd1j5f
  text: |-
    Implementation done (TDD):
    - RED 1: `swift build --build-tests` failed with "cannot find 'WebTextFormat' in scope". RED 2: with an empty stub, 24 issues failed as expected. `removedElementsDoNotAppear` passed on empty output, which proves nothing, so the test now also requires "Story one." in the output.
    - GREEN: `HTMLMarkdown.swift` has `WebTextFormat`, `ConvertedPage`, `HTMLMarkdown.convert`, and a private `HTMLBlockRenderer` that walks the DOM. Links use SwiftSoup `absUrl("href")`, which also obeys a `<base href>`.
    - Refactor while green: extracted `inlineCode`, `cells(of:)`, and `lines(of:separator:)`. `ListItemMarker.init(text:)` is in an extension so that the struct keeps its synthesized memberwise initializer.
    - Added `runOfEmptyLinesBecomesOneEmptyLine`. I watched it fail with the collapse regex removed, then put the regex back.
    - A trap: a Swift regex literal cannot start with a space, so `/ {2,}/` must be written `/\ {2,}/`.
    - The full `swift test` output has one "warning: missing creator for mutated node" line. It names `mlx-swift_Cmlx.bundle`. It comes from the mlx dependency build and is not from this change.
    - No ARCHITECTURE.md exists in the repository.
  timestamp: 2026-09-24T17:21:20.648137+00:00
- actor: claude-code
  id: 01m3a6zcefy40rykavefbmwba0
  text: |-
    ### implement — changed
    - evidence: 30 files — Package.swift, Sources/FoundationModelsMultitool/Capabilities/Web/HTMLMarkdown.swift, Tests/FoundationModelsMultitoolTests/HTMLMarkdownTests.swift, Tests/FoundationModelsMultitoolTests/WebGoldens/ (27 files: 9 pages x .html/.md/.txt). `swift test --filter HTMLMarkdownTests`: 7 tests, all pass. `swift test`: 1551 tests in 125 suites, all pass.
    - next: /review
  timestamp: 2026-09-24T17:21:24.943533+00:00
- actor: claude-code
  id: 01m3a73y9z7gsty3pab40x8a8h
  text: |-
    ### test — green
    - evidence: swift test — 1551 tests in 125 suites, 0 failures, 0 skipped. swift build --build-tests (forced rebuild) — build complete, no source warnings. The only warning is the pre-existing third-party mlx-swift bundle warning ("missing creator for mutated node ... Cmlx.bundle").
    - next: ready for review.
  timestamp: 2026-09-24T17:23:54.303798+00:00
position_column: doing
position_ordinal: '80'
title: 'Web: add SwiftSoup and HTMLMarkdown converter with goldens'
---
## What
Add the HTML parser dependency and the converter from HTML to markdown and to text. Design: `web.md` § "HTML to markdown" and § "Decisions", item 1 (SwiftSoup is confirmed).

- `Package.swift`: add `.package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")` (use the current release) and add the `SwiftSoup` product to the `FoundationModelsMultitool` library target. Add `.copy("WebGoldens")` to the resources of the unit test target (beside `.copy("FilesGoldens")`, `Package.swift:556`).
- Create `Sources/FoundationModelsMultitool/Capabilities/Web/HTMLMarkdown.swift`:
  - `enum HTMLMarkdown { static func convert(html: String, baseURL: URL, format: WebTextFormat) throws -> ConvertedPage }` where `ConvertedPage` has `title: String?` and `text: String`, and `WebTextFormat` is `.markdown` or `.text`.
  - Remove `script`, `style`, `nav`, `aside`, `header`, `footer`, `form`, `noscript`, `svg`, `iframe`, `.sidebar`, `.ad`, `.ads`, `.advertisement`.
  - Use `<main>` or `<article>` when there is exactly one, else `<body>`.
  - Emit headings, paragraphs, lists, links as `[text](absolute-url)` (resolve against `baseURL`), `pre` as fenced code with the language from `class="language-x"`, inline code, blockquote, emphasis, and simple tables. Remove runs of empty lines.
  - `title`: `<title>`, else `og:title`, else the first `<h1>`.
  - `.text` does the same walk with no markdown marks.

## Acceptance Criteria
- [x] `swift build` resolves and links SwiftSoup.
- [x] Each golden HTML file converts to its golden markdown file with no difference.
- [x] Relative links become absolute. Removed elements do not appear in the output.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/WebGoldens/` with small hand-written HTML files and their expected `.md` and `.txt` files: headings and lists, code fences with language, a table, relative links, a page with `<main>`, a page with nav/aside/ads, the three title sources.
- [x] Create `Tests/FoundationModelsMultitoolTests/HTMLMarkdownTests.swift`, which loads the goldens with `Bundle.module` (the same method as `HashlineTests.swift:59`).
- [x] Run `swift test --filter HTMLMarkdownTests`. All pass. Then run `swift test`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web