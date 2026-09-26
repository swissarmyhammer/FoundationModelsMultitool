// `SearchProviderAdapter` — the seam between the search chain and one search
// provider (web.md § "Providers and API keys").
//
// Each provider is one type that conforms to the protocol. The adapter makes
// the request of a query and reads the hits of a response. `request` and
// `parse` are pure functions, thus a unit test calls them with fixture bytes
// and no network. `WebSearchChain` sends the request, tries the providers in
// order, and writes the notes.

import Foundation
import FoundationModels

/// A query field that a provider can send to its service.
///
/// The raw value is the name of the field in `tools.web.search`. A note uses
/// it, for example `freshness is not supported by duckDuckGoHTML and was
/// ignored.`
enum SearchFeature: String, Sendable, Hashable, CaseIterable {
    /// The age limit of the results.
    case freshness

    /// The one host that the results must come from.
    case site

    /// The number of results.
    case count
}

/// The age limit of search results.
enum SearchFreshness: String, Sendable, Hashable, CaseIterable {
    /// Results from the last day.
    case day

    /// Results from the last week.
    case week

    /// Results from the last month.
    case month

    /// Results from the last year.
    case year
}

/// The values of one provider field for each age limit.
///
/// Each provider keeps one table for its age-limit field, and reads the value
/// of an age limit with ``value(for:)``. The initializer takes a value for
/// each age limit, thus a table always has all the values.
struct SearchFreshnessValues<Value: Sendable>: Sendable {
    /// The value for ``SearchFreshness/day``.
    let day: Value

    /// The value for ``SearchFreshness/week``.
    let week: Value

    /// The value for ``SearchFreshness/month``.
    let month: Value

    /// The value for ``SearchFreshness/year``.
    let year: Value

    /// The value of an age limit.
    ///
    /// - Parameter freshness: The age limit.
    /// - Returns: The value of the field of that age limit.
    func value(for freshness: SearchFreshness) -> Value {
        switch freshness {
        case .day: day
        case .week: week
        case .month: month
        case .year: year
        }
    }
}

/// One search query, after the verb checked its arguments.
///
/// A field that the caller did not set is `nil`. The chain adds an "is not
/// supported" note only for a field that the caller set.
struct SearchQuery: Sendable, Equatable {
    // The provider adapters read it, and the synthesized `Equatable`
    // conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// The text to search for. It is not empty.
    let text: String

    /// The number of results, or `nil` for the default of the provider.
    let count: Int?

    /// The age limit of the results, or `nil` for no limit.
    let freshness: SearchFreshness?

    /// The one host that the results must come from, or `nil` for all hosts.
    let site: String?

    /// Makes a query.
    ///
    /// - Parameters:
    ///   - text: The text to search for.
    ///   - count: The number of results, or `nil` for the default.
    ///   - freshness: The age limit, or `nil` for no limit.
    ///   - site: The one host of the results, or `nil` for all hosts.
    init(text: String, count: Int? = nil, freshness: SearchFreshness? = nil, site: String? = nil) {
        self.text = text
        self.count = count
        self.freshness = freshness
        self.site = site
    }

    /// The text with a `site:<host>` term after it when the query has a site,
    /// else the text. A provider with no site field sends this text.
    var textWithSiteTerm: String {
        site.map { "\(text) site:\($0)" } ?? text
    }

    /// The fields that the caller set, in the order of ``SearchFeature``.
    var requestedFeatures: [SearchFeature] {
        SearchFeature.allCases.filter { feature in
            switch feature {
            case .freshness: freshness != nil
            case .site: site != nil
            case .count: count != nil
            }
        }
    }
}

/// One search result.
///
/// `@Generable` makes the hit a field of the result of `tools.web.search`.
@Generable(description: "one search hit: its rank, title, URL, and snippet.")
struct WebHit: Sendable, Equatable {
    // The synthesized `Equatable` conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// The position of the hit in the results, from 1.
    let rank: Int

    // The synthesized `Equatable` conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// The title of the page.
    let title: String

    // The synthesized `Equatable` conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// The URL of the page.
    let url: String

    // The synthesized `Equatable` conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// A short text from the page, or an empty text when the provider gives
    /// none.
    let snippet: String
}

/// Why a provider gave no hits.
///
/// Each case sends the chain to the next provider.
enum ProviderFailure: Error, Sendable, Equatable {
    /// The service refused the API key, with this HTTP status: 401 or 403,
    /// or a status that only one provider uses for a refused key (for
    /// example 422 of the Brave Search API).
    case badKey(Int)

    /// The service refused the request because of its rate limit (HTTP 429).
    case rateLimited

    /// The service failed, with this HTTP status (5xx).
    case serverError(Int)

    /// The service gave a challenge page and not the results.
    case challenge

    /// The service gave no results.
    case noResults

    /// The response could not be read. The text tells why. It can hold text
    /// of the response, thus the chain redacts each key value in it.
    case parse(String)

    /// The HTTP status of a refused key.
    private static let unauthorizedStatus = 401

    /// The other HTTP status of a refused key.
    private static let forbiddenStatus = 403

    /// The HTTP status of a rate limit.
    private static let tooManyRequestsStatus = 429

    /// The HTTP statuses of a server failure.
    private static let serverErrorStatuses = 500...599

    /// Makes the failure that an HTTP status tells, before the adapter reads
    /// the body.
    ///
    /// - Parameter status: The HTTP status of the response.
    /// - Returns: ``badKey(_:)`` for 401 and 403, ``rateLimited`` for 429,
    ///   ``serverError(_:)`` for 5xx, else `nil`.
    init?(status: Int) {
        switch status {
        case Self.unauthorizedStatus, Self.forbiddenStatus: self = .badKey(status)
        case Self.tooManyRequestsStatus: self = .rateLimited
        case Self.serverErrorStatuses: self = .serverError(status)
        default: return nil
        }
    }
}

/// One search provider: the request of a query and the parse of a response.
protocol SearchProviderAdapter: Sendable {
    /// The name of the provider, for example `braveHTML`. A note and a
    /// correction show it.
    var name: String { get }

    /// The query fields that the provider sends to its service.
    var supports: Set<SearchFeature> { get }

    /// `true` when the request URL is host configuration, for example the
    /// base URL of a SearXNG instance. The guard then does not check the
    /// request URL. Each adapter declares the value, thus no adapter gets
    /// `false` by accident.
    var isHostConfiguration: Bool { get }

    /// Makes the request of a query.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - key: The API key value, or `nil` for a provider with no key.
    /// - Returns: The request.
    /// - Throws: An error when the request cannot be made.
    func request(for query: SearchQuery, key: String?) throws -> URLRequest

    /// Reads the hits of a response.
    ///
    /// - Parameters:
    ///   - data: The body of the response.
    ///   - response: The response.
    ///   - limit: The maximum number of hits, which is the count of the
    ///     query, or `nil` for all hits of the response.
    /// - Returns: The hits, with rank 1 first. The list is not empty, and it
    ///   has not more than `limit` hits.
    /// - Throws: The failure when the response gives no hits.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit]
}
