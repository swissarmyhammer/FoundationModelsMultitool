// `SemanticEntity` — one named unit of a file that the semantic diff
// compares: a function, a class, a JSON key, a markdown section.
//
// A port of `model/entity.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `SemanticEntity` and the function `build_entity_id`. The Rust struct
// derives `Serialize` for the wire. This port has no wire form yet: the
// `tools.git.diff` verb makes its own result rows.

/// One named unit of a file: `SemanticEntity` in `model/entity.rs`.
struct SemanticEntity: Equatable, Sendable {

    /// The stable id of the entity: ``makeID(filePath:entityType:name:parentID:)``.
    /// The matcher pairs two entities with the same id first.
    let id: String

    /// The path of the file that holds the entity.
    let filePath: String

    /// The kind of the entity that the plugin names, for example `function`.
    let entityType: String

    /// The name of the entity.
    let name: String

    /// The id of the entity that holds this one, or `nil` for a top-level
    /// entity.
    // The code plugin writes it, as in Rust; no code of the diff reads it.
    // periphery:ignore
    let parentID: String?

    /// The source text of the entity.
    let content: String

    /// ``SemanticHash/contentHash(_:)`` of ``content``.
    let contentHash: String

    /// ``SemanticHash/structuralHash(of:source:)`` of the parse tree of the
    /// entity, or `nil` when the plugin parses no tree. Two entities with
    /// the same structural hash differ only in comments or in format.
    let structuralHash: String?

    /// The 1-based first line of the entity in the file.
    let startLine: Int

    /// The 1-based last line of the entity in the file.
    let endLine: Int

    /// More facts that the plugin records, or `nil` when there are none.
    // The plugins write it, as in Rust; no code of the diff reads it.
    // periphery:ignore
    let metadata: [String: String]?
}

extension SemanticEntity {

    /// The id of an entity: `build_entity_id` in `model/entity.rs`.
    ///
    /// The id is `file::parent::name` for an entity with a parent, and
    /// `file::type::name` for a top-level entity.
    ///
    /// - Parameters:
    ///   - filePath: The path of the file that holds the entity.
    ///   - entityType: The kind of the entity.
    ///   - name: The name of the entity.
    ///   - parentID: The id of the parent entity, or `nil`.
    /// - Returns: The id.
    static func makeID(filePath: String, entityType: String, name: String, parentID: String?) -> String {
        "\(filePath)::\(parentID ?? entityType)::\(name)"
    }
}
