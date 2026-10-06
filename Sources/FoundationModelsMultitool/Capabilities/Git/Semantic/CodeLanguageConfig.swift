import SwiftTreeSitter
import TreeSitterGo
import TreeSitterRust
import TreeSitterSwift

// `CodeLanguageConfig` — the table of the languages that the code plugin of
// the semantic diff parses: for each one, its extensions, its tree-sitter
// grammar, and the node kinds that carry meaning.
//
// A port of `parser/plugins/code/languages.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `LanguageConfig`, one entry for each language of the package, the table
// `ALL_CONFIGS`, `get_language_config`, and `get_all_code_extensions`.
//
// git.md decision 7 ports each language of the Rust table. A language task
// adds its grammar package to `Package.swift`, one entry here, and the entry
// in ``all``. The entries are in the order of `ALL_CONFIGS`, thus the
// extensions of the plugin are in the same order as in Rust.
//
// Not ported: `extensions_for_language`, `dotted_lowercase_extension`, and
// `is_code_file` serve other Rust crates. The code plugin reads the extension
// of a path with ``ParserRegistry/fileExtension(of:)``, which has the same
// rules.

/// One language of the code plugin: `LanguageConfig` in `languages.rs`.
struct CodeLanguageConfig: Sendable {

    /// The id of the language, for example `rust`.
    let id: String

    /// The file extensions of the language, in lowercase with a leading
    /// dot, for example `.rs`.
    let extensions: [String]

    /// The node kinds that carry meaning in the language.
    let vocabulary: EntityVocabulary

    /// The tree-sitter grammar of the language (`get_language` in Rust).
    let language: Language
}

extension CodeLanguageConfig {

    /// Go: `GO_CONFIG`. A Go type declaration has no `name` field and no
    /// identifier child, thus it is not an entity, as in Rust.
    static let go = CodeLanguageConfig(
        id: "go", extensions: [".go"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "function_declaration", "method_declaration", "type_declaration", "var_declaration",
                "const_declaration",
            ],
            containerNodeTypes: [], callEntityIdentifiers: []),
        language: Language(tree_sitter_go()))

    /// Rust: `RUST_CONFIG`.
    static let rust = CodeLanguageConfig(
        id: "rust", extensions: [".rs"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "function_item", "struct_item", "enum_item", "impl_item", "trait_item", "mod_item", "const_item",
                "static_item", "type_item",
            ],
            containerNodeTypes: ["declaration_list"], callEntityIdentifiers: []),
        language: Language(tree_sitter_rust()))

    /// Swift: `SWIFT_CONFIG`. The grammar gives a `class`, a `struct`, an
    /// `enum`, and an `extension` the one kind `class_declaration`.
    static let swift = CodeLanguageConfig(
        id: "swift", extensions: [".swift"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "function_declaration", "class_declaration", "protocol_declaration", "init_declaration",
                "deinit_declaration", "subscript_declaration", "typealias_declaration", "property_declaration",
                "operator_declaration", "associatedtype_declaration",
            ],
            containerNodeTypes: ["class_body", "protocol_body", "enum_class_body"], callEntityIdentifiers: []),
        language: Language(tree_sitter_swift()))

    /// Each language of the code plugin, in the order of `ALL_CONFIGS`.
    static let all: [CodeLanguageConfig] = [go, rust, swift]

    /// The extensions of each language, in the order of ``all``: the
    /// extensions of the code plugin (`get_all_code_extensions`).
    static var allExtensions: [String] {
        all.flatMap(\.extensions)
    }

    /// The language that claims `fileExtension`: `get_language_config` in
    /// `languages.rs`.
    ///
    /// - Parameter fileExtension: The extension in lowercase with a leading
    ///   dot, as ``ParserRegistry/fileExtension(of:)`` gives it.
    /// - Returns: The language, or `nil` when no language claims the
    ///   extension.
    static func config(forExtension fileExtension: String) -> CodeLanguageConfig? {
        all.first { $0.extensions.contains(fileExtension) }
    }
}
