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
// The fetcher has no clock. The one time limit of a request is the tool-level
// timeout of the `runCode` call (`MultiTool.timeout(from:)`): when it fires,
// it cancels the task of the call, and the cancel stops the request. Thus the
// session and each request have no timer that can fire before it.
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

    /// The request failed before a response came, for example because the
    /// host did not accept the connection, or because the task of the call
    /// was cancelled.
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
        case .network(let url, let reason):
            "The request to \(url) failed: \(reason)"
        case .notText(let contentType):
            "The content type is not text: \(contentType). fetch reads text, HTML, JSON, and XML."
        case .unconvertible(let url, let reason):
            "The page at \(url) could not be converted: \(reason)"
        }
    }
}

/// Sends the requests of the web capability, with the guard, the redirect
/// limit, and the byte limit.
///
/// The fetcher makes one `URLSession` that sends no cookies, keeps no cookies,
/// has no URL cache, and has no timer.
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

    /// The time limit of each session timer: no limit.
    ///
    /// The session applies a request timer and a resource timer to each
    /// task. The one time limit of a request is the tool-level timeout of
    /// the `runCode` call, thus no session timer may fire before it.
    /// URLSession accepts `.infinity` for the request timer, the resource
    /// timer, and `URLRequest.timeoutInterval`, and a cancel still stops the
    /// task.
    static let noTimeLimit = TimeInterval.infinity

    /// The session that sends each request. It is internal, thus a test can
    /// read its configuration.
    let session: URLSession

    /// The limits and the user agent of each request. It is internal, thus
    /// the verbs read the byte limit from it.
    let policy: WebFetchPolicy

    /// The guard that checks each URL and each redirect hop.
    private let addressGuard: WebAddressGuard

    /// Makes a fetcher.
    ///
    /// - Parameters:
    ///   - sessionConfiguration: The configuration of the session. The
    ///     fetcher uses a copy with no cookies, no URL cache, and no timer,
    ///     thus the caller's object does not change. A test gives a
    ///     configuration whose `protocolClasses` holds a stub.
    ///   - policy: The limits and the user agent of each request.
    ///   - addressGuard: The guard that checks each URL and each redirect hop.
    init(sessionConfiguration: URLSessionConfiguration, policy: WebFetchPolicy, addressGuard: WebAddressGuard) {
        let configuration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? sessionConfiguration
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.noTimeLimit
        configuration.timeoutIntervalForResource = Self.noTimeLimit
        session = URLSession(configuration: configuration)
        self.policy = policy
        self.addressGuard = addressGuard
    }

    /// Sends `request` and reads its body.
    ///
    /// When the request has no `User-Agent` header, the fetcher sets the one
    /// of the policy. A request that sets its own `User-Agent` keeps it.
    ///
    /// The load has no time limit of its own. A cancel of the calling task,
    /// for example from the timeout of the `runCode` call, stops the request
    /// and ends the load with the network failure.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - guarded: `true` to check the URL of the request with the guard.
    ///     `false` is only for a URL of the host configuration, for example
    ///     the base URL of a SearXNG instance. The guard still checks each
    ///     redirect hop of an unguarded request.
    /// - Returns: The body, or the failure. A non-2xx status is a body, not a
    ///   failure.
    func load(_ request: URLRequest, guarded: Bool = true) async -> Result<FetchedBody, WebFetchFailure> {
        await send(prepare(request), guarded: guarded)
    }

    /// Decodes a text body.
    ///
    /// The text media types are `text/*`, `application/json`,
    /// `application/xml`, and each type with a `+json` or `+xml` suffix, for
    /// example `application/xhtml+xml`. The fetcher decodes with the charset
    /// of the response, else with UTF-8. A byte sequence that is not correct
    /// UTF-8, for example at the end of a truncated body, becomes U+FFFD.
    ///
    /// - Parameter body: The body that ``load(_:guarded:)`` read.
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

    /// Adds the policy `User-Agent` when the request has none, and removes the
    /// session timer of the request.
    ///
    /// A request that the caller made has a timer of its own (60 seconds by
    /// default), and that timer replaces the request timer of the session.
    /// Thus the fetcher sets it to ``noTimeLimit`` on each request.
    ///
    /// - Parameter request: The request of the caller.
    /// - Returns: The request to send.
    private func prepare(_ request: URLRequest) -> URLRequest {
        var prepared = request
        if prepared.value(forHTTPHeaderField: Self.userAgentHeader) == nil {
            prepared.setValue(policy.userAgent, forHTTPHeaderField: Self.userAgentHeader)
        }
        prepared.timeoutInterval = Self.noTimeLimit
        return prepared
    }

    /// Checks the URL, sends the request, and reads the body.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - guarded: `true` to check the URL of the request with the guard.
    /// - Returns: The body, or the failure.
    private func send(_ request: URLRequest, guarded: Bool) async -> Result<FetchedBody, WebFetchFailure> {
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
            return .failure(redirects.failure ?? .network(url: target, reason: error.localizedDescription))
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
