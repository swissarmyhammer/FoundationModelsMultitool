// `MCPServersToolTests` — the behavioral suite of the `mcpServers` tool: each
// operation, the approval of the user for a change of what runs, the secrets
// that the user gives outside the transcript, the verb aliases, and the
// endpoint of the tool.
//
// Each case uses its own registry, a stub approver that records each question,
// and the recording Keychain port of `MCPServerSecretsTests`.

import Foundation
import FoundationModels
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for ``MCPServersTool``.
@Suite("MCPServersToolTests")
struct MCPServersToolTests {

    // MARK: - Fixtures

    /// A stdio server.
    private static let github = MCPServerEntry(
        name: "github",
        transport: .stdio(command: "/usr/local/bin/github-mcp", args: ["--stdio"], env: ["LOG": "info"]))

    /// The value that the recording Keychain port gives for each request.
    private static let secretValue = "s3cr3t-t0ken-value"

    /// The questions that a stub approver got, in order.
    final class Questions: Sendable {
        /// The questions.
        private let list = Mutex<[String]>([])

        /// Records a question.
        ///
        /// - Parameter question: The question.
        func record(_ question: String) {
            list.withLock { $0.append(question) }
        }

        /// The questions, in order.
        var all: [String] {
            list.withLock { $0 }
        }
    }

    /// The tool, its registry, its storage, its Keychain port and the
    /// questions of its approver, for one case.
    private struct Setup {
        /// The storage.
        let storage: InMemoryMCPServerStorage

        /// The Keychain port.
        let secrets = MCPServerSecretsTests.RecordingSecrets()

        /// The registry.
        let registry: MCPServerRegistry

        /// The questions that the approver got.
        let questions = Questions()

        /// The tool.
        let tool: MCPServersTool

        /// Makes a setup.
        ///
        /// - Parameters:
        ///   - entries: The first servers.
        ///   - userApproves: The answer of the approver.
        init(_ entries: [MCPServerEntry] = [MCPServersToolTests.github], userApproves: Bool = true) throws {
            storage = InMemoryMCPServerStorage(entries)
            registry = MCPServerRegistry(storage: storage, secrets: secrets)
            let questions = questions
            tool = try MCPServersTool(registry: registry) { message in
                questions.record(message)
                return userApproves
            }
        }

        /// Calls one operation.
        ///
        /// - Parameters:
        ///   - op: The op string.
        ///   - fields: The fields.
        /// - Returns: The answer.
        /// - Throws: What the tool throws.
        func call(_ op: String, _ fields: [(String, any ConvertibleToGeneratedContent)] = []) async throws -> String {
            try await tool.call(arguments: SessionsToolFixtures.payload(op, fields))
        }

        /// The stored servers.
        var stored: [MCPServerEntry] {
            get async throws { try await storage.loadServers() }
        }
    }

    // MARK: - Read

    @Test("list mcp servers gives one line for each server, with the names of the env and no value")
    func listGivesOneLineForEachServer() async throws {
        let setup = try Setup()

        let output = try await setup.call("list mcp servers")

        #expect(output.contains("- github (stdio, on): /usr/local/bin/github-mcp --stdio; env LOG"), "\(output)")
        #expect(!output.contains("info"), "output was: \(output)")
    }

    @Test("show mcp server of an unknown name gives the corrective of the registry")
    func showOfAnUnknownName() async throws {
        let setup = try Setup()

        let output = try await setup.call("show mcp server", [("name", "absent")])

        #expect(output == MCPServerRegistryError.unknownServer("absent").description)
    }

    // MARK: - Add

    @Test("add mcp server asks the user to approve the program, then adds the server")
    func addAsksForApproval() async throws {
        let setup = try Setup([])

        let output = try await setup.call(
            "add mcp server", [("name", "local"), ("command", "/usr/local/bin/local-mcp"), ("args", ["--fast"])])

        #expect(output.hasPrefix("Added MCP server - local (stdio, on)"), "output was: \(output)")
        #expect(setup.questions.all == [
            "The agent wants to add the MCP server \"local\": it runs the program /usr/local/bin/local-mcp --fast "
                + "on this Mac. Approve it?"
        ])
        #expect(try await setup.stored.map(\.name) == ["local"])
    }

    @Test("add mcp server that the user declines changes nothing")
    func addThatTheUserDeclines() async throws {
        let setup = try Setup([], userApproves: false)

        let output = try await setup.call("add mcp server", [("name", "remote"), ("url", "https://example.com/mcp")])

        #expect(output.contains("did not approve"), "output was: \(output)")
        #expect(try await setup.stored.isEmpty)
    }

    @Test("add mcp server that breaks a rule gives the corrective and asks no question")
    func addThatBreaksARule() async throws {
        let setup = try Setup([])

        let output = try await setup.call("add mcp server", [("name", "local"), ("command", "npx")])

        #expect(output == MCPServerRegistryError.relativeCommand(server: "local", command: "npx").description)
        #expect(setup.questions.all.isEmpty)
    }

    @Test("add mcp server with a secret header asks the user through the Keychain port, and shows no value")
    func addWithASecretHeader() async throws {
        let setup = try Setup([])

        let output = try await setup.call(
            "add mcp server",
            [("name", "remote"), ("url", "https://example.com/mcp"), ("secretHeaders", ["Authorization"])])

        #expect(output.contains("headers Authorization"), "output was: \(output)")
        #expect(!output.contains(Self.secretValue), "output was: \(output)")
        #expect(setup.secrets.stored.withLock { $0 } == ["mcp.remote.header.Authorization": Self.secretValue])
        #expect(try await setup.stored.first?.transport == .http(
            url: "https://example.com/mcp", headers: ["Authorization": "keychain:mcp.remote.header.Authorization"]))
    }

    // MARK: - Edit

    @Test("edit mcp server of the args asks for approval; a rename asks no question")
    func editAsksForApprovalOnlyForWhatRuns() async throws {
        let setup = try Setup()

        let rename = try await setup.call("edit mcp server", [("name", "github"), ("newName", "gh")])
        let questionsAfterRename = setup.questions.all.count
        let args = try await setup.call("edit mcp server", [("name", "gh"), ("args", ["--verbose"])])

        #expect(rename.hasPrefix("Changed MCP server - gh"), "output was: \(rename)")
        #expect(questionsAfterRename == 0)
        #expect(args.contains("/usr/local/bin/github-mcp --verbose"), "output was: \(args)")
        #expect(setup.questions.all.count == 1)
    }

    @Test("edit mcp server with an env value with no = gives a corrective")
    func editWithABadEnvValue() async throws {
        let setup = try Setup()

        let output = try await setup.call("edit mcp server", [("name", "github"), ("env", ["LOG"])])

        #expect(output.contains("NAME=value"), "output was: \(output)")
        #expect(try await setup.stored == [Self.github])
    }

    // MARK: - Remove and switch

    @Test("disable, enable and remove change one server and ask no question")
    func disableEnableAndRemove() async throws {
        let setup = try Setup()

        let off = try await setup.call("disable mcp server", [("name", "github")])
        let on = try await setup.call("enable mcp server", [("name", "github")])
        let removed = try await setup.call("remove mcp server", [("name", "github")])

        #expect(off.contains("(stdio, off)"), "output was: \(off)")
        #expect(on.contains("(stdio, on)"), "output was: \(on)")
        #expect(removed.hasPrefix("Removed MCP server github."), "output was: \(removed)")
        #expect([off, on, removed].allSatisfy { $0.hasSuffix(MCPServersToolText.nextSession) })
        #expect(try await setup.stored.isEmpty)
        #expect(setup.questions.all.isEmpty)
    }

    @Test("delete and get are aliases of remove and show")
    func theVerbAliases() async throws {
        let setup = try Setup()

        let shown = try await setup.call("get mcp server", [("name", "github")])
        let deleted = try await setup.call("delete mcp server", [("name", "github")])

        #expect(shown.hasPrefix("- github"), "output was: \(shown)")
        #expect(deleted.hasPrefix("Removed MCP server github."), "output was: \(deleted)")
    }

    // MARK: - The endpoint

    @Test("the tool gives the one mcpServers endpoint of its registry")
    func theToolGivesTheEndpoint() throws {
        let setup = try Setup()

        let endpoint = try #require(setup.tool.graphQLEndpoints.first as? MCPServersGraph)

        #expect(setup.tool.name == "mcpServers")
        #expect(endpoint === MCPServersGraph.endpoint(of: setup.registry))
    }

    @Test("the default approver approves nothing with no tool call")
    func theDefaultApproverWithNoToolCall() async {
        #expect(await MCPServersTool.askTheUser("Approve it?") == false)
    }
}
