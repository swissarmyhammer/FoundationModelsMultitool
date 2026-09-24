---
assignees:
- claude-code
depends_on:
- 01M3A30QSWWD8A4GSMCD3C3DFQ
- 01M3A31C5CTHXKBHQEWW3VPNK0
- 01M3A31JYJRQ0Q7DR9VGF9E5NP
- 01M3A31T6MJJSGKHPG7P1T98NJ
- 01M3A32AEKXPYAX6SAEGY9KGJE
position_column: todo
position_ordinal: '9280'
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
- [ ] Each bad argument of both verbs gives the documented `correction` and does not throw.
- [ ] A failed search or fetch gives a `correction`; a non-2xx page is a normal result with `status` and content.
- [ ] A body larger than the byte limit gives a result with the truncation note in `notes`.
- [ ] Neither verb conforms to `BackgroundTool`.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebVerbArgumentTests.swift` with `WebStubURLProtocol`: each bound and enum value of both verbs (including `url` `ftp://x` and `site` `https://apple.com/x`), a stubbed search result shape, a stubbed fetch result shape, the truncation note.
- [ ] Run `swift test --filter WebVerbArgumentTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web