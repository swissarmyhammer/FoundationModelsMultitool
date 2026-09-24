---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
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
- [ ] `swift build` resolves and links SwiftSoup.
- [ ] Each golden HTML file converts to its golden markdown file with no difference.
- [ ] Relative links become absolute. Removed elements do not appear in the output.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebGoldens/` with small hand-written HTML files and their expected `.md` and `.txt` files: headings and lists, code fences with language, a table, relative links, a page with `<main>`, a page with nav/aside/ads, the three title sources.
- [ ] Create `Tests/FoundationModelsMultitoolTests/HTMLMarkdownTests.swift`, which loads the goldens with `Bundle.module` (the same method as `HashlineTests.swift:59`).
- [ ] Run `swift test --filter HTMLMarkdownTests`. All pass. Then run `swift test`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web