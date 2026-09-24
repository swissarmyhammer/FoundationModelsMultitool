// `WebConfiguration` — the configuration of the web capability: the search
// providers to try, the fetch limits, and the environment that the API keys
// come from (web.md § "Providers and API keys").
//
// No string form of a type in this file shows a key value. `WebAPIKey` shows
// `WebAPIKey(<redacted>)`, and `WebConfiguration` does not show the values of
// its environment dictionary.

import Foundation

/// A search provider that the web capability can send a query to.
///
/// `WebConfiguration.providers` holds the providers in the order to try. The
/// first provider that gives results wins.
public enum WebSearchProvider: Sendable, Hashable {
    /// The Brave search results page. It needs no key.
    case braveHTML
    /// The DuckDuckGo HTML results page. It needs no key.
    case duckDuckGoHTML
    /// The Brave Search API.
    case braveAPI(WebAPIKey)
    /// The Tavily search API.
    case tavily(WebAPIKey)
    /// The Exa search API.
    case exa(WebAPIKey)
    /// The Serper search API.
    case serper(WebAPIKey)
    /// The Kagi search API.
    case kagi(WebAPIKey)
    /// A SearXNG instance that the host runs, at this base URL.
    case searxng(URL)

    /// The name of the provider, for example `braveHTML`.
    ///
    /// The name is the name of the case. It holds no key and no URL, thus a
    /// note or a correction can show it.
    public var name: String {
        switch self {
        case .braveHTML: "braveHTML"
        case .duckDuckGoHTML: "duckDuckGoHTML"
        case .braveAPI: "braveAPI"
        case .tavily: "tavily"
        case .exa: "exa"
        case .serper: "serper"
        case .kagi: "kagi"
        case .searxng: "searxng"
        }
    }
}

/// An API key of a search provider.
///
/// A `.literal` key holds the value in memory. An `.environment` key holds
/// only the name of an environment variable. The capability reads the value
/// at the time of each call, from the environment dictionary of its
/// `WebConfiguration`.
///
/// `description`, `debugDescription`, and `customMirror` show
/// `WebAPIKey(<redacted>)`. They never show the value or the variable name.
public struct WebAPIKey: Sendable, Hashable {
    /// Where the key value comes from.
    private enum Source: Sendable, Hashable {
        /// The key value itself.
        case literal(String)
        /// The name of the environment variable that holds the key value.
        case environment(String)
    }

    /// Where the key value comes from.
    private let source: Source

    /// Makes a key that holds its value in memory.
    ///
    /// - Parameter value: The key value.
    /// - Returns: The key.
    public static func literal(_ value: String) -> WebAPIKey {
        WebAPIKey(source: .literal(value))
    }

    /// Makes a key that reads its value from an environment variable at the
    /// time of each call.
    ///
    /// - Parameter name: The name of the environment variable, for example
    ///   `TAVILY_API_KEY`.
    /// - Returns: The key.
    public static func environment(_ name: String) -> WebAPIKey {
        WebAPIKey(source: .environment(name))
    }

    /// Gets the key value.
    ///
    /// An empty value is not a usable key, thus it gives `nil` the same as a
    /// missing variable. The caller then goes to the next provider.
    ///
    /// - Parameter environment: The environment dictionary that an
    ///   `.environment` key reads its variable from. A `.literal` key does not
    ///   read it.
    /// - Returns: The key value, or `nil` when the variable is not set or the
    ///   value is empty.
    public func resolve(in environment: [String: String]) -> String? {
        let value: String? =
            switch source {
            case .literal(let value): value
            case .environment(let name): environment[name]
            }
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

extension WebAPIKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The text that each string form of a key shows.
    private static let redactedForm = "WebAPIKey(\(KeyRedaction.placeholder))"

    /// `WebAPIKey(<redacted>)`. It never shows the key value.
    public var description: String { Self.redactedForm }

    /// `WebAPIKey(<redacted>)`. It never shows the key value.
    public var debugDescription: String { Self.redactedForm }

    /// A mirror with no children. Thus `dump` shows only
    /// `WebAPIKey(<redacted>)`, and never the key value.
    public var customMirror: Mirror {
        Mirror(self, children: [], displayStyle: .struct)
    }
}

/// The limits and the user agent of each web request.
public struct WebFetchPolicy: Sendable, Equatable {
    /// The `User-Agent` of a request that does not set its own. It names this
    /// package.
    public static let packageUserAgent =
        "FoundationModelsMultitool (+https://github.com/swissarmyhammer/FoundationModelsMultitool)"

    /// The maximum number of body bytes to read from one response. The
    /// fetch stops at this limit and notes that the page is not complete.
    public var maxBytes: Int

    /// The `User-Agent` of a request that does not set its own.
    public var userAgent: String

    /// The maximum number of redirect hops for one request.
    public var maxRedirects: Int

    /// The time limit of one search provider, in seconds.
    public var searchTimeout: TimeInterval

    /// The time limit of one fetch, in seconds, when the call does not give
    /// its own.
    public var defaultFetchTimeout: TimeInterval

    /// Makes a fetch policy.
    ///
    /// - Parameters:
    ///   - maxBytes: The maximum number of body bytes to read from one
    ///     response. The default is 5 MB (5 × 1024 × 1024 bytes).
    ///   - userAgent: The `User-Agent` of a request that does not set its
    ///     own. The default is ``packageUserAgent``.
    ///   - maxRedirects: The maximum number of redirect hops. The default is
    ///     10.
    ///   - searchTimeout: The time limit of one search provider, in seconds.
    ///     The default is 10.
    ///   - defaultFetchTimeout: The time limit of one fetch, in seconds, when
    ///     the call does not give its own. The default is 30.
    public init(
        maxBytes: Int = 5_242_880,
        userAgent: String = WebFetchPolicy.packageUserAgent,
        maxRedirects: Int = 10,
        searchTimeout: TimeInterval = 10,
        defaultFetchTimeout: TimeInterval = 30
    ) {
        self.maxBytes = maxBytes
        self.userAgent = userAgent
        self.maxRedirects = maxRedirects
        self.searchTimeout = searchTimeout
        self.defaultFetchTimeout = defaultFetchTimeout
    }
}

/// The configuration of the web capability.
///
/// No string form of a configuration shows a key value: the providers show
/// only their names, and the environment dictionary shows no value.
public struct WebConfiguration: Sendable {
    /// The order to try. The first provider that gives results wins.
    public var providers: [WebSearchProvider]

    /// The limits and the user agent of each request.
    public var fetch: WebFetchPolicy

    /// The environment dictionary that each `.environment` key reads at the
    /// time of a call.
    public var environment: [String: String]

    /// Makes a configuration.
    ///
    /// - Parameters:
    ///   - providers: The providers, in the order to try.
    ///   - fetch: The limits and the user agent of each request.
    ///   - environment: The environment dictionary that each `.environment`
    ///     key reads. The default is empty.
    public init(
        providers: [WebSearchProvider],
        fetch: WebFetchPolicy = WebFetchPolicy(),
        environment: [String: String] = [:]
    ) {
        self.providers = providers
        self.fetch = fetch
        self.environment = environment
    }

    /// `braveHTML`, then `duckDuckGoHTML`. Reads no environment.
    public static let keyless = WebConfiguration(providers: [.braveHTML, .duckDuckGoHTML])

    /// Each keyed provider whose variable is set, in table order, then the
    /// keyless providers as the last fallback.
    ///
    /// The order is `braveAPI` (`BRAVE_SEARCH_API_KEY`, else `BRAVE_API_KEY`),
    /// `tavily` (`TAVILY_API_KEY`), `exa` (`EXA_API_KEY`), `serper`
    /// (`SERPER_API_KEY`), `kagi` (`KAGI_API_KEY`), `searxng` (`SEARXNG_URL`),
    /// `braveHTML`, `duckDuckGoHTML`. An empty variable is not set.
    ///
    /// A keyed provider holds `.environment(<name>)` and not the value. Thus
    /// the capability reads the value from ``environment`` at the time of
    /// each call. `SEARXNG_URL` is a base URL, not a key. It must be an
    /// `http` or `https` URL with a host, else it adds no provider.
    ///
    /// - Parameter environment: The environment dictionary to read. The
    ///   default is the environment of the process. The configuration keeps
    ///   it as ``environment``.
    /// - Returns: The configuration.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WebConfiguration {
        let keyed = keyedProviders.compactMap { $0.provider(in: environment) }
        let searxng = searxngProvider(in: environment).map { [$0] } ?? []
        return WebConfiguration(
            providers: keyed + searxng + keyless.providers, environment: environment)
    }
}

extension WebConfiguration {
    /// One row of the keyed provider table: the variables that can hold the
    /// key, and the case that holds the key.
    private struct KeyedProvider: Sendable {
        /// The environment variables that can hold the key, in the order to
        /// use. The first variable that is set wins.
        let variables: [String]

        /// Makes the provider case from its key.
        let make: @Sendable (WebAPIKey) -> WebSearchProvider

        /// Makes the provider that reads the first set variable of this row.
        ///
        /// - Parameter environment: The environment dictionary to read.
        /// - Returns: The provider, or `nil` when no variable of this row is
        ///   set.
        func provider(in environment: [String: String]) -> WebSearchProvider? {
            variables
                .map(WebAPIKey.environment)
                .first { $0.resolve(in: environment) != nil }
                .map(make)
        }
    }

    /// The keyed providers, in the order to try (web.md § "The provider
    /// list").
    private static let keyedProviders: [KeyedProvider] = [
        KeyedProvider(variables: ["BRAVE_SEARCH_API_KEY", "BRAVE_API_KEY"]) { .braveAPI($0) },
        KeyedProvider(variables: ["TAVILY_API_KEY"]) { .tavily($0) },
        KeyedProvider(variables: ["EXA_API_KEY"]) { .exa($0) },
        KeyedProvider(variables: ["SERPER_API_KEY"]) { .serper($0) },
        KeyedProvider(variables: ["KAGI_API_KEY"]) { .kagi($0) },
    ]

    /// The environment variable that holds the base URL of a SearXNG
    /// instance.
    private static let searxngVariable = "SEARXNG_URL"

    /// The URL schemes that a SearXNG base URL can have.
    private static let searxngSchemes: Set<String> = ["http", "https"]

    /// Makes the `searxng` provider from `SEARXNG_URL`.
    ///
    /// URL schemes are not case-sensitive, thus `HTTPS://` is also correct.
    ///
    /// - Parameter environment: The environment dictionary to read.
    /// - Returns: The provider, or `nil` when the variable is not set or does
    ///   not hold an `http` or `https` URL with a host.
    private static func searxngProvider(in environment: [String: String]) -> WebSearchProvider? {
        guard let value = environment[searxngVariable],
            let base = URL(string: value),
            let scheme = base.scheme?.lowercased(),
            searxngSchemes.contains(scheme),
            base.host()?.isEmpty == false
        else { return nil }
        return .searxng(base)
    }
}

extension WebConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The provider names, in order, for example `[braveAPI, braveHTML]`.
    private var providerNames: String {
        "[" + providers.map(\.name).joined(separator: ", ") + "]"
    }

    /// The text that the string forms show in place of the environment
    /// dictionary. It holds the number of variables and no value.
    private var redactedEnvironment: String {
        "\(environment.count) variables, \(KeyRedaction.placeholder)"
    }

    /// The providers by name, the fetch policy, and the number of environment
    /// variables. It never shows a key value.
    public var description: String {
        "WebConfiguration(providers: \(providerNames), fetch: \(fetch), environment: \(redactedEnvironment))"
    }

    /// The same text as ``description``. It never shows a key value.
    public var debugDescription: String { description }

    /// A mirror that `dump` reads. It shows the provider names and not the
    /// providers, and it shows no environment value.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "providers": providerNames,
                "fetch": fetch,
                "environment": redactedEnvironment,
            ],
            displayStyle: .struct)
    }
}
