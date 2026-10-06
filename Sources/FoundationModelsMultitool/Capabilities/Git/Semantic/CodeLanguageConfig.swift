import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSharp
import TreeSitterElixir
import TreeSitterFortran
import TreeSitterGo
import TreeSitterJava
import TreeSitterPHP
import TreeSitterRuby
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

    /// Java: `JAVA_CONFIG`. A `record` is not an entity, thus a method of a
    /// record has no parent, as in Rust.
    static let java = CodeLanguageConfig(
        id: "java", extensions: [".java"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "class_declaration", "method_declaration", "interface_declaration", "enum_declaration",
                "field_declaration", "constructor_declaration", "annotation_type_declaration",
            ],
            containerNodeTypes: ["class_body", "interface_body", "enum_body"], callEntityIdentifiers: []),
        language: Language(tree_sitter_java()))

    /// C: `C_CONFIG`. C comes before C++ in the table, thus C claims `.h`.
    static let c = CodeLanguageConfig(
        id: "c", extensions: [".c", ".h"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "function_definition", "struct_specifier", "enum_specifier", "union_specifier", "type_definition",
                "declaration",
            ],
            containerNodeTypes: [], callEntityIdentifiers: []),
        language: Language(tree_sitter_c()))

    /// C++: `CPP_CONFIG`. A namespace is a `module` entity, and the
    /// functions in it are its children.
    static let cpp = CodeLanguageConfig(
        id: "cpp", extensions: [".cpp", ".cc", ".cxx", ".hpp", ".hh", ".hxx"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "function_definition", "class_specifier", "struct_specifier", "enum_specifier",
                "namespace_definition", "template_declaration", "declaration", "type_definition",
            ],
            containerNodeTypes: ["field_declaration_list", "declaration_list"], callEntityIdentifiers: []),
        language: Language(tree_sitter_cpp()))

    /// Ruby: `RUBY_CONFIG`.
    static let ruby = CodeLanguageConfig(
        id: "ruby", extensions: [".rb"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: ["method", "singleton_method", "class", "module"],
            containerNodeTypes: ["body_statement"], callEntityIdentifiers: []),
        language: Language(tree_sitter_ruby()))

    /// C#: `CSHARP_CONFIG`. A `record` is not an entity, thus a method of a
    /// record has no parent, as in Rust.
    static let csharp = CodeLanguageConfig(
        id: "csharp", extensions: [".cs"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "method_declaration", "class_declaration", "interface_declaration", "enum_declaration",
                "struct_declaration", "namespace_declaration", "property_declaration", "constructor_declaration",
                "field_declaration",
            ],
            containerNodeTypes: ["declaration_list"], callEntityIdentifiers: []),
        language: Language(tree_sitter_c_sharp()))

    /// PHP: `PHP_CONFIG`, with the grammar of PHP in HTML
    /// (`LANGUAGE_PHP`), not of PHP only.
    static let php = CodeLanguageConfig(
        id: "php", extensions: [".php"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [
                "function_definition", "class_declaration", "method_declaration", "interface_declaration",
                "trait_declaration", "enum_declaration", "namespace_definition",
            ],
            containerNodeTypes: ["declaration_list", "enum_declaration_list"], callEntityIdentifiers: []),
        language: Language(tree_sitter_php()))

    /// Fortran: `FORTRAN_CONFIG`. The grammar keeps the name of a function,
    /// a subroutine, and a module in a `*_statement` child, not in a `name`
    /// field or an identifier child. Thus the name reader finds no name and
    /// the language gives no entity, as in Rust.
    static let fortran = CodeLanguageConfig(
        id: "fortran", extensions: [".f90", ".f95", ".f03", ".f08", ".f", ".for"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: ["function", "subroutine", "module", "program", "interface", "type_declaration"],
            containerNodeTypes: [], callEntityIdentifiers: []),
        language: Language(tree_sitter_fortran()))

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

    /// Elixir: `ELIXIR_CONFIG`. A definition is a call, such as `def` or
    /// `defmodule`, thus each entity comes from a declaring call, and the
    /// entities in the `do` block of a module are its children.
    static let elixir = CodeLanguageConfig(
        id: "elixir", extensions: [".ex", ".exs"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: [], containerNodeTypes: ["do_block"],
            callEntityIdentifiers: [
                "defmodule", "def", "defp", "defmacro", "defmacrop", "defguard", "defguardp", "defprotocol",
                "defimpl", "defstruct", "defexception", "defdelegate",
            ]),
        language: Language(tree_sitter_elixir()))

    /// Bash: `BASH_CONFIG`. The table claims `.sh` only, as in Rust.
    static let bash = CodeLanguageConfig(
        id: "bash", extensions: [".sh"],
        vocabulary: EntityVocabulary(
            entityNodeTypes: ["function_definition"], containerNodeTypes: [], callEntityIdentifiers: []),
        language: Language(tree_sitter_bash()))

    /// Each language of the code plugin, in the order of `ALL_CONFIGS`.
    static let all: [CodeLanguageConfig] = [
        go, rust, java, c, cpp, ruby, csharp, php, fortran, swift, elixir, bash,
    ]

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
