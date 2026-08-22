import FoundationModels
import FoundationModelsMultitool

// MARK: - Phase 2 `Capability` / `Builder.withCapability(_:)` fixtures
// (eventplan.md § "Registration of capabilities: noun/verb")
//
// The noun/verb grammar needs two parts. The capability gives the noun. The
// `Tool` conformer gives the verb, because `Tool.name` is the verb. These
// fixtures give one capability type and two tools with the verb names
// `first` and `second`.
//
// `StringArgument` and `PlainTextOutput` come from
// `ToolAPIRendererFixtures.swift` in this same test target.

/// A fixture tool with the verb `first`.
///
/// The name is the verb, and the verb is the only part of the path that a
/// tool gives. This tool has a name that no other fixture in this target
/// uses. Thus a path that holds `first` can come only from this tool.
struct DemoFirstTool: Tool {
    let name = "first"
    let description = "Does the first demonstration operation."

    func call(arguments: StringArgument) async throws -> PlainTextOutput {
        PlainTextOutput(text: arguments.value)
    }
}

/// A fixture tool with the verb `second`.
///
/// This tool is the second tool of the fixture capability. Two tools show
/// that `withCapability(_:)` gives the one noun to each tool of the
/// capability, and not to the first tool only.
struct DemoSecondTool: Tool {
    let name = "second"
    let description = "Does the second demonstration operation."

    func call(arguments: StringArgument) async throws -> PlainTextOutput {
        PlainTextOutput(text: arguments.value)
    }
}

/// A `Capability` that holds its noun and its tools as stored properties.
///
/// One fixture type is sufficient for each test in
/// `CapabilityRegistrationTests`. A capability is only a noun plus its
/// tools. Thus a test that must change the noun, or change the tools, gives
/// different values to this same type. A new type for each test would give
/// no more test coverage.
struct FixtureCapability: Capability {
    /// The one noun that each tool of this capability renders under.
    let noun: String

    /// The tools of this capability. Each tool gives its own verb.
    let tools: [any Tool]
}
