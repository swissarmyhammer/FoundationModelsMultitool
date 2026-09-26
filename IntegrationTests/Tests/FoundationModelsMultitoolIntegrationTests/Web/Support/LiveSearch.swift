// `LiveSearch` — the shared setup of the live search suites: one real web
// context with short timeouts, the call of the `search` verb, and the stable
// facts that the suites assert (web.md § "Testing", Level 2).
//
// The context uses the real session and the real resolver of the address
// guard, thus each request goes to the real provider. The search goes through
// `WebVerbCall.search` of `MultitoolTestSupport`, the call that the unit
// suites make too. A test asserts only facts that are stable for years: a
// well-known host in the hits, the `https` scheme, and the host that `site`
// asks for. It asserts no rank, no snippet, and no count of more than 3. A
// test does not retry.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The shared setup and the shared checks of the live search suites.
enum LiveSearch {
    /// The time limit of each live test, in minutes.
    ///
    /// One live search sends one request to each provider that it tries.
    /// With ``searchTimeoutSeconds`` for each provider, one minute is more
    /// than enough time. A live fetch has ``resourceTimeoutSeconds`` for each
    /// request, thus the fetch suites and the `runCode` suite use the same
    /// limit. A test that reaches the limit is parked, not slow.
    static let timeLimitMinutes = 1

    /// The query of each live search test.
    static let swiftQuery = "swift programming language"

    /// The host of the home page of the Swift programming language.
    static let swiftHost = "swift.org"

    /// The host that the `site` test gives to the search.
    static let appleDeveloperSite = "developer.apple.com"

    /// The domain that each hit of the `site` test must be under.
    static let appleDomain = "apple.com"

    /// The smallest number of hits that a live search must give.
    ///
    /// The assertion rule of web.md permits no count of more than 3.
    static let minimumHitCount = 3

    /// The URL scheme of each hit.
    static let secureScheme = "https"

    /// How many seconds one search provider can take before the chain goes to
    /// the next provider.
    static let searchTimeoutSeconds: TimeInterval = 10

    /// How many seconds one request can wait for more data before it fails.
    static let requestTimeoutSeconds: TimeInterval = 10

    /// How many seconds one request can take from start to end.
    static let resourceTimeoutSeconds: TimeInterval = 15

    // MARK: The search

    /// Sends one live search, with the real session and the real resolver.
    ///
    /// - Parameters:
    ///   - providers: The providers, in the order to try.
    ///   - site: The one host of the hits, or `nil` for all hosts.
    /// - Returns: The result of the `search` verb for ``swiftQuery``.
    /// - Throws: When the verb throws. The verb must not throw.
    static func search(providers: [WebSearchProvider], site: String? = nil) async throws -> SearchResult {
        let configuration = WebConfiguration(
            providers: providers, fetch: WebFetchPolicy(searchTimeout: searchTimeoutSeconds))
        let context = WebContext(
            configuration: configuration, sessionConfiguration: makeSessionConfiguration())
        return try await WebVerbCall.search(swiftQuery, site: site, context: context)
    }

    /// Makes the configuration of the one session of a live context, with
    /// ``requestTimeoutSeconds`` and ``resourceTimeoutSeconds``.
    ///
    /// `ShortTimeoutSession` of `MultitoolTestSupport` makes the
    /// configuration. This function gives it only the timeouts of the `Web/`
    /// suites. The live fetch suites and the live `runCode` suite also use
    /// it, thus each live request of the `Web/` suites has the same short
    /// timeouts.
    ///
    /// - Returns: The configuration.
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        ShortTimeoutSession.makeConfiguration(
            requestTimeout: requestTimeoutSeconds, resourceTimeout: resourceTimeoutSeconds)
    }

    // MARK: The shared tests

    /// The query test of one provider list: ``swiftQuery`` gives at least
    /// ``minimumHitCount`` hits, each hit URL is `https`, and a hit host is
    /// ``swiftHost`` or is under it. A correction records one failure, and
    /// the checks of the hits do not run.
    ///
    /// - Parameters:
    ///   - providers: The providers, in the order to try.
    ///   - sourceLocation: The location of the call, for the failure record.
    /// - Throws: When the verb throws. The verb must not throw.
    static func expectSwiftHomePageHit(
        providers: [WebSearchProvider], sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let result = try await search(providers: providers)
        guard hasHits(result, sourceLocation: sourceLocation) else { return }
        #expect(
            result.results.count >= minimumHitCount,
            "expected at least \(minimumHitCount) hits, got \(result.results.map(\.url))",
            sourceLocation: sourceLocation)
        for hit in result.results {
            #expect(
                URL(string: hit.url)?.scheme?.lowercased() == secureScheme,
                "the hit URL \(hit.url) is not \(secureScheme)", sourceLocation: sourceLocation)
        }
        let hosts = hosts(of: result)
        #expect(
            hosts.contains { isHost($0, under: swiftHost) },
            "expected a hit on \(swiftHost), got the hosts \(hosts)", sourceLocation: sourceLocation)
    }

    /// The `site` test of one provider list: ``swiftQuery`` with the site
    /// ``appleDeveloperSite`` gives hits, and each hit host is under
    /// ``appleDomain``. A correction records one failure, and the checks of
    /// the hits do not run.
    ///
    /// - Parameters:
    ///   - providers: The providers, in the order to try.
    ///   - sourceLocation: The location of the call, for the failure record.
    /// - Throws: When the search gives no hit, or when the verb throws.
    static func expectHitsOnAppleSite(
        providers: [WebSearchProvider], sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let result = try await search(providers: providers, site: appleDeveloperSite)
        guard hasHits(result, sourceLocation: sourceLocation) else { return }
        try #require(!result.results.isEmpty, "the site search gave no hit", sourceLocation: sourceLocation)
        for host in hosts(of: result) {
            #expect(
                isHost(host, under: appleDomain),
                "the hit host \(host) is not under \(appleDomain)", sourceLocation: sourceLocation)
        }
    }

    // MARK: The checks

    /// Records a failure when the result is a correction, with the text of
    /// the correction.
    ///
    /// - Parameters:
    ///   - result: The result of the `search` verb.
    ///   - sourceLocation: The location of the call, for the failure record.
    static func expectNoCorrection(
        _ result: SearchResult, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            result.correction == nil, correctionComment(result.correction ?? ""),
            sourceLocation: sourceLocation)
    }

    /// Tells if a result has hits to check, and records one failure when the
    /// result is a correction.
    ///
    /// A correction has no hits, thus the caller does not run the checks of
    /// the hits for it. The one failure has the comment
    /// ``correctionComment(_:)``, thus a suite can find a known correction by
    /// its exact text.
    ///
    /// - Parameters:
    ///   - result: The result of the `search` verb.
    ///   - sourceLocation: The location of the call, for the failure record.
    /// - Returns: `true` when the result is not a correction, thus the caller
    ///   runs the checks of the hits. `false` when the result is a correction.
    static func hasHits(_ result: SearchResult, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        guard let correction = result.correction else { return true }
        Issue.record(correctionComment(correction), sourceLocation: sourceLocation)
        return false
    }

    /// The comment of the failure that a correction records.
    ///
    /// - Parameter correction: The text of the correction.
    /// - Returns: The comment, with the text of the correction at the end.
    static func correctionComment(_ correction: String) -> Comment {
        Comment(rawValue: "the search gave a correction: \(correction)")
    }

    /// The hosts of the hits of a result, in rank order.
    ///
    /// - Parameter result: The result of the `search` verb.
    /// - Returns: The host of each hit, in lower case. A hit URL with no host
    ///   gives an empty text, thus no host check accepts it.
    private static func hosts(of result: SearchResult) -> [String] {
        result.results.map { hit in URL(string: hit.url)?.host()?.lowercased() ?? "" }
    }

    /// Tells if a host is a domain or is under it.
    ///
    /// - Parameters:
    ///   - host: The host, in lower case.
    ///   - domain: The domain, for example `swift.org`.
    /// - Returns: `true` when the host is the domain, or ends in `.` and the
    ///   domain. Thus `www.swift.org` is under `swift.org`, and
    ///   `notswift.org` is not.
    private static func isHost(_ host: String, under domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
