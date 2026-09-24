---
assignees:
- claude-code
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
- 01M3A33HKP5H238CS992MAJYVS
position_column: todo
position_ordinal: 8d80
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