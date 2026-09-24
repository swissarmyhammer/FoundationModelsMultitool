---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: 'Web: add WebConfiguration, WebAPIKey, and key redaction'
---
## What
Add the configuration types of the web capability. Design: `web.md` § "Providers and API keys" (the provider list, Keys, Configuration). Decisions 4 and 5 are confirmed: all six keyed providers, and `.fromEnvironment()` is the default.

- Create `Sources/FoundationModelsMultitool/Capabilities/Web/WebConfiguration.swift`:
  - `public enum WebSearchProvider: Sendable, Hashable` with the cases `braveHTML`, `duckDuckGoHTML`, `braveAPI(WebAPIKey)`, `tavily(WebAPIKey)`, `exa(WebAPIKey)`, `serper(WebAPIKey)`, `kagi(WebAPIKey)`, `searxng(URL)`, and a `name` (for example `braveHTML`).
  - `public struct WebAPIKey`: `.literal(String)` and `.environment(String)`; `func resolve(in environment: [String: String]) -> String?`. `description`, `debugDescription`, and `customMirror` show `WebAPIKey(<redacted>)` and never the value.
  - `public struct WebFetchPolicy: Sendable`: `maxBytes` (default 5 MB), `userAgent` (default names this package), `maxRedirects` (10), `searchTimeout` (10 s), `defaultFetchTimeout` (30 s).
  - `public struct WebConfiguration: Sendable`: `providers`, `fetch`, `environment`; `static let keyless` (`[.braveHTML, .duckDuckGoHTML]`, empty environment); `static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment)`. Order: `braveAPI` (`BRAVE_SEARCH_API_KEY`, then `BRAVE_API_KEY`), `tavily` (`TAVILY_API_KEY`), `exa` (`EXA_API_KEY`), `serper` (`SERPER_API_KEY`), `kagi` (`KAGI_API_KEY`), `searxng` (`SEARXNG_URL`), then the two keyless providers. A keyed case holds `.environment(<name>)`, so the value is read at call time.
- Create `Sources/FoundationModelsMultitool/Capabilities/Web/KeyRedaction.swift`: `func redactingKeys(_ text: String, keys: [String]) -> String` replaces each key value with `<redacted>`.

## Acceptance Criteria
- [ ] `fromEnvironment` with a given dictionary gives the documented order and uses the `BRAVE_API_KEY` alias only when `BRAVE_SEARCH_API_KEY` is not set.
- [ ] `.keyless` reads no environment.
- [ ] No string form of a `WebAPIKey` or of a `WebConfiguration` contains a key value.
- [ ] Redaction removes each occurrence of each key.

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebConfigurationTests.swift` (order, alias, SearXNG URL, keyless fallback at the end, `.keyless`).
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebAPIKeyTests.swift` (resolve at call time, missing variable gives `nil`, `String(describing:)`, `String(reflecting:)`, and `dump` show no value).
- [ ] Create `Tests/FoundationModelsMultitoolTests/KeyRedactionTests.swift`.
- [ ] Run `swift test --filter "WebConfigurationTests|WebAPIKeyTests|KeyRedactionTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web