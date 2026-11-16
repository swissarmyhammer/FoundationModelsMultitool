// `MCPServersGraph` — the `mcpServers` GraphQL endpoint: the MCP servers of
// the host for the clients of the host, one item at a time, over the same
// `MCPServerRegistry` that the `mcpServers` tool changes.
//
// A device of the user and the agent read and change the servers. An external
// client reads and changes none, because an MCP server runs a program on the
// Mac. A secret value of a mutation goes only to the Keychain port of the
// registry, and each response shows only the `keychain:` reference.

import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL
import Synchronization

/// The `mcpServers` GraphQL endpoint over one ``MCPServerRegistry``.
public final class MCPServersGraph: GraphQLEndpoint {
    /// The name of the endpoint.
    public static let endpointName = "mcpServers"

    /// The most changes that the change log keeps.
    static let changeLogCapacity = 256

    /// The name rules: the aliases of the endpoint.
    static let rules = GraphQLNameRules(
        aliases: GraphQLAliasTable(
            byType: [
                "Query": ["mcpServers": ["listMCPServers", "servers"], "mcpServer": ["getMCPServer", "server"]],
                "Mutation": [
                    "addMCPServer": ["createMCPServer"], "updateMCPServer": ["editMCPServer"],
                    "removeMCPServer": ["deleteMCPServer"],
                ],
                "Subscription": ["changes": ["mcpServerChanges"]],
            ],
            byField: [:]))

    /// The name of the endpoint.
    public let name = endpointName

    /// The version of the schema.
    public let version = "1"

    /// The scope: the host has one list of MCP servers.
    public let scope = GraphQLEndpointScope.server

    /// The registry.
    let registry: MCPServerRegistry

    /// The change log, which the changes of the registry feed.
    private let log: ChangeLog<MCPServerChange>

    /// The task that feeds the change log.
    private let feed: Task<Void, Never>

    /// Makes the endpoint of a registry. The endpoint subscribes to the
    /// changes of the registry before it returns.
    ///
    /// - Parameter registry: The registry.
    private init(registry: MCPServerRegistry) {
        self.registry = registry
        let changes = registry.changes()
        let log = ChangeLog<MCPServerChange>(capacity: Self.changeLogCapacity)
        self.log = log
        feed = Task {
            for await change in changes {
                _ = await log.append(change)
            }
        }
    }

    deinit {
        feed.cancel()
    }

    /// The one endpoint of a registry. Each call for the same registry gives
    /// the same endpoint while it lives, so each client reads one change log.
    ///
    /// - Parameter registry: The registry.
    /// - Returns: The endpoint.
    public static func endpoint(of registry: MCPServerRegistry) -> MCPServersGraph {
        let key = ObjectIdentifier(registry)
        return endpoints.withLock { endpoints in
            endpoints = endpoints.filter { $0.value.endpoint != nil }
            if let endpoint = endpoints[key]?.endpoint {
                return endpoint
            }
            let endpoint = MCPServersGraph(registry: registry)
            endpoints[key] = WeakEndpoint(endpoint: endpoint)
            return endpoint
        }
    }

    /// The SDL of the schema.
    public var schema: String {
        switch MCPServersGraphAPI.builtSchema {
        case .success(let built): printSchema(schema: built.schema)
        case .failure: ""
        }
    }

    /// Runs a query or a mutation.
    ///
    /// - Parameters:
    ///   - query: The document.
    ///   - variables: The values of the variables.
    ///   - operationName: The operation to run.
    ///   - viewer: The client of the call, or `nil` for the agent.
    /// - Returns: The JSON response.
    /// - Throws: An error of the engine.
    public func execute(
        query: String, variables: [String: Map], operationName: String?, viewer: GraphQLViewer?
    ) async throws -> String {
        try await api().respond(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: context(of: viewer))
    }

    /// Runs a subscription.
    ///
    /// - Parameters:
    ///   - query: The document.
    ///   - variables: The values of the variables.
    ///   - operationName: The operation to run.
    ///   - viewer: The client of the call, or `nil` for the agent.
    /// - Returns: The stream of the JSON responses.
    /// - Throws: An error of the engine.
    public func subscribe(
        query: String, variables: [String: Map], operationName: String?, viewer: GraphQLViewer?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await api().subscribe(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: context(of: viewer))
    }

    /// The context of one call.
    ///
    /// - Parameter viewer: The client of the call.
    /// - Returns: The context.
    private func context(of viewer: GraphQLViewer?) -> MCPServersGraphContext {
        MCPServersGraphContext(registry: registry, log: log, viewer: viewer)
    }

    /// The engine.
    ///
    /// - Returns: The engine.
    /// - Throws: The error of the schema build.
    private func api() throws -> MCPServersGraphAPI {
        MCPServersGraphAPI(schema: try MCPServersGraphAPI.builtSchema.get())
    }

    /// A weak reference to an endpoint.
    private struct WeakEndpoint {
        /// The endpoint.
        weak var endpoint: MCPServersGraph?
    }

    /// The live endpoint of each registry.
    private static let endpoints = Mutex<[ObjectIdentifier: WeakEndpoint]>([:])
}

// MARK: - Context and resolver

/// The context of one call of the `mcpServers` endpoint.
struct MCPServersGraphContext: GraphQLRunContext {
    /// The warnings of the call.
    let warnings = ResponseWarnings()

    /// The registry.
    let registry: MCPServerRegistry

    /// The change log of the endpoint.
    let log: ChangeLog<MCPServerChange>

    /// The client of the call, or `nil` for the agent.
    let viewer: GraphQLViewer?

    /// Checks that the client of the call may read and change the servers.
    ///
    /// - Throws: ``MCPServersRefusal`` with `UNTRUSTED_CLIENT` for an
    ///   external client.
    func requireTrusted() throws {
        guard viewer?.trust != .external else {
            throw MCPServersRefusal(kind: .untrustedClient, message: MCPServersRefusal.untrustedText)
        }
    }

    /// Runs the work of a trusted call, with each refusal of the registry as
    /// a coded error.
    ///
    /// - Parameter work: The work.
    /// - Returns: The result of the work.
    /// - Throws: The coded error of a refusal, and each other error.
    func trusted<Result>(_ work: () async throws -> Result) async throws -> Result {
        try requireTrusted()
        do {
            return try await work()
        } catch let error as MCPServerRegistryError {
            throw MCPServersRefusal.coded(error)
        }
    }
}

/// The root resolver of the `mcpServers` endpoint. It holds no state.
struct MCPServersGraphResolver: Sendable {
    /// Resolves `Query.mcpServers`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The servers, in their stored order.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func mcpServers(context: MCPServersGraphContext, arguments _: NoArguments) async throws -> [MCPServersGraphServer] {
        try await context.trusted { try await context.registry.list().map(MCPServersGraphServer.init) }
    }

    /// Resolves `Query.mcpServer`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The name of the server.
    /// - Returns: The server, or `nil` when no server has the name.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func mcpServer(
        context: MCPServersGraphContext, arguments: MCPServersGraphNameArguments
    ) async throws -> MCPServersGraphServer? {
        try await context.trusted {
            try await context.registry.server(named: arguments.name).map(MCPServersGraphServer.init)
        }
    }

    /// Resolves `Query.cursor`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The cursor of the newest change.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func cursor(context: MCPServersGraphContext, arguments _: NoArguments) async throws -> String {
        try context.requireTrusted()
        return await context.log.cursor
    }

    /// Resolves `Mutation.addMCPServer`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The new server.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func addMCPServer(
        context: MCPServersGraphContext, arguments: MCPServersGraphMutationArguments<MCPServersGraphAddInput>
    ) async throws -> MCPServersGraphServer {
        let input = arguments.input
        return try await context.trusted {
            let secrets = mcpServersGraphSecrets(headers: input.headerSecrets, env: input.envSecrets)
            return MCPServersGraphServer(try await context.registry.add(try input.entry(), secrets: secrets))
        }
    }

    /// Resolves `Mutation.updateMCPServer`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The server after the change.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func updateMCPServer(
        context: MCPServersGraphContext, arguments: MCPServersGraphMutationArguments<MCPServersGraphUpdateInput>
    ) async throws -> MCPServersGraphServer {
        let input = arguments.input
        return try await context.trusted {
            let secrets = mcpServersGraphSecrets(headers: input.headerSecrets, env: input.envSecrets)
            return MCPServersGraphServer(
                try await context.registry.update(named: input.name, with: input.update, secrets: secrets))
        }
    }

    /// Resolves `Mutation.removeMCPServer`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The server as it was.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func removeMCPServer(
        context: MCPServersGraphContext, arguments: MCPServersGraphMutationArguments<MCPServersGraphRemoveInput>
    ) async throws -> MCPServersGraphServer {
        try await context.trusted {
            MCPServersGraphServer(try await context.registry.remove(named: arguments.input.name))
        }
    }

    /// Resolves `Mutation.setMCPServerEnabled`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The server after the change.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func setMCPServerEnabled(
        context: MCPServersGraphContext, arguments: MCPServersGraphMutationArguments<MCPServersGraphEnableInput>
    ) async throws -> MCPServersGraphServer {
        try await context.trusted {
            MCPServersGraphServer(
                try await context.registry.setEnabled(arguments.input.enabled, named: arguments.input.name))
        }
    }

    /// Resolves the source stream of `Subscription.changes`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The cursor to resume after.
    /// - Returns: The stream of the entries after the cursor.
    /// - Throws: ``MCPServersRefusal`` for an external client, the coded
    ///   error of a refusal of the registry, and each error of the storage.
    func changes(
        context: MCPServersGraphContext, arguments: MCPServersGraphChangesArguments
    ) async throws -> ChangeLog<MCPServerChange>.Changes {
        try context.requireTrusted()
        return await context.log.changes(after: arguments.after)
    }
}
