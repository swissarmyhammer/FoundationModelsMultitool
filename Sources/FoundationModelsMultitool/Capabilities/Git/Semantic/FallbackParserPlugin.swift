import FoundationModelsCodeContext

// `FallbackParserPlugin` — the plugin of the semantic diff for each file that
// no other plugin reads.
//
// A port of `parser/plugins/fallback.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `FallbackParserPlugin` and the constant `CHUNK_SIZE`. The plugin claims no
// extension. ``ParserRegistry`` gives it each file whose extension no other
// plugin claims (git.md decision 13), and each file with no extension.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The fallback plugin: `FallbackParserPlugin` in `parser/plugins/fallback.rs`.
struct FallbackParserPlugin: SemanticParserPlugin {

    /// The entity type of each chunk (`"chunk"` in Rust).
    static let chunkEntityType = "chunk"

    /// The count of lines in each chunk: `CHUNK_SIZE` in Rust. The last
    /// chunk can have fewer lines.
    static let chunkLineCount = 20

    var id: String { ParserRegistry.fallbackPluginID }

    /// No extension: the registry selects this plugin by its id.
    var extensions: [String] { [] }

    /// The entities of one file: `extract_entities` in `fallback.rs`.
    ///
    /// The lines are the lines of the Rust `str::lines`. Each run of
    /// ``chunkLineCount`` lines is one entity, named `lines <first>-<last>`
    /// with 1-based line numbers. The content is the lines joined by a
    /// newline.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        let lines = RustText.lines(of: content)
        return stride(from: 0, to: lines.count, by: Self.chunkLineCount).map { start in
            let end = min(start + Self.chunkLineCount, lines.count)
            let chunk = lines[start..<end].joined(separator: "\n")
            let name = "lines \(start + 1)-\(end)"
            return SemanticEntity(
                filePath: filePath, entityType: Self.chunkEntityType, name: name, content: chunk,
                contentHash: CodeEntities.contentHash(chunk), startLine: start + 1, endLine: end)
        }
    }
}
