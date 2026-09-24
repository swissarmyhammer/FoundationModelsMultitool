// `WebSearchChain` — the provider order, the fallback, the notes, and the
// redaction of the web search (web.md § "Fallback" and § "Keys").
//
// The chain tries the providers in order. The first provider that gives hits
// wins, and the chain sends no request to a later provider. A provider that
// fails adds one note, and the chain goes to the next provider. When all
// providers fail, the result is one correction that names each provider and
// its failure. Before a note or the correction goes out, the chain replaces
// each key value of the call with `<redacted>`.

import Foundation

/// The result of a search.
enum SearchOutcome: Sendable, Equatable {
    /// The hits of the provider that won, and the notes: first one note for
    /// each provider that the chain skipped, then one note for each query
    /// field that the winner ignored.
    case hits(provider: String, hits: [WebHit], notes: [String])

    /// The correction when no provider gave hits. It names each provider and
    /// its failure, in order.
    case correction(String)
}

/// Tries the search providers in order, and goes to the next provider when
/// one fails.
struct WebSearchChain: Sendable {
    /// The first sentence of the correction when all providers fail.
    static let correctionLead = "No search provider gave results."

    /// The providers and their adapters, in the order to try.
    private let providers: [(WebSearchProvider, any SearchProviderAdapter)]

    /// The fetcher that sends each provider request.
    private let fetcher: WebFetcher

    /// The environment dictionary that each `.environment` key reads at the
    /// time of a call.
    private let environment: [String: String]

    /// Makes a chain.
    ///
    /// - Parameters:
    ///   - providers: The providers and their adapters, in the order to try.
    ///     The provider gives the API key. The adapter makes the request and
    ///     reads the response.
    ///   - fetcher: The fetcher that sends each provider request. Its
    ///     `searchTimeout` is the time limit of one provider.
    ///   - environment: The environment dictionary that each `.environment`
    ///     key reads at the time of a call.
    init(
        providers: [(WebSearchProvider, any SearchProviderAdapter)],
        fetcher: WebFetcher,
        environment: [String: String]
    ) {
        self.providers = providers
        self.fetcher = fetcher
        self.environment = environment
    }

    /// Searches with each provider in order, until one gives hits.
    ///
    /// - Parameter query: The query.
    /// - Returns: The hits of the first provider that gives hits, with the
    ///   notes; else one correction that names each provider and its failure.
    ///   No note and no correction holds a key value of this call.
    func search(_ query: SearchQuery) async -> SearchOutcome {
        let keys = providers.compactMap { provider, _ in provider.apiKey?.resolve(in: environment) }
        var skipped: [SkippedProvider] = []
        for (provider, adapter) in providers {
            switch await attempt(query, provider: provider, adapter: adapter) {
            case .success(let hits):
                let notes = skipped.map(\.note) + Self.ignoredFieldNotes(of: query, adapter: adapter)
                return .hits(
                    provider: adapter.name, hits: hits,
                    notes: notes.map { KeyRedaction.redactingKeys($0, keys: keys) })
            case .failure(let skip):
                skipped.append(SkippedProvider(name: adapter.name, reason: skip.reason))
            }
        }
        let correction = ([Self.correctionLead] + skipped.map(\.failure)).joined(separator: " ")
        return .correction(KeyRedaction.redactingKeys(correction, keys: keys))
    }

    /// Sends the request of one provider and reads its hits.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - provider: The provider, which gives the API key.
    ///   - adapter: The adapter of the provider.
    /// - Returns: The hits, or why the chain skips the provider.
    private func attempt(
        _ query: SearchQuery, provider: WebSearchProvider, adapter: any SearchProviderAdapter
    ) async -> Result<[WebHit], ProviderSkip> {
        let request: URLRequest
        do {
            request = try makeRequest(for: query, provider: provider, adapter: adapter)
        } catch {
            return .failure(error)
        }
        let timeout = Duration.seconds(fetcher.policy.searchTimeout)
        switch await fetcher.load(request, timeout: timeout, guarded: !adapter.isHostConfiguration) {
        case .failure(let failure):
            return .failure(.fetch(failure))
        case .success(let body):
            return Self.hits(in: body, adapter: adapter).mapError(ProviderSkip.provider)
        }
    }

    /// Makes the request of one provider, with the key value that the
    /// environment holds now.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - provider: The provider, which gives the API key.
    ///   - adapter: The adapter that makes the request.
    /// - Returns: The request.
    /// - Throws: ``ProviderSkip/keyNotSet(variable:)`` when the provider has
    ///   a key and the key has no value now, and
    ///   ``ProviderSkip/requestFailed(_:)`` when the adapter cannot make the
    ///   request.
    private func makeRequest(
        for query: SearchQuery, provider: WebSearchProvider, adapter: any SearchProviderAdapter
    ) throws(ProviderSkip) -> URLRequest {
        var key: String?
        if let apiKey = provider.apiKey {
            guard let value = apiKey.resolve(in: environment) else {
                throw .keyNotSet(variable: apiKey.variableName)
            }
            key = value
        }
        do {
            return try adapter.request(for: query, key: key)
        } catch {
            throw .requestFailed(String(describing: error))
        }
    }

    /// Reads the hits of one response.
    ///
    /// The status comes first: 401, 403, 429, and 5xx are failures before
    /// the adapter reads the body. An adapter that gives an empty list gives
    /// ``ProviderFailure/noResults``.
    ///
    /// - Parameters:
    ///   - body: The body and the facts of the response.
    ///   - adapter: The adapter that reads the body.
    /// - Returns: The hits, or the failure.
    private static func hits(
        in body: FetchedBody, adapter: any SearchProviderAdapter
    ) -> Result<[WebHit], ProviderFailure> {
        if let failure = ProviderFailure(status: body.status) {
            return .failure(failure)
        }
        guard let response = httpResponse(of: body) else {
            return .failure(.parse("the response has no HTTP form"))
        }
        do {
            let hits = try adapter.parse(body.bytes, response: response)
            return hits.isEmpty ? .failure(.noResults) : .success(hits)
        } catch {
            return .failure(error)
        }
    }

    /// Makes the HTTP response that an adapter reads, from the facts of a
    /// body.
    ///
    /// - Parameter body: The body and the facts of the response.
    /// - Returns: A response with the final URL, the status, and the
    ///   `Content-Type` with its charset; or `nil` when Foundation cannot
    ///   make it.
    private static func httpResponse(of body: FetchedBody) -> HTTPURLResponse? {
        let contentType = body.charset.map { "\(body.contentType); \(WebFetcher.charsetParameter)=\($0)" }
        return HTTPURLResponse(
            url: body.url, statusCode: body.status, httpVersion: nil,
            headerFields: [WebFetcher.contentTypeHeader: contentType ?? body.contentType])
    }

    /// Makes one note for each query field that the caller set and the
    /// adapter does not support.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - adapter: The adapter of the provider that won.
    /// - Returns: The notes, in the order of ``SearchFeature``.
    private static func ignoredFieldNotes(of query: SearchQuery, adapter: any SearchProviderAdapter) -> [String] {
        query.requestedFeatures
            .filter { !adapter.supports.contains($0) }
            .map { "\($0.rawValue) is not supported by \(adapter.name) and was ignored." }
    }
}

/// One provider that the chain skipped, and why.
private struct SkippedProvider {
    /// The name of the provider.
    let name: String

    /// Why the chain skipped it, for example `blocked (HTTP 429)`.
    let reason: String

    /// The note of the skip, for example
    /// `braveAPI: skipped, BRAVE_SEARCH_API_KEY is not set.`
    var note: String { "\(name): skipped, \(reason.endingSentence)" }

    /// The part of the correction for this provider, for example
    /// `braveHTML: blocked (HTTP 429).`
    var failure: String { "\(name): \(reason.endingSentence)" }
}

/// Why the chain skipped one provider.
private enum ProviderSkip: Error {
    /// The provider has a key, and the key has no value now. The variable is
    /// the name of the environment variable, or `nil` for an empty literal
    /// key.
    case keyNotSet(variable: String?)

    /// The adapter could not make the request, with the text of its error.
    case requestFailed(String)

    /// The fetcher failed: a guard refusal, a timeout, or a network failure.
    case fetch(WebFetchFailure)

    /// The provider answered with no hits.
    case provider(ProviderFailure)

    /// The reason in the note, with no end period, for example
    /// `no results`.
    var reason: String {
        switch self {
        case .keyNotSet(let variable): variable.map { "\($0) is not set" } ?? "the API key is empty"
        case .requestFailed(let text): "the request could not be made: \(text)"
        case .fetch(let failure): failure.correctiveMessage.startingLowercase
        case .provider(let failure): failure.reason
        }
    }
}

private extension ProviderFailure {
    /// The reason in the note, with no end period, for example
    /// `blocked (HTTP 429)`.
    var reason: String {
        switch self {
        case .badKey: "the API key was refused"
        case .rateLimited: "blocked (HTTP 429)"
        case .serverError(let status): "server error (HTTP \(status))"
        case .challenge: "blocked by a challenge page"
        case .noResults: "no results"
        case .parse(let text): "the response could not be read: \(text)"
        }
    }
}

private extension WebSearchProvider {
    /// The API key of a keyed provider, or `nil` for a provider with no key.
    var apiKey: WebAPIKey? {
        switch self {
        case .braveHTML, .duckDuckGoHTML, .searxng:
            nil
        case .braveAPI(let key), .tavily(let key), .exa(let key), .serper(let key), .kagi(let key):
            key
        }
    }
}

private extension String {
    /// The text with a period at the end, when it has none.
    var endingSentence: String {
        hasSuffix(".") ? self : self + "."
    }

    /// The text with its first character in lower case, for example a
    /// correction of the fetcher inside a note.
    var startingLowercase: String {
        prefix(1).lowercased() + dropFirst()
    }
}
