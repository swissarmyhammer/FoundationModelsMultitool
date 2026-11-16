// `OperationInferenceTests` — which operations of the `sessions` and the
// `mcpServers` tools run for a call with no `op`.
//
// The resolver of Extras infers an operation from the keys of a call only
// when the operation declares `isInferable`. Only an operation that reads
// declares it. An operation that changes something (it starts a session,
// sends a message, marks a message read, renames, edits or removes) runs
// only when the call names its `op`.

import Foundation
import FoundationModels
import Operations
import Testing

@testable import FoundationModelsMultitool

/// Tests of the `isInferable` flag of each operation.
@Suite("OperationInferenceTests")
struct OperationInferenceTests {

    /// The operations that only read, so a call with no `op` can run them.
    private static let readOperations: [any OperationDefinition.Type] = [
        ListSessions.self, CheckSession.self, ListMCPServers.self, ShowMCPServer.self,
    ]

    /// The operations that change something, so each needs its `op`.
    private static let changeOperations: [any OperationDefinition.Type] = [
        StartSession.self, ReadInbox.self, SendMessage.self, ReplyMessage.self, TagSession.self,
        UntagSession.self, RenameSession.self, PinSession.self, UnpinSession.self, ArchiveSession.self,
        AddMCPServer.self, EditMCPServer.self, RemoveMCPServer.self, EnableMCPServer.self,
        DisableMCPServer.self,
    ]

    @Test("only an operation that reads is inferable")
    func onlyReadOperationsAreInferable() {
        #expect(Self.readOperations.allSatisfy { $0.isInferable })
        #expect(Self.changeOperations.allSatisfy { !$0.isInferable })
    }

    @Test("a call with no op and a name shows the MCP server, and a call with no op that edits changes nothing")
    func anOpLessCallOfTheMCPServersTool() async throws {
        let entry = MCPServerEntry(
            name: "github", transport: .stdio(command: "/usr/local/bin/github-mcp", args: [], env: [:]))
        let storage = InMemoryMCPServerStorage([entry])
        let tool = try MCPServersTool(registry: MCPServerRegistry(storage: storage)) { _ in true }

        let shown = try await tool.call(arguments: GeneratedContent(properties: ["name": "github"]))
        let edited = try await tool.call(
            arguments: GeneratedContent(properties: ["name": "github", "newName": "gh"]))

        #expect(shown.hasPrefix("- github"), "output was: \(shown)")
        #expect(!edited.contains("Changed MCP server"), "output was: \(edited)")
        #expect(try await storage.loadServers() == [entry])
    }
}
