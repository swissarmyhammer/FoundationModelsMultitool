---
assignees:
- claude-code
position_column: todo
position_ordinal: '9480'
title: 'Web: use SearchQuery.textWithSiteTerm in DuckDuckGoHTMLProvider and BraveAPIProvider'
---
## What
`SearchQuery.textWithSiteTerm` (in `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderAdapter.swift`) makes the query text with a `site:<host>` term. `BraveHTMLProvider` uses it. Two older adapters keep their own copy of the same expression, `query.site.map { "\(query.text) site:\($0)" } ?? query.text`:
- `DuckDuckGoHTMLProvider.formFields(of:)`
- `BraveAPIProvider.queryItems(of:)`

Replace each copy with `query.textWithSiteTerm`. Found during ^w3vpnk0.

## Acceptance Criteria
- [ ] No adapter builds the `site:` term with its own expression.
- [ ] The request tests of both adapters stay green with no change.

## Tests
- [ ] Run `swift test --filter "DuckDuckGoHTMLProviderTests|KeyedProviderRequestTests"`, then `swift test`. #web