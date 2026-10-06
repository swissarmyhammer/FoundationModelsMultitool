// `SemanticParserPlugin` — the contract of one language plugin of the
// semantic diff.
//
// A port of `parser/plugin.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the trait
// `SemanticParserPlugin`. The Rust trait requires `Send + Sync`; this
// protocol requires `Sendable` for the same reason, because one registry
// serves each call of the diff verb.

/// One language plugin: `SemanticParserPlugin` in `parser/plugin.rs`.
///
/// A plugin names the file extensions it reads and cuts the text of one
/// file into entities. ``ParserRegistry`` selects the plugin for each file.
protocol SemanticParserPlugin: Sendable {

    /// The id of the plugin, for example `json`. The id `fallback`
    /// (``ParserRegistry/fallbackPluginID``) marks the plugin for each file
    /// that no other plugin reads.
    var id: String { get }

    /// The file extensions of the plugin, in lowercase with a leading dot,
    /// for example `.json`.
    var extensions: [String] { get }

    /// The entities of one file: `extract_entities` in `parser/plugin.rs`.
    ///
    /// A plugin that cannot read the text gives no entity. It does not
    /// throw: the Rust differ catches a panic and uses an empty list, and a
    /// Swift plugin gives that empty list itself.
    ///
    /// - Parameters:
    ///   - content: The text of the file.
    ///   - filePath: The path of the file, for the id of each entity.
    /// - Returns: The entities, in source order.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity]

    /// The similarity of two entities, from 0 to 1, for phase 3 of the
    /// matcher: `compute_similarity` in `parser/plugin.rs`.
    ///
    /// - Parameters:
    ///   - first: The entity of the old side.
    ///   - second: The entity of the new side.
    /// - Returns: The score.
    func similarity(between first: SemanticEntity, and second: SemanticEntity) -> Double
}

extension SemanticParserPlugin {

    /// The default similarity: ``EntityMatcher/defaultSimilarity(_:_:)``,
    /// as the default method of the Rust trait.
    func similarity(between first: SemanticEntity, and second: SemanticEntity) -> Double {
        EntityMatcher.defaultSimilarity(first, second)
    }
}
