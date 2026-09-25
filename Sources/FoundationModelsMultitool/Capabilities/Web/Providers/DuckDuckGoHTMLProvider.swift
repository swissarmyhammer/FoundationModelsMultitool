// `DuckDuckGoHTMLProvider` — the second keyless search provider (web.md §
// "The provider list").
//
// The provider posts the query as a form to the HTML results page of
// DuckDuckGo. It reads the organic results of the page with SwiftSoup. The
// page holds each ad in a `.result--ad` container, and the provider skips
// those containers. An older form of the page links each result through
// `//duckduckgo.com/l/?uddg=<target>`. The provider decodes such a link to the
// target URL. A page with no results and the elements of the anomaly form is
// a challenge page.

import Foundation
import SwiftSoup

/// The keyless search provider that reads the HTML results page of
/// DuckDuckGo.
struct DuckDuckGoHTMLProvider: SearchProviderAdapter {
    /// The URL of the HTML results page. The request posts the form to it.
    static let endpoint = "https://html.duckduckgo.com/html/"

    /// The body type of the request.
    private static let formContentType = "application/x-www-form-urlencoded"

    /// The form field of the query text.
    private static let queryField = "q"

    /// The form field of the age limit. A recorded page proves that the
    /// service obeys it.
    private static let dateField = "df"

    /// The value of ``dateField`` for each age limit.
    private static let dateValues = SearchFreshnessValues(
        day: "d", week: "w", month: "m", year: "y")

    /// The selector of each organic result container. An ad container also
    /// has the class `result`, and it has the class `result--ad` too.
    private static let organicResultSelector = ".result:not(.result--ad)"

    /// The selector of the title link in a result container.
    private static let titleLinkSelector = ".result__a"

    /// The selector of the snippet in a result container.
    private static let snippetSelector = ".result__snippet"

    /// The selector of the elements of the anomaly form of a challenge page.
    private static let challengeSelector = ".anomaly-modal, #challenge-form"

    /// The host of a redirect link.
    private static let redirectHost = "duckduckgo.com"

    /// The path of a redirect link.
    private static let redirectPath = "/l/"

    /// The query field of a redirect link that holds the target URL.
    private static let redirectTargetField = "uddg"

    /// The name of the provider: `duckDuckGoHTML`.
    let name = WebSearchProvider.duckDuckGoHTML.name

    /// The query fields that the provider sends: the `df` field, a `site:`
    /// term in the query, and the limit of the parse.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// `false`: the endpoint is fixed, thus the guard checks the search
    /// request.
    let isHostConfiguration = false

    /// Makes a `POST` request with the query as a form body. The provider has
    /// no key and does not read the key value.
    ///
    /// - Parameter query: The query. A site adds a `site:<host>` term to the
    ///   text. A freshness adds the `df` field.
    /// - Returns: The request.
    /// - Throws: ``InvalidProviderEndpoint`` when ``endpoint`` is not a URL.
    func request(for query: SearchQuery, key _: String?) throws -> URLRequest {
        var request = URLRequest(url: try SearchProviderSupport.endpointURL(Self.endpoint))
        request.httpMethod = SearchProviderSupport.postMethod
        request.setValue(Self.formContentType, forHTTPHeaderField: WebFetcher.contentTypeHeader)
        request.httpBody = Self.formBody(Self.formFields(of: query))
        return request
    }

    /// Reads the organic hits of a results page. The provider does not read
    /// the response.
    ///
    /// - Parameters:
    ///   - data: The body of the response: the HTML of the page.
    ///   - limit: The maximum number of hits, or `nil` for all hits of the
    ///     page.
    /// - Returns: The hits with no duplicate URL, with rank 1 first.
    /// - Throws: `.challenge` for a challenge page, `.noResults` for a page
    ///   with no results, and `.parse` when the page cannot be read.
    func parse(_ data: Data, response _: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        guard let html = String(data: data, encoding: .utf8) else { throw .parse("the body is not UTF-8") }
        let document = try SearchProviderSupport.reading { try SwiftSoup.parse(html, Self.endpoint) }
        let results = try SearchProviderSupport.reading { try document.select(Self.organicResultSelector).array() }
        let pageResults = try SearchProviderSupport.reading { try results.compactMap(Self.pageResult(of:)) }
        let hits = SearchProviderSupport.rankedHits(from: pageResults, limit: limit)
        guard hits.isEmpty else { return hits }
        let isChallenge = try SearchProviderSupport.reading {
            try document.select(Self.challengeSelector).first() != nil
        }
        throw isChallenge ? .challenge : .noResults
    }

    // MARK: - The request

    /// The fields of the form body of a query, in order.
    ///
    /// - Parameter query: The query.
    /// - Returns: The `q` field, then the `df` field when the query has a
    ///   freshness.
    private static func formFields(of query: SearchQuery) -> [(name: String, value: String)] {
        let dateFields = query.freshness.map { [(name: dateField, value: dateValues.value(for: $0))] } ?? []
        return [(name: queryField, value: query.textWithSiteTerm)] + dateFields
    }

    /// The `application/x-www-form-urlencoded` body of form fields.
    ///
    /// - Parameter fields: The fields, in order.
    /// - Returns: The UTF-8 bytes of the body.
    private static func formBody(_ fields: [(name: String, value: String)]) -> Data {
        let pairs = fields.map { field in
            "\(SearchProviderSupport.percentEncoded(field.name))=\(SearchProviderSupport.percentEncoded(field.value))"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    // MARK: - The parse

    /// Reads one organic result container.
    ///
    /// - Parameter container: The result container.
    /// - Returns: The result, or `nil` when the container has no title link,
    ///   no title, or no `http` or `https` target URL.
    /// - Throws: An error of SwiftSoup.
    private static func pageResult(of container: Element) throws -> ProviderResult? {
        guard let link = try container.select(titleLinkSelector).first() else { return nil }
        let title = try link.text()
        guard !title.isEmpty, let url = targetURL(of: try link.attr("href")) else { return nil }
        let snippet = try container.select(snippetSelector).first()?.text() ?? ""
        return ProviderResult(title: title, url: url, snippet: snippet)
    }

    // MARK: - The links

    /// The target URL of a title link.
    ///
    /// - Parameter href: The `href` of the link, with its entities decoded.
    /// - Returns: The decoded `uddg` target of a redirect link, else the
    ///   link; `nil` when that URL is not an absolute `http` or `https` URL.
    private static func targetURL(of href: String) -> String? {
        guard let link = URLComponents(string: href) else { return nil }
        guard isRedirect(link) else { return SearchProviderSupport.webURL(of: link) }
        let target = link.queryItems?.first { $0.name == redirectTargetField }?.value
        return target.flatMap(SearchProviderSupport.webURL(of:))
    }

    /// Tells if a link is a redirect link of DuckDuckGo.
    ///
    /// - Parameter link: The parts of the link.
    /// - Returns: `true` when the host is ``redirectHost`` or one of its
    ///   subdomains, in any case, and the path is ``redirectPath``.
    private static func isRedirect(_ link: URLComponents) -> Bool {
        guard let host = link.host?.lowercased() else { return false }
        let isRedirectHost = host == redirectHost || host.hasSuffix(".\(redirectHost)")
        return isRedirectHost && link.path == redirectPath
    }
}
