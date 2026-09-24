// `WebStubURLProtocol` — a stub `URLProtocol` for the web capability tests.
//
// Each test makes its own ``WebStub``: a table from a URL to a reply. The
// stub gives a `URLSessionConfiguration` whose `protocolClasses` holds
// ``WebStubURLProtocol`` and whose `httpAdditionalHeaders` holds the
// identifier of the stub. The session adds that header to each request and to
// each redirect hop. Thus the protocol finds the table of the correct test,
// and tests that run in parallel do not share a table. This is the same
// method as `LoopbackHTTPServer` (`Tests/Support/MCPTestServer/`), which
// finds its server from the host of the request.
//
// No request goes to the network.

import Foundation
@testable import FoundationModelsMultitool
import Synchronization
import Testing

/// What the stub does with a request to one URL.
enum WebStubReply: Sendable {
    /// Send a response with this status, these headers, and this body.
    case respond(status: Int, headers: [String: String], body: Data)

    /// Send a `302 Found` redirect whose `Location` is this URL.
    case redirect(location: URL)

    /// Fail the request with this `URLError` code.
    case fail(URLError.Code)

    /// Send nothing. The request stays open until the session cancels it.
    case hang
}

/// One request that the stub got.
struct WebStubRecord: Sendable, Equatable {
    /// The URL of the request.
    let url: URL

    /// The header fields of the request, as the session sent them.
    let headers: [String: String]
}

/// A table of replies for one test, and a record of each request it got.
final class WebStub: Sendable {
    /// The request header that holds the identifier of the stub.
    static let identifierHeader = "X-Web-Stub"

    /// The HTTP status of a normal page.
    static let okStatus = 200

    /// The HTTP status of a response that no row of the table gives.
    static let notFoundStatus = 404

    /// The HTTP status of a redirect reply.
    static let redirectStatus = 302

    /// The number of seconds in ``ampleTimeout``.
    private static let ampleTimeoutSeconds = 10

    /// The time limit of a stub request that must not time out. The stub
    /// answers at once, thus the limit is far from each answer.
    static let ampleTimeout: Duration = .seconds(ampleTimeoutSeconds)

    /// The stubs that exist now, by identifier. A stub removes its own entry
    /// when it goes away.
    private static let registry = Mutex<[String: WeakWebStub]>([:])

    /// The identifier that the session sends in ``identifierHeader``.
    let identifier = UUID().uuidString

    /// The reply for each URL, keyed by the absolute URL text.
    private let routes: [String: WebStubReply]

    /// Each request that the stub got, in order.
    private let recorded = Mutex<[WebStubRecord]>([])

    /// Makes a stub and registers it.
    ///
    /// - Parameter routes: The reply for each URL, keyed by the absolute URL
    ///   text, for example `https://example.com/page`. A URL with no row gets
    ///   a `404` response with no body.
    init(routes: [String: WebStubReply]) {
        self.routes = routes
        let entry = WeakWebStub(stub: self)
        Self.registry.withLock { $0[identifier] = entry }
    }

    deinit {
        let identifier = identifier
        _ = Self.registry.withLock { $0.removeValue(forKey: identifier) }
    }

    /// A new ephemeral session configuration that sends each request to this
    /// stub.
    var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebStubURLProtocol.self]
        configuration.httpAdditionalHeaders = [Self.identifierHeader: identifier]
        return configuration
    }

    /// Each request that the stub got, in order.
    var requests: [WebStubRecord] {
        recorded.withLock { $0 }
    }

    /// The URL of each request that the stub got, in order.
    var requestedURLs: [String] {
        requests.map(\.url.absoluteString)
    }

    /// Makes a fetcher whose session sends each request to this stub, and
    /// whose guard resolves each host name to a public address.
    ///
    /// - Parameter policy: The limits and the user agent of the fetcher.
    /// - Returns: The fetcher.
    func makeFetcher(policy: WebFetchPolicy = WebFetchPolicy()) -> WebFetcher {
        WebFetcher(
            sessionConfiguration: sessionConfiguration,
            policy: policy,
            addressGuard: WebAddressGuard(resolver: PublicHostResolver())
        )
    }

    /// Records a request and gives its reply.
    ///
    /// - Parameters:
    ///   - url: The URL of the request that the protocol loads.
    ///   - headers: The header fields of that request.
    /// - Returns: The reply of the row for `url`, else a `404` response.
    func reply(to url: URL, headers: [String: String]) -> WebStubReply {
        let record = WebStubRecord(url: url, headers: headers)
        recorded.withLock { $0.append(record) }
        return routes[url.absoluteString] ?? .respond(status: Self.notFoundStatus, headers: [:], body: Data())
    }

    /// Makes a `GET` request to a URL text.
    ///
    /// - Parameter text: The absolute URL text.
    /// - Returns: The request.
    /// - Throws: When `text` is not a URL.
    static func request(to text: String) throws -> URLRequest {
        try URLRequest(url: #require(URL(string: text)))
    }

    /// The stub that `request` names in ``identifierHeader``.
    ///
    /// - Parameter request: A request of a stub session.
    /// - Returns: The stub, or `nil` when the request names no stub that
    ///   exists now.
    static func stub(for request: URLRequest) -> WebStub? {
        guard let identifier = request.value(forHTTPHeaderField: identifierHeader) else { return nil }
        return registry.withLock { $0[identifier]?.stub }
    }
}

/// A weak reference to a ``WebStub``, so the registry does not keep a stub
/// alive after its test.
private struct WeakWebStub: Sendable {
    /// The stub, or `nil` after it went away.
    weak var stub: WebStub?
}

/// The error of a request that names no stub.
struct WebStubMissing: Error {}

/// The `URLProtocol` that answers each request of a stub session from the
/// table of its ``WebStub``.
///
/// The class adds no stored state. Each request finds its table through
/// ``WebStub/stub(for:)``.
final class WebStubURLProtocol: URLProtocol {
    /// The HTTP version of each stub response.
    private static let httpVersion = "HTTP/1.1"

    override static func canInit(with request: URLRequest) -> Bool {
        WebStub.stub(for: request) != nil
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = WebStub.stub(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: WebStubMissing())
            return
        }
        switch stub.reply(to: url, headers: request.allHTTPHeaderFields ?? [:]) {
        case .respond(let status, let headers, let body):
            respond(url: url, status: status, headers: headers, body: body)
        case .redirect(let target):
            redirect(from: url, to: target)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang:
            break
        }
    }

    override func stopLoading() {}

    /// Sends a whole response to the client.
    ///
    /// - Parameters:
    ///   - url: The URL of the request.
    ///   - status: The HTTP status.
    ///   - headers: The header fields.
    ///   - body: The body.
    private func respond(url: URL, status: Int, headers: [String: String], body: Data) {
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: Self.httpVersion, headerFields: headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Sends a `302 Found` redirect to the client. The new request keeps the
    /// header fields of the request, as a session does.
    ///
    /// - Parameters:
    ///   - url: The URL of the request.
    ///   - target: The URL of the next hop.
    private func redirect(from url: URL, to target: URL) {
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: WebStub.redirectStatus, httpVersion: Self.httpVersion,
                headerFields: ["Location": target.absoluteString]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        var next = request
        next.url = target
        client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
    }
}

/// A resolver that gives one public address for each host name.
///
/// A test that uses a host name such as `site.example` gives this resolver to
/// the guard, thus the guard allows the host and no lookup goes to the
/// network.
struct PublicHostResolver: HostResolver {
    /// The address of each host: a public address outside each blocked range.
    static let publicAddress = "93.184.215.14"

    /// The error when ``publicAddress`` does not parse.
    struct BadAddress: Error {}

    func addresses(for _: String) async throws -> [IPAddress] {
        guard let address = IPAddress(literal: Self.publicAddress) else { throw BadAddress() }
        return [address]
    }
}
