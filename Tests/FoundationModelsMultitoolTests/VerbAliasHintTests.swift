import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// Holds the did-you-mean hint to the verb alias table, for a guess that names
/// a real group and a verb that the group does not have.
///
/// **Why this suite exists.** In a SWE-bench run the model called
/// `tools.code_context.listFiles`, `tools.files.find` and `tools.shell.run`.
/// Tier 1 compares the whole dotted path, so the shared group prefix gives
/// each verb of the group trigrams in common with the guess. Thus tier 1
/// answered `code_context.listFiles` with `code_context.listSymbols`, and
/// `files.find` with `files.read`. The alias table names the verb that does
/// the work. See the type documentation of ``UnknownToolHint`` for the
/// measurements and the decisions.
///
/// The bundle has no embedder, so the reading costs no model.
@Suite("VerbAliasHintTests")
struct VerbAliasHintTests {

    /// Owns the temporary directory of each test. Thus it goes away when the
    /// test ends.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "verb-alias-hint-tests"

    /// The name of the shell store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The group of the code-intelligence verbs that the SWE-bench agent had.
    private static let codeContextGroup = "code_context"

    /// The path that finds files by name.
    private static let globPath = "files.glob"

    /// The path that runs one command.
    private static let executePath = "shell.execute"

    /// The path that makes a directory.
    private static let makeDirectoryPath = "files.makeDirectory"

    /// The path that removes a directory.
    private static let removeDirectoryPath = "files.removeDirectory"

    /// The code-intelligence verbs of the SWE-bench agent, in a short form.
    ///
    /// `listSymbols` is the verb that tier 1 named for `listFiles`, because the
    /// two share the `code_context.list` prefix.
    ///
    /// - Returns: the tools to add under ``codeContextGroup``.
    private static func codeContextTools() -> [any Tool] {
        [
            CatalogEntryTool(name: "getSymbol", description: "Jumps to the definition of a symbol."),
            CatalogEntryTool(name: "listSymbols", description: "Lists the symbols that one source file declares."),
            CatalogEntryTool(name: "grepCode", description: "Searches the indexed code with a regular expression."),
        ]
    }

    /// Builds the surface of the SWE-bench agent: the files verbs, the shell
    /// verbs and the code-intelligence group, with no embedder.
    ///
    /// - Parameter includesFiles: whether the files capability is mounted.
    /// - Returns: the registry, and the bundle built over it.
    /// - Throws: when the directory or the registry does not prepare.
    private func makeBundle(
        includesFiles: Bool = true
    ) throws -> (registry: MultiTool.Registry, bundle: MultiTool.RegistryBundle) {
        let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let builder = MultiTool.Builder()
        if includesFiles {
            builder.withFiles(root: root, readOnly: false)
        }
        let registry =
            try builder
            .withShell(
                storeDirectory: root.appendingPathComponent(Self.shellStoreDirectoryName, isDirectory: true))
            .addGroup(named: Self.codeContextGroup, Self.codeContextTools())
            .buildRegistry()
        let shape = MultiTool.RegistryBundleShape(bindsSearchTools: false, discovery: .none, embedder: nil)
        return (registry, MultiTool.RegistryBundle(registry: registry, shape: shape))
    }

    /// Resolves one guess over the surface of ``makeBundle(includesFiles:)``.
    ///
    /// - Parameters:
    ///   - guess: the wrong path, without its `tools.` prefix.
    ///   - includesFiles: whether the files capability is mounted.
    /// - Returns: the resolution.
    /// - Throws: when the surface does not prepare, or the guess gets no hint.
    private func resolve(_ guess: String, includesFiles: Bool = true) async throws -> UnknownToolHint.Resolution {
        let (registry, bundle) = try makeBundle(includesFiles: includesFiles)
        return try #require(
            await UnknownToolHint.hint(
                message: "TypeError: tools.\(guess) is not a function",
                snippet: "return await tools.\(guess)();",
                surface: registry.surface,
                searcher: bundle.hintSearcher
            )
        )
    }

    @Test("a made-up listFiles verb in a real group is answered with files.glob")
    func listFilesInARealGroupIsAnsweredWithGlob() async throws {
        let resolution = try await resolve("\(Self.codeContextGroup).listFiles")

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.globPath])
        #expect(resolution.text.contains("declare function glob("), "text was: \(resolution.text)")
        #expect(resolution.text.contains("Call tools.\(Self.globPath) instead."), "text was: \(resolution.text)")
        #expect(resolution.directive == .repairSnippet)
    }

    @Test("files.find is answered with files.glob alone")
    func filesFindIsAnsweredWithGlob() async throws {
        let resolution = try await resolve("files.find")

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.globPath])
    }

    @Test("shell.run is answered with shell.execute alone")
    func shellRunIsAnsweredWithExecute() async throws {
        let resolution = try await resolve("shell.run")

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.executePath])
    }

    @Test("files.mkdir is answered with files.makeDirectory alone")
    func filesMkdirIsAnsweredWithMakeDirectory() async throws {
        let resolution = try await resolve("files.mkdir")

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.makeDirectoryPath])
        #expect(resolution.text.contains("tools.\(Self.makeDirectoryPath)"), "text was: \(resolution.text)")
    }

    @Test("files.rmdir is answered with files.removeDirectory alone")
    func filesRmdirIsAnsweredWithRemoveDirectory() async throws {
        let resolution = try await resolve("files.rmdir")

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.removeDirectoryPath])
        #expect(resolution.text.contains("tools.\(Self.removeDirectoryPath)"), "text was: \(resolution.text)")
    }

    @Test("files.MkDir gets the same answer as files.mkdir")
    func filesMkDirInMixedCaseIsAnsweredWithMakeDirectory() async throws {
        let resolution = try await resolve("files.MkDir")

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.makeDirectoryPath])
    }

    @Test("an alias matches the verb in any letter case")
    func anAliasMatchesTheVerbInAnyLetterCase() async throws {
        let resolution = try await resolve("files.Find")

        #expect(resolution.suggestedPaths == [Self.globPath])
    }

    @Test("an alias whose path is not in the surface does not answer")
    func anAliasWhosePathIsAbsentDoesNotAnswer() async throws {
        let resolution = try await resolve("\(Self.codeContextGroup).listFiles", includesFiles: false)

        #expect(resolution.tier != .verbAlias)
        #expect(!resolution.suggestedPaths.contains(Self.globPath))
    }

    @Test("an alias verb under a group that does not exist keeps the ranked tiers")
    func anAliasVerbUnderNoGroupKeepsTheRankedTiers() async throws {
        let resolution = try await resolve("bash.run")

        #expect(resolution.tier == .catalogRelevance)
    }

    @Test("an alias answer is recorded against the alias tier")
    func anAliasAnswerIsRecordedAgainstTheAliasTier() async throws {
        let guess = "files.find"
        let resolution = try await resolve(guess)

        #expect(
            ImaginedToolLogRecord(metadata: resolution.logMetadata)
                == ImaginedToolLogRecord(imagined: guess, tier: "alias", suggested: [Self.globPath])
        )
    }
}
