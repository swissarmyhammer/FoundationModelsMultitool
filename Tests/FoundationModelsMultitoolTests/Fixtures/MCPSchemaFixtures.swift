import Foundation
import MCP
import Testing

// MARK: - MCP schema fixtures
//
// The two `SchemaConverter` suites read a corpus of real-world MCP tool
// `inputSchema` documents from `MCPFixtures/`, which `Package.swift` declares
// as a `.copy` resource of this target. This one loader is what both suites
// read a fixture through, thus the folder name and the decode step have one
// home.

/// The bundled folder that holds each MCP `inputSchema` fixture.
private let mcpFixturesSubdirectory = "MCPFixtures"

/// Loads one MCP tool `inputSchema` fixture from the bundled `MCPFixtures/` folder.
///
/// - Parameter fixtureName: The file name of the fixture, without its `.json`
///   extension.
/// - Returns: The fixture, decoded as the raw `Value` the MCP swift-sdk hands
///   a client from `tools/list`.
/// - Throws: When the fixture is not bundled with the test target, or when its
///   bytes do not decode as a `Value`.
func loadMCPSchemaFixture(_ fixtureName: String) throws -> Value {
    let url = try #require(
        Bundle.module.url(
            forResource: fixtureName,
            withExtension: "json",
            subdirectory: mcpFixturesSubdirectory
        ),
        "\(fixtureName).json fixture must be bundled with the test target"
    )
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Value.self, from: data)
}
