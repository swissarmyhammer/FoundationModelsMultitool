import Foundation
import FoundationModelsCodeContext
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``CodeParserPlugin`` — the code plugin of the semantic diff.
///
/// FoundationModelsCodeContext parses each file and reads its entities
/// (`CodeEntities`), and its own tests check the parse. These tests check the
/// part that this package owns: the routing of a file to the code plugin, and
/// the map from each `CodeEntity` to a ``SemanticEntity``.
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
            "lib/app.ex", "test/app_test.exs", "scripts/deploy.sh",
        ])
    func theDefaultRegistrySelectsTheCodePlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == CodeParserPlugin.pluginID)
    }

    /// The code plugin does not get a file that no language of the table
    /// claims: the default registry gives it to the fallback plugin.
    @Test("the default registry gives another extension to the fallback plugin")
    func theDefaultRegistryGivesAnotherExtensionToTheFallbackPlugin() {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: "notes.txt")?.id == ParserRegistry.fallbackPluginID)
    }

    /// CodeContext claims no `.f90` file or a file with another extension of
    /// that grammar, thus the default registry gives such a file to the
    /// fallback plugin (git.md decision 13).
    @Test(
        "the default registry gives an f90 file to the fallback plugin",
        arguments: [".f90", ".f95", ".f03", ".f08", ".f", ".for"])
    func theDefaultRegistryGivesAnF90FileToTheFallbackPlugin(fileExtension: String) {
        #expect(!CodeEntities.supportedFileExtensions.contains(fileExtension))
        #expect(
            ParserRegistry.makeDefault().plugin(forFilePath: "src/solver" + fileExtension)?.id
                == ParserRegistry.fallbackPluginID)
    }

    /// The plugin claims the extensions of each language of the table, in
    /// the order of the table.
    @Test("the plugin claims the extension of each language")
    func thePluginClaimsTheExtensionOfEachLanguage() {
        #expect(
            CodeParserPlugin().extensions == [
                ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".go", ".rs", ".java", ".c", ".h", ".cpp",
                ".cc", ".cxx", ".hpp", ".hh", ".hxx", ".rb", ".cs", ".php", ".swift", ".ex", ".exs", ".sh",
            ])
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

    // MARK: Map

    /// The plugin gives one ``SemanticEntity`` for each `CodeEntity` of
    /// CodeContext, in the same order, with each value of that entity. The
    /// source has a nested entity, thus a parent id and a structural hash
    /// are in the values.
    @Test("the plugin keeps each value of each CodeContext entity")
    func thePluginKeepsEachValueOfEachCodeContextEntity() throws {
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
        let codeEntities = CodeEntities.entities(in: source, filePath: "counter.rs")
        try #require(codeEntities.contains { $0.parentID != nil })

        let entities = Self.entities(source, at: "counter.rs")

        #expect(entities.map(\.id) == codeEntities.map(\.id))
        #expect(entities.map(\.filePath) == codeEntities.map(\.filePath))
        #expect(entities.map(\.entityType) == codeEntities.map(\.entityType))
        #expect(entities.map(\.name) == codeEntities.map(\.name))
        #expect(entities.map(\.parentID) == codeEntities.map(\.parentID))
        #expect(entities.map(\.content) == codeEntities.map(\.content))
        #expect(entities.map(\.contentHash) == codeEntities.map(\.contentHash))
        #expect(entities.map(\.structuralHash) == codeEntities.map(\.structuralHash))
        #expect(entities.map(\.startLine) == codeEntities.map(\.startLine))
        #expect(entities.map(\.endLine) == codeEntities.map(\.endLine))
        #expect(entities.map(\.metadata) == codeEntities.map(\.metadata))
    }
}
