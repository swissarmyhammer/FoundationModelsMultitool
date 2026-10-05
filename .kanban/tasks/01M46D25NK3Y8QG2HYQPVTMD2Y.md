---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m46jncp51egd0hnbbswcm92q
  text: |-
    Research done.
    - `WebSearchChain.run` calls `attempt` for each provider. The relaxed run goes through `run` too, thus a cooldown check at the start of `attempt` also applies to the relaxed run.
    - `nextStep(after:)` selects `correctionNextStep` only for `.provider(.noResults)`. A new skip case for a cooldown is not "no results", thus the step stays `correctionWaitStep` for a block.
    - `FetchedBody` is made only in `WebFetcher.read`. The fetcher has no clock (file header). Plan: `FetchedBody` keeps the raw `Retry-After` text; the cooldown code parses it.
    - `ProviderFallbackTests.relaxedFailureGivesExactCorrection` expects a second request to `braveHTML` in the relaxed run after HTTP 429. With the cooldown, that request must not go out; the test must change.
    - IntegrationTests `BlockedProviderRule` knows only "blocked (HTTP 429)." and "blocked by a challenge page.". A cooldown skip in the correction must also be a recognized block. `BlockedProviderRuleTests` builds keyless corrections in the order braveHTML, duckDuckGoHTML with `WebConfiguration.keyless.providers`; those tests must follow the new order.
    - `Tests/.../Support/ManualClock.swift` exists; its time moves only with `sleep`, which does not wait in real time.
  timestamp: 2026-10-05T17:44:24.517041+00:00
- actor: claude-code
  id: 01m46ka9pfn9f0t80gnf2bxk5g
  text: |-
    Implementation landed. Facts for the next agent:
    - New file `Sources/.../Web/ProviderCooldowns.swift`: a `final class` with a `Mutex<[String: Duration]>`, keyed by `adapter.name`. It reads the time from an injected `some Clock<Duration>` through one elapsed-time closure, thus an `any Clock<Duration>` works. `defaultCooldown` = 60 s, `maximumCooldown` = 600 s. `cooldown(forRetryAfter:at:)` parses seconds and the IMF-fixdate HTTP date (`Date(_, strategy: .http)`). The obsolete RFC 850 and asctime forms give the default; `.http` does not parse them. A date in the past gives zero.
    - `FetchedBody.retryAfter: String?` holds the raw header. The fetcher stays clockless; the chain parses the value with `Date.now`.
    - `WebSearchChain.attempt` checks the cooldown first and returns `ProviderSkip.coolingDown(remaining:)` with no request; after `.rateLimited` it starts the cooldown. The relaxed run goes through `attempt`, thus it respects the cooldown. A cooldown skip is not `.noResults`, thus `nextStep(after:)` gives `correctionWaitStep`.
    - Note text: `<name>: skipped, rate limited for <n> more seconds.` (`1 more second.` for one second; a part of a second counts as one more second).
    - `ProviderFallbackTests.relaxedFailureGivesExactCorrection` changed: the relaxed run now sends no request to `braveHTML`.
    - IntegrationTests `BlockedProviderRule` now accepts the cooldown reason (regex `rate limited for \d+ more seconds?\.`) as a block. `BlockedProviderRuleTests` follow the new keyless order and test the cooldown reason.
    - Problem seen: a `@Test` name must be one string literal; a `+` concatenation does not compile.
  timestamp: 2026-10-05T17:55:49.583253+00:00
- actor: claude-code
  id: 01m46kadse95sh3bmn723pekv8
  text: |-
    ### implement — changed
    - evidence: 16 files — new Sources/FoundationModelsMultitool/Capabilities/Web/ProviderCooldowns.swift, new Tests/FoundationModelsMultitoolTests/ProviderCooldownTests.swift; changed WebSearchChain.swift, WebFetcher.swift, WebConfiguration.swift, Providers/BraveHTMLProvider.swift, Providers/DuckDuckGoHTMLProvider.swift, ProviderFallbackTests.swift, WebConfigurationTests.swift, WebFetcherTests.swift, README.md, web.md, IntegrationTests Web/Support/BlockedProviderRule.swift, Web/BlockedProviderRuleTests.swift, Web/KeylessChainLiveTests.swift, Web/WebRunCodeLiveTests.swift. Commands: `swift build --build-tests` (0 warnings, 0 errors); `swift test` 1854 tests in 155 suites passed; `cd IntegrationTests && swift test --filter BlockedProviderRuleTests` 19 tests passed; `cd IntegrationTests && swift build --build-tests` build complete, 0 warnings.
    - next: /review
  timestamp: 2026-10-05T17:55:53.774624+00:00
- actor: claude-code
  id: 01m46kdbw4xgr2p1vdh0tmv6zp
  text: |-
    ### test — green
    - evidence: swift test — 1854 tests in 155 suites passed, 0 failed, 0 skipped; IntegrationTests swift build --build-tests — complete, only the known mlx-swift warning (missing creator for mutated node); IntegrationTests swift test --filter BlockedProviderRuleTests — 19 tests in 1 suite passed
    - next: review
  timestamp: 2026-10-05T17:57:30.116747+00:00
- actor: claude-code
  id: 01m46ke55a7t1arrprvdm3rgw5
  text: |-
    ### commit — changed
    - evidence: one local commit with subject "fix: put DuckDuckGo first and skip a provider after HTTP 429". It holds the new ProviderCooldowns.swift and its tests, the chain, fetcher, configuration and provider changes, README.md, web.md, the integration tests, and all .kanban changes (with the ledger of ^dj4egen). The sha is in the step record of the reply. No push.
    - next: review
  timestamp: 2026-10-05T17:57:56.010231+00:00
depends_on:
- 01M46D1NAKY1H93EN24ARTZPVB
position_column: doing
position_ordinal: '80'
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