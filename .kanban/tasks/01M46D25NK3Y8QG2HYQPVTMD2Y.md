---
assignees:
- claude-code
depends_on:
- 01M46D1NAKY1H93EN24ARTZPVB
position_column: todo
position_ordinal: '8280'
title: 'Web search: put DuckDuckGo first, and skip a provider for a cooldown after HTTP 429'
---
## Problem

In the SWE-bench run (reported by the FoundationModelsACPAgent session), the free Brave page sent HTTP 429 to both search calls. A curl request made later got HTTP 200, thus the limit was temporary. The chain tries `braveHTML` first on each call, thus each call sends one more request to a provider that blocks it, and the block can become longer.

## Where

- `Sources/FoundationModelsMultitool/Capabilities/Web/WebConfiguration.swift:214`: `public static let keyless = WebConfiguration(providers: [.braveHTML, .duckDuckGoHTML])`. The doc comment on line 213 and the `fromEnvironment` doc comment give the order too.
- `Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift`: `WebSearchChain` is a `Sendable` struct with no mutable state. `WebContext.swift:54` makes one chain for each web context, thus the cooldown state must live for the life of that context, not for one call.
- `Sources/FoundationModelsMultitool/Capabilities/Web/WebFetcher.swift:27`: `FetchedBody` has no response headers. It must carry the `Retry-After` value.
- `ProviderFailure.rateLimited` (`Providers/SearchProviderAdapter.swift:165`) has no value. `ProviderFailure(status:)` makes it from status 429.
- Header comments that say "first keyless" / "second keyless": `Providers/BraveHTMLProvider.swift:1`, `Providers/DuckDuckGoHTMLProvider.swift:1`. Docs: `web.md` § "The provider list", `README.md`.
- Tests that assert the order: `WebConfigurationTests.swift`, `IntegrationTests/.../Web/KeylessChainLiveTests.swift`. Find others with a search for `keyless`.

## Fix

1. Change the keyless order to `[.duckDuckGoHTML, .braveHTML]`. Update the doc comments, the file header comments, `web.md`, and `README.md`.
2. Add `retryAfter: String?` (or a parsed `Duration?`) to `FetchedBody`, read from the `Retry-After` header of the final response. Parse both forms: a number of seconds, and an HTTP date.
3. Add a cooldown store that the chain holds, for example a `final class` with a `Mutex` (from `Synchronization`) or an actor. Key it by the provider name (`adapter.name`). Give the chain an injectable clock (`any Clock<Duration>`, default `ContinuousClock`), thus a test does not wait.
4. After a `.rateLimited` failure, start a cooldown for that provider: the `Retry-After` time when the response has one, else 60 s. Put the 60 s in a named constant. Put a cap on a very long `Retry-After` (for example 10 minutes), and write the cap as a named constant.
5. Before `attempt(...)`, skip a provider that is in its cooldown. Send no request. Add a note/failure for it, for example `braveHTML: skipped, rate limited for 42 more seconds.` (reason text in `ProviderSkip`).
6. When the cooldown ends, the chain tries the provider again as usual.

## Tests

- A stub 429 with no `Retry-After` starts a 60 s cooldown; the next search sends no request to that provider, and the note names the skip.
- A stub 429 with `Retry-After: 5` starts a 5 s cooldown. Move the test clock past 5 s; the next search sends a request to the provider again.
- `Retry-After` as an HTTP date is parsed.
- `WebConfiguration.keyless.providers` is `[.duckDuckGoHTML, .braveHTML]`.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- No test sleeps in real time for the cooldown. #web #defect