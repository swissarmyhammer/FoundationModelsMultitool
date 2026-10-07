import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``CodeParserPlugin`` and ``CodeLanguageConfig`` — the port of
/// `parser/plugins/code/mod.rs` (the extraction part) and
/// `parser/plugins/code/languages.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// These tests parse real source with the tree-sitter grammars of the
/// package. They check the routing of a file to its grammar and the parts of
/// a parse that the golden suite (`CodeParserPluginGoldenTests`) does not
/// name: the parent of a nested entity, the line numbers, and the UTF-8 byte
/// offsets.
@Suite("CodeParserPluginTests")
struct CodeParserPluginTests {

    /// The entities that the code plugin reads from `content` at `filePath`.
    private static func entities(_ content: String, at filePath: String) -> [SemanticEntity] {
        CodeParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    // MARK: Routing

    /// The default registry gives each code extension to the code plugin,
    /// in any case, as `get_plugin` lowercases the extension.
    @Test(
        "the default registry selects the code plugin for each code extension",
        arguments: [
            "src/app.ts", "src/App.tsx", "src/app.js", "src/App.jsx", "src/module.mjs", "src/module.cjs",
            "app/main.py", "src/main.rs", "cmd/main.go", "Sources/App.swift", "SRC/MAIN.RS", "src/Main.java",
            "lib/list.c", "include/list.h", "src/app.cpp", "src/app.cc", "src/app.cxx", "include/app.hpp",
            "include/app.hh", "include/app.hxx", "src/Program.cs", "lib/app.rb", "public/index.php",
            "src/solver.f90", "src/solver.f95", "src/solver.f03", "src/solver.f08", "src/solver.f",
            "src/solver.for", "lib/app.ex", "test/app_test.exs", "scripts/deploy.sh",
        ])
    func theDefaultRegistrySelectsTheCodePlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == CodeParserPlugin.pluginID)
    }

    /// The default registry has no plugin for a file that no plugin reads:
    /// the fallback plugin is not ported yet.
    @Test("the default registry selects no plugin for another extension")
    func theDefaultRegistrySelectsNoPluginForAnotherExtension() {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: "notes.txt") == nil)
    }

    /// The plugin claims the extensions of each language of the table, in
    /// the order of the table.
    @Test("the plugin claims the extension of each language")
    func thePluginClaimsTheExtensionOfEachLanguage() {
        #expect(
            CodeParserPlugin().extensions == [
                ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".go", ".rs", ".java", ".c", ".h", ".cpp",
                ".cc", ".cxx", ".hpp", ".hh", ".hxx", ".rb", ".cs", ".php", ".f90", ".f95", ".f03", ".f08", ".f",
                ".for", ".swift", ".ex", ".exs", ".sh",
            ])
    }

    /// The table gives each extension its language, and no language to an
    /// extension that it does not list. C comes before C++ in the table,
    /// thus `.h` is C, as in `languages.rs`. Bash claims `.sh` only, thus
    /// `.bash` has no language, as in `languages.rs`. JavaScript claims
    /// `.jsx`: no JSX language is in the table.
    @Test(
        "the language table maps each extension to its language",
        arguments: [
            (".ts", "typescript"), (".tsx", "tsx"), (".js", "javascript"), (".jsx", "javascript"),
            (".mjs", "javascript"), (".cjs", "javascript"), (".py", "python"), (".rs", "rust"), (".go", "go"),
            (".swift", "swift"), (".java", "java"), (".c", "c"), (".h", "c"),
            (".cpp", "cpp"), (".cc", "cpp"), (".cxx", "cpp"), (".hpp", "cpp"), (".hh", "cpp"), (".hxx", "cpp"),
            (".cs", "csharp"), (".rb", "ruby"), (".php", "php"), (".f90", "fortran"), (".f95", "fortran"),
            (".f03", "fortran"), (".f08", "fortran"), (".f", "fortran"), (".for", "fortran"), (".ex", "elixir"),
            (".exs", "elixir"), (".sh", "bash"), (".bash", nil), (".txt", nil),
        ] as [(String, String?)])
    func theLanguageTableMapsEachExtension(fileExtension: String, languageID: String?) {
        #expect(CodeLanguageConfig.config(forExtension: fileExtension)?.id == languageID)
    }

    /// A file with an extension that no language claims gives no entity.
    @Test("an unknown extension gives no entity")
    func anUnknownExtensionGivesNoEntity() {
        #expect(Self.entities("fn main() {}\n", at: "file.unknown_ext").isEmpty)
    }

    /// An empty file gives no entity.
    @Test("an empty source gives no entity")
    func anEmptySourceGivesNoEntity() {
        #expect(Self.entities("", at: "empty.rs").isEmpty)
    }

    // MARK: Parse

    /// The methods of a Rust `impl` are entities of that `impl`, as in the
    /// Rust test `test_rust_impl_nested_methods`.
    @Test("the methods of a Rust impl are entities of the impl")
    func theMethodsOfARustImplAreEntitiesOfTheImpl() {
        let source = """
            pub struct Counter {
                count: u32,
            }

            impl Counter {
                pub fn new() -> Self {
                    Counter { count: 0 }
                }
            }
            """

        let entities = Self.entities(source, at: "counter.rs")

        #expect(entities.map(\.id) == [
            "counter.rs::struct::Counter", "counter.rs::impl::Counter", "counter.rs::counter.rs::impl::Counter::new",
        ])
        #expect(entities.map(\.parentID) == [nil, nil, "counter.rs::impl::Counter"])
    }

    /// The lines of an entity are the 1-based rows of its node.
    @Test("the lines of an entity are the rows of its node")
    func theLinesOfAnEntityAreTheRowsOfItsNode() throws {
        let source = "package main\n\nfunc Area(w, h float64) float64 {\n\treturn w * h\n}\n"

        let entity = try #require(Self.entities(source, at: "area.go").first)

        #expect(entity.name == "Area")
        #expect(entity.startLine == 3)
        #expect(entity.endLine == 5)
    }

    /// The plugin parses UTF-8, thus the text of an entity after a
    /// multi-byte character is the exact text of its node.
    @Test("an entity after a multi-byte character has its exact text")
    func anEntityAfterAMultiByteCharacterHasItsExactText() throws {
        let function = "func greet() -> String {\n    \"héllo\"\n}"
        let source = "// Café ☕️ crème\n" + function + "\n"

        let entity = try #require(Self.entities(source, at: "greet.swift").first)

        #expect(entity.name == "greet")
        #expect(entity.content == function)
        #expect(entity.contentHash == SemanticHash.contentHash(function))
    }
}
