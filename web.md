# web.md — The `web` capability: search and fetch in code mode

Note: This document uses ASD-STE100 Simplified Technical English. Code
identifiers (for example `WebCapability`) and product names (for example
Brave, Tavily) are technical names. They keep their usual form. Words such as
"mount", "render", "fetch", and "scrape" are technical verbs in this project.

## Status of this document

This is a design plan. No code for it exists yet. When the code ships, the code
and `README.md` are correct, and this document is the record of why.

## Goal

Add a `web` capability to MultiTool. The model can search the web and fetch a
page from a `runCode` snippet:

```js
const hits = await tools.web.search({ query: "swift structured concurrency" });
const pages = await Promise.all(
  hits.results.slice(0, 3).map(r => tools.web.fetch({ url: r.url, maxCharacters: 4000 })));
return pages.map(p => ({ url: p.url, title: p.title, head: p.content.slice(0, 400) }));
```

The capability has four properties:

1. It has the same shape as `files`: one noun, plain `Tool` verbs, one shared
   context, and a `withWeb(...)` builder short form. It is off by default.
2. With no configuration, it searches through the same public, keyless path
   that `swissarmyhammer` uses (the Brave HTML results page).
3. A host can add API-key search providers. A key comes from the code or from
   an environment variable. A key never goes into the sandbox, the rendered
   surface, a result, or an error message.
4. Integration tests search the real web and fetch real pages.

## Source material

The Rust source is in `../swissarmyhammer/crates/`:

| Path | What it holds |
|---|---|
| `swissarmyhammer-tools/src/mcp/tools/web/` | The MCP tool `web`: ops `search url` and `fetch url`, schema, dispatch. |
| `swissarmyhammer-web/src/search/brave.rs` | The Brave HTML scraper. |
| `swissarmyhammer-web/src/search/content_fetcher.rs` | The fetch of page content for each search result. |
| `swissarmyhammer-web/src/security.rs` | The URL guard (SSRF). |
| `swissarmyhammer-web/src/fetch.rs` | The `fetch url` path over `markdowndown`. |
| `markdowndown/src/` | HTML to markdown (`html2text`), GitHub and Google Docs converters. |

### What we copy

- **The keyless search request.**
  `GET https://search.brave.com/search?q=<percent-encoded>&source=web`, with
  `Accept: text/html` and a desktop browser `User-Agent`
  (`brave.rs:53-107`). The timeout is 10 seconds.
- **The parse rules** (`brave.rs:116-240`):
  - A result container is `[data-pos]`.
  - The title is `a .title`. When there is no title, use the text of the first
    `http` anchor.
  - The URL is the first `a[href]` that starts with `http`.
  - The snippet is the first text that is not empty of these rules, in
    order:
    1. `.generic-snippet .content`. This rule is not in `brave.rs`. The
       current Brave markup keeps the snippet in this element (a page
       recorded on 2026-09-24 has no `.snippet-description`). Decided
       2026-09-25.
    2. `.snippet-description` (`brave.rs`).
    3. The first `<p>` that has more than 20 characters (`brave.rs`).
  - Skip an entry that has no title or no URL. Remove duplicate URLs. Decode
    HTML entities. Stop at the requested count. No results is a failure of
    kind `noResults`.
- **The URL guard lists** (`security.rs:103-352`):
  - Schemes `http` and `https` only.
  - A blocklist of hosts: `localhost`, `127.0.0.1`, `::1`, `0.0.0.0`,
    `169.254.169.254`, `metadata.google.internal`, `metadata.azure.com`,
    `instance-data.ec2.internal`.
  - Blocked suffixes: `.local`, `.localhost`, `.internal`.
  - Private IPv4 ranges: `0/8`, `10/8`, `100.64/10`, `127/8`, `169.254/16`,
    `172.16/12`, `192.168/16`, `198.18/15`, `224/4`, `240/4`, broadcast.
  - IPv6: loopback, multicast, unspecified, and IPv4-mapped (check as IPv4).
- **The page cleanup before conversion** (`markdowndown` preprocessor): remove
  `script`, `style`, `nav`, `aside`, `.sidebar`, `.ad`, `.ads`,
  `.advertisement`.

### What we do not copy, and why

The Rust tool has defects. We do not port them.

| Rust behavior | Our behavior |
|---|---|
| `category`, `language`, `safe_search`, `time_range` are validated and then ignored (`brave.rs:87` sends only `q` and `source`). | A parameter is on the surface only if at least one provider uses it. When the selected provider cannot use a parameter, the result says so in `notes`. |
| `max_content_length` on fetch is validated and then ignored. | `maxCharacters` is a hard limit. A byte limit also stops the download. |
| The guard checks only the first resolved address, and it does not check redirect targets. | The guard checks each resolved address and each redirect hop. |
| `search url` also fetches the page of each result (`fetch_content`, default `true`), through a second HTTP client with no URL guard, and removes a result whose fetch fails. | `search` and `fetch` are separate. `search` never fetches a result page. A snippet fetches the pages it selects with `fetch`, for example with `Promise.all`. Each network request goes through one guard. |
| Body read in full with no size limit. | The body is read as a stream and stops at the byte limit. |
| One search backend and no fallback. | An ordered list of providers, with fallback on failure. |
| `PrivacyManager` and `AdaptiveRateLimiter` exist but are not used. | We do not port them. |
| Summary, key points, language guess, reading time in each result. | We do not port them. The snippet can compute what it needs. |

## The surface

`tools.web` has two verbs. They render in this order.

| Path | What it does |
|---|---|
| `tools.web.search` | Searches the web. Gives ranked hits: title, URL, snippet. It never fetches a page. |
| `tools.web.fetch` | Fetches one URL. Gives the page as markdown, text, or raw content, in windows. |

### `tools.web.search`

`@Generable struct SearchArguments`:

| Field | Type | Default | Limits |
|---|---|---|---|
| `query` | `String` | — | Trimmed, not empty, at most 500 characters. |
| `count` | `Int?` | 10 | 1 to 20. |
| `freshness` | `String?` | none | `day`, `week`, `month`, `year`. The lookup ignores case (`EnumParameter`). |
| `site` | `String?` | none | One host name. The provider adds `site:<host>` or its native filter. |

`@Generable struct SearchResult`:

| Field | Type | Meaning |
|---|---|---|
| `provider` | `String` | The provider that gave the results, for example `braveHTML`. |
| `results` | `[WebHit]` | `rank`, `title`, `url`, `snippet`. |
| `notes` | `[String]?` | Fallbacks that occurred and parameters that the provider ignored. |
| `correction` | `String?` | Set only when the call failed. Then `results` is empty. |

### `tools.web.fetch`

`@Generable struct FetchArguments`:

| Field | Type | Default | Limits |
|---|---|---|---|
| `url` | `String` | — | Absolute `http` or `https` URL. |
| `format` | `String?` | `markdown` | `markdown`, `text`, `raw`. |
| `offset` | `Int?` | 0 | The character offset of the window, for a long page. |
| `maxCharacters` | `Int?` | 20000 | 500 to 200000. |
| `timeout` | `Int?` | 30 | 1 to 120 seconds. |

`@Generable struct FetchResult`:

| Field | Type | Meaning |
|---|---|---|
| `url` | `String` | The final URL, after redirects. |
| `status` | `Int` | The HTTP status. |
| `contentType` | `String` | The media type from the response. |
| `title` | `String?` | The page title, for HTML. |
| `content` | `String` | The window of the converted content. |
| `totalCharacters` | `Int` | The length of the full converted content. |
| `nextOffset` | `Int?` | The `offset` of the next window, or `nil` at the end. |
| `notes` | `[String]?` | For example, that the download stopped at the byte limit and the page is not complete. |
| `correction` | `String?` | Set only when the call failed. |

A non-2xx status is not a correction. The model gets `status` and the body,
because a 404 page often tells the model what is wrong. A network failure, a
guard refusal, a timeout, or an unsupported binary type is a correction.

### Corrections, not throws

The verbs follow the files vocabulary (`CorrectiveResult.swift`,
`EnumParameter.swift`). A failure goes back in `correction` and the call does
not throw. Examples of the text:

- ``The `url` parameter must be an absolute http or https URL: ftp://x``
- `The address is not allowed: localtest.me resolves to 127.0.0.1, a loopback address.`
- `The request timed out after 30 seconds: https://example.org/slow`
- `The content type is not text: application/pdf. fetch reads text, HTML, JSON, and XML.`
- `No search provider gave results. braveHTML: blocked (HTTP 429). duckDuckGoHTML: no results.`

The description of each verb (`let description = """..."""`) tells the model
three things: when to use the verb, that `search` then `fetch` in one snippet
is the normal pattern, and that `Promise.all` fetches pages in parallel.

## Providers and API keys

### The provider list

```swift
public enum WebSearchProvider: Sendable, Hashable {
    case braveHTML                      // keyless, from swissarmyhammer
    case duckDuckGoHTML                 // keyless, second fallback
    case braveAPI(WebAPIKey)            // X-Subscription-Token
    case tavily(WebAPIKey)              // Authorization: Bearer
    case exa(WebAPIKey)                 // x-api-key
    case serper(WebAPIKey)              // X-API-KEY
    case kagi(WebAPIKey)                // Authorization: Bearer <key>
    case searxng(URL)                   // a host-run instance, format=json
}
```

| Provider | Request | Environment variable |
|---|---|---|
| `braveHTML` | `GET https://search.brave.com/search?q=…&source=web` | none |
| `duckDuckGoHTML` | `POST https://html.duckduckgo.com/html/` with form `q=…` | none |
| `braveAPI` | `GET https://api.search.brave.com/res/v1/web/search?q=…&count=…` | `BRAVE_SEARCH_API_KEY`, then `BRAVE_API_KEY` |
| `tavily` | `POST https://api.tavily.com/search` | `TAVILY_API_KEY` |
| `exa` | `POST https://api.exa.ai/search` | `EXA_API_KEY` |
| `serper` | `POST https://google.serper.dev/search` | `SERPER_API_KEY` |
| `kagi` | `POST https://kagi.com/api/v1/search` | `KAGI_API_KEY` |
| `searxng` | `GET <base>/search?q=…&format=json` | `SEARXNG_URL` (a base URL, not a key) |

The keyed provider tasks must examine each endpoint, header, and response
field against the current documentation of the provider before they write the
adapter. This table comes from memory, not from a check.

Each provider is one type that conforms to an internal protocol:

```swift
protocol SearchProviderAdapter: Sendable {
    var name: String { get }
    var supports: Set<SearchFeature> { get }   // .freshness, .site, .count
    func request(for query: SearchQuery, key: String?) throws -> URLRequest
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit]
}
```

`request` and `parse` are pure functions. Unit tests call them with fixture
bytes and no network. The chain gives the query count to `parse` as `limit`,
thus a provider that reads a whole results page stops at the requested count.

### Keys

```swift
public struct WebAPIKey: Sendable, Hashable, CustomStringConvertible {
    public static func literal(_ value: String) -> WebAPIKey
    public static func environment(_ name: String) -> WebAPIKey
    public var description: String { "WebAPIKey(<redacted>)" }
}
```

- `.literal` holds the value in memory. `.environment` holds only the name. The
  capability reads the value at the time of each call, from the environment
  dictionary that the capability got at construction. The default dictionary
  is `ProcessInfo.processInfo.environment`. A test gives its own dictionary.
- `description`, `debugDescription`, and `dump` show no key value.
- A key is used only in Swift, to make the `URLRequest`. The JavaScript
  sandbox never sees it. `tools.web.*` has no key parameter.
- Before a provider error text goes into `notes` or `correction`, the
  capability replaces each key value in it with `<redacted>`.

### Configuration

```swift
public struct WebConfiguration: Sendable {
    /// The order to try. The first provider that gives results wins.
    public var providers: [WebSearchProvider]
    public var fetch: WebFetchPolicy          // limits, user agent
    public var environment: [String: String]

    /// braveHTML, then duckDuckGoHTML. Reads no environment.
    public static let keyless: WebConfiguration

    /// Each keyed provider whose variable is set, in table order, then the
    /// keyless providers as the last fallback.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WebConfiguration
}
```

Builder short form, in `Surface/MultiToolBuilder.swift`, beside `withFiles`:

```swift
@discardableResult
public func withWeb(
    configuration: WebConfiguration = .fromEnvironment(),
    sessionConfiguration: URLSessionConfiguration = .ephemeral
) -> Self {
    withCapability(WebCapability(configuration: configuration,
                                 sessionConfiguration: sessionConfiguration))
}
```

- `withWeb` does not throw, the same as `withFiles`. It gets no resource at
  construction.
- `sessionConfiguration` is the test seam. A unit test gives a configuration
  whose `protocolClasses` has a stub `URLProtocol`. This is the same method as
  `LoopbackHTTPServer` (`Tests/Support/MCPTestServer/LoopbackHTTPServer.swift`).
- `MultiToolConfiguration` does not change. The files and shell capabilities
  also keep their configuration in the capability.

### Fallback

The capability tries providers in list order. It goes to the next provider
when a provider:

- has an `.environment` key whose variable is not set now,
- returns 401 or 403 (a bad key),
- returns 429 or 5xx,
- returns a challenge page (HTTP 200, but no `[data-pos]` and a known
  challenge marker, for `braveHTML`),
- returns no results,
- does not answer in its timeout.

Each skip adds one line to `notes`. When all providers fail, the result has a
`correction` that names each provider and its failure.

## Fetch

### The pipeline

1. **Check the arguments.** Check the bounds and the scheme.
2. **Guard.** `WebAddressGuard` resolves the host (`getaddrinfo`), and checks
   each address against the lists in "What we copy". It also refuses a URL
   with user info (`user:pass@`).
3. **Request.** One `URLSession` for each capability, from
   `sessionConfiguration`. It sends no cookies and has no URL cache. When the
   request has no `User-Agent`, it comes from `WebFetchPolicy` (the default
   names this package). A provider request that sets its own `User-Agent`
   (the Brave HTML request) keeps it.
4. **Redirects.** `urlSession(_:task:willPerformHTTPRedirection:...)` sends
   each hop through the guard. The limit is 10 hops.
5. **Body.** `URLSession.bytes(for:)`. Stop at `WebFetchPolicy.maxBytes`
   (default 5 MB). When it stops, set a note that the page is not complete.
6. **Content type.**
   - `text/html` and `application/xhtml+xml`: convert (see below).
   - `text/*`, `application/json`, `application/xml`, `+json`, `+xml`: use as
     is. Decode with the charset from the response, else UTF-8.
   - Other types: correction.
7. **Window.** Apply `offset` and `maxCharacters` to the converted text. Set
   `totalCharacters` and `nextOffset`.

The capability keeps a small cache of converted pages for one session. Each
entry is stored under the requested URL and under the final URL, with the
format. Thus a second window of a URL that redirects also finds the entry.
The cache has at most 16 pages (least recently used goes first). Thus a
snippet that reads a long page window by window downloads it one time.

### HTML to markdown

`HTMLMarkdown.swift` is a converter over a parsed DOM.

- Remove the elements in "What we copy", and also `header`, `footer`, `form`,
  `noscript`, `svg`, `iframe`.
- Use `<main>` or `<article>` when there is exactly one. Else use `<body>`.
- Emit headings, paragraphs, lists, links (`[text](absolute-url)`), `pre` as
  fenced code with the language from `class="language-x"`, inline `code`,
  `blockquote`, emphasis, and simple tables.
- Remove runs of empty lines. Keep the text in document order.
- `title` comes from `<title>`, else `og:title`, else the first `<h1>`.

`format: "text"` gives the same walk with no markdown marks.
`format: "raw"` gives the body with no change.

The DOM parser is SwiftSoup. See "Decisions", item 1.

## Mount in code mode

No change to the mount code is necessary. `withWeb` calls
`withCapability(_:)`, and the existing path does the rest:

- `RegistrySource.expanded()` makes the entries `web.search` and `web.fetch`.
- `validateNounOwnership` gives the noun `web` to this capability. A second
  `withWeb` or an MCP server named `web` is `.duplicateNoun`.
- `makePreamble` binds `tools.web.search` and `tools.web.fetch`.
- `searchTools`, `help()`, and `docs()` find the two verbs.
- The journal operation names are `search web` and `fetch web`.

The two verbs are synchronous, the same as the files verbs. They do not
declare `BackgroundTool`. See "Decisions", item 3.

## Files to add or change

```
Sources/FoundationModelsMultitool/Capabilities/Web/
  WebCapability.swift          noun "web", two verbs, one WebContext
  WebContext.swift             one WebFetcher, WebPageReader, and WebSearchChain
  WebFetcher.swift             URLSession, guard, redirect hook, byte limit, text decode
  WebPageReader.swift          conversion, windows, page cache
  WebSearchChain.swift         provider order, fallback, notes, redaction
  WebConfiguration.swift       WebConfiguration, WebSearchProvider, WebAPIKey, WebFetchPolicy
  Search.swift                 SearchArguments, SearchResult, WebHit, struct Search: Tool
  Fetch.swift                  FetchArguments, FetchResult, struct Fetch: Tool
  WebAddressGuard.swift        scheme, host, and IP checks; redirect hook
  HTMLMarkdown.swift           DOM to markdown and to text
  KeyRedaction.swift           removes key values from text
  Providers/
    SearchProviderAdapter.swift
    BraveHTMLProvider.swift
    DuckDuckGoHTMLProvider.swift
    BraveAPIProvider.swift
    TavilyProvider.swift
    ExaProvider.swift
    SerperProvider.swift
    KagiProvider.swift
    SearXNGProvider.swift
Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift   + withWeb(...)
Sources/MultitoolCLI/CLIRunner.swift                               + --web flag
Package.swift                                                      + SwiftSoup dependency (Decision 1)
README.md                                                          ## Capabilities: + web
docs/SECURITY.md                                                   + the web capability section
WebIntegrationTests/                                               new package (see Testing)
.github/workflows/web.yml                                          new workflow: web-integration job
```

## Testing

There are three levels of test. The root `swift test` stays offline. The two
live levels are separate packages, the same as `IntegrationTests/`.

### Level 1: unit tests, no network (root package)

All in `Tests/FoundationModelsMultitoolTests/`. A stub `URLProtocol`
(`Support/WebStubURLProtocol.swift`) answers each request from a table:
URL pattern to status, headers, and body. It records each request, so a test
can examine the headers.

| Suite | What it proves |
|---|---|
| `WebCapabilityTests` | The shape of `FilesCapabilityTests`: noun `web`, exactly two verbs, one shared context, `withWeb` renders both, no `web` entries without `withWeb`, `.duplicateNoun`, `searchTools` finds each verb, `help()` and `docs()`. |
| `WebVerbArgumentTests` | Each bound and each enum value of both verbs gives the correct correction text. |
| `BraveHTMLProviderTests` | Parse of a recorded Brave page in `WebGoldens/brave-*.html`. Titles, URLs, snippets, entity decode, duplicates, `count` limit, title fallback, snippet fallback, challenge page. |
| `DuckDuckGoHTMLProviderTests` | Parse of recorded pages. Decode of the `uddg=` redirect links. |
| `KeyedProviderTests` | For each keyed provider: the request (method, URL, auth header, body) and the parse of a recorded JSON response. The key is in the header and nowhere else. |
| `ProviderFallbackTests` | Each failure kind in "Fallback" goes to the next provider and adds a note. All failures give one correction that names each provider. |
| `WebAPIKeyTests` | `.environment` reads at call time. A missing variable skips the provider. `description`, `dump`, and `String(reflecting:)` show no value. |
| `KeyRedactionTests` | A provider error that echoes the key is redacted in `notes` and in `correction`. |
| `WebConfigurationTests` | `fromEnvironment` with a given dictionary: order, `BRAVE_API_KEY` alias, `SEARXNG_URL`, keyless fallback at the end. `.keyless` reads no environment. |
| `WebAddressGuardTests` | Each blocked host, suffix, and range, IPv6, IPv4-mapped IPv6, user info, bad scheme. A resolver stub gives many addresses, and one private address is sufficient for a refusal. |
| `WebRedirectGuardTests` | A redirect to `http://127.0.0.1/` is refused. Eleven hops are refused. |
| `WebFetcherTests` | Content types, charset, byte limit, non-2xx status, timeout correction, `User-Agent` handling, the unguarded request for host configuration. |
| `WebPageReaderTests` | Windows (`offset`, `nextOffset`, `totalCharacters`), formats, page cache hit (also after a redirect), eviction. |
| `HTMLMarkdownTests` | Goldens: `WebGoldens/*.html` to `*.md`. Headings, lists, code fences with language, relative links made absolute, tables, removed elements, title order. |
| `WebRunCodeTests` | JavaScript snippets through `MultiTool.call`, the shape of `FilesCrossOpFlowTests`: search then fetch; `Promise.all` over three fetches; a correction reaches the snippet as a value, not as an exception; a key value never appears in the return value or the console. |

### Level 2: live web tests, no model (new package `WebIntegrationTests/`)

These tests search the real web and fetch real pages. They do not load a
model, so they run in approximately one minute.

**Why a new package.** `IntegrationTests/Package.swift` states: "nothing here
reads the environment, and nothing may start doing so". The keyed provider
tests must read keys from the environment, because that is the feature under
test. A separate package keeps that rule true for `IntegrationTests/`. It also
keeps the root `swift test` offline, by the build graph and not by a
convention.

```
swift test --package-path WebIntegrationTests --no-parallel
```

`--no-parallel`, and `.serialized` on each suite, keep the request rate low.
Each test has `.timeLimit(.minutes(1))`.

**The assertion rule.** A live test asserts only facts that are stable for
years: a well-known host appears in the top results, a known page has a known
title. It does not assert a rank, a snippet, or a count of more than 3. A
test does not retry. When Brave changes its markup, `BraveHTMLLiveTests`
fails. That failure is the signal that we want.

| Suite | Tests |
|---|---|
| `BraveHTMLLiveTests` | Providers `[.braveHTML]` only. Query `swift programming language`: at least 3 hits, each URL is `https`, a hit host is `swift.org` or ends in `.swift.org`. Query with `site: "developer.apple.com"`: each hit host ends in `apple.com`. |
| `DuckDuckGoHTMLLiveTests` | The same two tests, with `[.duckDuckGoHTML]` only. |
| `KeylessChainLiveTests` | `.keyless`: the query gives hits, and `provider` is one of the two keyless names. |
| `FetchLiveTests` | `https://example.com`: title `Example Domain`, content contains `Example Domain`. `http://github.com`: final `url` starts with `https://github.com`. `https://en.wikipedia.org/wiki/Swift_(programming_language)` with `maxCharacters: 2000`: `nextOffset` is set; a second call with that offset gives the next text and no second download (cache). `https://api.github.com/zen`: `contentType` is `text/plain`, content is not empty. `https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf`: correction for a binary type. |
| `GuardLiveTests` | `http://localtest.me/` (a public DNS name that resolves to `127.0.0.1`): the correction names the loopback address. This proves that the guard checks the resolved address, not only the host name. `http://169.254.169.254/latest/meta-data/`: correction. |
| `KeyedProviderLiveTests` | Six `@Test` functions, one for each keyed provider, with a shared helper. (A Swift Testing trait applies to a whole test function, not to one argument of a parameterized test.) Each test builds `WebConfiguration.fromEnvironment()`, takes only its provider, and has `.enabled(if:)` on its variable. Each test: query `swift programming language`, at least 3 hits, `provider` is the name of the provider, and the key value is not in the rendered result. A test with no key shows as "skipped" with its name. It does not show as "passed". |
| `KeyedFallbackLiveTests` | `[.braveAPI(.literal("invalid-key")), .braveHTML]`: `provider` is `braveHTML`, `notes` names `braveAPI` with 401 or 403, and the text `invalid-key` is not in the result. |
| `ExpectedProvidersTests` | Reads `MULTITOOL_WEB_EXPECTED_PROVIDERS` (for example `braveAPI,tavily`). Each name in it must have its key in `fromEnvironment()`. CI sets this variable, so a secret that is not configured fails CI and does not become a quiet skip. Local runs do not set it. |
| `WebRunCodeLiveTests` | A real `MultiTool` with `.withWeb(configuration: .keyless)` and no model. The snippet at the top of this document runs, and returns 1 to 3 pages, each with a title and content. |

### Level 3: one real-model scenario (existing `IntegrationTests/`)

`WebResearchScenarioTests.swift`, beside `FilesBareSessionTests.swift`:

- Mount `.withWeb(configuration: .keyless)`. `.keyless` reads no environment,
  thus the rule of that package stays true.
- The prompt: "Find the address of the home page of the Swift programming
  language on the web. Answer with the URL only."
- The grade, with `ScenarioGrading`: the call log has `tools.web.search`, and
  the answer contains `swift.org`.
- It queues behind `liveProfileTurnstile`, the same as each other scenario.

### CI

- A new workflow file `.github/workflows/web.yml` with one job
  `web-integration`. It runs Level 2. Its triggers are `push` to `main`,
  `pull_request`, `workflow_dispatch`, and a daily `schedule`. The daily run
  finds markup drift in the keyless providers before a user finds it. A
  separate file keeps the expensive real-model job of `ci.yml` off the daily
  schedule.
- The job has no `needs`. It runs
  `swift build --package-path WebIntegrationTests --build-tests` and then
  `swift test --package-path WebIntegrationTests --no-parallel` on each push
  and pull request. The build step gives the compile coupling that
  `IntegrationTests/Package.swift` asks for. This is a change from the first
  design, which put the build step in the unit job of the shared
  `swift-ci.yaml`: that workflow has only one package-path input.
- The job maps the repository secrets `BRAVE_SEARCH_API_KEY`,
  `TAVILY_API_KEY`, `EXA_API_KEY`, `SERPER_API_KEY`, `KAGI_API_KEY` to
  environment variables. It sets `MULTITOOL_WEB_EXPECTED_PROVIDERS` to the
  provider names (not the secret names) of the secrets that `gh secret list`
  shows, for example `braveAPI,tavily`.

## Work items

The kanban board of this repository holds the work, as tasks with the tag
`web`. Their dependencies give the order. Each task ends with a green
`swift test`.

## Security

`docs/SECURITY.md` says that the sandbox has "no filesystem, network, process,
or Objective-C/Swift bridging access of any kind". That stays true. The
sandbox itself gets no network. The `web` capability is a tool that the host
mounts, the same as `files` and `shell`. The new section of `SECURITY.md`
must state:

- The capability is off by default. The host turns it on with `withWeb`.
- Each request goes through `WebAddressGuard`, and each redirect hop also.
- **Known limit:** the guard resolves the host, and then `URLSession`
  resolves it again to connect. A DNS server that gives a different answer
  the second time (DNS rebinding) can pass the guard. A host that must stop
  this uses a network policy outside the process.
- Keys stay in Swift. The sandbox and the model never see a key.
- Page content is data from outside. It can contain text that tries to give
  the model instructions. The capability does not remove such text. The host
  must know this.
- `searxng(URL)` is host configuration. The guard does not check the search
  request to that URL, because a local SearXNG instance is a normal case.
  The guard still checks each redirect hop of that request, and each result
  URL that a snippet fetches.

## Decisions

All five decisions are confirmed.

1. **DOM parser: add SwiftSoup. (Confirmed, 2026-09-24.)** The package has no HTML parser now. The
   package targets macOS 27 only, thus Foundation `XMLDocument` with
   `.documentTidyHTML` is available with no new dependency. But its tidy step
   is old and is not an HTML5 parser. It changes or drops modern markup, and
   the Brave results page is modern markup. A parser of our own is a large
   task with many defects. SwiftSoup is pure Swift, MIT license, and used a
   lot. It has CSS selectors, thus the `brave.rs` selectors port with no
   change. We use it for the Brave and DuckDuckGo parse and for
   `HTMLMarkdown`.
2. **`search` and `fetch` are separate. (Confirmed, 2026-09-24.)** `search`
   has no option to fetch result pages. It gives hits only. The snippet
   selects the pages and fetches them with `fetch`, for example with
   `Promise.all`. That is the product idea ("composition").
3. **Synchronous verbs, not background. (Confirmed, 2026-09-24.)** Each call has a hard timeout
   (search: 10 seconds for each provider; fetch: 30 seconds by default, 120 at
   most). `executionTimeLimit` (120 seconds) bounds the snippet. If a verb is
   often slower than `inlineSettleGrace`, we can declare `BackgroundTool` on
   it later. This is only an addition.
4. **All six keyed providers. (Confirmed, 2026-09-24.)** Brave API, Tavily,
   Exa, Serper, Kagi, and SearXNG. All six are built.
5. **Default configuration of `withWeb()` is `.fromEnvironment()`. (Confirmed, 2026-09-24.)** A host
   that wants no environment read uses `.keyless` or gives its own list.

## Out of scope

- A headless browser, or JavaScript execution for pages that render on the
  client.
- PDF to text.
- The GitHub issue and Google Docs converters of `markdowndown`.
- A configuration file for keys. The host reads its own configuration and
  gives `WebConfiguration`.
- Image, video, and news search categories.
