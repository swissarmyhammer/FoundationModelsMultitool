// `WebSearchChain` — the provider order, the fallback, the notes, and the
// redaction of the web search (web.md § "Fallback" and § "Keys").
//
// The chain tries the providers in order. The first provider that gives hits
// wins, and the chain sends no request to a later provider. A provider that
// fails adds one note, and the chain goes to the next provider. When all
// providers fail and one of them gave no results, the chain runs one more time
// with the relaxed text of the query: the text with no quote marks and no
// search operators. When that run fails too, or when the chain does not run
// again, the result is one correction that names each provider and its
// failure for the exact query, and then gives the next step for the model.
// Before a note or the correction goes out, the chain replaces each key value
// of the call with `<redacted>`.

import Foundation

/// The result of a search.
enum SearchOutcome: Sendable, Equatable {
    /// The hits of the provider that won, and the notes: first one note for
    /// each provider that the chain skipped, then one note for each query
    /// field that the winner ignored. Hits of a relaxed run have the relaxed
    /// note before these notes.
    case hits(provider: String, hits: [WebHit], notes: [String])

    /// The correction when no provider gave hits. It names each provider and
    /// its failure, in order, and then gives the next step for the model.
    case correction(String)
}

/// Tries the search providers in order, and goes to the next provider when
/// one fails.
struct WebSearchChain: Sendable {
    /// The first sentence of the correction when all providers fail.
    static let correctionLead = "No search provider gave results."

    /// The last sentence of the correction when one or more providers gave
    /// no results: the next step for the model.
    ///
    /// A provider that gave no results read the query and found nothing. A
    /// wider query can find results, thus the step tells the model to make
    /// the query wider. The step stays correct after a relaxed run that
    /// failed too: the relaxed text removes quote marks and operators, but
    /// it keeps each word, so fewer words can still help.
    static let correctionNextStep = "Search again with fewer words, with no quote marks and no names of persons."

    /// The last sentence of the correction when no provider gave no results:
    /// the next step for the model.
    ///
    /// Decision: the step is about the providers, not about the query. Each
    /// failure is then a block (HTTP 429 or a challenge page), a server
    /// error, a network failure, a response that the code cannot read, or a
    /// key problem. No provider read the query and found nothing, thus a
    /// different query does not help. A block, a server error, and a
    /// network failure can go away after some time, thus the step tells the
    /// model to wait. When one provider gave no results and another provider
    /// was blocked, the correction gives ``correctionNextStep``, because the
    /// query is the cause that the model can change.
    static let correctionWaitStep = "Wait, then search again."

    /// The first words of the note of a relaxed run. The relaxed text comes
    /// after them.
    private static let relaxedNoteLead = "No results for the exact query; these are the results for: "

    /// The quote marks that ``relaxedText(of:)`` removes: the straight quote
    /// mark and the typographic double quote marks. The typographic single
    /// quote marks stay, because `’` is also the apostrophe in a word.
    private static let quoteMarks: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}"]

    /// The search operators that start a word, in lower case. The relaxed
    /// text keeps the value after the operator.
    private static let prefixOperators = ["site:", "intitle:", "inurl:", "filetype:"]

    /// The signs that start a word as an operator: `-` excludes the word and
    /// `+` requires it.
    private static let signOperators: Set<Character> = ["-", "+"]

    /// The words that are Boolean operators. A search engine reads them as
    /// operators only in upper case.
    private static let booleanOperators: Set<Substring> = ["OR", "AND"]

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
    ///   - fetcher: The fetcher that sends each provider request. A provider
    ///     has no time limit of its own: the chain goes to the next provider
    ///     only when a provider fails or is blocked.
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
    /// When all providers fail and one or more of them gives no results, the
    /// chain runs one more time with the relaxed text of the query (see
    /// ``relaxedText(of:)``). It does not run again when the relaxed text is
    /// empty or is the same as the text of the query.
    ///
    /// - Parameter query: The query.
    /// - Returns: The hits of the first provider that gives hits, with the
    ///   notes. Else the hits of the relaxed run, with the relaxed note first.
    ///   Else one correction that names each provider and its failure for the
    ///   exact query, and then gives ``correctionNextStep`` or
    ///   ``correctionWaitStep``. No note and no correction holds a key value
    ///   of this call.
    func search(_ query: SearchQuery) async -> SearchOutcome {
        let keys = providers.compactMap { provider, _ in provider.apiKey?.resolve(in: environment) }
        switch await run(query) {
        case .hits(let provider, let hits, let notes):
            return Self.hitsOutcome(provider: provider, hits: hits, notes: notes, keys: keys)
        case .allFailed(let skipped):
            let correction = ([Self.correctionLead] + skipped.map(\.failure) + [Self.nextStep(after: skipped)])
                .joined(separator: " ")
            let exactOutcome = SearchOutcome.correction(KeyRedaction.redactingKeys(correction, keys: keys))
            return await relaxedSearch(query, after: skipped, keys: keys) ?? exactOutcome
        }
    }

    /// Selects the last sentence of the correction.
    ///
    /// - Parameter skipped: The providers that the run of the exact query
    ///   skipped, in order.
    /// - Returns: ``correctionNextStep`` when one or more providers gave no
    ///   results, else ``correctionWaitStep``.
    private static func nextStep(after skipped: [SkippedProvider]) -> String {
        skipped.contains(where: \.gaveNoResults) ? correctionNextStep : correctionWaitStep
    }

    /// Makes the relaxed text of a query text: the text with no quote marks
    /// and no search operators.
    ///
    /// The function removes:
    /// - the straight quote mark and the typographic double quote marks;
    /// - the operators `site:`, `intitle:`, `inurl:`, and `filetype:` at the
    ///   start of a word, in each letter case. The value after the operator
    ///   stays as a word;
    /// - a leading `-` or `+` on a word. A hyphen inside a word stays;
    /// - the words `OR` and `AND` in upper case. A search engine reads only
    ///   the upper case words as operators, thus `or` and `and` stay.
    ///
    /// Then the whitespace collapses to one space between words, with no
    /// space at the start or the end. The `site` field of a query is not in
    /// its text, thus this function does not change it.
    ///
    /// - Parameter text: The query text.
    /// - Returns: The relaxed text. It is empty when the text holds only
    ///   quote marks and operators.
    static func relaxedText(of text: String) -> String {
        text.filter { !quoteMarks.contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .filter { !booleanOperators.contains($0) }
            .map(relaxedWord)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Removes the operator from one word of a query text.
    ///
    /// - Parameter word: The word, with no whitespace and no quote marks.
    /// - Returns: The word with no leading sign and no leading operator; it is
    ///   empty when the word is only an operator.
    private static func relaxedWord(_ word: Substring) -> Substring {
        let unsigned = word.first.map(signOperators.contains) == true ? word.dropFirst() : word
        let prefix = prefixOperators.first { unsigned.prefix($0.count).lowercased() == $0 }
        return prefix.map { unsigned.dropFirst($0.count) } ?? unsigned
    }

    /// Runs the chain one more time with the relaxed text of the query, when
    /// a provider gave no results for the exact query.
    ///
    /// - Parameters:
    ///   - query: The exact query.
    ///   - skipped: The providers that the run of the exact query skipped.
    ///   - keys: The key values of this call, which the notes must not hold.
    /// - Returns: The hits of the relaxed run, with the relaxed note first and
    ///   then the notes of that run; or `nil` when no provider gave no
    ///   results, when the relaxed text is empty or the same as the text, or
    ///   when the relaxed run fails too.
    private func relaxedSearch(
        _ query: SearchQuery, after skipped: [SkippedProvider], keys: [String]
    ) async -> SearchOutcome? {
        guard skipped.contains(where: \.gaveNoResults) else { return nil }
        let relaxed = Self.relaxedText(of: query.text)
        guard !relaxed.isEmpty, relaxed != query.text else { return nil }
        guard case .hits(let provider, let hits, let notes) = await run(query.replacingText(with: relaxed)) else {
            return nil
        }
        return Self.hitsOutcome(
            provider: provider, hits: hits, notes: [Self.relaxedNoteLead + relaxed] + notes, keys: keys)
    }

    /// Tries each provider in order with one query, until one gives hits.
    ///
    /// - Parameter query: The query.
    /// - Returns: The hits of the first provider that gives hits, with one
    ///   note for each skipped provider and then one note for each ignored
    ///   field; else each skipped provider, in order. The notes are not
    ///   redacted.
    private func run(_ query: SearchQuery) async -> ChainRun {
        var skipped: [SkippedProvider] = []
        for (provider, adapter) in providers {
            switch await attempt(query, provider: provider, adapter: adapter) {
            case .success(let hits):
                let notes = skipped.map(\.note) + Self.ignoredFieldNotes(of: query, adapter: adapter)
                return .hits(provider: adapter.name, hits: hits, notes: notes)
            case .failure(let skip):
                skipped.append(SkippedProvider(name: adapter.name, skip: skip))
            }
        }
        return .allFailed(skipped)
    }

    /// Makes the outcome of hits, with each key value in the notes replaced.
    ///
    /// - Parameters:
    ///   - provider: The name of the provider that won.
    ///   - hits: The hits.
    ///   - notes: The notes, before the redaction.
    ///   - keys: The key values of this call.
    /// - Returns: The outcome.
    private static func hitsOutcome(
        provider: String, hits: [WebHit], notes: [String], keys: [String]
    ) -> SearchOutcome {
        .hits(provider: provider, hits: hits, notes: notes.map { KeyRedaction.redactingKeys($0, keys: keys) })
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
        switch await fetcher.load(request, guarded: !adapter.isHostConfiguration) {
        case .failure(let failure):
            return .failure(.fetch(failure))
        case .success(let body):
            return Self.hits(in: body, adapter: adapter, limit: query.count).mapError(ProviderSkip.provider)
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
    /// the adapter reads the body. The adapter reads each other status, thus
    /// it can map a status that only its service uses, for example the HTTP
    /// 422 of a refused Brave Search API key. An adapter that gives an empty
    /// list gives ``ProviderFailure/noResults``.
    ///
    /// - Parameters:
    ///   - body: The body and the facts of the response.
    ///   - adapter: The adapter that reads the body.
    ///   - limit: The maximum number of hits, which is the count of the
    ///     query, or `nil` for all hits of the response.
    /// - Returns: The hits, or the failure.
    private static func hits(
        in body: FetchedBody, adapter: any SearchProviderAdapter, limit: Int?
    ) -> Result<[WebHit], ProviderFailure> {
        if let failure = ProviderFailure(status: body.status) {
            return .failure(failure)
        }
        guard let response = httpResponse(of: body) else {
            return .failure(.parse("the response has no HTTP form"))
        }
        do {
            let hits = try adapter.parse(body.bytes, response: response, limit: limit)
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

/// The result of one run of the chain over all providers, before the chain
/// redacts the notes.
private enum ChainRun {
    /// The hits of the provider that won, and the notes of the run.
    case hits(provider: String, hits: [WebHit], notes: [String])

    /// No provider gave hits. Each skipped provider, in order.
    case allFailed([SkippedProvider])
}

/// One provider that the chain skipped, and why.
private struct SkippedProvider {
    /// The name of the provider.
    let name: String

    /// Why the chain skipped it.
    let skip: ProviderSkip

    /// `true` when the provider answered with no results.
    var gaveNoResults: Bool {
        guard case .provider(.noResults) = skip else { return false }
        return true
    }

    /// The note of the skip, for example
    /// `braveAPI: skipped, BRAVE_SEARCH_API_KEY is not set.`
    var note: String { "\(name): skipped, \(skip.reason.endingSentence)" }

    /// The part of the correction for this provider, for example
    /// `braveHTML: blocked (HTTP 429).`
    var failure: String { "\(name): \(skip.reason.endingSentence)" }
}

/// Why the chain skipped one provider.
private enum ProviderSkip: Error {
    /// The provider has a key, and the key has no value now. The variable is
    /// the name of the environment variable, or `nil` for an empty literal
    /// key.
    case keyNotSet(variable: String?)

    /// The adapter could not make the request, with the text of its error.
    case requestFailed(String)

    /// The fetcher failed: a guard refusal, too many redirects, or a network
    /// failure.
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
        case .badKey(let status): "the API key was refused (HTTP \(status))"
        case .rateLimited: "blocked (HTTP 429)"
        case .serverError(let status): "server error (HTTP \(status))"
        case .challenge: "blocked by a challenge page"
        case .noResults: "no results"
        case .parse(let text): "the response could not be read: \(text)"
        }
    }
}

private extension SearchQuery {
    /// A copy of the query with another text. The count, the freshness, and
    /// the site do not change.
    ///
    /// - Parameter text: The text of the copy.
    /// - Returns: The copy.
    func replacingText(with text: String) -> SearchQuery {
        SearchQuery(text: text, count: count, freshness: freshness, site: site)
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
