import Foundation
import Testing

@testable import FoundationModelsMultitool

/// A resolver that gives fixed addresses for each host name.
///
/// The tests use it in place of `getaddrinfo`, thus no test uses the network.
private struct StubResolver: HostResolver {
    /// The address texts that each host name resolves to.
    let table: [String: [String]]

    /// The error that a lookup of a host with no row gives.
    struct UnknownHost: Error {}

    /// The error that an address text that does not parse gives.
    struct BadAddressText: Error {}

    func addresses(for host: String) async throws -> [IPAddress] {
        guard let texts = table[host] else { throw UnknownHost() }
        return try texts.map { text in
            guard let address = IPAddress(literal: text) else { throw BadAddressText() }
            return address
        }
    }
}

/// A resolver that records an issue when the guard calls it.
///
/// A test that gives a literal IP host uses it. Thus the test proves that the
/// guard checks a literal IP host without a resolver call.
private struct UnexpectedResolver: HostResolver {
    /// The error that each call gives.
    struct UnexpectedCall: Error {}

    func addresses(for host: String) async throws -> [IPAddress] {
        Issue.record("The guard called the resolver for the literal host \(host).")
        throw UnexpectedCall()
    }
}

/// Tests for `WebAddressGuard.check(_:)`: the scheme, the user info, the host
/// blocklist, the host suffixes, and each address that the host resolves to.
///
/// The resolver is a stub in each test, thus no test uses the network.
@Suite("WebAddressGuard")
struct WebAddressGuardTests {
    /// The host name that the stub resolves to the address under test.
    private static let testHost = "addresses.example"

    /// Makes a guard whose resolver gives `addresses` for ``testHost``.
    private static func guardResolving(_ addresses: [String]) -> WebAddressGuard {
        WebAddressGuard(resolver: StubResolver(table: [testHost: addresses]))
    }

    /// Checks `http://<testHost>/` with a guard whose resolver gives `addresses`.
    private static func checkTestHost(resolvingTo addresses: [String]) async throws
        -> WebGuardRefusal? {
        let url = try #require(URL(string: "http://\(testHost)/"))
        return await guardResolving(addresses).check(url)
    }

    /// Checks `text` with a guard whose resolver must not be called.
    private static func checkLiteral(_ text: String) async throws -> WebGuardRefusal? {
        let url = try #require(URL(string: text))
        return await WebAddressGuard(resolver: UnexpectedResolver()).check(url)
    }

    // MARK: - Allowed

    @Test("https://example.com with a public address is allowed")
    func publicHostIsAllowed() async throws {
        let url = try #require(URL(string: "https://example.com"))
        let guardian = WebAddressGuard(
            resolver: StubResolver(table: ["example.com": ["93.184.215.14"]]))
        #expect(await guardian.check(url) == nil)
    }

    @Test("an upper-case scheme and host are allowed")
    func upperCaseSchemeIsAllowed() async throws {
        let url = try #require(URL(string: "HTTPS://EXAMPLE.COM/"))
        let guardian = WebAddressGuard(
            resolver: StubResolver(table: ["example.com": ["93.184.215.14"]]))
        #expect(await guardian.check(url) == nil)
    }

    @Test(
        "a public address next to a blocked range is allowed",
        arguments: [
            "9.255.255.255", "11.0.0.1", "100.63.255.255", "100.128.0.1", "126.255.255.255",
            "128.0.0.1", "169.253.255.255", "169.255.0.1", "172.15.255.255", "172.32.0.1",
            "192.167.255.255", "192.169.0.1", "198.17.255.255", "198.20.0.1",
            "223.255.255.255", "2606:4700::1111", "fec0::1", "fbff:ffff::1",
            "::ffff:93.184.215.14"
        ]
    )
    func publicAddressIsAllowed(address: String) async throws {
        #expect(try await Self.checkTestHost(resolvingTo: [address]) == nil)
    }

    @Test("a literal public IP host is allowed without a resolver call")
    func literalPublicHostIsAllowed() async throws {
        #expect(try await Self.checkLiteral("http://93.184.215.14/") == nil)
        #expect(try await Self.checkLiteral("http://[2606:4700::1111]/") == nil)
    }

    // MARK: - Scheme and user info

    @Test(
        "a scheme that is not http or https is refused",
        arguments: ["ftp://example.com/file", "file:///etc/passwd", "gopher://example.com/"])
    func badSchemeIsRefused(text: String) async throws {
        let refusal = try #require(try await Self.checkLiteral(text))
        let scheme = try #require(URL(string: text)?.scheme)
        #expect(refusal.correctiveMessage.contains("scheme \(scheme)"))
    }

    @Test(
        "a URL with user info is refused, and the message does not show the password",
        arguments: ["http://user:secret-word@example.com/", "https://user@example.com/"])
    func userInfoIsRefused(text: String) async throws {
        let refusal = try #require(try await Self.checkLiteral(text))
        #expect(refusal.correctiveMessage.contains("user info"))
        #expect(refusal.correctiveMessage.contains("example.com"))
        #expect(!refusal.correctiveMessage.contains("secret-word"))
    }

    @Test("a URL with no host is refused")
    func missingHostIsRefused() async throws {
        let refusal = try #require(try await Self.checkLiteral("http:///path"))
        #expect(refusal.correctiveMessage.contains("no host"))
    }

    // MARK: - Host names

    @Test(
        "each host on the blocklist is refused",
        arguments: [
            ("http://localhost/", "localhost"),
            ("http://127.0.0.1/", "127.0.0.1"),
            ("http://[::1]/", "::1"),
            ("http://0.0.0.0/", "0.0.0.0"),
            ("http://169.254.169.254/latest/meta-data/", "169.254.169.254"),
            ("http://metadata.google.internal/", "metadata.google.internal"),
            ("http://metadata.azure.com/", "metadata.azure.com"),
            ("http://instance-data.ec2.internal/", "instance-data.ec2.internal"),
            ("http://LOCALHOST./", "localhost")
        ])
    func blockedHostIsRefused(text: String, host: String) async throws {
        let refusal = try #require(try await Self.checkLiteral(text))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: the host \(host) is on the blocklist.")
    }

    @Test(
        "each blocked host suffix is refused",
        arguments: [
            ("http://printer.local/", "printer.local", ".local"),
            ("http://app.localhost/", "app.localhost", ".localhost"),
            ("http://db.internal/", "db.internal", ".internal"),
            ("http://Printer.Local./", "printer.local", ".local")
        ])
    func blockedSuffixIsRefused(text: String, host: String, suffix: String) async throws {
        let refusal = try #require(try await Self.checkLiteral(text))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: the host \(host) ends in \(suffix).")
    }

    // MARK: - Resolved addresses

    @Test("the message names the host, the address, and the kind of address")
    func messageNamesHostAndAddress() async throws {
        let url = try #require(URL(string: "http://localtest.me/"))
        let guardian = WebAddressGuard(
            resolver: StubResolver(table: ["localtest.me": ["127.0.0.1"]]))
        let refusal = try #require(await guardian.check(url))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: localtest.me resolves to 127.0.0.1, a loopback address."
        )
    }

    @Test(
        "each blocked IPv4 range is refused",
        arguments: [
            ("0.1.2.3", "a this-network address"),
            ("10.0.0.1", "a private address"),
            ("10.255.255.255", "a private address"),
            ("100.64.0.1", "a shared address"),
            ("100.127.255.255", "a shared address"),
            ("127.0.0.1", "a loopback address"),
            ("127.255.0.9", "a loopback address"),
            ("169.254.0.1", "a link-local address"),
            ("172.16.0.1", "a private address"),
            ("172.31.255.255", "a private address"),
            ("192.168.1.1", "a private address"),
            ("198.18.0.1", "a benchmark address"),
            ("198.19.255.255", "a benchmark address"),
            ("224.0.0.1", "a multicast address"),
            ("239.255.255.255", "a multicast address"),
            ("240.0.0.1", "a reserved address"),
            ("255.255.255.254", "a reserved address"),
            ("255.255.255.255", "a broadcast address")
        ])
    func blockedIPv4IsRefused(address: String, kind: String) async throws {
        let refusal = try #require(try await Self.checkTestHost(resolvingTo: [address]))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: \(Self.testHost) resolves to \(address), \(kind).")
    }

    @Test(
        "each blocked IPv6 class is refused",
        arguments: [
            ("::1", "a loopback address"),
            ("::", "an unspecified address"),
            ("ff02::1", "a multicast address"),
            ("ff0e::1", "a multicast address"),
            ("fc00::1", "a unique local address"),
            ("fd12:3456::1", "a unique local address"),
            ("fe80::1", "a link-local address"),
            ("febf::1", "a link-local address")
        ])
    func blockedIPv6IsRefused(address: String, kind: String) async throws {
        let refusal = try #require(try await Self.checkTestHost(resolvingTo: [address]))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: \(Self.testHost) resolves to \(address), \(kind).")
    }

    @Test(
        "an IPv4-mapped IPv6 address is checked as IPv4",
        arguments: [
            ("::ffff:127.0.0.1", "a loopback address"),
            ("::ffff:10.0.0.1", "a private address"),
            ("::ffff:169.254.169.254", "a link-local address")
        ])
    func mappedIPv4IsRefused(address: String, kind: String) async throws {
        let refusal = try #require(try await Self.checkTestHost(resolvingTo: [address]))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: \(Self.testHost) resolves to \(address), \(kind).")
    }

    @Test(
        "a host with one public and one private address is refused",
        arguments: [
            ["93.184.215.14", "10.0.0.1"],
            ["10.0.0.1", "93.184.215.14"],
            ["93.184.215.14", "2606:4700::1111", "fe80::1"]
        ])
    func oneBlockedAddressAmongManyIsRefused(addresses: [String]) async throws {
        let refusal = try #require(try await Self.checkTestHost(resolvingTo: addresses))
        #expect(refusal.correctiveMessage.contains(Self.testHost))
    }

    @Test(
        "a literal IP host in a blocked range is refused without a resolver call",
        arguments: [
            ("http://10.0.0.1/", "10.0.0.1", "a private address"),
            ("http://[fe80::1]/", "fe80::1", "a link-local address"),
            ("http://[::ffff:192.168.0.1]/", "::ffff:192.168.0.1", "a private address")
        ])
    func literalBlockedHostIsRefused(text: String, address: String, kind: String) async throws {
        let refusal = try #require(try await Self.checkLiteral(text))
        #expect(
            refusal.correctiveMessage == "The address is not allowed: \(address) is \(kind).")
    }

    @Test("a host that does not resolve is refused")
    func unresolvedHostIsRefused() async throws {
        let url = try #require(URL(string: "http://nothing.example/"))
        let refusal = try #require(await WebAddressGuard(resolver: StubResolver(table: [:])).check(url))
        #expect(
            refusal.correctiveMessage == "The address is not allowed: nothing.example does not resolve.")
    }

    @Test("a host that resolves to no address is refused")
    func hostWithNoAddressIsRefused() async throws {
        let refusal = try #require(try await Self.checkTestHost(resolvingTo: []))
        #expect(
            refusal.correctiveMessage
                == "The address is not allowed: \(Self.testHost) does not resolve.")
    }

    @Test("the refusal is a corrective failure with the same message")
    func refusalIsCorrectiveFailure() async throws {
        let refusal = try #require(try await Self.checkLiteral("ftp://example.com/"))
        let failure: any CorrectiveFailure = refusal
        #expect(failure.correctiveMessage == refusal.correctiveMessage)
    }

    // MARK: - The default resolver

    @Test("the default guard checks a literal IP host")
    func defaultGuardChecksLiteralHost() async throws {
        let url = try #require(URL(string: "http://10.1.2.3/"))
        let refusal = try #require(await WebAddressGuard().check(url))
        #expect(refusal.correctiveMessage == "The address is not allowed: 10.1.2.3 is a private address.")
    }

    @Test(
        "the system resolver gives the address of a numeric host",
        arguments: ["127.0.0.1", "::1", "fe80::1"])
    func systemResolverParsesNumericHost(text: String) async throws {
        let addresses = try await SystemHostResolver().addresses(for: text)
        #expect(addresses.map(\.description).contains(text))
    }

    @Test("an IP address shows its standard text")
    func addressDescriptionIsStandardText() throws {
        let long = try #require(IPAddress(literal: "2001:0db8:0000:0000:0000:0000:0000:0001"))
        #expect(long.description == "2001:db8::1")
        #expect(IPAddress(literal: "not an address") == nil)
    }
}
