import FoundationModelsCodeContext

// `CodeParserPlugin` — the language plugin of the semantic diff for source
// code.
//
// FoundationModelsCodeContext owns all tree-sitter work: it parses each file
// and reads its entities (`CodeEntities`). Its values are a port of
// `parser/plugins/code/mod.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`. This plugin does not
// parse. It gives each `CodeEntity` of CodeContext to the semantic diff as a
// ``SemanticEntity`` with the same values. The Rust plugin uses the default
// `compute_similarity`, thus this plugin uses the default
// ``SemanticParserPlugin/similarity(between:and:)``.

/// The code plugin: `CodeParserPlugin` in `parser/plugins/code/mod.rs`.
struct CodeParserPlugin: SemanticParserPlugin {

    /// The id of the code plugin.
    static let pluginID = "code"

    var id: String { Self.pluginID }

    /// The extensions that CodeContext reads: `CodeEntities.supportedFileExtensions`.
    ///
    /// Each one is in lowercase with a leading dot, the form that
    /// ``ParserRegistry/fileExtension(of:)`` gives, thus the registry uses
    /// them with no change.
    var extensions: [String] { CodeEntities.supportedFileExtensions }

    /// The entities of one file: `extract_entities` in
    /// `parser/plugins/code/mod.rs`, through `CodeEntities.entities(in:filePath:)`.
    ///
    /// A file whose extension no language claims, or that the grammar does
    /// not parse, gives no entity.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        CodeEntities.entities(in: content, filePath: filePath).map(SemanticEntity.init(codeEntity:))
    }
}

extension SemanticEntity {

    /// The semantic entity with each value of `codeEntity`.
    ///
    /// The two types are ports of the same Rust struct, thus each value
    /// goes across with no change.
    ///
    /// - Parameter codeEntity: An entity that CodeContext read from a source file.
    init(codeEntity: CodeEntity) {
        self.init(
            id: codeEntity.id, filePath: codeEntity.filePath, entityType: codeEntity.entityType,
            name: codeEntity.name, parentID: codeEntity.parentID, content: codeEntity.content,
            contentHash: codeEntity.contentHash, structuralHash: codeEntity.structuralHash,
            startLine: codeEntity.startLine, endLine: codeEntity.endLine, metadata: codeEntity.metadata)
    }
}
