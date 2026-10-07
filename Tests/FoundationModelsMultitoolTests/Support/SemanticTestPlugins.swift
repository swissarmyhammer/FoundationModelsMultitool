import FoundationModelsCodeContext

@testable import FoundationModelsMultitool

/// A small ``SemanticParserPlugin`` for the semantic diff suites: one entity
/// for each line of the form `name = body`.
///
/// The entity type is `line`, the name is the text before ` = `, and the
/// content is the text after it. Thus a new body under the same name is a
/// modified entity, and the same body under a new name is a renamed one. A
/// line with no ` = ` is not an entity. The plugin has no tree, thus each
/// entity has no structural hash.
struct LineEntityPlugin: SemanticParserPlugin {

    /// The entity type of each entity of this plugin.
    static let entityType = "line"

    /// The text between the name and the body of one line.
    static let separator = " = "

    let id: String

    let extensions: [String]

    /// A line plugin with the id `lines` for the `.lines` extension.
    init(id: String = "lines", extensions: [String] = [".lines"]) {
        self.id = id
        self.extensions = extensions
    }

    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        content.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            guard let separatorRange = line.range(of: Self.separator) else { return nil }
            let name = String(line[..<separatorRange.lowerBound])
            let body = String(line[separatorRange.upperBound...])
            return SemanticEntity(
                id: SemanticEntity.makeID(filePath: filePath, entityType: Self.entityType, name: name, parentID: nil),
                filePath: filePath, entityType: Self.entityType, name: name, parentID: nil, content: body,
                contentHash: CodeEntities.contentHash(body), structuralHash: nil,
                startLine: index + 1, endLine: index + 1, metadata: nil)
        }
    }
}

/// A ``SemanticParserPlugin`` that wraps ``LineEntityPlugin`` and gives its
/// own similarity score for each pair, thus a suite can see that the
/// differ calls the similarity of the plugin and not the default one.
struct FixedSimilarityPlugin: SemanticParserPlugin {

    /// The score of each pair.
    let score: Double

    /// The plugin that extracts the entities.
    private let lines = LineEntityPlugin(id: "fixed", extensions: [".fixed"])

    var id: String { lines.id }

    var extensions: [String] { lines.extensions }

    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        lines.extractEntities(content: content, filePath: filePath)
    }

    func similarity(between first: SemanticEntity, and second: SemanticEntity) -> Double {
        score
    }
}
