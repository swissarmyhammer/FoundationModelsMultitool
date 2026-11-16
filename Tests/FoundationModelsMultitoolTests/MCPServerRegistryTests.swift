// `MCPServerRegistryTests` — the behavioral suite of `MCPServerRegistry`: the
// item API over the MCP servers of the host (one item at a time, not a
// rewrite of the whole list), its validation, its errors and its change
// events.
//
// Each case uses its own `InMemoryMCPServerStorage`. No case reads a clock or
// waits for a time.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for ``MCPServerRegistry``.
@Suite("MCPServerRegistryTests")
struct MCPServerRegistryTests {

    // MARK: - Fixtures

    /// A stdio server with one env value.
    private static let github = MCPServerEntry(
        name: "github",
        transport: .stdio(command: "/usr/local/bin/github-mcp", args: ["--stdio"], env: ["LOG": "info"]))

    /// An http server with one header reference.
    private static let linear = MCPServerEntry(
        name: "linear",
        transport: .http(url: "https://mcp.linear.app/mcp", headers: ["Authorization": "keychain:linear-token"]))

    /// The names that a host keeps for its own capabilities.
    private static let reserved: Set<String> = ["files", "shell"]

    /// A registry over a storage that holds `entries`.
    ///
    /// - Parameter entries: The first servers of the storage.
    /// - Returns: The storage and the registry.
    private static func registry(
        holding entries: [MCPServerEntry] = []
    ) -> (InMemoryMCPServerStorage, MCPServerRegistry) {
        let storage = InMemoryMCPServerStorage(entries)
        return (storage, MCPServerRegistry(storage: storage, reservedNames: reserved))
    }

    /// The error that `body` throws, as a registry error.
    ///
    /// - Parameter body: The call.
    /// - Returns: The error, or `nil` when the call does not throw a
    ///   registry error.
    private static func registryError(_ body: () async throws -> Void) async -> MCPServerRegistryError? {
        do {
            try await body()
            return nil
        } catch {
            return error as? MCPServerRegistryError
        }
    }

    // MARK: - Read

    @Test("list gives each server of the storage in its order, and server(named:) gives one")
    func listAndGet() async throws {
        let (_, registry) = Self.registry(holding: [Self.github, Self.linear])

        #expect(try await registry.list() == [Self.github, Self.linear])
        #expect(try await registry.server(named: "linear") == Self.linear)
        #expect(try await registry.server(named: "absent") == nil)
    }

    // MARK: - Add

    @Test("add appends the server, saves it, and the new server is enabled by default")
    func addSavesTheServer() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github])

        let added = try await registry.add(Self.linear)

        #expect(added == Self.linear)
        #expect(added.enabled)
        #expect(try await storage.loadServers() == [Self.github, Self.linear])
    }

    @Test("add of a name that a server has already is duplicateName, and nothing changes")
    func addOfADuplicateName() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github])
        var copy = Self.linear
        copy.name = "github"

        let error = await Self.registryError { _ = try await registry.add(copy) }

        #expect(error == .duplicateName("github"))
        #expect(try await storage.loadServers() == [Self.github])
    }

    /// One server that the registry refuses, and the error.
    struct InvalidCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test report.
        let testDescription: String

        /// The server.
        let entry: MCPServerEntry

        /// The error.
        let error: MCPServerRegistryError
    }

    /// Each rule of a valid server.
    static let invalidCases: [InvalidCase] = [
        InvalidCase(
            testDescription: "an upper-case name",
            entry: MCPServerEntry(name: "GitHub", transport: .stdio(command: "/bin/x", args: [], env: [:])),
            error: .invalidName("GitHub")),
        InvalidCase(
            testDescription: "a name with a dot",
            entry: MCPServerEntry(name: "git.hub", transport: .stdio(command: "/bin/x", args: [], env: [:])),
            error: .invalidName("git.hub")),
        InvalidCase(
            testDescription: "an empty name",
            entry: MCPServerEntry(name: "", transport: .stdio(command: "/bin/x", args: [], env: [:])),
            error: .invalidName("")),
        InvalidCase(
            testDescription: "a reserved name",
            entry: MCPServerEntry(name: "files", transport: .stdio(command: "/bin/x", args: [], env: [:])),
            error: .reservedName("files")),
        InvalidCase(
            testDescription: "a relative command",
            entry: MCPServerEntry(name: "local", transport: .stdio(command: "npx", args: [], env: [:])),
            error: .relativeCommand(server: "local", command: "npx")),
        InvalidCase(
            testDescription: "a url that is not http or https",
            entry: MCPServerEntry(name: "remote", transport: .http(url: "ftp://example.com", headers: [:])),
            error: .invalidURL(server: "remote", url: "ftp://example.com")),
        InvalidCase(
            testDescription: "a literal header value",
            entry: MCPServerEntry(
                name: "remote", transport: .http(url: "https://example.com/mcp", headers: ["Authorization": "abc"])),
            error: .literalSecret(server: "remote", key: .header("Authorization"))),
        InvalidCase(
            testDescription: "a keychain reference with no name",
            entry: MCPServerEntry(
                name: "remote", transport: .http(url: "https://example.com/mcp", headers: ["Token": "keychain:"])),
            error: .literalSecret(server: "remote", key: .header("Token"))),
    ]

    @Test("add refuses a server that breaks a rule, and saves nothing", arguments: invalidCases)
    func addRefusesAnInvalidServer(_ invalid: InvalidCase) async throws {
        let (storage, registry) = Self.registry()

        let error = await Self.registryError { _ = try await registry.add(invalid.entry) }

        #expect(error == invalid.error)
        #expect(try await storage.loadServers().isEmpty)
    }

    @Test("an error text names the key of a literal secret but never its value")
    func anErrorTextHasNoSecretValue() {
        let error = MCPServerRegistryError.literalSecret(server: "remote", key: .header("Authorization"))

        #expect(error.description.contains("Authorization"))
        #expect(error.description.contains("keychain:"))
    }

    // MARK: - Update

    @Test("update changes only the given fields of one server")
    func updateChangesOnlyTheGivenFields() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github, Self.linear])

        let updated = try await registry.update(named: "github", with: MCPServerUpdate(args: ["--stdio", "--verbose"]))

        let expected = MCPServerEntry(
            name: "github",
            transport: .stdio(
                command: "/usr/local/bin/github-mcp", args: ["--stdio", "--verbose"], env: ["LOG": "info"]))
        #expect(updated == expected)
        #expect(try await storage.loadServers() == [expected, Self.linear])
    }

    @Test("update with a new name renames the server in its place")
    func updateRenames() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github, Self.linear])

        let renamed = try await registry.update(named: "github", with: MCPServerUpdate(name: "gh"))

        #expect(renamed.name == "gh")
        #expect(try await storage.loadServers().map(\.name) == ["gh", "linear"])
    }

    @Test("update to the name of another server is duplicateName")
    func updateToADuplicateName() async throws {
        let (_, registry) = Self.registry(holding: [Self.github, Self.linear])

        let error = await Self.registryError {
            _ = try await registry.update(named: "github", with: MCPServerUpdate(name: "linear"))
        }

        #expect(error == .duplicateName("linear"))
    }

    @Test("update with a url changes a stdio server to an http server")
    func updateChangesTheTransport() async throws {
        let (_, registry) = Self.registry(holding: [Self.github])

        let updated = try await registry.update(
            named: "github", with: MCPServerUpdate(url: "https://api.github.com/mcp"))

        #expect(updated.transport == .http(url: "https://api.github.com/mcp", headers: [:]))
    }

    @Test("update with a command and a url is conflictingTransport")
    func updateWithTwoTransports() async throws {
        let (_, registry) = Self.registry(holding: [Self.github])

        let error = await Self.registryError {
            _ = try await registry.update(
                named: "github", with: MCPServerUpdate(command: "/bin/x", url: "https://example.com/mcp"))
        }

        #expect(error == .conflictingTransport(server: "github"))
    }

    @Test("update with headers for a stdio server is conflictingTransport")
    func updateWithKeysOfTheOtherTransport() async throws {
        let (_, registry) = Self.registry(holding: [Self.github])

        let error = await Self.registryError {
            _ = try await registry.update(named: "github", with: MCPServerUpdate(headers: ["A": "keychain:a"]))
        }

        #expect(error == .conflictingTransport(server: "github"))
    }

    @Test("update and remove of an unknown server are unknownServer")
    func unknownServer() async throws {
        let (_, registry) = Self.registry(holding: [Self.github])

        let update = await Self.registryError {
            _ = try await registry.update(named: "absent", with: MCPServerUpdate(enabled: false))
        }
        let remove = await Self.registryError { _ = try await registry.remove(named: "absent") }
        let enable = await Self.registryError { _ = try await registry.setEnabled(true, named: "absent") }

        #expect(update == .unknownServer("absent"))
        #expect(remove == .unknownServer("absent"))
        #expect(enable == .unknownServer("absent"))
    }

    // MARK: - Remove and enable

    @Test("remove takes out one server and gives it")
    func removeTakesOutOneServer() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github, Self.linear])

        let removed = try await registry.remove(named: "github")

        #expect(removed == Self.github)
        #expect(try await storage.loadServers() == [Self.linear])
    }

    @Test("setEnabled turns a server off and on")
    func setEnabledTurnsAServerOffAndOn() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github])

        let off = try await registry.setEnabled(false, named: "github")
        let stored = try await storage.loadServers()
        let on = try await registry.setEnabled(true, named: "github")

        #expect(off.enabled == false)
        #expect(stored.first?.enabled == false)
        #expect(on.enabled)
    }

    // MARK: - Another writer

    @Test("each change reads the storage again, so a change of another writer stays")
    func aChangeOfAnotherWriterStays() async throws {
        let (storage, registry) = Self.registry(holding: [Self.github])
        _ = try await registry.list()
        try await storage.saveServers([Self.github, Self.linear])

        _ = try await registry.setEnabled(false, named: "github")

        #expect(try await storage.loadServers().map(\.name) == ["github", "linear"])
    }

    // MARK: - Change events

    @Test("each change gives one event with the server after the change and the name before it")
    func eachChangeGivesOneEvent() async throws {
        let (_, registry) = Self.registry()
        var events = await registry.changes().makeAsyncIterator()

        _ = try await registry.add(Self.github)
        _ = try await registry.update(named: "github", with: MCPServerUpdate(name: "gh"))
        _ = try await registry.setEnabled(false, named: "gh")
        _ = try await registry.remove(named: "gh")

        var renamed = Self.github
        renamed.name = "gh"
        var disabled = renamed
        disabled.enabled = false
        #expect(await events.next() == .added(Self.github))
        #expect(await events.next() == .updated(renamed, previousName: "github"))
        #expect(await events.next() == .updated(disabled, previousName: "gh"))
        #expect(await events.next() == .removed(disabled))
    }

    @Test("a refused change gives no event")
    func aRefusedChangeGivesNoEvent() async throws {
        let (_, registry) = Self.registry(holding: [Self.github])
        var events = await registry.changes().makeAsyncIterator()

        _ = await Self.registryError { _ = try await registry.add(Self.github) }
        _ = try await registry.add(Self.linear)

        #expect(await events.next() == .added(Self.linear))
    }
}
