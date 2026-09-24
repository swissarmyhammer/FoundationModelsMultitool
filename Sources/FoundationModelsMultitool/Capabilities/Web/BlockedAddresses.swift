// `BlockedAddresses` — the address ranges that the web capability's URL guard
// (`WebAddressGuard.swift`) refuses, with the kind of each range.

/// The kind of an address that the guard refuses.
///
/// The correction names the kind, thus the model knows why the address is not
/// allowed.
enum BlockedAddressKind: Sendable {
    /// `0.0.0.0/8`, an address of "this network".
    case thisNetwork
    /// `10/8`, `172.16/12`, and `192.168/16`.
    case privateNetwork
    /// `100.64/10`, the shared address space of carrier NAT.
    case shared
    /// `127/8` and `::1`.
    case loopback
    /// `169.254/16` and `fe80::/10`.
    case linkLocal
    /// `198.18/15`, the network for benchmark tests.
    case benchmark
    /// `224/4` and `ff00::/8`.
    case multicast
    /// `240/4`, the reserved addresses.
    case reserved
    /// `255.255.255.255`.
    case broadcast
    /// `::`.
    case unspecified
    /// `fc00::/7`.
    case uniqueLocal

    /// The phrase that the correction shows, for example `a loopback address`.
    var phrase: String {
        switch self {
        case .thisNetwork: "a this-network address"
        case .privateNetwork: "a private address"
        case .shared: "a shared address"
        case .loopback: "a loopback address"
        case .linkLocal: "a link-local address"
        case .benchmark: "a benchmark address"
        case .multicast: "a multicast address"
        case .reserved: "a reserved address"
        case .broadcast: "a broadcast address"
        case .unspecified: "an unspecified address"
        case .uniqueLocal: "a unique local address"
        }
    }
}

/// A range of addresses in CIDR form, for example `10.0.0.0/8`.
struct AddressBlock: Sendable {
    /// The first address of the range.
    let network: IPAddress

    /// The number of leading bits that each address of the range shares with
    /// ``network``.
    let prefixLength: Int

    /// Makes a range from its CIDR text.
    ///
    /// The text is a constant of this file. A text that does not parse is an
    /// error of the programmer, thus it stops the program.
    ///
    /// - Parameter cidr: The CIDR text, for example `10.0.0.0/8`.
    init(_ cidr: String) {
        guard
            let slash = cidr.firstIndex(of: "/"),
            let network = IPAddress(literal: String(cidr[..<slash])),
            let prefixLength = Int(cidr[cidr.index(after: slash)...]),
            (0...network.bytes.count * UInt8.bitWidth).contains(prefixLength)
        else {
            preconditionFailure("The CIDR text \(cidr) is not valid.")
        }
        self.network = network
        self.prefixLength = prefixLength
    }

    /// The IPv4-mapped IPv6 addresses, `::ffff:0.0.0.0/96`.
    static let ipv4Mapped = AddressBlock("::ffff:0.0.0.0/96")

    /// Tells if `address` is in the range.
    ///
    /// - Parameter address: The address to check.
    /// - Returns: `true` when `address` has the family of ``network`` and the
    ///   same first ``prefixLength`` bits.
    func contains(_ address: IPAddress) -> Bool {
        guard address.family == network.family else { return false }
        let wholeBytes = prefixLength / UInt8.bitWidth
        let remainingBits = prefixLength % UInt8.bitWidth
        guard address.bytes.prefix(wholeBytes) == network.bytes.prefix(wholeBytes) else {
            return false
        }
        guard remainingBits > 0 else { return true }
        let mask = UInt8.max << (UInt8.bitWidth - remainingBits)
        return address.bytes[wholeBytes] & mask == network.bytes[wholeBytes] & mask
    }
}

/// The address ranges that the guard refuses, with the kind of each range.
///
/// A namespace, and not a value: each member is `static`.
enum BlockedAddresses {
    /// The blocked ranges, in the order to check. A narrow range comes before
    /// a wide range that contains it, thus the broadcast address is not shown
    /// as a reserved address.
    static let ranges: [(block: AddressBlock, kind: BlockedAddressKind)] = [
        (AddressBlock("255.255.255.255/32"), .broadcast),
        (AddressBlock("0.0.0.0/8"), .thisNetwork),
        (AddressBlock("10.0.0.0/8"), .privateNetwork),
        (AddressBlock("100.64.0.0/10"), .shared),
        (AddressBlock("127.0.0.0/8"), .loopback),
        (AddressBlock("169.254.0.0/16"), .linkLocal),
        (AddressBlock("172.16.0.0/12"), .privateNetwork),
        (AddressBlock("192.168.0.0/16"), .privateNetwork),
        (AddressBlock("198.18.0.0/15"), .benchmark),
        (AddressBlock("224.0.0.0/4"), .multicast),
        (AddressBlock("240.0.0.0/4"), .reserved),
        (AddressBlock("::/128"), .unspecified),
        (AddressBlock("::1/128"), .loopback),
        (AddressBlock("ff00::/8"), .multicast),
        (AddressBlock("fc00::/7"), .uniqueLocal),
        (AddressBlock("fe80::/10"), .linkLocal)
    ]

    /// Finds the blocked kind of `address`.
    ///
    /// An IPv4-mapped IPv6 address is checked as its IPv4 address.
    ///
    /// - Parameter address: The address to check.
    /// - Returns: The kind of the first blocked range that contains the
    ///   address, or `nil` when the address is allowed.
    static func kind(of address: IPAddress) -> BlockedAddressKind? {
        let checked = address.mappedIPv4 ?? address
        return ranges.first { $0.block.contains(checked) }?.kind
    }
}
