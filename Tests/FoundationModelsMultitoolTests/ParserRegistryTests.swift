import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``ParserRegistry`` — the port of `parser/registry.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The registry selects a plugin by the extension of the file path, with
/// the plugin whose id is `fallback` for each other file. The extension
/// rules are the rules of the Rust `Path::extension`, in lowercase, with a
/// leading dot.
@Suite("ParserRegistryTests")
struct ParserRegistryTests {

    /// A registry with the line plugin for `.lines` and a fallback plugin.
    private static func registryWithFallback() -> ParserRegistry {
        var registry = ParserRegistry()
        registry.register(LineEntityPlugin())
        registry.register(LineEntityPlugin(id: ParserRegistry.fallbackPluginID, extensions: []))
        return registry
    }

    /// The id of the plugin that the registry selects for `filePath`, or
    /// `nil` when it selects none.
    private static func selectedID(_ registry: ParserRegistry, _ filePath: String) -> String? {
        registry.plugin(forFilePath: filePath)?.id
    }

    /// The extension of the path selects the plugin.
    @Test("the extension of the path selects the plugin")
    func theExtensionSelectsThePlugin() {
        #expect(Self.selectedID(Self.registryWithFallback(), "src/notes.lines") == "lines")
    }

    /// The extension match ignores case, as the Rust `to_lowercase` does.
    @Test("an upper-case extension selects the plugin")
    func anUpperCaseExtensionSelectsThePlugin() {
        #expect(Self.selectedID(Self.registryWithFallback(), "src/NOTES.LINES") == "lines")
    }

    /// A file with an unknown extension gets the fallback plugin.
    @Test("an unknown extension selects the fallback plugin")
    func anUnknownExtensionSelectsTheFallback() {
        #expect(Self.selectedID(Self.registryWithFallback(), "data.xyz") == ParserRegistry.fallbackPluginID)
    }

    /// A file with no extension gets the fallback plugin.
    @Test("a file with no extension selects the fallback plugin")
    func aFileWithNoExtensionSelectsTheFallback() {
        #expect(Self.selectedID(Self.registryWithFallback(), "Makefile") == ParserRegistry.fallbackPluginID)
    }

    /// A dot file such as `.lines` has no extension, as in Rust.
    @Test("a dot file has no extension")
    func aDotFileHasNoExtension() {
        #expect(Self.selectedID(Self.registryWithFallback(), "src/.lines") == ParserRegistry.fallbackPluginID)
    }

    /// A dot in a folder name is not an extension of the file.
    @Test("a dot in a folder name is not an extension")
    func aDotInAFolderNameIsNotAnExtension() {
        #expect(Self.selectedID(Self.registryWithFallback(), "notes.lines/readme") == ParserRegistry.fallbackPluginID)
    }

    /// Only the text after the last dot is the extension.
    @Test("only the text after the last dot is the extension")
    func onlyTheLastDotCounts() {
        let registry = Self.registryWithFallback()

        #expect(Self.selectedID(registry, "archive.lines.gz") == ParserRegistry.fallbackPluginID)
        #expect(Self.selectedID(registry, "archive.gz.lines") == "lines")
    }

    /// With no fallback plugin, a file with an unknown extension gets none.
    @Test("with no fallback plugin an unknown extension selects none")
    func withNoFallbackAnUnknownExtensionSelectsNone() {
        var registry = ParserRegistry()
        registry.register(LineEntityPlugin())

        #expect(registry.plugin(forFilePath: "data.xyz") == nil)
    }

    /// A plugin that is registered later for the same extension wins, as
    /// the Rust `HashMap::insert` does.
    @Test("a later plugin for the same extension wins")
    func aLaterPluginForTheSameExtensionWins() {
        var registry = ParserRegistry()
        registry.register(LineEntityPlugin(id: "first", extensions: [".lines"]))
        registry.register(LineEntityPlugin(id: "second", extensions: [".lines", ".more"]))

        #expect(Self.selectedID(registry, "a.lines") == "second")
        #expect(Self.selectedID(registry, "a.more") == "second")
    }

    /// A lookup by id finds the first plugin with that id.
    @Test("a lookup by id finds the first plugin with that id")
    func aLookupByIDFindsTheFirstPlugin() {
        var registry = ParserRegistry()
        registry.register(LineEntityPlugin(id: "same", extensions: [".one"]))
        registry.register(LineEntityPlugin(id: "same", extensions: [".two"]))

        #expect(registry.plugin(withID: "same")?.extensions == [".one"])
        #expect(registry.plugin(withID: "other") == nil)
    }
}
