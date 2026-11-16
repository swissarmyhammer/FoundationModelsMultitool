// `MCPServersTool` — the `mcpServers` tool: the model lists, shows, adds,
// edits, removes, and turns on or off one MCP server of the host at a time
// (D100: the agent can do what the UI can). It is an operation tool over the
// same `MCPServerRegistry` as the `mcpServers` GraphQL endpoint, and it gives
// that endpoint in its `graphQLEndpoints`.
//
// Two rules keep the user in control:
//
// - An add, or an edit that changes the command, the args or the url, makes
//   the host run another program or reach another server. The tool asks the
//   user to approve it before it saves. A decline changes nothing.
// - The model never gives a secret value. It names the header or the env
//   variable that needs a secret, and the Keychain port of the host asks the
//   user for the value outside the transcript. A result shows the name of a
//   secret, never its value.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Asks the user to approve a change of an MCP server.
///
/// - Parameter message: The change, in words that the user reads.
/// - Returns: True when the user approves it.
public typealias MCPServerApprover = @Sendable (_ message: String) async -> Bool

/// The `mcpServers` tool over one ``MCPServerRegistry``.
public struct MCPServersTool: Tool, OperationDescribing {
    /// The raw payload: an `op` and the fields of one operation.
    public typealias Arguments = GeneratedContent

    /// The answer of the operation, or a corrective text.
    public typealias Output = String

    /// The model-facing name of the tool.
    static let toolName = "mcpServers"

    /// The description that the model reads.
    static let toolDescription = """
        Manage the MCP servers of this Mac, one at a time: list, show, add, edit, remove, enable and disable. \
        The user approves each server that you add, and each new command, args or url. Never put a secret in a \
        field, and never ask the user to type a secret in this conversation: name the header or env variable in \
        secretHeaders or secretEnv. When the host cannot ask for the value, make the change with no secret, and \
        ask the user to add the secret to the MCP server in the app.
        """

    /// The approver that asks the user through an elicitation of the
    /// current tool call: a form with no field, which the user accepts or
    /// declines. With no tool call, or with no answer, the change is not
    /// approved.
    public static let askTheUser: MCPServerApprover = { message in
        guard let context = ToolContext.current else {
            return false
        }
        let request = ElicitationRequest(
            message: message, elicitationId: ULID(), requestedSchema: ElicitationRequestedSchema(properties: [:]),
            source: toolName)
        guard let answer = try? await context.elicit(request) else {
            return false
        }
        return answer.action == .accept
    }

    /// The verb aliases of the tool over the defaults of the resolver: the
    /// verbs of the tool stay, and the usual other words go to them.
    static let verbAliases: [String: String] = [
        "show": "show", "get": "show", "remove": "remove", "delete": "remove", "rm": "remove", "update": "edit",
        "change": "edit", "create": "add", "new": "add",
    ]

    /// The tool that resolves and dispatches each call.
    let operationTool: OperationTool<MCPServersToolContext>

    /// The endpoint over the same registry.
    private let endpoint: MCPServersGraph

    /// Makes the tool over a registry.
    ///
    /// - Parameters:
    ///   - registry: The registry. Give the same registry to each tool and
    ///     endpoint of one host, so each client sees one change log.
    ///   - approve: Asks the user to approve a change that runs another
    ///     program or reaches another server. The default is
    ///     ``askTheUser``.
    /// - Throws: The error of `OperationTool.init` when the schema of the
    ///   operations cannot be fused.
    public init(registry: MCPServerRegistry, approve: @escaping MCPServerApprover = askTheUser) throws {
        endpoint = MCPServersGraph.endpoint(of: registry)
        operationTool = try OperationTool(
            name: Self.toolName,
            description: Self.toolDescription,
            context: MCPServersToolContext(registry: registry, approve: approve),
            operations: [
                AnyOperation(ListMCPServers.self),
                AnyOperation(ShowMCPServer.self),
                AnyOperation(AddMCPServer.self),
                AnyOperation(EditMCPServer.self),
                AnyOperation(RemoveMCPServer.self),
                AnyOperation(EnableMCPServer.self),
                AnyOperation(DisableMCPServer.self),
            ],
            resolver: OperationResolver(verbAliases: Self.verbAliases))
    }

    /// The model-facing name of the tool: `mcpServers`.
    public var name: String {
        operationTool.name
    }

    /// The description that the model reads.
    public var description: String {
        operationTool.description
    }

    /// The fused schema of the operations.
    public var parameters: GenerationSchema {
        operationTool.parameters
    }

    /// Whether FoundationModels puts ``parameters`` into the prompt.
    public var includesSchemaInInstructions: Bool {
        operationTool.includesSchemaInInstructions
    }

    /// One descriptor for each operation, in tool order.
    public var operationDescriptors: [OperationDescriptor] {
        operationTool.operationDescriptors
    }

    /// Resolves `arguments` to one operation and dispatches it.
    ///
    /// - Parameter arguments: The payload of the model.
    /// - Returns: The plain-text answer, or a corrective text.
    /// - Throws: The error of `OperationTool.call(arguments:)`.
    public func call(arguments: GeneratedContent) async throws -> String {
        Self.plainText(of: try await operationTool.call(arguments: arguments))
    }

    /// Dispatches one operation for a host, as a `runCode` verb does.
    ///
    /// - Parameter arguments: The payload with the `op` key and the fields.
    /// - Returns: The plain-text answer, or a corrective text.
    /// - Throws: The refusal of `OperationTool.perform(_:)`.
    public func perform(_ arguments: GeneratedContent) async throws -> String {
        Self.plainText(of: try await operationTool.perform(arguments))
    }

    /// The plain text of an answer of the operation tool, which encodes the
    /// text of an operation as a JSON string.
    ///
    /// - Parameter answer: The answer.
    /// - Returns: The plain text.
    private static func plainText(of answer: String) -> String {
        (try? JSONDecoder().decode(String.self, from: Data(answer.utf8))) ?? answer
    }
}

extension MCPServersTool: GraphQLEndpointTool {
    /// One endpoint: ``MCPServersGraph`` over the registry of the tool.
    public var graphQLEndpoints: [any GraphQLEndpoint] {
        [endpoint]
    }
}

/// The shared context of the operations of the `mcpServers` tool.
struct MCPServersToolContext: Sendable {
    /// The registry.
    let registry: MCPServerRegistry

    /// Asks the user to approve a change.
    let approve: MCPServerApprover

    /// Runs the work of an operation, and gives the text of a refusal as
    /// the answer.
    ///
    /// - Parameter work: The work.
    /// - Returns: The answer, or the corrective text of a refusal.
    func answer(_ work: () async throws -> String) async -> String {
        do {
            return try await work()
        } catch let refusal as MCPServerRegistryError {
            return refusal.description
        } catch let refusal as MCPServersToolRefusal {
            return refusal.text
        } catch {
            return "The change of the MCP servers failed: \(error.localizedDescription). Nothing changed."
        }
    }

    /// Asks the user to approve a change, and throws when the user declines.
    ///
    /// - Parameter message: The change, in words that the user reads.
    /// - Throws: ``MCPServersToolRefusal`` for a decline.
    func requireApproval(_ message: String) async throws {
        guard await approve(message) else {
            throw MCPServersToolRefusal(
                text: "The user did not approve the change. Nothing changed. Do not try again unless the user asks.")
        }
    }
}

/// A call that the `mcpServers` tool refuses, with its corrective text.
struct MCPServersToolRefusal: Error {
    /// The corrective text.
    let text: String
}
