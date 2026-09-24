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

    /// The HTTP method of the request.
    private static let postMethod = "POST"

    /// The body type of the request.
    private static let formContentType = "application/x-www-form-urlencoded"

    /// The form field of the query text.
    private static let queryField = "q"

    /// The form field of the age limit. A recorded page proves that the
    /// service obeys it.
    private static let dateField = "df"

    /// The ASCII bytes that the form body keeps with no percent encoding: the
    /// unreserved characters of RFC 3986.
    private static let unreservedBytes = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

    /// The format of one percent-encoded byte.
    private static let percentEncodedByteFormat = "%%%02X"

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

    /// The schemes of a hit URL.
    private static let webSchemes: Set<String> = ["http", "https"]

    /// The scheme of a link that has a host and no scheme, for example
    /// `//example.com/page`.
    private static let defaultScheme = "https"

    /// The error of `request` when ``endpoint`` is not a URL.
    struct InvalidEndpoint: Error, CustomStringConvertible {
        /// The text of the error.
        var description: String { "the endpoint is not a URL: \(DuckDuckGoHTMLProvider.endpoint)" }
    }

    /// The name of the provider: `duckDuckGoHTML`.
    let name = WebSearchProvider.duckDuckGoHTML.name

    /// The query fields that the provider sends: the `df` field, a `site:`
    /// term in the query, and the limit of the parse.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// Makes a `POST` request with the query as a form body.
    ///
    /// - Parameters:
    ///   - query: The query. A site adds a `site:<host>` term to the text. A
    ///     freshness adds the `df` field.
    ///   - key: The key value. The provider has no key and does not read it.
    /// - Returns: The request.
    /// - Throws: ``InvalidEndpoint`` when ``endpoint`` is not a URL.
    func request(for query: SearchQuery, key _: String?) throws -> URLRequest {
        guard let url = URL(string: Self.endpoint) else { throw InvalidEndpoint() }
        var request = URLRequest(url: url)
        request.httpMethod = Self.postMethod
        request.setValue(Self.formContentType, forHTTPHeaderField: WebFetcher.contentTypeHeader)
        request.httpBody = Self.formBody(Self.formFields(of: query))
        return request
    }

    /// Reads the organic hits of a results page.
    ///
    /// - Parameters:
    ///   - data: The body of the response: the HTML of the page.
    ///   - response: The response. The provider does not read it.
    ///   - limit: The maximum number of hits, or `nil` for all hits of the
    ///     page.
    /// - Returns: The hits with no duplicate URL, with rank 1 first.
    /// - Throws: `.challenge` for a challenge page, `.noResults` for a page
    ///   with no results, and `.parse` when the page cannot be read.
    func parse(_ data: Data, response _: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        guard let html = String(data: data, encoding: .utf8) else { throw .parse("the body is not UTF-8") }
        let document = try Self.reading { try SwiftSoup.parse(html, Self.endpoint) }
        let results = try Self.reading { try document.select(Self.organicResultSelector).array() }
        let hits = Self.hits(from: try Self.reading { try results.compactMap(Self.pageResult(of:)) }, limit: limit)
        guard hits.isEmpty else { return hits }
        let isChallenge = try Self.reading { try document.select(Self.challengeSelector).first() != nil }
        throw isChallenge ? .challenge : .noResults
    }

    // MARK: - The request

    /// The fields of the form body of a query, in order.
    ///
    /// - Parameter query: The query.
    /// - Returns: The `q` field, then the `df` field when the query has a
    ///   freshness.
    private static func formFields(of query: SearchQuery) -> [(name: String, value: String)] {
        let text = query.site.map { "\(query.text) site:\($0)" } ?? query.text
        let dateFields = query.freshness.map { [(name: dateField, value: $0.duckDuckGoDateValue)] } ?? []
        return [(name: queryField, value: text)] + dateFields
    }

    /// The `application/x-www-form-urlencoded` body of form fields.
    ///
    /// - Parameter fields: The fields, in order.
    /// - Returns: The UTF-8 bytes of the body.
    private static func formBody(_ fields: [(name: String, value: String)]) -> Data {
        let pairs = fields.map { "\(formEncoded($0.name))=\(formEncoded($0.value))" }
        return Data(pairs.joined(separator: "&").utf8)
    }

    /// Percent-encodes each UTF-8 byte of a text that is not an unreserved
    /// character. A space becomes `%20`, and a `+` becomes `%2B`.
    ///
    /// - Parameter text: The text of a form name or a form value.
    /// - Returns: The encoded text.
    private static func formEncoded(_ text: String) -> String {
        text.utf8.map { byte in
            unreservedBytes.contains(byte)
                ? String(UnicodeScalar(byte)) : String(format: percentEncodedByteFormat, byte)
        }.joined()
    }

    // MARK: - The parse

    /// Runs a step of the page read, and changes its error to `.parse`.
    ///
    /// - Parameter step: The step, which can throw an error of SwiftSoup.
    /// - Returns: The value of the step.
    /// - Throws: `.parse` with the text of the error of the step.
    private static func reading<Value>(_ step: () throws -> Value) throws(ProviderFailure) -> Value {
        do {
            return try step()
        } catch {
            throw .parse(String(describing: error))
        }
    }

    /// Reads one organic result container.
    ///
    /// - Parameter container: The result container.
    /// - Returns: The result, or `nil` when the container has no title link,
    ///   no title, or no `http` or `https` target URL.
    /// - Throws: An error of SwiftSoup.
    private static func pageResult(of container: Element) throws -> PageResult? {
        guard let link = try container.select(titleLinkSelector).first() else { return nil }
        let title = try link.text()
        guard !title.isEmpty, let url = targetURL(of: try link.attr("href")) else { return nil }
        let snippet = try container.select(snippetSelector).first()?.text() ?? ""
        return PageResult(title: title, url: url, snippet: snippet)
    }

    /// Makes the hits of the results of a page: the first result of each
    /// URL, up to the limit, with rank 1 first.
    ///
    /// - Parameters:
    ///   - results: The results, in page order.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits.
    private static func hits(from results: [PageResult], limit: Int?) -> [WebHit] {
        var seenURLs: Set<String> = []
        let unique = results.filter { seenURLs.insert($0.url).inserted }
        return unique.prefix(limit ?? unique.count).enumerated().map { index, result in
            WebHit(rank: index + 1, title: result.title, url: result.url, snippet: result.snippet)
        }
    }

    // MARK: - The links

    /// The target URL of a title link.
    ///
    /// - Parameter href: The `href` of the link, with its entities decoded.
    /// - Returns: The decoded `uddg` target of a redirect link, else the
    ///   link; `nil` when that URL is not an absolute `http` or `https` URL.
    private static func targetURL(of href: String) -> String? {
        guard let link = URLComponents(string: href) else { return nil }
        guard isRedirect(link) else { return webURL(of: link) }
        let target = link.queryItems?.first { $0.name == redirectTargetField }?.value
        return target.flatMap(URLComponents.init(string:)).flatMap(webURL(of:))
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

    /// The text of an absolute `http` or `https` URL.
    ///
    /// - Parameter components: The parts of the URL. A URL with a host and no
    ///   scheme gets ``defaultScheme``.
    /// - Returns: The URL text, or `nil` when the URL has no host or another
    ///   scheme.
    private static func webURL(of components: URLComponents) -> String? {
        var absolute = components
        if absolute.scheme == nil, absolute.host != nil {
            absolute.scheme = defaultScheme
        }
        guard let scheme = absolute.scheme?.lowercased(), webSchemes.contains(scheme),
            absolute.host?.isEmpty == false
        else { return nil }
        return absolute.string
    }
}

/// One organic result of a page, before the duplicate check.
private struct PageResult {
    /// The text of the title link.
    let title: String

    /// The absolute `http` or `https` target URL.
    let url: String

    /// The text of the snippet, or an empty text when the result has none.
    let snippet: String
}

private extension SearchFreshness {
    /// The value of the `df` form field of DuckDuckGo for this age limit.
    var duckDuckGoDateValue: String {
        switch self {
        case .day: "d"
        case .week: "w"
        case .month: "m"
        case .year: "y"
        }
    }
}
