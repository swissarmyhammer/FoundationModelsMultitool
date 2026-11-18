// `MCPServersGraphTests` — the behavioral suite of the `mcpServers` GraphQL
// endpoint: the toolkit conformance, the schema golden file, each query and
// mutation, the coded errors, the refusal of an external client, the secrets,
// and the change subscription.
//
// Each case uses its own registry over an `InMemoryMCPServerStorage`. No case
// reads a clock or waits for a time.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for ``MCPServersGraph``.
@Suite("MCPServersGraphTests", .timeLimit(.minutes(1)))
struct MCPServersGraphTests {

    // MARK: - Fixtures

    /// A secret value that no response may hold.
    private static let token = "s3cr3t-t0ken-value"

    /// A stdio server.
    private static let github = MCPServerEntry(
        name: "github",
        transport: .stdio(command: "/usr/local/bin/github-mcp", args: ["--stdio"], env: ["LOG": "info"]))

    /// An http server, turned off.
    private static let linear = MCPServerEntry(
        name: "linear",
        transport: .http(url: "https://mcp.linear.app/mcp", headers: ["Authorization": "keychain:linear-token"]),
        enabled: false)

    /// The selection of each server that a case reads.
    private static let selection =
        "{ name enabled transport command args env { name value secret } url headers { name value secret } }"

    /// The external client of a case.
    private static let externalViewer = GraphQLViewer.external()

    /// The registry, its storage and its endpoint, for one case.
    private struct Setup {
        /// The storage.
        let storage: InMemoryMCPServerStorage

        /// The Keychain port.
        let secrets = MCPServerSecretsTests.RecordingSecrets()

        /// The registry.
        let registry: MCPServerRegistry

        /// The endpoint.
        let graph: MCPServersGraph

        /// Makes a setup whose storage holds `entries`.
        ///
        /// - Parameter entries: The first servers.
        init(_ entries: [MCPServerEntry] = [MCPServersGraphTests.github, MCPServersGraphTests.linear]) {
            storage = InMemoryMCPServerStorage(entries)
            registry = MCPServerRegistry(storage: storage, reservedNames: ["files"], secrets: secrets)
            graph = MCPServersGraph.endpoint(of: registry)
        }

    }

    // MARK: - The endpoint contract

    @Test("the endpoint is mcpServers, version 1, with the server scope, one endpoint for each registry")
    func theEndpointFacts() {
        let setup = Setup()

        #expect(setup.graph.name == "mcpServers")
        #expect(setup.graph.version == "1")
        #expect(setup.graph.scope == .server)
        #expect(MCPServersGraph.endpoint(of: setup.registry) === setup.graph)
    }

    @Test("the endpoint conforms, with the listMCPServers and mcpServerChanges alias probes")
    func theEndpointConforms() async throws {
        let setup = Setup()
        let cursor = try await GraphQLReply.cursor(of: setup.graph)
        try await setup.registry.setEnabled(true, named: "linear")
        let probes = [
            GraphQLAliasProbe(query: "{ listMCPServers { name } }", from: "listMCPServers", to: "mcpServers"),
            GraphQLAliasProbe(
                query: "subscription($after: String) { mcpServerChanges(after: $after) { name } }",
                variables: ["after": .string(cursor)], from: "mcpServerChanges", to: "changes", kind: .subscription),
        ]

        let problems = await GraphQLEndpointConformance.problems(
            of: setup.graph, scope: .server, probes: probes, codes: MCPServersRefusal.codes, clock: ManualRunClock())

        #expect(problems.isEmpty, "problems: \(problems)")
    }

    @Test("the schema matches the golden file")
    func theSchemaMatchesTheGoldenFile() {
        let goldenFile = RepositoryFile.root
            .appendingPathComponent("Tests/FoundationModelsMultitoolTests/Goldens")
            .appendingPathComponent("mcpServers.graphql")

        let problems = GraphQLSchemaGolden.problems(of: Setup().graph.schema, against: goldenFile)

        #expect(problems.isEmpty, "problems: \(problems)")
    }

    // MARK: - Queries

    @Test("mcpServers gives each server in its stored order, with each field")
    func mcpServersGivesEachServer() async throws {
        let setup = Setup()

        let servers = try await GraphQLReply.run("{ mcpServers \(Self.selection) }", on: setup.graph).list("mcpServers")

        #expect(servers.compactMap { $0["name"] as? String } == ["github", "linear"])
        #expect(servers[0]["transport"] as? String == "STDIO")
        #expect(servers[0]["command"] as? String == "/usr/local/bin/github-mcp")
        #expect(servers[0]["args"] as? [String] == ["--stdio"])
        #expect(servers[1]["transport"] as? String == "HTTP")
        #expect(servers[1]["enabled"] as? Bool == false)
        let header = try #require((servers[1]["headers"] as? [[String: Any]])?.first)
        #expect(header["value"] as? String == "keychain:linear-token")
        #expect(header["secret"] as? Bool == true)
    }

    @Test("mcpServer gives one server, or null for an unknown name")
    func mcpServerGivesOneServer() async throws {
        let setup = Setup()

        let known = try await GraphQLReply.run("{ mcpServer(name: \"linear\") { name url } }", on: setup.graph).object(
            "mcpServer")
        let unknown = try await GraphQLReply.run("{ mcpServer(name: \"absent\") { name } }", on: setup.graph)

        #expect(known["url"] as? String == "https://mcp.linear.app/mcp")
        #expect(unknown.isNull("mcpServer"))
    }

    // MARK: - Mutations

    @Test("addMCPServer with a header secret stores the value in the Keychain port and shows only the reference")
    func addWithASecret() async throws {
        let setup = Setup([])

        let reply = try await GraphQLReply.run(
            "mutation { addMCPServer(input: {name: \"remote\", url: \"https://example.com/mcp\", "
                + "headerSecrets: [{name: \"Authorization\", value: \"\(Self.token)\"}]}) \(Self.selection) }",
            on: setup.graph)
        let stored = String(decoding: try JSONEncoder().encode(try await setup.storage.loadServers()), as: UTF8.self)

        #expect(reply.codes.isEmpty, "messages: \(reply.messages)")
        let header = try #require((try reply.object("addMCPServer")["headers"] as? [[String: Any]])?.first)
        #expect(header["value"] as? String == "keychain:mcp.remote.header.Authorization")
        #expect(setup.secrets.stored.withLock { $0 } == ["mcp.remote.header.Authorization": Self.token])
        #expect(!stored.contains(Self.token))
    }

    @Test("updateMCPServer renames and changes the args in place; setMCPServerEnabled and removeMCPServer change one")
    func updateEnableAndRemove() async throws {
        let setup = Setup()

        let update = try await GraphQLReply.run(
            "mutation { updateMCPServer(input: {name: \"github\", newName: \"gh\", args: [\"--verbose\"]}) "
                + "{ name args } }", on: setup.graph)
        let enable = try await GraphQLReply.run(
            "mutation { setMCPServerEnabled(input: {name: \"linear\", enabled: true}) { enabled } }", on: setup.graph)
        let remove = try await GraphQLReply.run(
            "mutation { removeMCPServer(input: {name: \"gh\"}) { name } }", on: setup.graph)

        #expect(try update.object("updateMCPServer")["args"] as? [String] == ["--verbose"])
        #expect(try enable.object("setMCPServerEnabled")["enabled"] as? Bool == true)
        #expect(try remove.object("removeMCPServer")["name"] as? String == "gh")
        #expect(try await setup.storage.loadServers().map(\.name) == ["linear"])
    }

    /// One refused mutation and its code.
    struct RefusalCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test report.
        let testDescription: String

        /// The mutation.
        let document: String

        /// The code.
        let code: String
    }

    /// Each kind of refusal of the registry, as a coded error.
    static let refusalCases: [RefusalCase] = [
        RefusalCase(
            testDescription: "a duplicate name",
            document: "mutation { addMCPServer(input: {name: \"github\", command: \"/bin/x\"}) { name } }",
            code: "DUPLICATE_NAME"),
        RefusalCase(
            testDescription: "a reserved name",
            document: "mutation { addMCPServer(input: {name: \"files\", command: \"/bin/x\"}) { name } }",
            code: "INVALID_NAME"),
        RefusalCase(
            testDescription: "a relative command",
            document: "mutation { addMCPServer(input: {name: \"local\", command: \"npx\"}) { name } }",
            code: "INVALID_INPUT"),
        RefusalCase(
            testDescription: "a command and a url",
            document: "mutation { addMCPServer(input: {name: \"x\", command: \"/bin/x\", url: \"https://a.b\"}) "
                + "{ name } }",
            code: "INVALID_INPUT"),
        RefusalCase(
            testDescription: "a literal header",
            document: "mutation { addMCPServer(input: {name: \"x\", url: \"https://a.b\", "
                + "headers: [{name: \"Authorization\", value: \"abc\"}]}) { name } }",
            code: "INVALID_INPUT"),
        RefusalCase(
            testDescription: "an unknown server",
            document: "mutation { removeMCPServer(input: {name: \"absent\"}) { name } }",
            code: "NOT_FOUND"),
    ]

    @Test("a refusal of the registry is a coded error, and nothing changes", arguments: refusalCases)
    func aRefusalIsACodedError(_ refusal: RefusalCase) async throws {
        let setup = Setup()

        let reply = try await GraphQLReply.run(refusal.document, on: setup.graph)

        #expect(reply.codes == [refusal.code], "messages: \(reply.messages)")
        #expect(try await setup.storage.loadServers() == [Self.github, Self.linear])
    }

    @Test("an external client can read and change no MCP server")
    func anExternalClientIsRefused() async throws {
        let setup = Setup()

        let list = try await GraphQLReply.run("{ mcpServers { name } }", viewer: Self.externalViewer, on: setup.graph)
        let remove = try await GraphQLReply.run(
            "mutation { removeMCPServer(input: {name: \"github\"}) { name } }", viewer: Self.externalViewer,
            on: setup.graph)

        #expect(list.codes == ["UNTRUSTED_CLIENT"])
        #expect(remove.codes == ["UNTRUSTED_CLIENT"])
        #expect(try await setup.storage.loadServers().count == 2)
    }

    // MARK: - Changes

    @Test("each change gives one row: the kind, the name, the name before a rename, and the server")
    func eachChangeGivesOneRow() async throws {
        let setup = Setup()
        let cursor = try await GraphQLReply.cursor(of: setup.graph)
        var responses = try await setup.graph.subscribe(
            query: "subscription($after: String) { changes(after: $after) { cursor kind name previousName "
                + "server { name enabled transport } } }",
            variables: ["after": .string(cursor)], operationName: nil, viewer: nil
        ).makeAsyncIterator()

        _ = try await GraphQLReply.run(
            "mutation { updateMCPServer(input: {name: \"github\", newName: \"gh\"}) { name } }", on: setup.graph)
        _ = try await GraphQLReply.run(
            "mutation { setMCPServerEnabled(input: {name: \"gh\", enabled: false}) { name } }", on: setup.graph)
        _ = try await GraphQLReply.run(
            "mutation { removeMCPServer(input: {name: \"linear\"}) { name } }", on: setup.graph)
        var changes: [[String: Any]] = []
        for _ in 0..<3 {
            changes.append(try GraphQLReply(json: try #require(try await responses.next())).object("changes"))
        }

        #expect(changes.map { $0["kind"] as? String } == ["UPDATED", "UPDATED", "REMOVED"])
        #expect(changes.map { $0["name"] as? String } == ["gh", "gh", "linear"])
        #expect(changes.map { $0["previousName"] as? String } == ["github", "gh", "linear"])
        #expect((changes[1]["server"] as? [String: Any])?["enabled"] as? Bool == false)
    }
}
