import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Tests for `MultiTool.currentRegistry`. A host builds the tools of a
/// sub-agent run from this registry. Then the sub-agent sees the catalog that
/// the root session has now, not the catalog from build time.
@Suite("CurrentRegistryTests")
struct CurrentRegistryTests {

    /// The rendered path of `CitiesTool`.
    private static let citiesPath = "getCities"

    /// The rendered path of `TempTool`.
    private static let temperaturePath = "getTemperature"

    /// The `runCode` tool that `makeSessionTools` mounts, found by type.
    private static func runCode(in tools: [any Tool]) throws -> MultiTool {
        try #require(tools.compactMap { $0 as? MultiTool }.first)
    }

    /// A registry over `CitiesTool` alone, mounted. Returns the root `runCode`
    /// and the staging half of its holder.
    private static func mountedRoot() throws -> (root: MultiTool, staging: any RegistryStaging) {
        let registry = try MultiTool.Builder(mode: .open).addTool(CitiesTool()).buildRegistry()
        let (tools, staging) = try registry.makeSessionToolsAndStaging(selection: nil)
        return (try runCode(in: tools), staging)
    }

    /// A registry over `TempTool` alone.
    private static func temperatureRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder(mode: .open).addTool(TempTool()).buildRegistry()
    }

    @Test("a sub-agent built from currentRegistry after a catalog change sees the new verbs")
    func freshSubAgentSeesTheCatalogChange() async throws {
        let (root, staging) = try Self.mountedRoot()
        staging.stage(try Self.temperatureRegistry())
        await root.submissionWillBegin()

        let subTools = try root.currentRegistry.makeSessionTools(selection: nil)

        let paths = try await helpPaths(of: Self.runCode(in: subTools))
        #expect(paths == [Self.temperaturePath])
    }

    @Test("a sub-agent restored after a catalog change builds from the registry that is current at restore time")
    func restoredSubAgentSeesTheCatalogChange() async throws {
        let (root, staging) = try Self.mountedRoot()
        let beforeChange = try root.currentRegistry.makeSessionTools(selection: nil)
        staging.stage(try Self.temperatureRegistry())
        await root.submissionWillBegin()

        let restored = try root.currentRegistry.makeSessionTools(selection: nil)

        let pathsBefore = try await helpPaths(of: Self.runCode(in: beforeChange))
        let pathsRestored = try await helpPaths(of: Self.runCode(in: restored))
        #expect(pathsBefore == [Self.citiesPath])
        #expect(pathsRestored == [Self.temperaturePath])
    }
}
