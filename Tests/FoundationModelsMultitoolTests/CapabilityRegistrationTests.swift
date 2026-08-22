import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// Phase 2 coverage for `Capability` and the registration primitive
/// `MultiTool.Builder.register(noun:tool:)` — eventplan.md § "Registration of
/// capabilities: noun/verb".
///
/// The grammar of a path is fixed: `tools.<noun>.<verb>`. The capability
/// gives the noun one time. Each `Tool` gives its own verb through
/// `Tool.name`. These tests hold the builder to that grammar, and to the two
/// failures that `buildRegistry()` must report: an illegal noun, and one
/// verb that two capabilities give under the same noun.
@Suite("CapabilityRegistration")
struct CapabilityRegistrationTests {
    @Test("withCapability(_:) renders one tools.<noun>.<verb> entry for each tool of the capability")
    func capabilityRendersOneEntryForEachTool() throws {
        let capability = FixtureCapability(noun: "demo", tools: [DemoFirstTool(), DemoSecondTool()])

        let surface = try MultiTool.Builder()
            .withCapability(capability)
            .build()

        #expect(surface.entries.map(\.path) == ["demo.first", "demo.second"])
        #expect(surface.entries.allSatisfy { $0.group == "demo" })
    }

    @Test("register(noun:tool:) renders the tool at tools.<noun>.<Tool.name>")
    func registerRendersTheToolUnderTheNoun() throws {
        let registry = try MultiTool.Builder()
            .register(noun: "demo", tool: DemoFirstTool())
            .buildRegistry()

        #expect(registry.surface.entries.map(\.path) == ["demo.first"])
        // The live tool is reachable at the same path the surface states, so
        // a snippet that reads the surface can call what it read.
        let live = try #require(registry.tools["demo.first"])
        #expect(live is DemoFirstTool)
    }

    @Test("a capability whose noun is not a legal TypeScript identifier makes buildRegistry() throw")
    func illegalNounThrows() throws {
        let capability = FixtureCapability(noun: "bad noun!", tools: [DemoFirstTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(capability)
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .illegalGroupName && builderError.name == "bad noun!"
        }
    }

    @Test("two capabilities with the same noun and the same verb make buildRegistry() throw")
    func duplicateNounAndVerbThrows() throws {
        // An MCP server named after a capability that exists is the case
        // eventplan.md names. Both give the noun `demo`, and both give the
        // verb `first`, so `tools.demo.first` has two meanings.
        let capability = FixtureCapability(noun: "demo", tools: [DemoFirstTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(capability)
                .withCapability(capability)
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName && builderError.name == "first"
        }
    }
}
