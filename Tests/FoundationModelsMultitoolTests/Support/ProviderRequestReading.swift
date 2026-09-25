// `ProviderRequestReading` — reads the query fields of a search provider
// request in a test.
//
// A provider sends its query fields as URL query items or as a JSON body. The
// request tests of the providers read them with these steps, and compare them
// with the documented field names and values.

import Foundation
import Testing

/// The steps that read the query fields of a provider request.
///
/// A namespace, and not a value: each member is `static`.
enum ProviderRequestReading {
    /// The `Content-Type` header of a request with a body.
    private static let contentTypeHeader = "Content-Type"

    /// The media type of a JSON body.
    private static let jsonMediaType = "application/json"

    /// The query items of a request, by name.
    ///
    /// - Parameter request: The request.
    /// - Returns: The value of each query item. An item with no value has an
    ///   empty value.
    /// - Throws: When the request has no URL.
    static func queryItems(of request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    /// The JSON body of a request, decoded. The test also expects the JSON
    /// `Content-Type`.
    ///
    /// - Parameters:
    ///   - type: The type of the body.
    ///   - request: The request.
    /// - Returns: The body.
    /// - Throws: When the request has no body, or the body does not decode.
    static func jsonBody<Body: Decodable>(_ type: Body.Type, of request: URLRequest) throws -> Body {
        #expect(request.value(forHTTPHeaderField: contentTypeHeader) == jsonMediaType)
        return try JSONDecoder().decode(type, from: #require(request.httpBody))
    }
}
