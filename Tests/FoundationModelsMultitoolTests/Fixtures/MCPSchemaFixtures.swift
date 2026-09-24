import Foundation
import MCP

// MARK: - MCP schema fixtures
//
// The two `SchemaConverter` suites read a corpus of real-world MCP tool
// `inputSchema` documents from `MCPFixtures/`, which `Package.swift` declares
// as a `.copy` resource of this target. This one loader is what both suites
// read a fixture through, thus the folder name has one home. `TestResource`
// holds the lookup and the decode step.

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
    try TestResource.bundledJSON(Value.self, named: fixtureName, in: mcpFixturesSubdirectory)
}
