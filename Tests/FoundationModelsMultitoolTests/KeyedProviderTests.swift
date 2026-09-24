import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the keyed search providers: the request shape, the key place, the
/// parse of the recorded response, and the error map.
///
/// One parameterized suite runs each test over each row of
/// ``KeyedProviderCase/all``. Each test calls `request` or `parse` directly
/// with fixture bytes, thus no test uses the network or a real key.
@Suite("KeyedProviders")
struct KeyedProviderTests {
    /// The query of the request tests.
    private static let query = SearchQuery(text: "swift programming language")

    /// The `Accept` header of each request.
    private static let acceptHeader = "Accept"

    /// The media type of a JSON body.
    private static let jsonMediaType = "application/json"

    /// The limit in the limit test. It is less than each recorded hit count.
    private static let limitedCount = 2

    /// A documented error status and the failure that it maps to.
    private static let statusFailures: [(status: Int, failure: ProviderFailure)] = [
        (401, .badKey), (403, .badKey), (429, .rateLimited), (500, .serverError(500)), (503, .serverError(503))
    ]

    /// A status that the error map does not name: a payment or plan limit.
    private static let unmappedErrorStatus = 402

    /// A result with a web URL and a title.
    private static let goodResult = FixtureResult(
        title: "Good", url: "https://good.example/page", snippet: "A good result.")

    /// Makes the request of ``query`` with ``KeyedProviderCase/fakeKey``.
    ///
    /// - Parameter provider: The row under test.
    /// - Returns: The request.
    /// - Throws: When the adapter cannot make the request.
    private static func request(of provider: KeyedProviderCase) throws -> URLRequest {
        try provider.adapter.request(for: query, key: KeyedProviderCase.fakeKey)
    }

    // MARK: - The request

    @Test("the request has the documented method, URL, and key header", arguments: KeyedProviderCase.all)
    func requestShape(provider: KeyedProviderCase) throws {
        let request = try Self.request(of: provider)
        let url = try #require(request.url)
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.query = nil
        #expect(request.httpMethod == provider.method)
        #expect(components.string == provider.endpoint)
        #expect(
            request.value(forHTTPHeaderField: provider.keyHeader) == provider.keyPrefix + KeyedProviderCase.fakeKey)
        #expect(request.value(forHTTPHeaderField: Self.acceptHeader) == Self.jsonMediaType)
    }

    @Test("the key is in the key header and in no other part of the request", arguments: KeyedProviderCase.all)
    func keyOnlyInHeader(provider: KeyedProviderCase) throws {
        let request = try Self.request(of: provider)
        let key = KeyedProviderCase.fakeKey
        #expect(request.url?.absoluteString.contains(key) == false)
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!body.contains(key))
        let headersWithKey = (request.allHTTPHeaderFields ?? [:]).filter { $0.value.contains(key) }.map(\.key)
        #expect(headersWithKey == [provider.keyHeader])
    }

    @Test("a request with no key is refused", arguments: KeyedProviderCase.all)
    func requestNeedsKey(provider: KeyedProviderCase) {
        #expect(throws: (any Error).self) { try provider.adapter.request(for: Self.query, key: nil) }
    }

    @Test("the adapter has the provider name and declares the fields it sends", arguments: KeyedProviderCase.all)
    func nameAndSupports(provider: KeyedProviderCase) {
        #expect(provider.adapter.name == provider.name)
        #expect(provider.adapter.supports == provider.supports)
        #expect(!provider.adapter.isHostConfiguration)
    }

    // MARK: - The recorded response

    @Test("the recorded response gives hits with https URLs and titles", arguments: KeyedProviderCase.all)
    func recordedResponseParses(provider: KeyedProviderCase) throws {
        let hits = try provider.parse(provider.recordedResponse())
        #expect(hits.count == provider.goldenHitCount)
        #expect(hits.map(\.rank) == Array(1...provider.goldenHitCount))
        #expect(hits.allSatisfy { $0.url.hasPrefix("https://") })
        #expect(hits.allSatisfy { !$0.title.isEmpty })
        #expect(hits.first == provider.firstHit)
    }

    @Test("the parse stops at the limit", arguments: KeyedProviderCase.all)
    func parseStopsAtLimit(provider: KeyedProviderCase) throws {
        let hits = try provider.parse(provider.recordedResponse(), limit: Self.limitedCount)
        #expect(hits.map(\.rank) == Array(1...Self.limitedCount))
    }

    @Test("a result with no web URL or no title is skipped", arguments: KeyedProviderCase.all)
    func unusableResultsAreSkipped(provider: KeyedProviderCase) throws {
        let body = provider.responseBody([
            FixtureResult(title: "Not web", url: "ftp://files.example/file", snippet: ""),
            FixtureResult(title: "", url: "https://untitled.example/", snippet: ""),
            FixtureResult(title: "No host", url: "https:///path", snippet: ""),
            Self.goodResult
        ])
        let hits = try provider.parse(Data(body.utf8))
        let expected = WebHit(
            rank: 1, title: Self.goodResult.title, url: Self.goodResult.url, snippet: Self.goodResult.snippet)
        #expect(hits == [expected])
    }

    // MARK: - Failures

    @Test(
        "each documented error status maps to its failure",
        arguments: KeyedProviderCase.all, statusFailures.indices)
    func errorStatusMaps(provider: KeyedProviderCase, index: Int) throws {
        let (status, failure) = Self.statusFailures[index]
        let body = try provider.recordedResponse()
        #expect(throws: failure) { try provider.parse(body, status: status) }
    }

    @Test("an error status that the map does not name is a parse failure", arguments: KeyedProviderCase.all)
    func unmappedStatusIsParseFailure(provider: KeyedProviderCase) throws {
        let body = Data("{\"error\": \"credits are exhausted\"}".utf8)
        let failure = try #require(throws: ProviderFailure.self) {
            try provider.parse(body, status: Self.unmappedErrorStatus)
        }
        #expect(failure == .parse("the service answered HTTP \(Self.unmappedErrorStatus)"))
    }

    @Test("an empty result list gives .noResults", arguments: KeyedProviderCase.all)
    func emptyListIsNoResults(provider: KeyedProviderCase) {
        let body = Data(provider.responseBody([]).utf8)
        #expect(throws: ProviderFailure.noResults) { try provider.parse(body) }
    }

    @Test("a body that is not JSON gives .parse", arguments: KeyedProviderCase.all)
    func unreadableBodyIsParseFailure(provider: KeyedProviderCase) throws {
        let failure = try #require(throws: ProviderFailure.self) {
            try provider.parse(Data("<html>not json</html>".utf8))
        }
        let isParseFailure = if case .parse = failure { true } else { false }
        #expect(isParseFailure, "expected .parse, got \(failure)")
    }
}
