import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// Phase 2 coverage for `Capability` and the registration primitive
/// `MultiTool.Builder.register(noun:tool:)` — eventplan.md § "Registration of
/// capabilities: noun/verb".
///
/// The grammar of a path is fixed: `tools.<noun>.<verb>`. The capability
/// gives the noun one time. Each `Tool` gives its own verb through
/// `Tool.name`. These tests hold the builder to that grammar, and to the
/// three failures that `buildRegistry()` must report: an illegal noun, one
/// verb that two capabilities give under the same noun, and a second
/// registration under a noun that a capability already owns.
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

    @Test("two capabilities with the same noun and different verbs make buildRegistry() throw")
    func twoCapabilitiesClaimingOneNounThrow() throws {
        // A capability owns its whole noun, so the two verbs need not collide.
        // `demo.first` and `demo.second` are different paths, and the second
        // claim on `demo` is the failure all the same.
        let first = FixtureCapability(noun: "demo", tools: [DemoFirstTool()])
        let second = SecondCapability(noun: "demo", tools: [DemoSecondTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(first)
                .withCapability(second)
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == "demo"
        }
    }

    @Test("the error of a second claim on one noun names the noun and both capabilities")
    func twoCapabilitiesClaimingOneNounNameBothClaimants() throws {
        let first = FixtureCapability(noun: "demo", tools: [DemoFirstTool()])
        let second = SecondCapability(noun: "demo", tools: [DemoSecondTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(first)
                .withCapability(second)
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.message.contains("demo")
                && builderError.message.contains("FixtureCapability")
                && builderError.message.contains("SecondCapability")
        }
    }

    @Test("a capability and an addGroup(named:) call that use one noun make buildRegistry() throw")
    func capabilityAndGroupUnderOneNounThrow() throws {
        let capability = FixtureCapability(noun: "demo", tools: [DemoFirstTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(capability)
                .addGroup(named: "demo", [DemoSecondTool()])
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == "demo"
        }
    }

    @Test("a capability and a standalone tool that use one name make buildRegistry() throw")
    func capabilityAndStandaloneToolUnderOneNameThrow() throws {
        // `DemoFirstTool` has the name `demo` nowhere, so the standalone tool
        // here is the capability's own noun spelled as a flat entry.
        let capability = FixtureCapability(noun: "first", tools: [DemoSecondTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(capability)
                .addTool(DemoFirstTool())
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == "first"
        }
    }

    @Test("the files capability and a second registration named files make buildRegistry() throw")
    func filesCapabilityAndSecondFilesRegistrationThrow() throws {
        // eventplan.md § "Registration of capabilities: noun/verb": "An MCP
        // server with the name `files`, against the files capability, fails
        // loudly at buildRegistry()." The server registers through the
        // primitive `register(noun:tool:)`, and its verb is its own.
        let files = FixtureCapability(noun: "files", tools: [DemoFirstTool()])

        #expect {
            try MultiTool.Builder()
                .withCapability(files)
                .register(noun: "files", tool: DemoSecondTool())
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == "files"
        }
    }
}
