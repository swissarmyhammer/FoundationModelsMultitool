---
assignees:
- claude-code
depends_on:
- 01M3A310C33P2DWGRX67YFR99X
- 01M3A2ZQDDZWJVE2MA3GFABKGY
position_column: todo
position_ordinal: '8680'
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
- [ ] The recorded page gives at least 5 hits, each with an `https` URL and a non-empty title.
- [ ] Each ported fixture of `brave.rs` gives the same result as the Rust test.
- [ ] The challenge page gives `.challenge`, and the chain goes to the next provider.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/BraveHTMLProviderTests.swift`: the request (URL, headers, the `site:` form), the recorded page, each fallback fixture, duplicates, the `count` limit, entity decode, the challenge page.
- [ ] Run `swift test --filter BraveHTMLProviderTests`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web