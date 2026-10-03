import Testing

@testable import MultitoolTestSupport

/// The offline checks of ``FetchedPagesRule``: which pages of the goal
/// snippet are a pass, and which pages are a failure (card `^4dfyx4q`, web.md
/// § "Testing", the `WebRunCodeLiveTests` row).
///
/// Each check gives pages to the rule. No check sends a request. Thus each
/// check always runs, and it is fast.
@Suite("FetchedPagesRule: pages with a URL and a title, and one page with content, pass, and each other set fails")
struct FetchedPagesRuleTests {
    /// The URL of the page with content.
    private static let contentURL = "https://www.swift.org/documentation/"

    /// The URL of the page that JavaScript draws, whose content is empty.
    private static let scriptPageURL =
        "https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/"

    /// The correction of a fetch that failed.
    private static let fetchCorrection =
        "The request to https://docs.swift.org/ failed: The network connection was lost."

    /// A page with a URL, a title, and content.
    private static let pageWithContent = WebPageHead(
        url: contentURL, title: "Documentation | Swift.org", head: "Swift is a programming language.")

    /// A page with a URL and a title, and empty content, as `fetch` gives it
    /// for a page that JavaScript draws.
    private static let pageWithEmptyContent = WebPageHead(url: scriptPageURL, title: "Documentation", head: "")

    // MARK: The pass

    @Test("a page with content and a page with empty content pass")
    func pageWithContentAndEmptyPagePass() {
        let pages = [Self.pageWithContent, Self.pageWithEmptyContent]
        #expect(FetchedPagesRule.failures(of: pages).isEmpty)
    }

    // MARK: The failures

    @Test("pages with no content at all fail")
    func pagesWithNoContentFail() {
        #expect(FetchedPagesRule.failures(of: [Self.pageWithEmptyContent]) == [.noPageWithContent])
    }

    @Test("no page fails, because no page has content")
    func noPageFails() {
        #expect(FetchedPagesRule.failures(of: []) == [.noPageWithContent])
    }

    @Test("a page with no title fails")
    func pageWithNoTitleFails() {
        let untitled = WebPageHead(url: Self.scriptPageURL, title: nil, head: "")
        #expect(
            FetchedPagesRule.failures(of: [Self.pageWithContent, untitled]) == [.noTitle(url: Self.scriptPageURL)])
    }

    @Test("a page with an empty title fails")
    func pageWithEmptyTitleFails() {
        let untitled = WebPageHead(url: Self.scriptPageURL, title: "", head: "")
        #expect(
            FetchedPagesRule.failures(of: [Self.pageWithContent, untitled]) == [.noTitle(url: Self.scriptPageURL)])
    }

    @Test("a page with no URL fails")
    func pageWithNoURLFails() {
        let unaddressed = WebPageHead(url: "", title: "Documentation", head: "")
        #expect(FetchedPagesRule.failures(of: [Self.pageWithContent, unaddressed]) == [.invalidURL("")])
    }

    @Test("a page with a URL that is not an absolute http or https URL fails")
    func pageWithRelativeURLFails() {
        let relativeURL = "/documentation/"
        let unaddressed = WebPageHead(url: relativeURL, title: "Documentation", head: "")
        #expect(FetchedPagesRule.failures(of: [Self.pageWithContent, unaddressed]) == [.invalidURL(relativeURL)])
    }

    @Test("a failed fetch fails")
    func failedFetchFails() {
        let failed = WebPageHead(url: Self.scriptPageURL, title: nil, head: "", correction: Self.fetchCorrection)
        #expect(
            FetchedPagesRule.failures(of: [Self.pageWithContent, failed])
                == [.fetchFailed(url: Self.scriptPageURL, correction: Self.fetchCorrection)])
    }
}
