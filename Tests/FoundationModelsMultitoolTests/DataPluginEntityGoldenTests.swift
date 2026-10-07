import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Golden tests for the entities of the data-format plugins and the fallback
/// plugin: ``JSONParserPlugin``, ``YAMLParserPlugin``, ``TOMLParserPlugin``,
/// ``CSVParserPlugin``, ``MarkdownParserPlugin``, and
/// ``FallbackParserPlugin``.
///
/// `GitSemanticGoldens/entities/<format>-cases.json` holds the input cases:
/// a name, a file path, and the text of the file. A throwaway Rust program
/// read each case with the default registry of
/// `../swissarmyhammer/crates/swissarmyhammer-sem/` (`get_plugin` on the
/// path, then `extract_entities` inside `catch_unwind`, as the Rust differ
/// does) and wrote `<format>-expected.json`: the plugin id and every field of
/// each entity, the content hash included. serde_yaml_ng 0.10.0, toml
/// 1.1.2, and serde_json 1.0.150 were in its `Cargo.lock`.
@Suite("DataPluginEntityGoldenTests")
struct DataPluginEntityGoldenTests {

    /// The resource folder of the cases.
    private static let goldenFolder = "GitSemanticGoldens/entities"

    /// One input case: `Case` of the Rust program.
    struct InputCase: Decodable {
        let name: String
        let path: String
        let content: String
    }

    /// One entity of the expected JSON, with the field names of the Rust
    /// program.
    struct ExpectedEntity: Decodable, Equatable {
        let id: String
        let filePath: String
        let entityType: String
        let name: String
        let parentID: String?
        let content: String
        let contentHash: String
        let structuralHash: String?
        let startLine: Int
        let endLine: Int
        let metadata: [String: String]?

        /// The JSON keys of the Rust program: `parentId` is the camelCase
        /// name of the Rust field.
        enum CodingKeys: String, CodingKey {
            case id, filePath, entityType, name
            case parentID = "parentId"
            case content, contentHash, structuralHash, startLine, endLine, metadata
        }
    }

    /// The expected output of one case.
    struct ExpectedCase: Decodable {
        let name: String
        let pluginId: String
        let entities: [ExpectedEntity]
    }

    /// The expected form of a Swift entity.
    private static func expected(_ entity: SemanticEntity) -> ExpectedEntity {
        ExpectedEntity(
            id: entity.id, filePath: entity.filePath, entityType: entity.entityType, name: entity.name,
            parentID: entity.parentID, content: entity.content, contentHash: entity.contentHash,
            structuralHash: entity.structuralHash, startLine: entity.startLine, endLine: entity.endLine,
            metadata: entity.metadata)
    }

    /// The Swift default registry gives each case to the plugin that Rust
    /// selects, and that plugin gives the entities of the Rust plugin, field
    /// for field.
    @Test(
        "the data plugins match the Rust entities",
        arguments: ["fallback", "csv", "markdown", "json", "yaml", "toml"])
    func theDataPluginsMatchTheRustEntities(format: String) throws {
        let inputs = try TestResource.bundledJSON([InputCase].self, named: "\(format)-cases", in: Self.goldenFolder)
        let outputs = try TestResource.bundledJSON([ExpectedCase].self, named: "\(format)-expected", in: Self.goldenFolder)
        let registry = ParserRegistry.makeDefault()

        #expect(inputs.map(\.name) == outputs.map(\.name))
        for (input, output) in zip(inputs, outputs) {
            let plugin = try #require(registry.plugin(forFilePath: input.path))
            let entities = plugin.extractEntities(content: input.content, filePath: input.path)

            #expect(plugin.id == output.pluginId, "\(format)/\(input.name)")
            #expect(entities.map(Self.expected) == output.entities, "\(format)/\(input.name)")
        }
    }
}
