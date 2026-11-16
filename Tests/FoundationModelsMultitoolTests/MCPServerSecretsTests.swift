// `MCPServerSecretsTests` — the behavioral suite of the secrets of the MCP
// server registry (D101): a secret value goes only to the Keychain port of
// the host, and the storage, the change events and the error texts hold only
// `keychain:` references.

import Foundation
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the secrets of ``MCPServerRegistry``.
@Suite("MCPServerSecretsTests")
struct MCPServerSecretsTests {

    // MARK: - Fixtures

    /// A secret value that no stored text may hold.
    private static let token = "s3cr3t-t0ken-value"

    /// The Keychain port of a test: it records each stored value, and
    /// answers each request with a fixed answer.
    final class RecordingSecrets: MCPServerSecrets {
        /// The value of each stored Keychain item, by its name.
        let stored = Mutex<[String: String]>([:])

        /// True when the user gives each requested secret.
        let userGives: Bool

        /// Makes a port.
        ///
        /// - Parameter userGives: True when the user gives each requested
        ///   secret.
        init(userGives: Bool = true) {
            self.userGives = userGives
        }

        /// Records the value and gives the reference of the name scheme.
        func store(_ value: String, server: String, key: MCPSecretKey) async throws -> String {
            stored.withLock { $0[key.keychainItemName(server: server)] = value }
            return key.keychainReference(server: server)
        }

        /// Gives the reference of the name scheme, or `nil` for a decline.
        func request(server: String, key: MCPSecretKey) async throws -> String? {
            guard userGives else {
                return nil
            }
            stored.withLock { $0[key.keychainItemName(server: server)] = MCPServerSecretsTests.token }
            return key.keychainReference(server: server)
        }
    }

    /// An http server with no header.
    private static let remote = MCPServerEntry(
        name: "remote", transport: .http(url: "https://example.com/mcp", headers: [:]))

    /// A stdio server with one plain env value.
    private static let local = MCPServerEntry(
        name: "local", transport: .stdio(command: "/usr/local/bin/local-mcp", args: [], env: ["LOG": "info"]))

    /// The text of each stored server and each change: the texts in which
    /// no secret value may show.
    ///
    /// - Parameters:
    ///   - storage: The storage.
    ///   - changes: The changes.
    /// - Returns: The texts.
    private static func texts(
        of storage: InMemoryMCPServerStorage, _ changes: [MCPServerChange]
    ) async throws -> String {
        let encoded = try JSONEncoder().encode(try await storage.loadServers())
        return String(decoding: encoded, as: UTF8.self) + changes.map { "\($0)" }.joined()
    }

    // MARK: - Store

    @Test("add with a header secret stores the value in the port, and only the reference in the storage and event")
    func addStoresTheSecretInThePort() async throws {
        let storage = InMemoryMCPServerStorage()
        let secrets = RecordingSecrets()
        let registry = MCPServerRegistry(storage: storage, secrets: secrets)
        var events = registry.changes().makeAsyncIterator()

        let added = try await registry.add(Self.remote, secrets: [.header("Authorization"): Self.token])
        let event = try #require(await events.next())

        #expect(added.transport == .http(url: "https://example.com/mcp", headers: [
            "Authorization": "keychain:mcp.remote.header.Authorization"
        ]))
        #expect(secrets.stored.withLock { $0 } == ["mcp.remote.header.Authorization": Self.token])
        #expect(try await !Self.texts(of: storage, [event]).contains(Self.token))
    }

    @Test("update with an env secret keeps the other env values and stores only the reference")
    func updateStoresTheSecretInThePort() async throws {
        let storage = InMemoryMCPServerStorage([Self.local])
        let secrets = RecordingSecrets()
        let registry = MCPServerRegistry(storage: storage, secrets: secrets)

        let updated = try await registry.update(
            named: "local", with: MCPServerUpdate(), secrets: [.env("API_TOKEN"): Self.token])

        #expect(updated.transport == .stdio(command: "/usr/local/bin/local-mcp", args: [], env: [
            "LOG": "info", "API_TOKEN": "keychain:mcp.local.env.API_TOKEN",
        ]))
        #expect(try await !Self.texts(of: storage, []).contains(Self.token))
    }

    @Test("a refused add stores no secret")
    func aRefusedAddStoresNoSecret() async throws {
        let secrets = RecordingSecrets()
        let registry = MCPServerRegistry(storage: InMemoryMCPServerStorage([Self.remote]), secrets: secrets)

        await #expect(throws: MCPServerRegistryError.duplicateName("remote")) {
            try await registry.add(Self.remote, secrets: [.header("Authorization"): Self.token])
        }
        #expect(secrets.stored.withLock { $0 }.isEmpty)
    }

    @Test("a header secret for a stdio server is conflictingTransport, and stores nothing")
    func aSecretOfTheOtherTransport() async throws {
        let secrets = RecordingSecrets()
        let registry = MCPServerRegistry(storage: InMemoryMCPServerStorage(), secrets: secrets)

        await #expect(throws: MCPServerRegistryError.conflictingTransport(server: "local")) {
            try await registry.add(Self.local, secrets: [.header("Authorization"): Self.token])
        }
        #expect(secrets.stored.withLock { $0 }.isEmpty)
    }

    @Test("a secret value with no port is noSecretStore, and the error text has no value")
    func aSecretWithNoPort() async throws {
        let registry = MCPServerRegistry(storage: InMemoryMCPServerStorage())

        do {
            try await registry.add(Self.remote, secrets: [.header("Authorization"): Self.token])
            Issue.record("the add did not throw")
        } catch let error as MCPServerRegistryError {
            #expect(error == .noSecretStore)
            #expect(!error.description.contains(Self.token))
        }
    }

    // MARK: - Request

    @Test("requestSecrets gives a reference for each key that the user gives")
    func requestSecretsGivesReferences() async throws {
        let registry = MCPServerRegistry(storage: InMemoryMCPServerStorage(), secrets: RecordingSecrets())

        let references = try await registry.requestSecrets([.header("Authorization")], server: "remote")

        #expect(references == [.header("Authorization"): "keychain:mcp.remote.header.Authorization"])
    }

    @Test("requestSecrets of a declined key is secretDeclined")
    func requestSecretsOfADeclinedKey() async throws {
        let registry = MCPServerRegistry(
            storage: InMemoryMCPServerStorage(), secrets: RecordingSecrets(userGives: false))

        await #expect(throws: MCPServerRegistryError.secretDeclined(server: "remote", key: .header("Authorization"))) {
            try await registry.requestSecrets([.header("Authorization")], server: "remote")
        }
    }
}
