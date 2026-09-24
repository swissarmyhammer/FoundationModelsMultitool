---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3a4rcnb0fy2yqwhz9fd2ves
  text: |-
    Research done.
    - The `Capabilities/Web/` folder does not exist yet. This task creates it.
    - No type in the package has a custom `description`, `debugDescription`, or `customMirror` now. There is no prior redaction pattern to reuse.
    - `MultiToolConfiguration` is the pattern for a limits struct: `public static let default...` constants, `TimeInterval` for time, and a public init with defaults. `WebFetchPolicy` follows it.
    - `ShellDotfolder` is the pattern for a function that reads an injected `environment: [String: String] = ProcessInfo.processInfo.environment`.
    - `WebConfiguration` holds the whole environment dictionary. Thus its default string forms would show each key value. It must have its own `description`, `debugDescription`, and `customMirror` that do not show the dictionary values.
    - Rule "a function belongs to a type": `redactingKeys` goes in an `enum KeyRedaction` namespace as a `static func`, with the signature of the card.
    - Rule `no_direct_standard_out_logs` flags a `dump` call also in tests. The `dump(_:to:)` test needs `// swiftlint:disable:next no_direct_standard_out_logs` with a reason, because it writes to a String, not to standard out.
  timestamp: 2026-09-24T16:42:38.635571+00:00
- actor: claude-code
  id: 01m3a53tm97v6zx9sp10wzhb17
  text: |-
    Implementation landed (TDD: the stubs first gave assertion failures in all three suites, then the real code made them pass).
    - `WebConfiguration.swift` holds `WebSearchProvider` (with `name`), `WebAPIKey`, `WebFetchPolicy`, and `WebConfiguration`.
    - `fromEnvironment` reads a table of rows (variables, case). Each keyed case holds `.environment(<name>)`. The Brave row tries `BRAVE_SEARCH_API_KEY`, then `BRAVE_API_KEY`.
    - Decision: an EMPTY variable (and an empty `.literal`) counts as "not set". `resolve(in:)` gives `nil`, and `fromEnvironment` adds no provider. Thus `BRAVE_SEARCH_API_KEY=""` lets the `BRAVE_API_KEY` alias apply. Tests hold this.
    - Decision: `SEARXNG_URL` must be an `http` or `https` URL (scheme not case-sensitive) with a host. Else it adds no provider.
    - `WebConfiguration` string forms show the provider NAMES only (not the `searxng` URL, which can hold user info) and `N variables, <redacted>` for the environment.
    - `KeyRedaction.redactingKeys(_:keys:)` is a `static func` in an `enum KeyRedaction` namespace (rule: a function belongs to a type). It replaces the longest key first, thus a key that contains a shorter key goes whole. `KeyRedaction.placeholder` is the one `<redacted>` text; `WebAPIKey` uses it too.
    - New test helper `Tests/FoundationModelsMultitoolTests/WebRedactionProbe.swift` gets the `dump` output as a String for two suites. It carries `// swiftlint:disable:next no_direct_standard_out_logs`, because `dump(_:to:)` writes into a String.
    - `swiftlint` (no_magic_numbers, missing_docs, force rules, stdout rule) gives 0 violations on the six files. `swift format lint` gives no idiom finding.
    - The build prints `warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS`. It is a SwiftPM warning about the mlx-swift dependency bundle, not about this change.
  timestamp: 2026-09-24T16:48:53.385499+00:00
- actor: claude-code
  id: 01m3a54bd98a88nh6agycrtfpf
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebConfiguration.swift, Sources/FoundationModelsMultitool/Capabilities/Web/KeyRedaction.swift, Tests/FoundationModelsMultitoolTests/WebConfigurationTests.swift, Tests/FoundationModelsMultitoolTests/WebAPIKeyTests.swift, Tests/FoundationModelsMultitoolTests/KeyRedactionTests.swift, Tests/FoundationModelsMultitoolTests/WebRedactionProbe.swift. `swift test --filter "WebConfigurationTests|WebAPIKeyTests|KeyRedactionTests"`: 32 tests in 3 suites passed. `swift test`: 1544 tests in 124 suites passed.
    - next: /review. The task stays in `doing`. Nothing is committed.
  timestamp: 2026-09-24T16:49:10.569146+00:00
- actor: claude-code
  id: 01m3a5ck98z7z43gs38gqvft6a
  text: |-
    ### test — green
    - evidence: `swift test` — 1544 tests passed, 0 failed, 0 skipped, in 124 suites. `swift test --filter "WebConfigurationTests|WebAPIKeyTests|KeyRedactionTests"` — 32 tests passed, 0 failed.
    - warnings: `swift build` shows one warning: `missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. This warning is from the build system for the `mlx-swift` dependency bundle. It is not from this project's Swift sources. It was present before this task's change and is noted as pre-existing on earlier tasks.
    - next: ready for review.
  timestamp: 2026-09-24T16:53:40.776432+00:00
position_column: doing
position_ordinal: '80'
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
- [x] `fromEnvironment` with a given dictionary gives the documented order and uses the `BRAVE_API_KEY` alias only when `BRAVE_SEARCH_API_KEY` is not set.
- [x] `.keyless` reads no environment.
- [x] No string form of a `WebAPIKey` or of a `WebConfiguration` contains a key value.
- [x] Redaction removes each occurrence of each key.

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/WebConfigurationTests.swift` (order, alias, SearXNG URL, keyless fallback at the end, `.keyless`).
- [x] Create `Tests/FoundationModelsMultitoolTests/WebAPIKeyTests.swift` (resolve at call time, missing variable gives `nil`, `String(describing:)`, `String(reflecting:)`, and `dump` show no value).
- [x] Create `Tests/FoundationModelsMultitoolTests/KeyRedactionTests.swift`.
- [x] Run `swift test --filter "WebConfigurationTests|WebAPIKeyTests|KeyRedactionTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web