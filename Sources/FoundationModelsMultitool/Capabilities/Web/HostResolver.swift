// `HostResolver` — resolves a host name to its addresses for the web
// capability's URL guard (`WebAddressGuard.swift`). The default
// implementation, ``SystemHostResolver``, calls `getaddrinfo`.

import Darwin
import Foundation

/// Gives the addresses of a host name.
///
/// The guard gets a resolver at init. The default is ``SystemHostResolver``.
/// A test gives a stub, thus the test does not use the network.
protocol HostResolver: Sendable {
    /// Resolves `host` to its addresses.
    ///
    /// - Parameter host: The host name, for example `example.com`.
    /// - Returns: Each address of the host.
    /// - Throws: An error when the host does not resolve.
    func addresses(for host: String) async throws -> [IPAddress]
}

/// The error that ``SystemHostResolver`` gives when `getaddrinfo` fails.
struct HostResolutionError: Error, CustomStringConvertible {
    /// The host name that did not resolve.
    let host: String

    /// The status that `getaddrinfo` gave.
    let status: Int32

    /// The host and the text of the status, from `gai_strerror`.
    var description: String {
        "\(host) does not resolve: \(String(cString: gai_strerror(status)))"
    }
}

/// Resolves a host name with `getaddrinfo`.
struct SystemHostResolver: HostResolver {
    /// Resolves `host` with `getaddrinfo`.
    ///
    /// `getaddrinfo` blocks until the answer comes. Thus the call runs on a
    /// global dispatch queue and does not block a thread of the Swift
    /// concurrency pool.
    ///
    /// - Parameter host: The host name, for example `example.com`.
    /// - Returns: Each IPv4 and IPv6 address of the host.
    /// - Throws: ``HostResolutionError`` when `getaddrinfo` fails.
    func addresses(for host: String) async throws -> [IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try Self.lookUpAddresses(of: host) })
            }
        }
    }

    /// Calls `getaddrinfo` for `host` and reads each address of the answer.
    ///
    /// - Parameter host: The host name.
    /// - Returns: Each IPv4 and IPv6 address of the answer.
    /// - Throws: ``HostResolutionError`` when `getaddrinfo` fails.
    private static func lookUpAddresses(of host: String) throws -> [IPAddress] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var answer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &answer)
        guard status == 0 else { throw HostResolutionError(host: host, status: status) }
        defer { freeaddrinfo(answer) }
        let entries = sequence(first: answer) { $0?.pointee.ai_next }.compactMap { $0?.pointee }
        return entries.compactMap { entry in entry.ai_addr.flatMap { IPAddress(socketAddress: $0) } }
    }
}
