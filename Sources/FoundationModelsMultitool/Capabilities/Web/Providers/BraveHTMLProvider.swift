// `BraveHTMLProvider` — the first keyless search provider (web.md § "What we
// copy" and § "The provider list").
//
// The provider sends the query to the Brave results page with the headers of
// a desktop browser, as `swissarmyhammer` does (`brave.rs`). It reads each
// `[data-pos]` container of the page with SwiftSoup, with the parse rules of
// `brave.rs`. A page with no container and a challenge marker is a challenge
// page, and not a page with no results.

import Foundation
import SwiftSoup

/// The keyless search provider that reads the Brave search results page.
struct BraveHTMLProvider: SearchProviderAdapter {
    /// The URL of the results page.
    static let endpoint = "https://search.brave.com/search"

    /// The `User-Agent` of each request: the desktop browser of `brave.rs`.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/131.0.0.0 Safari/537.36"

    /// The media type that the request asks for.
    private static let htmlMediaType = "text/html"

    /// The query item of the query text.
    private static let queryItem = "q"

    /// The query item that selects the kind of results.
    private static let sourceItem = "source"

    /// The value of ``sourceItem``: the web results.
    private static let webSource = "web"

    /// The query item of the age limit. A recorded page proves that the
    /// service obeys it.
    private static let timeFilterItem = "tf"

    /// The selector of each result container.
    private static let containerSelector = "[data-pos]"

    /// The selector of the title in a result container.
    private static let titleSelector = "a .title"

    /// The selector of each link in a result container.
    private static let linkSelector = "a[href]"

    /// The attribute of the target URL of a link.
    private static let hrefAttribute = "href"

    /// The selector of the snippet in a result container.
    private static let snippetSelector = ".snippet-description"

    /// The selector of a paragraph, for the snippet when the container has
    /// no ``snippetSelector`` text.
    private static let paragraphSelector = "p"

    /// The number of characters of the longest paragraph that is too short
    /// to be a snippet.
    private static let shortParagraphLength = 20

    /// The selector of the captcha form of a challenge page. SwiftSoup
    /// compares the attribute value in any case.
    private static let challengeFormSelector = "form[action*=captcha]"

    /// The word of the text of a challenge page, in lower case.
    private static let challengeWord = "captcha"

    /// The name of the provider: `braveHTML`.
    let name = WebSearchProvider.braveHTML.name

    /// The query fields that the provider sends: the `tf` item, a `site:`
    /// term in the query, and the limit of the parse.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// Makes a `GET` request of the results page, with the headers of a
    /// desktop browser. The provider has no key and does not read the key
    /// value.
    ///
    /// - Parameter query: The query. A site adds a `site:<host>` term to the
    ///   text. A freshness adds the `tf` item.
    /// - Returns: The request.
    /// - Throws: ``InvalidProviderEndpoint`` when ``endpoint`` is not a URL.
    func request(for query: SearchQuery, key _: String?) throws -> URLRequest {
        var request = try SearchProviderSupport.getRequest(
            to: Self.endpoint, items: Self.queryItems(of: query), accepting: Self.htmlMediaType)
        request.setValue(Self.userAgent, forHTTPHeaderField: WebFetcher.userAgentHeader)
        return request
    }

    /// Reads the hits of a results page. The provider does not read the
    /// response.
    ///
    /// - Parameters:
    ///   - data: The body of the response: the HTML of the page.
    ///   - limit: The maximum number of hits, or `nil` for all hits of the
    ///     page.
    /// - Returns: The hits with no duplicate URL, with rank 1 first.
    /// - Throws: `.challenge` for a page with no result container and a
    ///   challenge marker, `.noResults` for another page with no hits, and
    ///   `.parse` when the page cannot be read.
    func parse(_ data: Data, response _: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        guard let html = String(data: data, encoding: .utf8) else { throw .parse("the body is not UTF-8") }
        let document = try SearchProviderSupport.reading { try SwiftSoup.parse(html, Self.endpoint) }
        let containers = try SearchProviderSupport.reading { try document.select(Self.containerSelector).array() }
        let pageResults = try SearchProviderSupport.reading { try containers.compactMap(Self.pageResult(of:)) }
        let hits = SearchProviderSupport.rankedHits(from: pageResults, limit: limit)
        guard hits.isEmpty else { return hits }
        guard containers.isEmpty else { throw .noResults }
        let isChallenge = try SearchProviderSupport.reading { try Self.hasChallengeMarker(document) }
        throw isChallenge ? .challenge : .noResults
    }

    // MARK: - The request

    /// The query items of a query, in order.
    ///
    /// - Parameter query: The query.
    /// - Returns: The `q` item and the `source` item, then the `tf` item
    ///   when the query has a freshness.
    private static func queryItems(of query: SearchQuery) -> [(name: String, value: String)] {
        let timeItems = query.freshness.map { [(name: timeFilterItem, value: $0.braveTimeFilterValue)] } ?? []
        return [(name: queryItem, value: query.textWithSiteTerm), (name: sourceItem, value: webSource)] + timeItems
    }

    // MARK: - The parse

    /// Reads one result container.
    ///
    /// - Parameter container: The result container.
    /// - Returns: The result, or `nil` when the container has no link to an
    ///   `http` or `https` URL, or no title.
    /// - Throws: An error of SwiftSoup.
    private static func pageResult(of container: Element) throws -> ProviderResult? {
        guard let link = try firstWebLink(in: container) else { return nil }
        let titleText = try container.select(titleSelector).first()?.text() ?? ""
        let title = titleText.isEmpty ? try link.element.text() : titleText
        guard !title.isEmpty else { return nil }
        return ProviderResult(title: title, url: link.url, snippet: try snippet(of: container))
    }

    /// The first link of a container whose target is an `http` or `https`
    /// URL.
    ///
    /// - Parameter container: The result container.
    /// - Returns: The link and its URL, or `nil` when no link has such a
    ///   target.
    /// - Throws: An error of SwiftSoup.
    private static func firstWebLink(in container: Element) throws -> (element: Element, url: String)? {
        let links = try container.select(linkSelector).array()
        let targets = try links.map { link in (element: link, url: webURL(of: try link.attr(hrefAttribute))) }
        return targets.lazy.compactMap { target in target.url.map { (element: target.element, url: $0) } }.first
    }

    /// The snippet of a container: the ``snippetSelector`` text, else the
    /// first paragraph that is longer than ``shortParagraphLength``.
    ///
    /// - Parameter container: The result container.
    /// - Returns: The snippet, or an empty text when the container has none.
    /// - Throws: An error of SwiftSoup.
    private static func snippet(of container: Element) throws -> String {
        let description = try container.select(snippetSelector).first()?.text() ?? ""
        guard description.isEmpty else { return description }
        let paragraphs = try container.select(paragraphSelector).array().map { try $0.text() }
        return paragraphs.first { $0.count > shortParagraphLength } ?? ""
    }

    /// Tells if a page with no result container is a challenge page.
    ///
    /// - Parameter document: The page.
    /// - Returns: `true` when the page has a captcha form, or when the text
    ///   of its body holds ``challengeWord`` in any case. The text of a
    ///   script is not body text.
    /// - Throws: An error of SwiftSoup.
    private static func hasChallengeMarker(_ document: Document) throws -> Bool {
        guard try document.select(challengeFormSelector).first() == nil else { return true }
        let bodyText = try document.body()?.text() ?? ""
        return bodyText.lowercased().contains(challengeWord)
    }

    // MARK: - The links

    /// The text of the absolute `http` or `https` URL of a link.
    ///
    /// - Parameter href: The `href` of the link, with its entities decoded.
    /// - Returns: The URL text, or `nil` when the link has no scheme (for
    ///   example `/path` or `//host/path`), or another scheme, as in
    ///   `brave.rs`.
    private static func webURL(of href: String) -> String? {
        guard let link = URLComponents(string: href), link.scheme != nil else { return nil }
        return SearchProviderSupport.webURL(of: link)
    }
}

private extension SearchFreshness {
    /// The value of the `tf` query item of Brave for this age limit.
    var braveTimeFilterValue: String {
        switch self {
        case .day: "pd"
        case .week: "pw"
        case .month: "pm"
        case .year: "py"
        }
    }
}
