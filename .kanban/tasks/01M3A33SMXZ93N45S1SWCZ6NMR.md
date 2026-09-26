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
- actor: claude-code
  id: 01m3f1k3yn7dm51539j02q8n7z
  text: |-
    Implementation landed (after the decision of 2026-09-26).
    - Production: `ProviderFailure.badKey` is now `badKey(Int)` and holds the HTTP status. The note is `<name>: skipped, the API key was refused (HTTP <status>).` for 401, 403, and 422. `BraveAPIProvider.parse` maps HTTP 422 with `error.code == SUBSCRIPTION_TOKEN_INVALID` to `.badKey(422)`. HTTP 422 with another code stays `.parse("the service answered HTTP 422")`. The chain checks 401/403/429/5xx before the adapter, and gives each other status to the adapter, thus the 422 map is in the adapter.
    - TDD: `ProviderFallbackTests.refusedKeySkips` (new text) and the new `BraveAPIChainTests` (real Brave adapter, WebStub) failed first for the right reason, then passed. `KeyedProviderRequestTests.braveInvalidTokenIsBadKey` added. `KeyedProviderTests.statusFailures` updated to `.badKey(401)`, `.badKey(403)`.
    - Live: `Web/KeyedProviderLiveTests.swift` (six tests, no `.enabled(if:)`, `#require` with a comment that names the variables) and `Web/KeyedFallbackLiveTests.swift`. `LiveSearch.search` takes an `environment` argument (default empty). New `LiveSearch.expectNoLeak(of:in:)` checks titles, URLs, snippets, notes, and the correction.
    - Fact: the live Brave body for `invalid-key` is `{"error":{"code":"SUBSCRIPTION_TOKEN_INVALID","detail":"The provided subscription token is invalid.","meta":{"component":"authentication"},"status":422},"type":"ErrorResponse"}` (curl, 2026-09-26).
    - Fact: in this toolchain `URL(string: <String constant>)` is not optional in a test, thus `try #require(URL(string:))` gives a compiler warning. I used `URL(string:)` directly in `BraveAPIChainTests`.
    - web.md: § "Fallback" (422 and the status in the note), Level 1 row `BraveAPIChainTests`, Level 2 rows `KeyedProviderLiveTests` and `KeyedFallbackLiveTests`, `ExpectedProvidersTests` row removed. § "CI" not changed; it still names `MULTITOOL_WEB_EXPECTED_PROVIDERS`. I wrote a note on the web.yml card (01M3A34A9941ZGD8FXMTHVF1SZ) for a person to decide.
  timestamp: 2026-09-26T14:23:32.309454+00:00
- actor: claude-code
  id: 01m3f1k9ezhsx7nd6wqsq6vmh4
  text: |-
    ### implement — changed
    - evidence: 12 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveAPIProvider.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderAdapter.swift, Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift, Tests/FoundationModelsMultitoolTests/BraveAPIChainTests.swift (new), Tests/FoundationModelsMultitoolTests/ProviderFallbackTests.swift, Tests/FoundationModelsMultitoolTests/KeyedProviderTests.swift, Tests/FoundationModelsMultitoolTests/KeyedProviderRequestTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/KeyedProviderLiveTests.swift (new), IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/KeyedFallbackLiveTests.swift (new), IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearch.swift, web.md, this card. Runs: `swift build --build-tests --package-path IntegrationTests` complete, 0 source warnings. Keyless live filter plus KeyedFallbackLiveTests: 14 tests in 7 suites passed. Root `swift test`: 1796 tests in 145 suites passed. KeyedProviderLiveTests: 6 of 6 fail on this computer by design (no key variables set); each message names its variable. Each file has fewer than 400 lines (largest: ProviderFallbackTests.swift, 371).
    - next: /review. A person decides web.md § "CI" and the web.yml card (MULTITOOL_WEB_EXPECTED_PROVIDERS has no reader now; which keyed suites CI runs).
  timestamp: 2026-09-26T14:23:37.951610+00:00
- actor: claude-code
  id: 01m3f1sa0x65xhzyxkxdp0vnrp
  text: |-
    ### test — green
    - evidence: root `swift test` — 1796 tests in 145 suites, 0 fail, 0 skip, 0 warning (repo code). `swift build --build-tests --package-path IntegrationTests` — build OK, 0 warning (repo code). `swift test --package-path IntegrationTests --no-parallel --filter "BraveHTMLLiveTests|DuckDuckGoHTMLLiveTests|KeylessChainLiveTests|FetchLiveTests|GuardLiveTests|WebRunCodeLiveTests|KeyedFallbackLiveTests"` — 14 tests in 7 suites pass, with 2 known issues (DuckDuckGo challenge page, per the 2026-09-26 decision). `swift test --package-path IntegrationTests --no-parallel --filter KeyedProviderLiveTests` — 6 tests fail, as set by the 2026-09-26 decision (no API key is on this machine). Each fail message names its own missing variable: `BRAVE_SEARCH_API_KEY or BRAVE_API_KEY`, `TAVILY_API_KEY`, `EXA_API_KEY`, `SERPER_API_KEY`, `KAGI_API_KEY`, `SEARXNG_URL`. No other kind of fail is present.
    - note: one build warning, `missing creator for mutated node ... mlx-swift_Cmlx.bundle`, comes from the vendored mlx-swift package under `.build/checkouts`. This is outside this repo. It is noted here, not fixed.
    - next: none. All four required test runs are green (with the two allowed exceptions).
  timestamp: 2026-09-26T14:26:55.133922+00:00
- actor: claude-code
  id: 01m3f21hhvnek653wtrhtpzn31
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 0d02475). 0 findings, 0 confirmed, 0 refuted. 10 files reviewed. 7 files not reviewed: 6 `.kanban/` files (ignored by `.reviewignore`) and `web.md` (no validator matches it). The commit renames no file. The description has no earlier `## Review Findings` section.
    - next: the task moved to `done`. A person decides web.md § "CI" and the web.yml card (01M3A34A9941ZGD8FXMTHVF1SZ), as the implement comment says.
  timestamp: 2026-09-26T14:31:24.987272+00:00
- actor: claude-code
  id: 01m3f222a5hwsffjc3kqvqb66m
  text: |-
    ### finish iteration 2 — clean
    - iteration 1: stuck (two conflicts; the user decided on 2026-09-26)
    - implement: changed — 11 files (keyed live tests always run; Brave 422 is a refused key; notes name the status)
    - test: green — root 1796 passed; live keyless + fallback 14 passed, 2 known issues; the 6 keyed tests fail on this machine only because no key is set, as decided
    - commit: 0d02475
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-26T14:31:42.149156+00:00
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
- 01M3A33HKP5H238CS992MAJYVS
- 01M3EXW2YT5AH23TP2PGF2GEHA
position_column: done
position_ordinal: ffe880
title: 'Web: add keyed live tests, the key-leak checks, and the Brave API refused-key note'
---
## What
Add the live tests of the six keyed providers to the `IntegrationTests` package, and make the Brave API refused-key note name the HTTP status. Design: `web.md` § "Testing / Level 2", the rows `KeyedProviderLiveTests` and `KeyedFallbackLiveTests`, and "The environment rule". The user decision of 2026-09-26 (see comments) replaces the first design.

Live tests. Create under `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/`. Use `Web/Support/LiveSearch.swift` and the `MultitoolTestSupport` product (`WebVerbCall`, `RunOutput`, `ShortTimeoutSession`).
- `KeyedProviderLiveTests.swift`: six `@Test` functions, one for each provider (`braveAPI`, `tavily`, `exa`, `serper`, `kagi`, `searxng`), with one shared helper. Each test ALWAYS runs. No test has `.enabled(if:)`, and no test reads the environment to decide if it runs. Each test builds `WebConfiguration.fromEnvironment()` and keeps only its provider. When its variable is not set, the test fails with a message that names the variable (`BRAVE_SEARCH_API_KEY` or the alias `BRAVE_API_KEY`, `TAVILY_API_KEY`, `EXA_API_KEY`, `SERPER_API_KEY`, `KAGI_API_KEY`, `SEARXNG_URL`). Each test queries `swift programming language` and checks: at least 3 hits, `provider` is its name, and the key value is not in the results, the notes, or the correction.
- `KeyedFallbackLiveTests.swift`: `[.braveAPI(.literal("invalid-key")), .braveHTML]` gives `provider == "braveHTML"`, hits from `braveHTML`, a refused-key note that names `braveAPI`, and no `invalid-key` text in the results, the notes, or the correction.
- No `ExpectedProvidersTests`. The decision removes it.

Production change (use `/tdd`, unit tests in the root `Tests/`, no network):
- `BraveAPIProvider` maps HTTP 422 with the error code `SUBSCRIPTION_TOKEN_INVALID` to a refused key (`.badKey`). The live Brave Search API gives this answer for an invalid token.
- The refused-key note names the HTTP status, for example `braveAPI: skipped, the API key was refused (HTTP 422).` The notes for 401 and 403 also name their status.

Documents: update `web.md` § "Testing" Level 2 rows (the keyed tests always run, `ExpectedProvidersTests` is removed, the text of the fallback note) and § "Fallback".

## Acceptance Criteria
- [ ] A unit test proves that a Brave API answer of HTTP 422 with `SUBSCRIPTION_TOKEN_INVALID` gives the note `braveAPI: skipped, the API key was refused (HTTP 422).`
- [ ] Unit tests prove that 401 and 403 notes name their status.
- [ ] With no key variables set, each of the six keyed tests fails with a message that names its variable. This is the expected result on a machine with no keys.
- [ ] `KeyedFallbackLiveTests` passes against the live services.
- [ ] With a real key, its test passes and no key text is in the result.
- [ ] Each file has fewer than 400 lines.

## Tests
- [ ] Unit tests in `Tests/FoundationModelsMultitoolTests/` for the 422 map and the status in the refused-key note.
- [ ] `KeyedProviderLiveTests.swift` and `KeyedFallbackLiveTests.swift`.
- [ ] `swift build --build-tests --package-path IntegrationTests` compiles.
- [ ] Run the keyless live filter plus `KeyedFallbackLiveTests` one time. Pass.
- [ ] Root `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web