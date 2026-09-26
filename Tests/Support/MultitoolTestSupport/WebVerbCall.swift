// `WebVerbCall` — the one call of each web verb, `search` and `fetch`, for the
// suites of two packages.
//
// The unit suites call each verb over a stub session (`WebVerbFixture`). The
// live suites of `WebIntegrationTests/` call each verb over the real session
// (`LiveSearch`, `LiveFetch`). The call is the same in both packages: make the
// verb over a context, and give it the arguments. This file holds that call
// one time. The context is the only difference, thus each caller gives its own
// context.
//
// The verbs and their argument and result types are `internal` to the
// library, thus this file reads them with `@testable import`, and each caller
// reads this file with `@testable import MultitoolTestSupport`.

@testable import FoundationModelsMultitool

/// The one call of each web verb over a web context.
enum WebVerbCall {
    /// Calls the `search` verb.
    ///
    /// - Parameters:
    ///   - query: The query text.
    ///   - count: The number of results, or `nil` for the default.
    ///   - freshness: The age limit, or `nil` for no limit.
    ///   - site: The one host of the results, or `nil` for all hosts.
    ///   - context: The web context that the verb uses.
    /// - Returns: The result of the verb.
    /// - Throws: When the verb throws. The verb must not throw.
    static func search(
        _ query: String, count: Int? = nil, freshness: String? = nil, site: String? = nil,
        context: WebContext
    ) async throws -> SearchResult {
        try await Search(context: context).call(
            arguments: .init(query: query, count: count, freshness: freshness, site: site))
    }

    /// Calls the `fetch` verb.
    ///
    /// - Parameters:
    ///   - url: The URL text.
    ///   - format: The format name, or `nil` for the default.
    ///   - offset: The character offset of the window, or `nil` for 0.
    ///   - maxCharacters: The window size, or `nil` for the default.
    ///   - timeout: The time limit in seconds, or `nil` for the default.
    ///   - context: The web context that the verb uses. Two calls that share
    ///     one context share one page cache.
    /// - Returns: The result of the verb.
    /// - Throws: When the verb throws. The verb must not throw.
    static func fetch(
        _ url: String, format: String? = nil, offset: Int? = nil, maxCharacters: Int? = nil,
        timeout: Int? = nil, context: WebContext
    ) async throws -> FetchResult {
        try await Fetch(context: context).call(
            arguments: .init(
                url: url, format: format, offset: offset, maxCharacters: maxCharacters, timeout: timeout))
    }
}
