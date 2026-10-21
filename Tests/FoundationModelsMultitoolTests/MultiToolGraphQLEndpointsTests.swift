import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsMultitool

/// Coverage for EXTRAS-7 / D82: the top-level `runCode` tool is a
/// `GraphQLEndpointTool`, and it gives the endpoints of its capabilities.
///
/// A host reads endpoints only from its top-level tool list, so this is the
/// one way a host finds the endpoint of a capability that the registry
/// flattens into verbs. Each case reaches the endpoints through a cast from
/// `any Tool`, the same way a host reaches them.
@Suite("MultiToolGraphQLEndpointsTests")
struct MultiToolGraphQLEndpointsTests {

    // MARK: - Fixtures

    /// A `GraphQLEndpoint` that only describes itself. No case runs a
    /// document, so each run gives an empty response.
    struct StubEndpoint: GraphQLEndpoint {
        /// The name of the endpoint.
        let name: String

        /// The version of the schema of the endpoint.
        let version: String

        /// The scope of the endpoint.
        let scope: GraphQLEndpointScope

        /// The schema of the endpoint in SDL.
        let schema = "type Query { ping: String }"

        /// Gives an empty response: no case runs a document.
        func execute(
            query _: String,
            variables _: [String: Map],
            operationName _: String?,
            viewer _: GraphQLViewer?
        ) async throws -> String {
            "{}"
        }

        /// Gives a stream that ends at once: no case subscribes.
        func subscribe(
            query _: String,
            variables _: [String: Map],
            operationName _: String?,
            viewer _: GraphQLViewer?
        ) async throws -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in continuation.finish() }
        }
    }

    /// A plain tool that gives the endpoints it holds.
    struct EndpointTool: GraphQLEndpointTool {
        /// The verb of the tool under the noun of its capability.
        let name: String

        /// The description the surface renders.
        let description = "A tool that gives GraphQL endpoints."

        /// The endpoints of the tool.
        let graphQLEndpoints: [any GraphQLEndpoint]

        /// Gives the name of the tool: no case calls it.
        func call(arguments _: NoArguments) async throws -> String {
            name
        }
    }

    /// An operation tool that gives the endpoints it holds, as `SettingsTool`
    /// does. Every operation goes to the wrapped ``NotesOperationTool``.
    struct EndpointOperationTool: OperationDescribing, GraphQLEndpointTool {
        /// The name of the tool. The noun of the mount replaces it on the surface.
        let name = "notesWithEndpoints"

        /// The tool that holds the operations and the store.
        let notes = NotesOperationTool()

        /// The endpoints of the tool.
        let graphQLEndpoints: [any GraphQLEndpoint]

        var description: String { notes.description }

        var operationDescriptors: [OperationDescriptor] { notes.operationDescriptors }

        func call(arguments: NotesCallArguments) async throws -> String {
            try await notes.call(arguments: arguments)
        }

        func perform(_ arguments: GeneratedContent) async throws -> String {
            try await notes.perform(arguments)
        }
    }

    /// A capability over the tools it holds.
    struct EndpointCapability: Capability {
        /// The noun of the capability.
        let noun: String

        /// The tools of the capability.
        let tools: [any Tool]
    }

    // MARK: - Shared test values

    /// The name two endpoints share in the repeat case.
    private static let sharedName = "kanban"

    /// The verb of each ``EndpointTool``.
    private static let verb = "query"

    /// An endpoint of the session folder.
    private static let boardEndpoint = StubEndpoint(name: sharedName, version: "1", scope: .sessionFolder)

    /// An endpoint with the name and the scope of ``boardEndpoint``, and
    /// another version.
    private static let repeatedBoardEndpoint = StubEndpoint(
        name: sharedName, version: "2", scope: .sessionFolder)

    /// An endpoint with the name of ``boardEndpoint`` and another scope.
    private static let serverBoardEndpoint = StubEndpoint(name: sharedName, version: "1", scope: .server)

    /// An endpoint of the settings of the server.
    private static let settingsEndpoint = StubEndpoint(name: "settings", version: "1", scope: .server)

    /// An endpoint of the snapshots of the session folder.
    private static let snapshotsEndpoint = StubEndpoint(name: "snapshots", version: "1", scope: .sessionFolder)

    // MARK: - Helpers

    /// A capability under `noun` whose one tool gives `endpoints`.
    ///
    /// - Parameters:
    ///   - noun: The noun of the capability.
    ///   - endpoints: The endpoints of its tool.
    /// - Returns: The capability.
    private static func capability(_ noun: String, giving endpoints: [any GraphQLEndpoint]) -> EndpointCapability {
        EndpointCapability(noun: noun, tools: [EndpointTool(name: verb, graphQLEndpoints: endpoints)])
    }

    /// The descriptions of the endpoints that `multiTool` gives as an
    /// `any Tool`, the way a host reads them.
    ///
    /// - Parameter multiTool: The `runCode` tool.
    /// - Returns: The description of each endpoint, in order.
    /// - Throws: When the cast to `GraphQLEndpointTool` fails.
    private static func endpointDescriptions(of multiTool: MultiTool) throws -> [GraphQLEndpointDescription] {
        let tool: any Tool = multiTool
        let endpointTool = try #require(tool as? any GraphQLEndpointTool)
        return endpointTool.graphQLEndpoints.map(\.endpointDescription)
    }

    // MARK: - Cases

    @Test("a cast of runCode from any Tool to GraphQLEndpointTool succeeds")
    func castFromAnyToolSucceeds() throws {
        let tool: any Tool = MultiTool(registry: try MultiTool.Builder().buildRegistry())
        #expect(tool is any GraphQLEndpointTool)
    }

    @Test("a capability whose tool conforms gives its endpoints through runCode")
    func capabilityGivesItsEndpoints() throws {
        let registry = try MultiTool.Builder()
            .withCapability(Self.capability("snapshots", giving: [Self.snapshotsEndpoint]))
            .buildRegistry()

        #expect(
            try Self.endpointDescriptions(of: MultiTool(registry: registry))
                == [Self.snapshotsEndpoint.endpointDescription])
    }

    @Test("an operation tool mounted with withOperationTool gives its endpoints, although it renders as verbs")
    func operationToolGivesItsEndpoints() throws {
        let registry = try MultiTool.Builder()
            .withOperationTool(
                noun: "settings", tool: EndpointOperationTool(graphQLEndpoints: [Self.settingsEndpoint]))
            .buildRegistry()

        #expect(
            try Self.endpointDescriptions(of: MultiTool(registry: registry))
                == [Self.settingsEndpoint.endpointDescription])
    }

    @Test("two endpoints with one name and one scope give the first in capability order")
    func repeatedEndpointsKeepTheFirst() throws {
        let registry = try MultiTool.Builder()
            .withCapability(Self.capability("board", giving: [Self.boardEndpoint]))
            .withCapability(
                Self.capability("mirror", giving: [Self.repeatedBoardEndpoint, Self.serverBoardEndpoint]))
            .buildRegistry()

        #expect(
            try Self.endpointDescriptions(of: MultiTool(registry: registry))
                == [Self.boardEndpoint.endpointDescription, Self.serverBoardEndpoint.endpointDescription])
    }

    @Test("a registry with no endpoint gives none")
    func registryWithNoEndpointGivesNone() throws {
        let registry = try MultiTool.Builder()
            .withCapability(Self.capability("plain", giving: []))
            .addTool(CitiesTool())
            .buildRegistry()

        #expect(try Self.endpointDescriptions(of: MultiTool(registry: registry)).isEmpty)
    }

    @Test("direct mode keeps the endpoints of the registry")
    func directModeKeepsTheEndpoints() throws {
        let registry = try MultiTool.Builder()
            .withCapability(Self.capability("snapshots", giving: [Self.snapshotsEndpoint]))
            .buildRegistry()
            .directMode()

        #expect(
            try Self.endpointDescriptions(of: MultiTool(registry: registry))
                == [Self.snapshotsEndpoint.endpointDescription])
    }

    @Test("after a registry swap runCode gives the endpoints of the new registry")
    func registrySwapGivesTheNewEndpoints() async throws {
        let runCode = MultiTool(
            registry: try MultiTool.Builder()
                .withCapability(Self.capability("snapshots", giving: [Self.snapshotsEndpoint]))
                .buildRegistry())

        runCode.stage(
            try MultiTool.Builder()
                .withCapability(Self.capability("settings", giving: [Self.settingsEndpoint]))
                .buildRegistry())
        await runCode.submissionWillBegin()

        #expect(try Self.endpointDescriptions(of: runCode) == [Self.settingsEndpoint.endpointDescription])
    }
}
