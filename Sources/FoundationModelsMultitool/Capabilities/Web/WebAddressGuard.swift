// `WebAddressGuard` — the URL guard of the web capability (SSRF).
//
// The guard refuses a URL that can reach the host computer, the local network,
// or a cloud metadata service (web.md § "What we copy", the URL guard lists,
// and § "Fetch / The pipeline", step 2). It checks the scheme, the user info,
// and the host name. Then it resolves the host and checks EACH address.
//
// A refusal is a correction in the files vocabulary (`CorrectiveResult.swift`).
// The guard does not throw.
//
// Known limit (web.md § "Security"): `URLSession` resolves the host again to
// connect. A DNS server that gives a different address the second time can
// pass the guard.
//
// This file holds the guard itself (``WebGuardRefusal``, ``WebAddressGuard``)
// and its redirect hook (``RedirectCheck``), which `WebFetcher.swift` gives to
// each request. ``IPAddress`` is in `IPAddress.swift`, the blocked ranges are
// in `BlockedAddresses.swift`, and the resolver is in `HostResolver.swift`.

import Foundation
import Synchronization

/// A refusal of the guard, with the correction for the model.
///
/// It is an `Error` only so it can be a `Result` failure. The guard never
/// throws it.
struct WebGuardRefusal: CorrectiveFailure, Equatable, Sendable {
    /// The correction that tells the model why the URL is not allowed.
    let correctiveMessage: String

    /// Makes a refusal whose correction starts with the common lead.
    ///
    /// - Parameter reason: The reason, for example
    ///   `localtest.me resolves to 127.0.0.1, a loopback address`.
    init(reason: String) {
        correctiveMessage = "The address is not allowed: \(reason)."
    }
}

/// Refuses a URL that can reach the host computer, the local network, or a
/// cloud metadata service.
///
/// The checks, in order: the scheme is `http` or `https`; the URL has no user
/// info; the host is not on the blocklist and does not end in a blocked
/// suffix; and each address of the host is outside the blocked ranges. A
/// literal IP host is checked without a resolver call.
struct WebAddressGuard: Sendable {
    /// The schemes that the guard allows.
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// The host names that the guard refuses before it resolves them.
    static let blockedHosts: Set<String> = [
        "localhost", "127.0.0.1", "::1", "0.0.0.0", "169.254.169.254",
        "metadata.google.internal", "metadata.azure.com", "instance-data.ec2.internal"
    ]

    /// The host name suffixes that the guard refuses before it resolves them.
    static let blockedSuffixes = [".local", ".localhost", ".internal"]

    /// The resolver that gives the addresses of a host name.
    let resolver: any HostResolver

    /// Makes a guard.
    ///
    /// - Parameter resolver: The resolver for host names. The default calls
    ///   `getaddrinfo`.
    init(resolver: any HostResolver = SystemHostResolver()) {
        self.resolver = resolver
    }

    /// Checks `url`.
    ///
    /// - Parameter url: The URL of a request or of a redirect hop.
    /// - Returns: The refusal, or `nil` when the URL is allowed.
    func check(_ url: URL) async -> WebGuardRefusal? {
        switch Self.host(of: url) {
        case .failure(let refusal):
            refusal
        case .success(let host):
            await checkAddresses(of: host)
        }
    }

    /// Checks the scheme, the user info, and the host name of `url`.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: The normalized host name when these checks pass: lower case,
    ///   with no brackets and no trailing dot. Else the refusal.
    static func host(of url: URL) -> Result<String, WebGuardRefusal> {
        let scheme = url.scheme?.lowercased() ?? ""
        guard allowedSchemes.contains(scheme) else {
            return .failure(WebGuardRefusal(reason: "the scheme \(scheme) is not http or https"))
        }
        let host = normalizedHost(url.host(percentEncoded: false) ?? "")
        guard !host.isEmpty else {
            return .failure(WebGuardRefusal(reason: "the URL has no host"))
        }
        guard url.user(percentEncoded: true) == nil, url.password(percentEncoded: true) == nil else {
            return .failure(
                WebGuardRefusal(reason: "the URL to \(host) has user info (user:pass@). Remove it")
            )
        }
        guard !blockedHosts.contains(host) else {
            return .failure(WebGuardRefusal(reason: "the host \(host) is on the blocklist"))
        }
        if let suffix = blockedSuffixes.first(where: { host.hasSuffix($0) }) {
            return .failure(WebGuardRefusal(reason: "the host \(host) ends in \(suffix)"))
        }
        return .success(host)
    }

    /// Makes the form of a host name that the checks compare: lower case, with
    /// no brackets around an IPv6 literal and no trailing dot.
    ///
    /// - Parameter host: The host of the URL.
    /// - Returns: The normalized host name.
    static func normalizedHost(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasPrefix("["), normalized.hasSuffix("]") {
            normalized = String(normalized.dropFirst().dropLast())
        }
        if normalized.hasSuffix(".") {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }

    /// Checks each address of `host`.
    ///
    /// A literal IP host is its own address, and the resolver is not called.
    ///
    /// - Parameter host: The normalized host name.
    /// - Returns: The refusal for the first blocked address, or `nil` when
    ///   each address is allowed.
    private func checkAddresses(of host: String) async -> WebGuardRefusal? {
        if let literal = IPAddress(literal: host) {
            return BlockedAddresses.kind(of: literal).map {
                WebGuardRefusal(reason: "\(host) is \($0.phrase)")
            }
        }
        guard let addresses = try? await resolver.addresses(for: host), !addresses.isEmpty else {
            return WebGuardRefusal(reason: "\(host) does not resolve")
        }
        return addresses.lazy.compactMap { address in
            BlockedAddresses.kind(of: address).map {
                WebGuardRefusal(reason: "\(host) resolves to \(address), \($0.phrase)")
            }
        }.first
    }
}

/// The redirect hook of the guard for one request of `WebFetcher`: the guard
/// checks the URL of each redirect hop, and the hop count must stay at or
/// below the limit.
///
/// A refused hop is not followed, and the check cancels the task. The
/// fetcher then reads ``failure`` in place of the cancel error.
final class RedirectCheck: NSObject, URLSessionTaskDelegate, Sendable {
    /// The guard that checks each hop.
    private let addressGuard: WebAddressGuard

    /// The maximum number of hops.
    private let limit: Int

    /// The URL of the first request, for the failure text.
    private let origin: String

    /// The number of hops so far, and the failure of the first refused hop.
    private let state = Mutex<(hops: Int, failure: WebFetchFailure?)>((0, nil))

    /// Makes the check for one request.
    ///
    /// - Parameters:
    ///   - addressGuard: The guard that checks each hop.
    ///   - limit: The maximum number of hops.
    ///   - origin: The URL of the first request.
    init(addressGuard: WebAddressGuard, limit: Int, origin: String) {
        self.addressGuard = addressGuard
        self.limit = limit
        self.origin = origin
    }

    /// The failure of the refused hop, or `nil` when no hop was refused.
    var failure: WebFetchFailure? {
        state.withLock { $0.failure }
    }

    /// Counts the hop, and checks its URL with the guard.
    ///
    /// - Parameters:
    ///   - session: The session of the request.
    ///   - task: The task of the request.
    ///   - response: The redirect response.
    ///   - request: The request of the next hop.
    /// - Returns: `request` when the hop is allowed, else `nil`.
    func urlSession(
        _: URLSession, task: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        let hops = state.withLock { state in
            state.hops += 1
            return state.hops
        }
        guard hops <= limit else {
            return refuse(.tooManyRedirects(url: origin, limit: limit), task: task)
        }
        guard let url = request.url else {
            return refuse(.refused(WebGuardRefusal(reason: "the redirect has no URL")), task: task)
        }
        if let refusal = await addressGuard.check(url) {
            return refuse(.refused(refusal), task: task)
        }
        return request
    }

    /// Keeps `failure`, stops the redirect, and cancels the task.
    ///
    /// - Parameters:
    ///   - failure: The failure of the hop.
    ///   - task: The task of the request.
    /// - Returns: `nil`, which tells the session not to follow the hop.
    private func refuse(_ failure: WebFetchFailure, task: URLSessionTask) -> URLRequest? {
        state.withLock { $0.failure = $0.failure ?? failure }
        task.cancel()
        return nil
    }
}
