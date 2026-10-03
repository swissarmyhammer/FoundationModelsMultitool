// `FetchedPagesRule` — the check of the pages that the goal snippet of web.md
// fetched in `WebRunCodeLiveTests` (web.md § "Testing", the
// `WebRunCodeLiveTests` row).

import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The written check of the pages that the goal snippet fetched.
///
/// **The check (decided by the user, 2026-10-03, card `^4dfyx4q`).** The
/// search rank and the render method of a live search hit are not stable. A
/// page that JavaScript draws has its text only inside `<noscript>`, and
/// `fetch` gives empty content for it. Thus the check asserts only facts that
/// stay true:
///
/// - Each page has an absolute `http` or `https` URL and a title that is not
///   empty, and its fetch did not give a correction.
/// - At least one page has content.
///
/// A page with empty content passes with those checks: the fetch reached the
/// page, and the converter ran. A failed fetch, a page with no URL or no
/// title, or no page with content fails the test. The check sends no request,
/// and it does not retry.
enum FetchedPagesRule {
    /// Why the pages fail the check.
    enum Failure: Equatable {
        /// The fetch of the page gave this correction.
        case fetchFailed(url: String, correction: String)

        /// The URL of the page is not an absolute `http` or `https` URL with a
        /// host. The check is the URL rule of the `fetch` verb,
        /// `Fetch.httpURL(_:)`.
        case invalidURL(String)

        /// The page has no title, or an empty title.
        case noTitle(url: String)

        /// No page has content.
        case noPageWithContent
    }

    /// Gives each failure of the pages.
    ///
    /// - Parameter pages: The pages that the snippet returned.
    /// - Returns: One failure for each page that fails, in the order of the
    ///   pages, then ``Failure/noPageWithContent`` when no page has content.
    ///   Empty when the pages pass.
    static func failures(of pages: [WebPageHead]) -> [Failure] {
        let pageFailures = pages.compactMap(failure(of:))
        let hasContent = pages.contains { !$0.head.isEmpty }
        return hasContent ? pageFailures : pageFailures + [.noPageWithContent]
    }

    /// Records one issue for each failure of the pages.
    ///
    /// - Parameters:
    ///   - pages: The pages that the snippet returned.
    ///   - output: The rendered output of the snippet, for the failure
    ///     comment.
    ///   - sourceLocation: The location of the call, for the failure record.
    static func expectPages(
        _ pages: [WebPageHead], output: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for failure in failures(of: pages) {
            Issue.record("the pages fail the check (\(failure)): \(output)", sourceLocation: sourceLocation)
        }
    }

    /// Gives the failure of one page.
    ///
    /// A failed fetch has the requested URL and no title, thus the
    /// correction is the one failure that it reports.
    ///
    /// - Parameter page: One page that the snippet returned.
    /// - Returns: The first failure of the page, or `nil` when it passes.
    private static func failure(of page: WebPageHead) -> Failure? {
        if let correction = page.correction {
            return .fetchFailed(url: page.url, correction: correction)
        }
        guard Fetch.httpURL(page.url) != nil else { return .invalidURL(page.url) }
        guard page.title?.isEmpty == false else { return .noTitle(url: page.url) }
        return nil
    }
}
