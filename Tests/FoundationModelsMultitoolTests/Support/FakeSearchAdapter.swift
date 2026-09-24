// `FakeSearchAdapter` — a search adapter for the tests of `WebSearchChain`.
//
// The adapter reads a small line format, not the page of a real provider.
// Thus a test controls each failure kind of a provider with the body and the
// status of one `WebStub` reply.

import Foundation
@testable import FoundationModelsMultitool

/// A search adapter for the chain tests. It reads a small line format.
///
/// Each line of a body is one hit: the title, a tab, and the URL. An empty
/// body is `.noResults`. A body that is ``challengeMarker`` is `.challenge`.
/// A line with no tab is `.parse`, and the failure text holds the line. Thus
/// a body that echoes the key gives a failure text that holds the key.
struct FakeSearchAdapter: SearchProviderAdapter {
    /// The request header that holds the key, when the chain gives one.
    static let keyHeader = "X-Fake-Key"

    /// The body of a challenge page.
    static let challengeMarker = "CHALLENGE"

    /// The number of parts in one line of a hit: the title and the URL.
    private static let partsPerLine = 2

    /// The error of `request` when the adapter has no endpoint.
    struct MissingEndpoint: Error, CustomStringConvertible {
        /// The text of the error.
        var description: String { "the fake adapter has no endpoint" }
    }

    /// The name of the provider, for example `braveHTML`.
    let name: String

    /// The URL of each request, or `nil` to make `request` throw.
    let endpoint: URL?

    /// The query fields that the provider supports.
    let supports: Set<SearchFeature>

    /// `true` when the endpoint is host configuration.
    let isHostConfiguration: Bool

    /// Makes a fake adapter.
    ///
    /// - Parameters:
    ///   - name: The name of the provider.
    ///   - endpoint: The URL of each request, or `nil` to make `request`
    ///     throw.
    ///   - supports: The query fields that the provider supports.
    ///   - isHostConfiguration: `true` when the endpoint is host
    ///     configuration.
    init(name: String, endpoint: URL?, supports: Set<SearchFeature> = [], isHostConfiguration: Bool = false) {
        self.name = name
        self.endpoint = endpoint
        self.supports = supports
        self.isHostConfiguration = isHostConfiguration
    }

    /// Makes a `GET` request to ``endpoint``, with the key in ``keyHeader``.
    ///
    /// - Parameters:
    ///   - query: The query. The fake does not read it.
    ///   - key: The key value, or `nil` for a keyless provider.
    /// - Returns: The request.
    /// - Throws: ``MissingEndpoint`` when ``endpoint`` is `nil`.
    func request(for _: SearchQuery, key: String?) throws -> URLRequest {
        guard let endpoint else { throw MissingEndpoint() }
        var request = URLRequest(url: endpoint)
        request.setValue(key, forHTTPHeaderField: Self.keyHeader)
        return request
    }

    /// Reads the hits of a body in the line format.
    ///
    /// - Parameters:
    ///   - data: The body.
    ///   - response: The response. The fake does not read it.
    ///   - limit: The maximum number of hits, or `nil` for one hit for each
    ///     line.
    /// - Returns: One hit for each line up to `limit`, with rank 1 first.
    /// - Throws: `.challenge`, `.noResults`, or `.parse` as the type comment
    ///   states.
    func parse(_ data: Data, response _: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        guard let text = String(bytes: data, encoding: .utf8) else { throw .parse("the body is not UTF-8") }
        guard text != Self.challengeMarker else { throw .challenge }
        let lines = text.split(separator: "\n")
        guard !lines.isEmpty else { throw .noResults }
        return try lines.prefix(limit ?? lines.count).enumerated().map { index, line throws(ProviderFailure) in
            try Self.hit(from: line, rank: index + 1)
        }
    }

    /// Reads one line of a hit.
    ///
    /// - Parameters:
    ///   - line: The line: the title, a tab, and the URL.
    ///   - rank: The rank of the hit.
    /// - Returns: The hit, with an empty snippet.
    /// - Throws: `.parse` with the line when the line is not two parts.
    private static func hit(from line: Substring, rank: Int) throws(ProviderFailure) -> WebHit {
        let parts = line.split(separator: "\t")
        guard parts.count == partsPerLine, let title = parts.first, let url = parts.last else {
            throw .parse("bad line: \(line)")
        }
        return WebHit(rank: rank, title: String(title), url: String(url), snippet: "")
    }
}

extension SearchOutcome {
    /// The notes of a `.hits` outcome, or `nil` for a correction. A test
    /// unwraps it with `#require`.
    var hitNotes: [String]? {
        guard case .hits(_, _, let notes) = self else { return nil }
        return notes
    }

    /// The text of a `.correction` outcome, or `nil` for hits. A test
    /// unwraps it with `#require`.
    var correctionText: String? {
        guard case .correction(let text) = self else { return nil }
        return text
    }
}
