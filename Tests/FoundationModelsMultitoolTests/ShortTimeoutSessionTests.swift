// `ShortTimeoutSessionTests` — the one session configuration with short
// timeouts that the live web suites of `IntegrationTests/` use.
//
// The live suites cannot prove the timeouts, because the real web answers in
// time on most runs. This suite proves them without the network: each test
// makes a configuration and reads its values.

import Foundation
import Testing

@testable import MultitoolTestSupport

/// The configuration that `ShortTimeoutSession.makeConfiguration` makes.
@Suite("ShortTimeoutSessionTests")
struct ShortTimeoutSessionTests {
    /// The request timeout that each test gives, in seconds.
    private static let requestTimeoutSeconds: TimeInterval = 7

    /// The resource timeout that each test gives, in seconds. It is not
    /// equal to ``requestTimeoutSeconds``, thus a swap of the two fails.
    private static let resourceTimeoutSeconds: TimeInterval = 11

    @Test("the configuration has the request timeout that the caller gives")
    func requestTimeoutIsTheGivenValue() {
        let configuration = ShortTimeoutSession.makeConfiguration(
            requestTimeout: Self.requestTimeoutSeconds, resourceTimeout: Self.resourceTimeoutSeconds)
        #expect(configuration.timeoutIntervalForRequest == Self.requestTimeoutSeconds)
    }

    @Test("the configuration has the resource timeout that the caller gives")
    func resourceTimeoutIsTheGivenValue() {
        let configuration = ShortTimeoutSession.makeConfiguration(
            requestTimeout: Self.requestTimeoutSeconds, resourceTimeout: Self.resourceTimeoutSeconds)
        #expect(configuration.timeoutIntervalForResource == Self.resourceTimeoutSeconds)
    }

    @Test("each call gives a new configuration, thus one caller cannot change the values of another")
    func eachCallGivesANewConfiguration() {
        let first = ShortTimeoutSession.makeConfiguration(
            requestTimeout: Self.requestTimeoutSeconds, resourceTimeout: Self.resourceTimeoutSeconds)
        let second = ShortTimeoutSession.makeConfiguration(
            requestTimeout: Self.requestTimeoutSeconds, resourceTimeout: Self.resourceTimeoutSeconds)
        #expect(first !== second)
    }
}
