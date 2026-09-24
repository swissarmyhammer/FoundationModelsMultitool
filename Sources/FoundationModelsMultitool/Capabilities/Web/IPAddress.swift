// `IPAddress` — an IPv4 or an IPv6 address for the web capability's URL guard
// (`WebAddressGuard.swift`).
//
// The address keeps its bytes in network order. Thus one prefix match
// (``AddressBlock/contains(_:)``, in `BlockedAddresses.swift`) works for the
// two families.

import Darwin
import Foundation

/// An IPv4 or an IPv6 address.
///
/// The address keeps its bytes in network order. Thus one prefix match works
/// for the two families.
struct IPAddress: Sendable, Hashable, CustomStringConvertible {
    /// The family of an address.
    enum Family: CaseIterable, Sendable {
        /// An IPv4 address.
        case ipv4
        /// An IPv6 address.
        case ipv6

        /// The `AF_` constant of the family, for the C functions.
        var addressFamily: Int32 {
            switch self {
            case .ipv4: AF_INET
            case .ipv6: AF_INET6
            }
        }

        /// The number of bytes in an address of the family.
        var byteCount: Int {
            switch self {
            case .ipv4: MemoryLayout<in_addr>.size
            case .ipv6: MemoryLayout<in6_addr>.size
            }
        }

        /// Parses the standard text of an address of the family.
        ///
        /// - Parameter text: The text, for example `10.0.0.1` or `fe80::1`.
        /// - Returns: The bytes in network order, or `nil` when `text` is not
        ///   an address of the family.
        func bytes(parsing text: String) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: byteCount)
            let status = bytes.withUnsafeMutableBytes { inet_pton(addressFamily, text, $0.baseAddress) }
            return status == 1 ? bytes : nil
        }

        /// Makes the standard text of an address of the family.
        ///
        /// - Parameter bytes: The bytes of the address, in network order.
        /// - Returns: The text, for example `10.0.0.1` or `fe80::1`.
        func text(of bytes: [UInt8]) -> String {
            var characters = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let capacity = socklen_t(characters.count)
            _ = bytes.withUnsafeBytes { inet_ntop(addressFamily, $0.baseAddress, &characters, capacity) }
            let utf8 = characters.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(bytes: utf8, encoding: .ascii) ?? ""
        }
    }

    /// The family of the address.
    let family: Family

    /// The bytes of the address, in network order.
    let bytes: [UInt8]

    /// Makes an address from its standard text.
    ///
    /// - Parameter literal: The text, for example `10.0.0.1`, `fe80::1`, or
    ///   `::ffff:127.0.0.1`.
    init?(literal: String) {
        let parsed = Family.allCases.lazy.compactMap { family in
            family.bytes(parsing: literal).map { (family, $0) }
        }.first
        guard let (family, bytes) = parsed else { return nil }
        self.init(family: family, bytes: bytes)
    }

    /// Makes an address from a socket address that `getaddrinfo` gives.
    ///
    /// - Parameter socketAddress: The socket address.
    /// - Returns: `nil` when the socket address is not IPv4 or IPv6.
    init?(socketAddress: UnsafePointer<sockaddr>) {
        switch Int32(socketAddress.pointee.sa_family) {
        case AF_INET:
            let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            self.init(family: .ipv4, bytes: withUnsafeBytes(of: address) { Array($0) })
        case AF_INET6:
            let address = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_addr
            }
            self.init(family: .ipv6, bytes: withUnsafeBytes(of: address) { Array($0) })
        default:
            return nil
        }
    }

    /// Makes an address from its family and its bytes.
    ///
    /// - Parameters:
    ///   - family: The family of the address.
    ///   - bytes: The bytes of the address, in network order.
    private init(family: Family, bytes: [UInt8]) {
        self.family = family
        self.bytes = bytes
    }

    /// The standard text of the address, for example `10.0.0.1` or `fe80::1`.
    var description: String { family.text(of: bytes) }

    /// The IPv4 address in an IPv4-mapped IPv6 address, for example `10.0.0.1`
    /// in `::ffff:10.0.0.1`.
    ///
    /// `nil` when the address is not an IPv4-mapped IPv6 address.
    var mappedIPv4: IPAddress? {
        guard AddressBlock.ipv4Mapped.contains(self) else { return nil }
        return IPAddress(family: .ipv4, bytes: Array(bytes.suffix(Family.ipv4.byteCount)))
    }
}
