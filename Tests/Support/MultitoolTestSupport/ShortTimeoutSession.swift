// `ShortTimeoutSession` — the one session configuration with short timeouts,
// for the live web suites of `IntegrationTests/`.
//
// The live `Web/` suites and `WebResearchScenarioTests` each give the web
// capability a real `URLSession`. Each one needs the same configuration:
// `.ephemeral`, as the capability defaults to, with timeouts that stop a slow
// request early. This file makes that configuration one time. The timeout
// values are the only difference, thus each caller gives its own values.

import Foundation

/// The one configuration of a live web session with short timeouts.
enum ShortTimeoutSession {
    /// Makes the configuration of the one session of a live web context:
    /// `.ephemeral`, as the capability defaults to, with short timeouts.
    ///
    /// Each call makes a new configuration, thus a caller that changes its
    /// configuration does not change the configuration of another caller.
    ///
    /// - Parameters:
    ///   - requestTimeout: How many seconds one request can wait for more
    ///     data before it fails.
    ///   - resourceTimeout: How many seconds one request can take from start
    ///     to end.
    /// - Returns: The configuration.
    static func makeConfiguration(
        requestTimeout: TimeInterval, resourceTimeout: TimeInterval
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }
}
