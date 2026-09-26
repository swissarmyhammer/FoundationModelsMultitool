---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3exet0e4hrjh0e8s2cgy2ry
  text: |-
    Research done. Facts found:
    - `WebIntegrationTests/Support/LiveSearch.swift` gives the shared parts: `swiftQuery`, `minimumHitCount`, the short timeouts, `makeShortTimeoutConfiguration()`, `expectHits(of:)`. `WebVerbCall.search` of `MultitoolTestSupport` makes the call. `SearchResult` has `provider`, `results` (`WebHit` title, url, snippet, rank), `notes`, `correction`, and is `@Generable`.
    - `WebConfiguration.fromEnvironment()` adds a keyed provider only when its variable is set and not empty. `braveAPI` reads `BRAVE_SEARCH_API_KEY`, else `BRAVE_API_KEY`. `searxng` needs an `http` or `https` URL with a host in `SEARXNG_URL`.
    - No test in the repository uses `.enabled(if:)` or `.disabled(...)` now.
    - The live Brave Search API answers HTTP 422 (not 401 or 403) for an invalid token. I checked it with curl on 2026-09-26: `curl -H 'X-Subscription-Token: invalid-key' 'https://api.search.brave.com/res/v1/web/search?q=swift+programming+language'` gives `HTTP 422` and `{"error":{"code":"SUBSCRIPTION_TOKEN_INVALID",...,"status":422}}`.
    - `BraveAPIProvider` reads the body with `SearchProviderSupport.decodedBody`. `ProviderFailure(status:)` maps only 401 and 403 to `.badKey`, thus 422 becomes `.parse("the service answered HTTP 422")`. The note is then `braveAPI: skipped, the response could not be read: the service answered HTTP 422.`
    - For a real 401 or 403, the note text is `braveAPI: skipped, the API key was refused.` It holds no status number.
  timestamp: 2026-09-26T13:11:16.750205+00:00
- actor: claude-code
  id: 01m3exf4735p5mpcvr67grp9ds
  text: |-
    BLOCKER: two conflicts. I wrote no code. A person must decide.

    1. Rule conflict: `test-integrity/test-partitioning` against `web.md` Level 2 and this card.
       - The card and `web.md` say: each keyed test has `.enabled(if:)` on its environment variable, and shows as "skipped" when the variable is not set.
       - The rule `test-partitioning` says, under "What to flag", item 1 "Environment-variable test switching — a test, a test helper, or a test configuration that reads an environment variable to decide if a test runs". It also says "An environment variable is NOT the convention. Do not use one to select, skip, or switch tests." Its exception "An environment variable that carries configuration into a test that always runs" does not apply, because the keyed tests do not always run.
       - This is a rule that fights a documented contract (`web.md`). By the implement rules I must not resolve it myself. Decision needed: change `web.md` and the card (for example, the keyed tests always run and fail when no key is set, or they go to a separate package or target), or give a written exception to the rule for `WebIntegrationTests/`.

    2. Card conflict with the live service: `KeyedFallbackLiveTests`.
       - The card says: `[.braveAPI(.literal("invalid-key")), .braveHTML]` gives "a note that names `braveAPI` with 401 or 403".
       - The live Brave Search API answers HTTP 422 `SUBSCRIPTION_TOKEN_INVALID` for an invalid token (checked with curl on 2026-09-26). The production note is then `braveAPI: skipped, the response could not be read: the service answered HTTP 422.`
       - Also, for a real 401 or 403, the production note is `braveAPI: skipped, the API key was refused.` It does not hold the number 401 or 403.
       - Thus the test as the card states it fails against the live service. Decision needed: (a) change the card and `web.md` to expect the note that the live service gives (for example, the note names `braveAPI` and the key is refused or the status is 422), or (b) change production code so that 422 maps to `.badKey` and the note names the HTTP status. Option (b) changes production code, which this card does not name.

    The card is in `doing`. No file changed.
  timestamp: 2026-09-26T13:11:27.203894+00:00
- actor: claude-code
  id: 01m3exf77h0vhymewe89zxry46
  text: |-
    ### implement — stuck
    - evidence: no files changed. Conflict 1: rule `test-partitioning` forbids a test that an environment variable skips, and `web.md` Level 2 and this card require `.enabled(if:)` on each key variable. Conflict 2: the live Brave API answers HTTP 422 (not 401 or 403) for `invalid-key`, and the production note holds no status number for 401 or 403, thus the `KeyedFallbackLiveTests` check of the card cannot pass.
    - next: a person decides both conflicts (see the BLOCKER comment), updates `web.md` and the card, and starts `/implement` again.
  timestamp: 2026-09-26T13:11:30.289824+00:00
- actor: claude-code
  id: 01m3exwk35e5tr3rjkmhgpf10d
  text: |-
    ### decision — 2026-09-26
    The user decides both conflicts:
    1. All live web tests go in the existing `IntegrationTests/` package. Task ^gf2geha merges `WebIntegrationTests/` into it and removes the separate package. The `IntegrationTests` rule changes: an API key from the environment is allowed as configuration. The six keyed tests ALWAYS run (no `.enabled(if:)`); a missing key fails the test with a clear message that names the variable. `ExpectedProvidersTests` is then not needed; drop it from this card.
    2. Map the Brave API HTTP 422 `SUBSCRIPTION_TOKEN_INVALID` to a refused key (`.badKey`) in `BraveAPIProvider`. The refused-key note names the HTTP status, for example `braveAPI: skipped, the API key was refused (HTTP 422).`; 401 and 403 notes also name their status. `KeyedFallbackLiveTests` checks for the refused-key note that names `braveAPI`.
    This task now depends on ^gf2geha. Update this card's description to match (pass `tags: ["web"]`).
  timestamp: 2026-09-26T13:18:48.421240+00:00
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
- 01M3A33HKP5H238CS992MAJYVS
- 01M3EXW2YT5AH23TP2PGF2GEHA
position_column: todo
position_ordinal: '9080'
title: 'Web: add keyed live tests, the key-leak checks, and ExpectedProvidersTests'
---
## What
Add the live tests of the six keyed providers to the web live package. Design: `web.md` § "Testing / Level 2", the rows `KeyedProviderLiveTests`, `KeyedFallbackLiveTests`, `ExpectedProvidersTests`.

Create under `WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/`:
- `KeyedProviderLiveTests.swift`: six `@Test` functions, one for each provider (`braveAPI`, `tavily`, `exa`, `serper`, `kagi`, `searxng`), with one shared helper. A Swift Testing trait applies to a whole test function, not to one argument of a parameterized test, so each function has its own `.enabled(if:)` on its variable (`BRAVE_SEARCH_API_KEY` or `BRAVE_API_KEY`, `TAVILY_API_KEY`, `EXA_API_KEY`, `SERPER_API_KEY`, `KAGI_API_KEY`, `SEARXNG_URL`). Each test builds `WebConfiguration.fromEnvironment()`, keeps only its provider, queries `swift programming language`, and checks: at least 3 hits, `provider` is its name, and the key value is in no field of the rendered result.
- `KeyedFallbackLiveTests.swift`: `[.braveAPI(.literal("invalid-key")), .braveHTML]` gives `provider == "braveHTML"`, a note that names `braveAPI` with 401 or 403, and no `invalid-key` text in the result.
- `ExpectedProvidersTests.swift`: read `MULTITOOL_WEB_EXPECTED_PROVIDERS` (a comma list of provider names). Each name in it must have its variable set, so `fromEnvironment()` includes that provider. When the variable is not set, the test passes with no check (local runs).

## Acceptance Criteria
- [ ] With no key variables set, the output lists each of the six keyed tests as skipped by name, and the fallback test and `ExpectedProvidersTests` pass.
- [ ] With `MULTITOOL_WEB_EXPECTED_PROVIDERS=tavily` and no `TAVILY_API_KEY`, `ExpectedProvidersTests` fails with a message that names `TAVILY_API_KEY`.
- [ ] With a real key, its test passes and no key text is in the result.

## Tests
- [ ] The three files above.
- [ ] Run `swift test --package-path WebIntegrationTests --no-parallel`. Pass, with the six keyed tests skipped by name when no key is set.
- [ ] Run `MULTITOOL_WEB_EXPECTED_PROVIDERS=tavily swift test --package-path WebIntegrationTests --filter ExpectedProvidersTests` with no `TAVILY_API_KEY`. It fails as described.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web