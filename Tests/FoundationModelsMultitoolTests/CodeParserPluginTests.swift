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
        arguments: ["src/main.rs", "cmd/main.go", "Sources/App.swift", "SRC/MAIN.RS"])
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
        #expect(CodeParserPlugin().extensions == [".go", ".rs", ".swift"])
    }

    /// The table gives each extension its language, and no language to an
    /// extension that it does not list.
    @Test(
        "the language table maps each extension to its language",
        arguments: [(".rs", "rust"), (".go", "go"), (".swift", "swift"), (".txt", nil)] as [(String, String?)])
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
