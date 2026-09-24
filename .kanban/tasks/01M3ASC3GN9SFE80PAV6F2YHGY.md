---
assignees:
- claude-code
position_column: todo
position_ordinal: '9580'
title: 'Web: read the snippet of the current Brave results markup'
---
## What
`BraveHTMLProvider` uses the snippet rules of `brave.rs`: `.snippet-description`, else the first `<p>` with more than 20 characters. The recorded page `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results.html` (recorded 2026-09-24) has no `.snippet-description` and no such `<p>` in its `[data-pos]` containers. Thus each hit of a real Brave page has an empty snippet.

The current markup holds the snippet in `.generic-snippet .content` (for example `<div class="content desktop-default-regular t-primary line-clamp-dynamic ...">Swift is <strong>a general-purpose ...</strong>.</div>`).

A person must decide: add `.generic-snippet .content` as the first snippet selector (a change from the `brave.rs` rules in web.md § "What we copy"), and update web.md to match. Found during ^w3vpnk0.

## Acceptance Criteria
- [ ] The recorded page gives a non-empty snippet for its first hit.
- [ ] The ported `brave.rs` snippet fixtures stay green.
- [ ] web.md § "What we copy" states the snippet rules that the code uses.

## Tests
- [ ] Add a snippet assertion to `BraveHTMLProviderTests` for the recorded page. Run `swift test --filter BraveHTMLProviderTests`, then `swift test`. #web