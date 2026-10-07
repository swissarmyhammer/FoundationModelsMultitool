import Foundation
import SwiftTreeSitter
import TreeSitter

// `CodeParserPlugin` — the language plugin of the semantic diff for source
// code: it parses a file with tree-sitter and reads its entities.
//
// A port of the extraction part of `parser/plugins/code/mod.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `CodeParserPlugin`, `parse_code`, and `ParsedCode::entities`. The parts of
// that file for duplication, commented code, the test census, and the public
// surface serve the `code_context` tool, and this port does not have them.
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.
//
// The Rust code keeps one parser for each language and thread. A
// SwiftTreeSitter `Parser` is a class that is not `Sendable`, thus this port
// makes one parser for each parse.
//
// The parse reads the UTF-8 bytes of the file (`TSInputEncodingUTF8`), thus
// each byte offset of a node is a UTF-8 offset, as in Rust. The `parse(_:)`
// call of SwiftTreeSitter reads UTF-16 and gives UTF-16 offsets.

/// The code plugin: `CodeParserPlugin` in `parser/plugins/code/mod.rs`.
struct CodeParserPlugin: SemanticParserPlugin {

    /// The id of the code plugin.
    static let pluginID = "code"

    var id: String { Self.pluginID }

    /// The extensions of each language of ``CodeLanguageConfig/all``.
    var extensions: [String] { CodeLanguageConfig.allExtensions }

    /// The entities of one file: `extract_entities` in
    /// `parser/plugins/code/mod.rs`.
    ///
    /// A file whose extension no language claims, or that the grammar does
    /// not parse, gives no entity.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        guard let config = CodeLanguageConfig.config(forExtension: ParserRegistry.fileExtension(of: filePath))
        else { return [] }
        let source = Array(content.utf8)
        guard let root = Self.parse(source, config: config) else { return [] }
        return CodeEntityExtractor.extractEntities(
            root: root, source: source, filePath: filePath, vocabulary: config.vocabulary)
    }

    /// The root of the parse of `source` with the grammar of `config`, or
    /// `nil` when the parse makes no tree: `parse_code` in
    /// `parser/plugins/code/mod.rs`.
    ///
    /// The Rust `parse_code` writes a warning and gives `None` when the
    /// parser does not accept the grammar (an ABI version that the runtime
    /// does not support). Here that is a programmer error, not a state that
    /// a file can cause: `Package.swift` pins the runtime and each grammar,
    /// and the golden suite loads each grammar of ``CodeLanguageConfig/all``.
    /// Thus this port stops with a precondition failure.
    private static func parse(_ source: [UInt8], config: CodeLanguageConfig) -> TreeSitterSyntaxNode? {
        let parser = Parser()
        do {
            try parser.setLanguage(config.language)
        } catch {
            preconditionFailure("the tree-sitter runtime does not accept the \(config.id) grammar: \(error)")
        }
        let data = Data(source)
        let tree = parser.parse(tree: nil as Tree?, encoding: TSInputEncodingUTF8) { offset, _ in
            offset < data.count ? data[offset...] : nil
        }
        return tree?.rootNode.map(TreeSitterSyntaxNode.init(node:))
    }
}

/// One node of a tree-sitter parse, as ``CodeEntityExtractor`` and
/// ``SemanticHash`` read it.
///
/// Each SwiftTreeSitter `Node` holds a reference to its tree, thus the tree
/// stays alive while a node of it is in use.
struct TreeSitterSyntaxNode: CodeSyntaxNode {

    /// The tree-sitter node.
    let node: Node

    var kind: String { node.nodeType ?? "" }

    var startByte: Int { Int(node.byteRange.lowerBound) }

    var endByte: Int { Int(node.byteRange.upperBound) }

    var startRow: Int { Int(node.pointRange.lowerBound.row) }

    var endRow: Int { Int(node.pointRange.upperBound.row) }

    var children: [TreeSitterSyntaxNode] {
        (0..<node.childCount).compactMap { node.child(at: $0) }.map(Self.init(node:))
    }

    var namedChildren: [TreeSitterSyntaxNode] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }.map(Self.init(node:))
    }

    func child(byFieldName name: String) -> TreeSitterSyntaxNode? {
        node.child(byFieldName: name).map(Self.init(node:))
    }
}
