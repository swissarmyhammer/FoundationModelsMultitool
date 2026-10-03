// `WebContext` — the one shared state of the two web verbs (web.md § "Files
// to add or change").
//
// The context holds one `WebFetcher`, one `WebPageReader`, and one
// `WebSearchChain`. All three come from one `WebConfiguration` and one
// `URLSessionConfiguration`. The reader and the chain use the same fetcher,
// thus each request of the capability goes through one session and one
// guard. The web capability gives the same context to `search` and to
// `fetch`, thus the page cache of the reader is one cache for the session.
//
// The context also maps each `WebSearchProvider` case to its adapter.

import Foundation

/// The shared state of the web verbs: one fetcher, one page reader, and one
/// search chain.
///
/// The context is a class because the verbs share it: each verb holds the
/// same context, thus they share one page cache and one session.
final class WebContext: Sendable {
    /// The fetcher that sends each request of the capability.
    let fetcher: WebFetcher

    /// The reader that loads, converts, and caches the pages of `fetch`.
    let reader: WebPageReader

    /// The chain that tries the search providers of `search` in order.
    let searchChain: WebSearchChain

    /// Makes a context.
    ///
    /// The initializer sends no request. It only makes the session, the
    /// reader, and the chain.
    ///
    /// - Parameters:
    ///   - configuration: The providers, the fetch policy, and the
    ///     environment that the API keys come from.
    ///   - sessionConfiguration: The configuration of the one session. A test
    ///     gives a configuration whose `protocolClasses` holds a stub.
    ///   - resolver: The resolver of the address guard. The default is
    ///     ``SystemHostResolver``. A test gives a stub, thus no lookup goes to
    ///     the network.
    init(
        configuration: WebConfiguration,
        sessionConfiguration: URLSessionConfiguration,
        resolver: any HostResolver = SystemHostResolver()
    ) {
        let fetcher = WebFetcher(
            sessionConfiguration: sessionConfiguration,
            policy: configuration.fetch,
            addressGuard: WebAddressGuard(resolver: resolver))
        self.fetcher = fetcher
        reader = WebPageReader(fetcher: fetcher)
        searchChain = WebSearchChain(
            providers: configuration.providers.map { ($0, $0.searchAdapter) },
            fetcher: fetcher,
            environment: configuration.environment)
    }
}

extension WebSearchProvider {
    /// The adapter that makes the request of this provider and reads its
    /// response.
    ///
    /// The switch has no `default`, thus a new provider case does not
    /// compile until it has an adapter.
    var searchAdapter: any SearchProviderAdapter {
        switch self {
        case .braveHTML: BraveHTMLProvider()
        case .duckDuckGoHTML: DuckDuckGoHTMLProvider()
        case .braveAPI: BraveAPIProvider()
        case .tavily: TavilyProvider()
        case .exa: ExaProvider()
        case .serper: SerperProvider()
        case .kagi: KagiProvider()
        case .searxng(let base): SearXNGProvider(base: base)
        }
    }
}
