import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Holds the did-you-mean ranker to naming the RUNNER for a guess that asks to
/// run a command, over the nine-entry files-and-shell surface.
///
/// **Why this suite exists.** `UnknownToolHint` answers a guess that resembles
/// no catalog name with `MultiTool.RegistryBundle.hintSearcher`, and that
/// searcher fuses three ranked lists: BM25, character-trigram Dice, and cosine.
/// The trigram list is a list of SPELLING, and it is measured over the whole
/// rendered block. A guess spelled out as a plain-language intent shares its
/// trigrams with every block that holds the words, so that list falls to an
/// order by the size of the block: `shell.execute` renders the largest block of
/// the nine and `shell.getLines` the smallest. Card `^pwn02m4` measured the
/// result — `terminal.runCommand`, `bash.run` and `terminal.runTests` were each
/// answered with the verb that READS what a command printed, although BM25 and
/// cosine both named the runner first — and dropped the trigram weight for this
/// searcher alone. See ``MultiTool/hintSearchWeights``.
///
/// **What it holds, and what it cannot.** This suite builds the bundle with no
/// embedder, so it reads the BM25 list alone and the reading is exact and
/// costs no model. The gated `UnknownToolHintLiveTests` holds the same three
/// guesses with the shipped embedder behind them, where cosine ranks as well.
/// This suite is the fast guard that the weights are still the shipped ones.
@Suite("HintRankingTests")
struct HintRankingTests {

    /// Owns the temporary directory this test makes. Thus it goes away when the
    /// test ends, and the directories do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "hint-ranking-tests"

    /// The name of the shell store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The path the surface really defines for the work each guess asks for.
    private static let runnerPath = "shell.execute"

    /// The wrong `tools.*` paths that each ask to run a command, and that the
    /// keyword ranking answers with the runner.
    ///
    /// `bash.run` and `terminal.runTests` are held by the gated suite instead:
    /// each one spells out to one matching word, `run`, and BM25 alone divides
    /// that word by the length of the block. Cosine settles them, and cosine
    /// needs an embedder no unit test carries.
    private static let runACommandGuesses = ["terminal.runCommand"]

    /// The bundle a host really gets over the files-and-shell surface, with no
    /// embedder.
    ///
    /// - Returns: The registry, and the bundle built over it.
    /// - Throws: When the directory, the store or the registry does not prepare.
    private func makeBundle() throws -> (registry: MultiTool.Registry, bundle: MultiTool.RegistryBundle) {
        let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let registry = try MultiTool.Builder()
            .withFiles(root: root, readOnly: false)
            .withShell(
                storeDirectory: root.appendingPathComponent(
                    Self.shellStoreDirectoryName, isDirectory: true))
            .buildRegistry()
        let shape = MultiTool.RegistryBundleShape(
            bindsSearchTools: false, discovery: .none, embedder: nil)
        return (registry, MultiTool.RegistryBundle(registry: registry, shape: shape))
    }

    @Test("a guess that asks to run a command is answered with the verb that runs one")
    func aRunACommandGuessIsAnsweredWithTheRunner() async throws {
        let (registry, bundle) = try makeBundle()
        for guess in Self.runACommandGuesses {
            let resolution = try #require(
                await UnknownToolHint.hint(
                    message: "TypeError: tools.\(guess) is not a function",
                    snippet: "const answer = await tools.\(guess)();",
                    surface: registry.surface,
                    searcher: bundle.hintSearcher
                )
            )

            #expect(
                resolution.tier == .catalogRelevance,
                "\"\(guess)\" was answered by \(resolution.tier.rawValue), and no name resembles it")
            #expect(
                resolution.suggestedPaths.first == Self.runnerPath,
                """
                "\(guess)" asks to run a command and was answered with \
                \(resolution.suggestedPaths), and \(Self.runnerPath) is the verb that runs one
                """
            )
        }
    }
}
