// `SearchProviderSupport` — the request and parse steps that more than one
// search provider adapter uses (web.md § "Providers and API keys").
//
// A keyed provider sends its key in one header, sends the query as URL query
// items or as a JSON body, and gives its results as JSON. Each adapter keeps
// only its own field names. The steps that are the same for each provider are
// here: the endpoint URL, the key check, the percent encoding, the JSON
// request, the status check and the decode of the response, and the rank of
// the hits, the text of an HTML fragment, and the start date of an age limit.

import Foundation
import SwiftSoup

/// The error of `request` when the calendar cannot make the start date of an
/// age limit.
struct InvalidStartDate: Error, CustomStringConvertible {
    /// The text of the error.
    var description: String { "the start date of the age limit cannot be made" }
}

/// The error of `request` when the endpoint of an adapter is not a URL.
struct InvalidProviderEndpoint: Error, CustomStringConvertible {
    /// The endpoint text that is not a URL.
    let endpoint: String

    /// The text of the error.
    var description: String { "the endpoint is not a URL: \(endpoint)" }
}

/// The error of `request` when a keyed provider gets no key.
struct MissingProviderKey: Error, CustomStringConvertible {
    /// The name of the provider.
    let provider: String

    /// The text of the error. It holds no key value.
    var description: String { "\(provider) needs an API key" }
}

/// One result of a provider response, before the check of its URL and title.
struct ProviderResult: Sendable {
    /// The title of the result.
    let title: String

    /// The URL of the result.
    let url: String

    /// A short text from the page, or an empty text when the provider gives
    /// none.
    let snippet: String
}

/// The request and parse steps that more than one search provider uses.
///
/// A namespace, and not a value: each member is `static`.
enum SearchProviderSupport {
    /// The HTTP method of a request with its query in the URL.
    static let getMethod = "GET"

    /// The HTTP method of a request with a body.
    static let postMethod = "POST"

    /// The header that tells the media type that the client reads.
    static let acceptHeader = "Accept"

    /// The media type of a JSON body.
    static let jsonMediaType = "application/json"

    /// The HTTP statuses of a response that holds results.
    private static let successStatuses = 200...299

    /// The ASCII bytes that a percent-encoded text keeps with no change: the
    /// unreserved characters of RFC 3986.
    private static let unreservedBytes = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

    /// The format of one percent-encoded byte.
    private static let percentEncodedByteFormat = "%%%02X"

    /// The calendar unit of each age limit. The earliest date of an age limit
    /// is ``ageLimitUnitCount`` of its unit before the time of the request.
    private static let ageLimitUnits = SearchFreshnessValues<Calendar.Component>(
        day: .day, week: .weekOfYear, month: .month, year: .year)

    /// The number of calendar units in each age limit.
    private static let ageLimitUnitCount = 1

    /// The schemes of a hit URL.
    private static let webSchemes: Set<String> = ["http", "https"]

    /// The scheme of a link that has a host and no scheme, for example
    /// `//example.com/page`.
    private static let defaultScheme = "https"

    // MARK: - The request

    /// Makes the URL of an endpoint.
    ///
    /// - Parameter endpoint: The text of the endpoint URL.
    /// - Returns: The URL.
    /// - Throws: ``InvalidProviderEndpoint`` when the text is not a URL.
    static func endpointURL(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else { throw InvalidProviderEndpoint(endpoint: endpoint) }
        return url
    }

    /// Gets the key of a keyed provider.
    ///
    /// - Parameters:
    ///   - key: The key value that the chain gives, or `nil`.
    ///   - provider: The name of the provider.
    /// - Returns: The key value.
    /// - Throws: ``MissingProviderKey`` when the key is `nil` or empty.
    static func requiredKey(_ key: String?, provider: String) throws -> String {
        guard let key, !key.isEmpty else { throw MissingProviderKey(provider: provider) }
        return key
    }

    /// Keeps a count in the range that a provider documents.
    ///
    /// - Parameters:
    ///   - count: The count of the query, or `nil` for the default of the
    ///     provider.
    ///   - range: The counts that the provider accepts.
    /// - Returns: The nearest count in `range`, or `nil` when `count` is `nil`.
    static func clampedCount(_ count: Int?, to range: ClosedRange<Int>) -> Int? {
        count.map { min(max($0, range.lowerBound), range.upperBound) }
    }

    /// Percent-encodes each UTF-8 byte of a text that is not an unreserved
    /// character. A space becomes `%20`, and a `+` becomes `%2B`.
    ///
    /// - Parameter text: The text of a form field or a query item.
    /// - Returns: The encoded text.
    static func percentEncoded(_ text: String) -> String {
        text.utf8.map { byte in
            unreservedBytes.contains(byte)
                ? String(UnicodeScalar(byte)) : String(format: percentEncodedByteFormat, byte)
        }.joined()
    }

    /// Makes a `GET` request that asks for JSON, with its query items
    /// percent-encoded.
    ///
    /// - Parameters:
    ///   - endpoint: The text of the endpoint URL.
    ///   - items: The query items, in order.
    /// - Returns: The request.
    /// - Throws: ``InvalidProviderEndpoint`` when the URL cannot be made.
    static func jsonGetRequest(to endpoint: String, items: [(name: String, value: String)]) throws -> URLRequest {
        try getRequest(to: endpoint, items: items, accepting: jsonMediaType)
    }

    /// Makes a `GET` request that asks for one media type, with its query
    /// items percent-encoded.
    ///
    /// - Parameters:
    ///   - endpoint: The text of the endpoint URL.
    ///   - items: The query items, in order.
    ///   - mediaType: The media type of the `Accept` header.
    /// - Returns: The request.
    /// - Throws: ``InvalidProviderEndpoint`` when the URL cannot be made.
    static func getRequest(
        to endpoint: String, items: [(name: String, value: String)], accepting mediaType: String
    ) throws -> URLRequest {
        var components = URLComponents(url: try endpointURL(endpoint), resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = items
            .map { "\(percentEncoded($0.name))=\(percentEncoded($0.value))" }
            .joined(separator: "&")
        guard let url = components?.url else { throw InvalidProviderEndpoint(endpoint: endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = getMethod
        request.setValue(mediaType, forHTTPHeaderField: acceptHeader)
        return request
    }

    /// Makes a `POST` request with a JSON body that asks for JSON.
    ///
    /// - Parameters:
    ///   - endpoint: The text of the endpoint URL.
    ///   - body: The body. A `nil` optional field is not in the JSON.
    /// - Returns: The request.
    /// - Throws: ``InvalidProviderEndpoint`` when the endpoint is not a URL,
    ///   or the error of the encoder.
    static func jsonPostRequest(to endpoint: String, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: try endpointURL(endpoint))
        request.httpMethod = postMethod
        request.setValue(jsonMediaType, forHTTPHeaderField: WebFetcher.contentTypeHeader)
        request.setValue(jsonMediaType, forHTTPHeaderField: acceptHeader)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }

    /// The earliest date of an age limit.
    ///
    /// - Parameters:
    ///   - freshness: The age limit.
    ///   - now: The time of the request.
    /// - Returns: `now`, less the age limit, in the Gregorian calendar in UTC.
    /// - Throws: ``InvalidStartDate`` when the calendar cannot make the date.
    static func startDate(of freshness: SearchFreshness, before now: Date) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let unit = ageLimitUnits.value(for: freshness)
        guard let start = calendar.date(byAdding: unit, value: -ageLimitUnitCount, to: now) else {
            throw InvalidStartDate()
        }
        return start
    }

    // MARK: - The parse

    /// The text of an HTML fragment, with its markup removed and its entities
    /// decoded.
    ///
    /// - Parameter html: The HTML fragment, for example a title that holds
    ///   `&amp;` or a description that holds `<strong>` markup.
    /// - Returns: The text.
    /// - Throws: `.parse` when SwiftSoup cannot read the fragment.
    static func text(ofHTML html: String) throws(ProviderFailure) -> String {
        try reading { try SwiftSoup.parseBodyFragment(html).text() }
    }

    /// Checks the status of a response and decodes its JSON body.
    ///
    /// - Parameters:
    ///   - type: The type of the body.
    ///   - data: The body of the response.
    ///   - response: The response.
    /// - Returns: The decoded body.
    /// - Throws: `.badKey`, `.rateLimited`, or `.serverError` for the status
    ///   that each names; `.parse` for another status that is not 2xx, and
    ///   for a body that does not decode.
    static func decodedBody<Body: Decodable>(
        _ type: Body.Type, from data: Data, response: HTTPURLResponse
    ) throws(ProviderFailure) -> Body {
        let status = response.statusCode
        if let failure = ProviderFailure(status: status) { throw failure }
        guard successStatuses.contains(status) else { throw .parse("the service answered HTTP \(status)") }
        return try reading { try JSONDecoder().decode(type, from: data) }
    }

    /// Runs a step of the response read, and changes its error to `.parse`.
    ///
    /// - Parameter step: The step, for example a decode or a SwiftSoup read.
    /// - Returns: The value of the step.
    /// - Throws: `.parse` with the text of the error of the step.
    static func reading<Value>(_ step: () throws -> Value) throws(ProviderFailure) -> Value {
        do {
            return try step()
        } catch {
            throw .parse(String(describing: error))
        }
    }

    /// Makes the hits of the results of a JSON response.
    ///
    /// - Parameters:
    ///   - results: The results, in response order.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits of the results that have a title and an absolute
    ///   `http` or `https` URL, with no duplicate URL, with rank 1 first.
    /// - Throws: `.noResults` when no result is a hit.
    static func checkedHits(from results: [ProviderResult], limit: Int?) throws(ProviderFailure) -> [WebHit] {
        let usable = results.compactMap { result in
            webURL(of: result.url).flatMap { url in
                result.title.isEmpty ? nil : ProviderResult(title: result.title, url: url, snippet: result.snippet)
            }
        }
        let hits = rankedHits(from: usable, limit: limit)
        guard !hits.isEmpty else { throw .noResults }
        return hits
    }

    /// Makes the hits of results: the first result of each URL, up to the
    /// limit, with rank 1 first.
    ///
    /// - Parameters:
    ///   - results: The results, in response order.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits.
    static func rankedHits(from results: [ProviderResult], limit: Int?) -> [WebHit] {
        var seenURLs: Set<String> = []
        let unique = results.filter { seenURLs.insert($0.url).inserted }
        return unique.prefix(limit ?? unique.count).enumerated().map { index, result in
            WebHit(rank: index + 1, title: result.title, url: result.url, snippet: result.snippet)
        }
    }

    // MARK: - The links

    /// The text of an absolute `http` or `https` URL.
    ///
    /// - Parameter text: The text of the URL.
    /// - Returns: The URL text, or `nil` when the text is not an `http` or
    ///   `https` URL with a host.
    static func webURL(of text: String) -> String? {
        URLComponents(string: text).flatMap(webURL(of:))
    }

    /// The text of an absolute `http` or `https` URL.
    ///
    /// - Parameter components: The parts of the URL. A URL with a host and no
    ///   scheme gets ``defaultScheme``.
    /// - Returns: The URL text, or `nil` when the URL has no host or another
    ///   scheme.
    static func webURL(of components: URLComponents) -> String? {
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
