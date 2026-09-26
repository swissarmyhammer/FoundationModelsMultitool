// `LiveFetch` — the shared setup of the live fetch suites: one real web
// context with short timeouts, and the check that a fetch gave a page (web.md
// § "Testing", Level 2).
//
// The context uses the real session and the real resolver of the address
// guard, thus each request goes to the real page, and each guard check reads
// the real DNS answer. Each suite calls the `fetch` verb through
// `WebVerbCall.fetch` of `MultitoolTestSupport`, the call that the unit suites
// make too. A test asserts only facts that are stable for years: a known
// title, a known redirect, a known media type. A test does not retry.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The shared setup and the shared checks of the live fetch suites.
enum LiveFetch {
    /// Makes one live web context, with the real resolver and the short
    /// timeouts of ``LiveSearch/makeSessionConfiguration()``.
    ///
    /// The configuration is `.keyless`, which reads no environment. The fetch
    /// verb uses no search provider, thus the provider list has no effect on
    /// a fetch. A test that reads two windows of one page makes one context
    /// and gives it to both calls, thus both calls share one page cache.
    ///
    /// - Returns: The context.
    static func makeContext() -> WebContext {
        WebContext(configuration: .keyless, sessionConfiguration: LiveSearch.makeSessionConfiguration())
    }

    /// Stops the test when the result is a correction, with the text of the
    /// correction.
    ///
    /// A correction has no page, thus the checks of the page cannot run for
    /// it.
    ///
    /// - Parameters:
    ///   - result: The result of the `fetch` verb.
    ///   - sourceLocation: The location of the call, for the failure record.
    /// - Throws: When the result is a correction.
    static func requireNoCorrection(
        _ result: FetchResult, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try #require(
            result.correction == nil, "the fetch of \(result.url) gave a correction: \(result.correction ?? "")",
            sourceLocation: sourceLocation)
    }
}
