import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the cooldown of a provider after HTTP 429: the time of the
/// cooldown from the `Retry-After` header, the skip of a provider in its
/// cooldown, and the end of the cooldown.
///
/// Each chain gets a ``ManualClock``. Its time moves only when the test calls
/// `sleep`, and that call does not wait in real time. A `WebStub` answers each
/// request, thus no test uses the network.
@Suite("ProviderCooldown")
struct ProviderCooldownTests {
    /// The status of a rate limit.
    private static let rateLimitStatus = 429

    /// The time of a cooldown when the response has no `Retry-After` header.
    private static let defaultCooldown = Duration.seconds(60)

    /// The longest cooldown, also for a longer `Retry-After` time.
    private static let maximumCooldown = Duration.seconds(600)

    /// A `Retry-After` value in seconds, below the maximum.
    private static let shortRetrySeconds = 5

    /// A `Retry-After` value in seconds, above the maximum.
    private static let longRetrySeconds = 86_400

    /// A time that is shorter than the short `Retry-After` time by one second.
    private static let oneSecondBeforeShortEnd = Duration.seconds(4)

    /// A time that moves the clock past the end of the short cooldown.
    private static let pastShortEnd = Duration.seconds(6)

    /// The `Retry-After` header name.
    private static let retryAfterHeader = "Retry-After"

    /// An HTTP date in the IMF-fixdate form.
    private static let httpDate = "Wed, 21 Oct 2015 07:28:00 GMT"

    /// The time of ``httpDate`` as seconds after 1970-01-01 00:00:00 UTC.
    private static let httpDateEpochSeconds: TimeInterval = 1_445_412_480

    /// The number of seconds between the time of the call and ``httpDate``
    /// in the HTTP date test.
    private static let secondsBeforeHTTPDate = 90

    /// The URL of the endpoint of the fake provider `name`.
    ///
    /// - Parameter name: The name of the provider.
    /// - Returns: The URL text.
    private static func endpoint(_ name: String) -> String {
        "https://\(name.lowercased()).example/search"
    }

    /// The URL of a URL text.
    ///
    /// - Parameter text: The absolute URL text.
    /// - Returns: The URL.
    /// - Throws: When `text` is not a URL.
    private static func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    /// A provider with a fake adapter whose endpoint is ``endpoint(_:)`` of
    /// its name.
    ///
    /// - Parameters:
    ///   - provider: The provider.
    ///   - name: The name of the provider.
    /// - Returns: The provider and its adapter.
    /// - Throws: When the endpoint is not a URL.
    private static func fake(
        _ provider: WebSearchProvider, _ name: String
    ) throws -> (WebSearchProvider, any SearchProviderAdapter) {
        try (provider, FakeSearchAdapter(name: name, endpoint: url(endpoint(name))))
    }

    /// The two providers of the tests: `braveHTML` first, then
    /// `duckDuckGoHTML`.
    ///
    /// - Returns: The providers and their adapters.
    /// - Throws: When an endpoint is not a URL.
    private static func providers() throws -> [(WebSearchProvider, any SearchProviderAdapter)] {
        try [fake(.braveHTML, "braveHTML"), fake(.duckDuckGoHTML, "duckDuckGoHTML")]
    }

    /// A `200` reply with one hit in the line format of ``FakeSearchAdapter``.
    private static let hitsReply = WebStubReply.respond(
        status: WebStub.okStatus, headers: ["Content-Type": "text/plain"],
        body: Data("Result\thttps://result.example/1".utf8))

    /// A `429` reply.
    ///
    /// - Parameter retryAfter: The value of the `Retry-After` header, or
    ///   `nil` for a reply with no such header.
    /// - Returns: The reply.
    private static func rateLimitReply(retryAfter: String? = nil) -> WebStubReply {
        var headers = ["Content-Type": "text/plain"]
        headers[retryAfterHeader] = retryAfter
        return .respond(status: rateLimitStatus, headers: headers, body: Data("slow down".utf8))
    }

    /// The number of requests that `stub` got for the provider `name`.
    ///
    /// - Parameters:
    ///   - stub: The stub.
    ///   - name: The name of the provider.
    /// - Returns: The count.
    private static func requestCount(_ stub: WebStub, _ name: String) -> Int {
        stub.requestedURLs.filter { $0 == endpoint(name) }.count
    }

    /// Makes a chain over ``providers()`` with `clock`.
    ///
    /// - Parameters:
    ///   - stub: The stub that answers each request.
    ///   - clock: The clock of the cooldowns.
    /// - Returns: The chain.
    /// - Throws: When an endpoint is not a URL.
    private static func chain(_ stub: WebStub, clock: ManualClock) throws -> WebSearchChain {
        try WebSearchChain(providers: providers(), fetcher: stub.makeFetcher(), environment: [:], clock: clock)
    }

    // MARK: - The skip

    @Test("HTTP 429 with no Retry-After starts a 60 second cooldown, and the next search skips the provider")
    func rateLimitWithoutRetryAfterStartsDefaultCooldown() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveHTML"): Self.rateLimitReply(), Self.endpoint("duckDuckGoHTML"): Self.hitsReply
        ])
        let chain = try Self.chain(stub, clock: ManualClock())
        _ = await chain.search(SearchQuery(text: "swift"))
        let outcome = await chain.search(SearchQuery(text: "swift"))
        #expect(outcome.hitNotes == ["braveHTML: skipped, rate limited for 60 more seconds."])
        #expect(Self.requestCount(stub, "braveHTML") == 1)
        #expect(Self.requestCount(stub, "duckDuckGoHTML") == 2)
    }

    @Test("HTTP 429 with Retry-After: 5 starts a 5 second cooldown, and the provider gets a request after it")
    func cooldownEndsAfterRetryAfter() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveHTML"): Self.rateLimitReply(retryAfter: String(Self.shortRetrySeconds)),
            Self.endpoint("duckDuckGoHTML"): Self.hitsReply
        ])
        let clock = ManualClock()
        let chain = try Self.chain(stub, clock: clock)
        _ = await chain.search(SearchQuery(text: "swift"))
        try await clock.sleep(for: Self.oneSecondBeforeShortEnd)
        let during = await chain.search(SearchQuery(text: "swift"))
        #expect(during.hitNotes == ["braveHTML: skipped, rate limited for 1 more second."])
        #expect(Self.requestCount(stub, "braveHTML") == 1)
        try await clock.sleep(for: Self.pastShortEnd - Self.oneSecondBeforeShortEnd)
        let after = await chain.search(SearchQuery(text: "swift"))
        #expect(after.hitNotes == ["braveHTML: skipped, blocked (HTTP 429)."])
        #expect(Self.requestCount(stub, "braveHTML") == 2)
    }

    @Test("a cooldown skip is a block, thus the correction ends with the step to wait")
    func cooldownSkipGivesWaitStep() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveHTML"): Self.rateLimitReply(),
            Self.endpoint("duckDuckGoHTML"): .respond(
                status: WebStub.okStatus, headers: ["Content-Type": "text/plain"],
                body: Data(FakeSearchAdapter.challengeMarker.utf8))
        ])
        let chain = try Self.chain(stub, clock: ManualClock())
        _ = await chain.search(SearchQuery(text: "swift"))
        let outcome = await chain.search(SearchQuery(text: "swift"))
        let expected = [
            WebSearchChain.correctionLead, "braveHTML: rate limited for 60 more seconds.",
            "duckDuckGoHTML: blocked by a challenge page.", WebSearchChain.correctionWaitStep
        ].joined(separator: " ")
        #expect(outcome == .correction(expected))
        #expect(Self.requestCount(stub, "braveHTML") == 1)
    }

    // MARK: - The time of a cooldown

    @Test("no Retry-After gives the default cooldown of 60 seconds")
    func missingRetryAfterGivesDefault() {
        #expect(ProviderCooldowns.cooldown(forRetryAfter: nil, at: Date()) == Self.defaultCooldown)
    }

    @Test("Retry-After as a number of seconds gives that time")
    func secondsRetryAfterGivesThatTime() {
        let cooldown = ProviderCooldowns.cooldown(forRetryAfter: " \(Self.shortRetrySeconds) ", at: Date())
        #expect(cooldown == .seconds(Self.shortRetrySeconds))
    }

    @Test("Retry-After as an HTTP date gives the time from now to that date")
    func httpDateRetryAfterIsParsed() {
        let date = Date(timeIntervalSince1970: Self.httpDateEpochSeconds)
        let now = date.addingTimeInterval(-TimeInterval(Self.secondsBeforeHTTPDate))
        let cooldown = ProviderCooldowns.cooldown(forRetryAfter: Self.httpDate, at: now)
        #expect(cooldown == .seconds(Self.secondsBeforeHTTPDate))
    }

    @Test("Retry-After as an HTTP date in the past gives no cooldown")
    func pastHTTPDateGivesNoCooldown() {
        let after = Date(timeIntervalSince1970: Self.httpDateEpochSeconds + TimeInterval(Self.secondsBeforeHTTPDate))
        #expect(ProviderCooldowns.cooldown(forRetryAfter: Self.httpDate, at: after) == .zero)
    }

    @Test("a Retry-After time above the cap gives the cap of 10 minutes")
    func longRetryAfterIsCapped() {
        let cooldown = ProviderCooldowns.cooldown(forRetryAfter: String(Self.longRetrySeconds), at: Date())
        #expect(cooldown == Self.maximumCooldown)
    }

    @Test("a Retry-After value that is not a number and not an HTTP date gives the default cooldown")
    func unreadableRetryAfterGivesDefault() {
        #expect(ProviderCooldowns.cooldown(forRetryAfter: "soon", at: Date()) == Self.defaultCooldown)
    }
}
