// `KeyedProviderCase` — one row of the parameterized suite of the keyed search
// providers (`KeyedProviderTests`). The suite also has a row for `searxng`,
// which uses the same JSON steps but sends no key.
//
// Each row holds the adapter under test, the documented request shape, the
// name of the recorded JSON response in `WebGoldens/`, and a function that
// writes a response body in the JSON form of that provider. Thus one test
// function checks each provider.

import Foundation
@testable import FoundationModelsMultitool
import Testing

/// One result that a test writes into a response body.
struct FixtureResult: Sendable {
    /// The title of the result.
    let title: String

    /// The URL of the result.
    let url: String

    /// The snippet text of the result.
    let snippet: String
}

/// One keyed search provider under test, with its documented request shape.
struct KeyedProviderCase: Sendable, CustomTestStringConvertible {
    /// The key value of each request in the suite. It is a fake value.
    static let fakeKey = "fake-test-key-value"

    /// The resource folder of the recorded responses.
    static let goldensFolder = "WebGoldens"

    /// The number of hits in `brave-api-results.json`.
    private static let braveGoldenHitCount = 4

    /// The number of hits in `tavily-results.json`.
    private static let tavilyGoldenHitCount = 4

    /// The number of hits in `exa-results.json`.
    private static let exaGoldenHitCount = 3

    /// The number of hits in `serper-results.json`.
    private static let serperGoldenHitCount = 4

    /// The number of hits in `kagi-results.json`. The related searches of the
    /// file are not hits.
    private static let kagiGoldenHitCount = 4

    /// The number of hits in `searxng-results.json`.
    private static let searxngGoldenHitCount = 4

    /// The base URL of the SearXNG instance of the suite, from the example
    /// of the SearXNG documentation.
    static let searxngBase = "https://searx.example.org"

    /// The first hit of `brave-api-results.json`, `serper-results.json`,
    /// `kagi-results.json`, and `searxng-results.json`: the Swift.org home
    /// page.
    private static let swiftOrgFirstHit = WebHit(
        rank: 1, title: "Swift.org - Welcome to Swift.org", url: "https://www.swift.org/",
        snippet: "Swift is a general-purpose programming language that's approachable for newcomers "
            + "and powerful for experts.")

    /// The adapter under test.
    let adapter: any SearchProviderAdapter

    /// The name of the provider case in `WebSearchProvider`.
    let name: String

    /// The documented HTTP method.
    let method: String

    /// The documented URL, with no query.
    let endpoint: String

    /// The documented header that holds the key.
    let keyHeader: String

    /// The text before the key in ``keyHeader``, for example `Bearer `.
    let keyPrefix: String

    /// The query fields that the adapter must declare.
    let supports: Set<SearchFeature>

    /// The name of the recorded response in ``goldensFolder``, with no
    /// extension.
    let golden: String

    /// The number of hits that the recorded response gives.
    let goldenHitCount: Int

    /// The first hit of the recorded response.
    let firstHit: WebHit

    /// Writes a response body that holds the results, in the JSON form of
    /// the provider.
    let responseBody: @Sendable ([FixtureResult]) -> String

    /// `true` when the adapter must declare its request URL as host
    /// configuration. The default is `false`.
    var isHostConfiguration = false

    /// The name of the provider, which the test output shows.
    var testDescription: String { name }

    /// The providers that send a key, in the order of the provider table.
    static let keyed: [KeyedProviderCase] = [braveAPI, tavily, exa, serper, kagi]

    /// Each provider of the suite: the keyed providers, then `searxng`, which
    /// sends no key.
    static let all: [KeyedProviderCase] = keyed + [searxng]

    /// The row of `braveAPI`.
    static let braveAPI = KeyedProviderCase(
        adapter: BraveAPIProvider(),
        name: WebSearchProvider.braveAPI(.literal(fakeKey)).name,
        method: "GET",
        endpoint: "https://api.search.brave.com/res/v1/web/search",
        keyHeader: "X-Subscription-Token",
        keyPrefix: "",
        supports: [.freshness, .site, .count],
        golden: "brave-api-results",
        goldenHitCount: braveGoldenHitCount,
        firstHit: swiftOrgFirstHit,
        responseBody: { results in
            let items = results.map { result in
                "{\"title\": \(json(result.title)), \"url\": \(json(result.url)), "
                    + "\"description\": \(json(result.snippet))}"
            }
            return "{\"type\": \"search\", \"web\": {\"type\": \"search\", \"results\": ["
                + items.joined(separator: ", ") + "]}}"
        })

    /// The row of `tavily`.
    static let tavily = KeyedProviderCase(
        adapter: TavilyProvider(),
        name: WebSearchProvider.tavily(.literal(fakeKey)).name,
        method: "POST",
        endpoint: "https://api.tavily.com/search",
        keyHeader: "Authorization",
        keyPrefix: "Bearer ",
        supports: [.freshness, .site, .count],
        golden: "tavily-results",
        goldenHitCount: tavilyGoldenHitCount,
        firstHit: WebHit(
            rank: 1,
            title: "Welcome to Swift.org",
            url: "https://www.swift.org/",
            snippet: "Swift is a general-purpose programming language that's approachable for newcomers "
                + "and powerful for experts. It is fast, modern, safe, and a joy to write."),
        responseBody: { results in
            let items = results.map { result in
                "{\"title\": \(json(result.title)), \"url\": \(json(result.url)), "
                    + "\"content\": \(json(result.snippet)), \"score\": 0.5}"
            }
            return "{\"query\": \"q\", \"results\": [" + items.joined(separator: ", ") + "]}"
        })

    /// The row of `exa`.
    static let exa = KeyedProviderCase(
        adapter: ExaProvider(),
        name: WebSearchProvider.exa(.literal(fakeKey)).name,
        method: "POST",
        endpoint: "https://api.exa.ai/search",
        keyHeader: "x-api-key",
        keyPrefix: "",
        supports: [.freshness, .site, .count],
        golden: "exa-results",
        goldenHitCount: exaGoldenHitCount,
        firstHit: WebHit(
            rank: 1,
            title: "Swift.org - Welcome to Swift.org",
            url: "https://www.swift.org/",
            snippet: "Swift is a general-purpose programming language that's approachable for newcomers "
                + "and powerful for experts. It is fast, modern, safe, and a joy to write."),
        responseBody: { results in
            let items = results.map { result in
                "{\"title\": \(json(result.title)), \"url\": \(json(result.url)), "
                    + "\"highlights\": [\(json(result.snippet))]}"
            }
            return "{\"requestId\": \"r\", \"results\": [" + items.joined(separator: ", ") + "]}"
        })

    /// The row of `serper`.
    static let serper = KeyedProviderCase(
        adapter: SerperProvider(),
        name: WebSearchProvider.serper(.literal(fakeKey)).name,
        method: "POST",
        endpoint: "https://google.serper.dev/search",
        keyHeader: "X-API-KEY",
        keyPrefix: "",
        supports: [.freshness, .site, .count],
        golden: "serper-results",
        goldenHitCount: serperGoldenHitCount,
        firstHit: swiftOrgFirstHit,
        responseBody: { results in
            let items = results.enumerated().map { index, result in
                "{\"title\": \(json(result.title)), \"link\": \(json(result.url)), "
                    + "\"snippet\": \(json(result.snippet)), \"position\": \(index + 1)}"
            }
            return "{\"searchParameters\": {\"q\": \"q\"}, \"organic\": [" + items.joined(separator: ", ") + "]}"
        })

    /// The row of `kagi`.
    static let kagi = KeyedProviderCase(
        adapter: KagiProvider(),
        name: WebSearchProvider.kagi(.literal(fakeKey)).name,
        method: "POST",
        endpoint: "https://kagi.com/api/v1/search",
        keyHeader: "Authorization",
        keyPrefix: "Bearer ",
        supports: [.freshness, .site, .count],
        golden: "kagi-results",
        goldenHitCount: kagiGoldenHitCount,
        firstHit: swiftOrgFirstHit,
        responseBody: { results in
            let items = results.map { result in
                "{\"url\": \(json(result.url)), \"title\": \(json(result.title)), "
                    + "\"snippet\": \(json(result.snippet))}"
            }
            return "{\"meta\": {\"trace\": \"t\"}, \"data\": {\"search\": [" + items.joined(separator: ", ") + "]}}"
        })

    /// The row of `searxng`. SearXNG takes no key, thus the key fields are
    /// empty, and the row is not in ``keyed``.
    static let searxng = KeyedProviderCase(
        adapter: SearXNGProvider(base: searxngBaseURL),
        name: WebSearchProvider.searxng(searxngBaseURL).name,
        method: "GET",
        endpoint: searxngBase + "/search",
        keyHeader: "",
        keyPrefix: "",
        supports: [.freshness, .site, .count],
        golden: "searxng-results",
        goldenHitCount: searxngGoldenHitCount,
        firstHit: swiftOrgFirstHit,
        responseBody: { results in
            let items = results.map { result in
                "{\"url\": \(json(result.url)), \"title\": \(json(result.title)), "
                    + "\"content\": \(json(result.snippet)), \"engine\": \"e\"}"
            }
            return "{\"query\": \"q\", \"results\": [" + items.joined(separator: ", ") + "], \"answers\": []}"
        },
        isHostConfiguration: true)

    /// The URL of ``searxngBase``. The text is a literal URL, thus the
    /// fallback does not occur. If it occurs, the `file:` URL makes each
    /// request test of the `searxng` row fail.
    private static var searxngBaseURL: URL {
        URL(string: searxngBase) ?? URL(filePath: "/")
    }

    /// The bytes of the recorded response of this provider.
    ///
    /// - Returns: The UTF-8 bytes of the JSON file.
    /// - Throws: When the test bundle does not hold the file.
    func recordedResponse() throws -> Data {
        try Data(contentsOf: TestResource.bundledURL(
            named: golden, withExtension: TestResource.jsonExtension, in: Self.goldensFolder))
    }

    /// A response of the documented endpoint with a status.
    ///
    /// - Parameter status: The HTTP status.
    /// - Returns: The response.
    /// - Throws: When Foundation cannot make the response.
    func response(status: Int) throws -> HTTPURLResponse {
        let url = try #require(URL(string: endpoint))
        return try #require(
            HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
    }

    /// Reads the hits of a body with the adapter under test.
    ///
    /// - Parameters:
    ///   - data: The body.
    ///   - status: The HTTP status. The default is 200.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits.
    /// - Throws: The failure of the parse, or an error when the response
    ///   cannot be made.
    func parse(_ data: Data, status: Int = WebStub.okStatus, limit: Int? = nil) throws -> [WebHit] {
        try adapter.parse(data, response: response(status: status), limit: limit)
    }

    /// Writes a text as a JSON string literal, with its quotes.
    ///
    /// - Parameter text: The text.
    /// - Returns: The JSON string literal.
    private static func json(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? "\"\""
    }
}
