// `WebFetcher` — the HTTP layer of the web capability (web.md § "Fetch / The
// pipeline", steps 2 to 6, and § "Security").
//
// Each network request of the capability goes through one `WebFetcher`. The
// fetcher checks the URL with `WebAddressGuard`, sends the request on one
// `URLSession` that keeps no cookies and no cache, checks each redirect hop
// with the guard, stops after `WebFetchPolicy.maxRedirects` hops, and reads at
// most `WebFetchPolicy.maxBytes` of the body. `decodeText(_:)` then decodes a
// text body with its charset.
//
// A failure is a correction in the files vocabulary (`CorrectiveResult.swift`).
// The fetcher does not throw. A non-2xx status is not a failure: the caller
// gets the status and the body.
//
// The redirect hook, `RedirectCheck`, is in `WebAddressGuard.swift`, beside
// the guard that it calls (web.md § "Files to add or change").

import Foundation

/// The body of a response, and the facts about the response that the web
/// capability uses.
struct FetchedBody: Sendable, Equatable {
    /// The final URL, after each redirect.
    let url: URL

    /// The HTTP status of the final response.
    let status: Int

    /// The media type of the response, in lower case and with no parameters,
    /// for example `text/html`.
    let contentType: String

    /// The `charset` parameter of the content type, in lower case, or `nil`
    /// when the response gives none.
    let charset: String?

    /// The body bytes that the fetcher read.
    let bytes: Data

    /// `true` when the body is longer than the byte limit, and the fetcher
    /// stopped at the limit.
    let truncated: Bool
}

/// A failure of the fetcher, with the correction for the model.
///
/// It is an `Error` only so it can be a `Result` failure. The fetcher never
/// throws it.
enum WebFetchFailure: CorrectiveFailure, Equatable, Sendable {
    /// The guard refused the URL of the request or of a redirect hop.
    case refused(WebGuardRefusal)

    /// The request made more redirect hops than the limit.
    case tooManyRedirects(url: String, limit: Int)

    /// The request did not complete in its time limit.
    case timeout(url: String, limit: Duration)

    /// The request failed before a response came, for example because the
    /// host did not accept the connection.
    case network(url: String, reason: String)

    /// The media type of the response is not text.
    case notText(contentType: String)

    /// The HTML converter could not read the page.
    case unconvertible(url: String, reason: String)

    /// The correction that tells the model what went wrong.
    var correctiveMessage: String {
        switch self {
        case .refused(let refusal):
            refusal.correctiveMessage
        case .tooManyRedirects(let url, let limit):
            "The request made more than \(limit) redirects: \(url)"
        case .timeout(let url, let limit):
            "The request timed out after \(Self.secondsPhrase(limit)): \(url)"
        case .network(let url, let reason):
            "The request to \(url) failed: \(reason)"
        case .notText(let contentType):
            "The content type is not text: \(contentType). fetch reads text, HTML, JSON, and XML."
        case .unconvertible(let url, let reason):
            "The page at \(url) could not be converted: \(reason)"
        }
    }

    /// States a time limit in seconds, for example `30 seconds`, `1 second`,
    /// or `0.5 seconds`.
    ///
    /// - Parameter limit: The time limit.
    /// - Returns: The number of seconds and the unit word.
    private static func secondsPhrase(_ limit: Duration) -> String {
        let seconds = limit.timeInterval
        guard seconds == seconds.rounded() else { return "\(seconds) seconds" }
        let whole = Int(seconds)
        return whole == 1 ? "1 second" : "\(whole) seconds"
    }
}

private extension Duration {
    /// The number of attoseconds in one second.
    static let attosecondsPerSecond = 1e18

    /// The duration in seconds, with the part of a second.
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / Self.attosecondsPerSecond
    }
}

/// Sends the requests of the web capability, with the guard, the redirect
/// limit, and the byte limit.
///
/// The fetcher makes one `URLSession` that sends no cookies, keeps no cookies,
/// and has no URL cache.
final class WebFetcher: Sendable {
    /// The request header that names the client program.
    static let userAgentHeader = "User-Agent"

    /// The response header that gives the media type of the body.
    static let contentTypeHeader = "Content-Type"

    /// The media type parameter that names the character encoding.
    static let charsetParameter = "charset"

    /// The media type of a response that gives no content type (RFC 9110,
    /// section 8.3).
    static let unknownContentType = "application/octet-stream"

    /// The media types, other than `text/*`, whose body is text.
    static let textMediaTypes: Set<String> = ["application/json", "application/xml"]

    /// The start of each media type whose body is text.
    static let textMediaTypePrefix = "text/"

    /// The structured syntax suffixes (RFC 6839) whose body is text, for
    /// example `application/ld+json` and `application/xhtml+xml`.
    static let textMediaTypeSuffixes = ["+json", "+xml"]

    /// The session that sends each request. It is internal, thus a test can
    /// read its configuration.
    let session: URLSession

    /// The limits and the user agent of each request.
    private let policy: WebFetchPolicy

    /// The guard that checks each URL and each redirect hop.
    private let addressGuard: WebAddressGuard

    /// Makes a fetcher.
    ///
    /// - Parameters:
    ///   - sessionConfiguration: The configuration of the session. The
    ///     fetcher uses a copy with no cookies and no URL cache, thus the
    ///     caller's object does not change. A test gives a configuration
    ///     whose `protocolClasses` holds a stub.
    ///   - policy: The limits and the user agent of each request.
    ///   - addressGuard: The guard that checks each URL and each redirect hop.
    init(sessionConfiguration: URLSessionConfiguration, policy: WebFetchPolicy, addressGuard: WebAddressGuard) {
        let configuration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? sessionConfiguration
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        self.policy = policy
        self.addressGuard = addressGuard
    }

    /// Sends `request` and reads its body.
    ///
    /// When the request has no `User-Agent` header, the fetcher sets the one
    /// of the policy. A request that sets its own `User-Agent` keeps it.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - timeout: The time limit of the whole load: the guard, each
    ///     redirect hop, and the body.
    ///   - guarded: `true` to check the URL of the request with the guard.
    ///     `false` is only for a URL of the host configuration, for example
    ///     the base URL of a SearXNG instance. The guard still checks each
    ///     redirect hop of an unguarded request.
    /// - Returns: The body, or the failure. A non-2xx status is a body, not a
    ///   failure.
    func load(_ request: URLRequest, timeout: Duration, guarded: Bool = true) async
        -> Result<FetchedBody, WebFetchFailure>
    {
        let prepared = prepare(request, timeout: timeout)
        let target = request.url?.absoluteString ?? ""
        return await withTaskGroup(of: Result<FetchedBody, WebFetchFailure>.self) { group in
            group.addTask { await self.send(prepared, timeout: timeout, guarded: guarded) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failure(.timeout(url: target, limit: timeout))
            }
            let first = await group.next() ?? .failure(.timeout(url: target, limit: timeout))
            group.cancelAll()
            return first
        }
    }

    /// Decodes a text body.
    ///
    /// The text media types are `text/*`, `application/json`,
    /// `application/xml`, and each type with a `+json` or `+xml` suffix, for
    /// example `application/xhtml+xml`. The fetcher decodes with the charset
    /// of the response, else with UTF-8. A byte sequence that is not correct
    /// UTF-8, for example at the end of a truncated body, becomes U+FFFD.
    ///
    /// - Parameter body: The body that ``load(_:timeout:guarded:)`` read.
    /// - Returns: The text, or the failure for a media type that is not text.
    func decodeText(_ body: FetchedBody) -> Result<String, WebFetchFailure> {
        guard Self.isText(body.contentType) else {
            return .failure(.notText(contentType: body.contentType))
        }
        let encoding = body.charset.flatMap(Self.encoding(named:)) ?? .utf8
        if let text = String(bytes: body.bytes, encoding: encoding) {
            return .success(text)
        }
        // The strict decode failed. The lossy UTF-8 decode is intended here: it
        // changes each byte sequence that is not correct into U+FFFD.
        // swiftlint:disable:next optional_data_string_conversion
        return .success(String(decoding: body.bytes, as: UTF8.self))
    }

    /// Adds the policy `User-Agent` when the request has none, and sets the
    /// time limit of the session.
    ///
    /// - Parameters:
    ///   - request: The request of the caller.
    ///   - timeout: The time limit of the load.
    /// - Returns: The request to send.
    private func prepare(_ request: URLRequest, timeout: Duration) -> URLRequest {
        var prepared = request
        if prepared.value(forHTTPHeaderField: Self.userAgentHeader) == nil {
            prepared.setValue(policy.userAgent, forHTTPHeaderField: Self.userAgentHeader)
        }
        prepared.timeoutInterval = timeout.timeInterval
        return prepared
    }

    /// Checks the URL, sends the request, and reads the body.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - timeout: The time limit of the load, for the timeout failure.
    ///   - guarded: `true` to check the URL of the request with the guard.
    /// - Returns: The body, or the failure.
    private func send(_ request: URLRequest, timeout: Duration, guarded: Bool) async
        -> Result<FetchedBody, WebFetchFailure>
    {
        let target = request.url?.absoluteString ?? ""
        if guarded, let refusal = await checkURL(of: request) {
            return .failure(.refused(refusal))
        }
        let redirects = RedirectCheck(addressGuard: addressGuard, limit: policy.maxRedirects, origin: target)
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            if let failure = redirects.failure {
                bytes.task.cancel()
                return .failure(failure)
            }
            return try .success(await read(bytes, response: response))
        } catch {
            return .failure(redirects.failure ?? Self.failure(for: error, url: target, timeout: timeout))
        }
    }

    /// Checks the URL of `request` with the guard.
    ///
    /// - Parameter request: The request to send.
    /// - Returns: The refusal, or `nil` when the URL is allowed.
    private func checkURL(of request: URLRequest) async -> WebGuardRefusal? {
        guard let url = request.url else {
            return WebGuardRefusal(reason: "the request has no URL")
        }
        return await addressGuard.check(url)
    }

    /// Reads at most `maxBytes` of the body, and the facts of the response.
    ///
    /// - Parameters:
    ///   - bytes: The body stream of the response.
    ///   - response: The final response.
    /// - Returns: The body.
    /// - Throws: The error of the body stream, or `URLError(.badServerResponse)`
    ///   when the response is not an HTTP response with a URL.
    private func read(_ bytes: URLSession.AsyncBytes, response: URLResponse) async throws -> FetchedBody {
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            bytes.task.cancel()
            throw URLError(.badServerResponse)
        }
        var data = Data()
        var truncated = false
        for try await byte in bytes {
            guard data.count < policy.maxBytes else {
                truncated = true
                bytes.task.cancel()
                break
            }
            data.append(byte)
        }
        let (contentType, charset) = Self.mediaType(of: http.value(forHTTPHeaderField: Self.contentTypeHeader))
        return FetchedBody(
            url: url, status: http.statusCode, contentType: contentType, charset: charset, bytes: data,
            truncated: truncated
        )
    }

    /// Reads the media type and the charset of a `Content-Type` header.
    ///
    /// The fetcher reads the header itself and does not use
    /// `URLResponse.mimeType`, because `mimeType` can guess a type from the
    /// body when the header is missing.
    ///
    /// - Parameter header: The `Content-Type` header, for example
    ///   `Text/HTML; charset="UTF-8"`, or `nil` when the response has none.
    /// - Returns: The media type in lower case, else ``unknownContentType``;
    ///   and the `charset` parameter in lower case with no quotes, else `nil`.
    private static func mediaType(of header: String?) -> (type: String, charset: String?) {
        let parts = (header ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let type = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? unknownContentType
        let charset = parts.dropFirst().lazy
            .map { $0.split(separator: "=", maxSplits: 1) }
            .first { $0.first?.trimmingCharacters(in: .whitespaces) == charsetParameter }
            .flatMap { $0.dropFirst().first }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        return (type, charset)
    }

    /// Makes the failure for an error of the session.
    ///
    /// - Parameters:
    ///   - error: The error of the session.
    ///   - url: The URL of the request.
    ///   - timeout: The time limit of the load.
    /// - Returns: The timeout failure for `URLError.timedOut`, else the
    ///   network failure.
    private static func failure(for error: any Error, url: String, timeout: Duration) -> WebFetchFailure {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timeout(url: url, limit: timeout)
        }
        return .network(url: url, reason: error.localizedDescription)
    }

    /// Tells if a media type has a text body.
    ///
    /// - Parameter contentType: The media type, in lower case.
    /// - Returns: `true` for `text/*`, a type in ``textMediaTypes``, and a
    ///   type with a suffix in ``textMediaTypeSuffixes``.
    private static func isText(_ contentType: String) -> Bool {
        contentType.hasPrefix(textMediaTypePrefix)
            || textMediaTypes.contains(contentType)
            || textMediaTypeSuffixes.contains { contentType.hasSuffix($0) }
    }

    /// Finds the string encoding of an IANA charset name.
    ///
    /// - Parameter charset: The charset name, for example `iso-8859-1`.
    /// - Returns: The encoding, or `nil` when the name is not known.
    private static func encoding(named charset: String) -> String.Encoding? {
        let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
