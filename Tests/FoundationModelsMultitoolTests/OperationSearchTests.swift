import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// Coverage for discovery over the verbs of an `OperationDescribing` tool.
/// Each verb is its own `APISurface.Entry`, so the searcher ranks one verb,
/// `searchTools` formats one verb, the selection prompt reads one verb, and
/// the did-you-mean hint proposes one verb.
///
/// Every case runs against ``NotesOperationTool``
/// (`Fixtures/OperationToolFixtures.swift`), mounted as a standalone tool so
/// its five verbs stand under `tools.notes`.
@Suite("OperationSearchTests")
struct OperationSearchTests {
    // MARK: - Shared test constants

    /// The verb name of the `tag note` operation.
    private static let tagNoteVerbName = "tagNote"

    /// The path of the `tag note` verb of the standalone fixture.
    private static let tagNotePath = "notes.\(tagNoteVerbName)"

    /// The path of the `list note` verb of the standalone fixture.
    private static let listNotePath = "notes.listNote"

    /// The task the searcher must answer with the `tagNote` verb first.
    ///
    /// Lexical wording on purpose: the unit target has no semantic embedder,
    /// so the ranking is BM25 and trigram over the verb blocks, and the task
    /// must hold words the `tagNote` block holds. A paraphrase such as
    /// `attach a label to a note` needs an embedder, and card `^km5wdgd`
    /// measures it against the live one.
    private static let tagTask = "tag a note"

    /// The task the searcher must answer with the `listNote` verb first, in
    /// lexical wording for the reason ``tagTask`` gives.
    private static let listTask = "list every note"

    /// A path one letter away from the `tagNote` verb, which no entry has.
    private static let nearMissPath = "notes.tagNotes"

    /// A snippet that calls the near miss, with no `try`, so the run fails
    /// and the hint runs.
    private static let nearMissSnippet = #"return tools.\#(nearMissPath)({ id: "n1", tag: "due" });"#

    // MARK: - Helpers

    /// A registry that holds the fixture as a standalone tool.
    ///
    /// - Returns: The registry.
    /// - Throws: What `buildRegistry()` throws.
    private static func makeRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(NotesOperationTool()).buildRegistry()
    }

    /// The entry of `registry` at `path`.
    ///
    /// - Parameters:
    ///   - path: The `tools.*` path of the entry, without the prefix.
    ///   - registry: The registry to read.
    /// - Returns: The entry.
    /// - Throws: When no entry has the path.
    private static func entry(at path: String, in registry: MultiTool.Registry) throws -> APISurface.Entry {
        try #require(registry.surface.entries.first { $0.path == path }, "no entry at \(path)")
    }

    /// The first match the discovery searcher gives for `task` over the
    /// verbs of `registry`.
    ///
    /// The searcher is the one `SearchToolsTool.makeSearcher(over:selection:embedder:)`
    /// builds, in `.auto` mode with no selection tier and no embedder, so
    /// the ranking is retrieval alone.
    ///
    /// - Parameters:
    ///   - task: The plain-language task to search for.
    ///   - registry: The registry whose entries the searcher indexes.
    /// - Returns: The best match.
    /// - Throws: When the searcher gives no match.
    private static func firstMatch(for task: String, in registry: MultiTool.Registry) async throws -> Match<APISurface.Entry> {
        let searcher = SearchToolsTool.makeSearcher(over: registry.surface.entries, selection: nil, embedder: nil)
        let matches = try await searcher.search(intent: task, limit: 1)
        return try #require(matches.first, "no match for \(task)")
    }

    // MARK: - Ranking

    @Test("the discovery searcher ranks notes.tagNote first for the task to tag a note")
    func tagNoteRanksFirstForTaggingANote() async throws {
        let registry = try Self.makeRegistry()

        let match = try await Self.firstMatch(for: Self.tagTask, in: registry)

        #expect(match.id == Self.tagNotePath)
    }

    @Test("the discovery searcher ranks notes.listNote first for the task to list every note")
    func listNoteRanksFirstForListingEveryNote() async throws {
        let registry = try Self.makeRegistry()

        let match = try await Self.firstMatch(for: Self.listTask, in: registry)

        #expect(match.id == Self.listNotePath)
    }

    // MARK: - The formatted result

    @Test("format(task:matches:) for one verb match gives the verb block, then its qualified example")
    func formatGivesTheVerbBlockThenItsQualifiedExample() throws {
        let registry = try Self.makeRegistry()
        let entry = try Self.entry(at: Self.tagNotePath, in: registry)
        let match = Match(id: entry.id, block: entry.block, score: 1, signals: nil, item: entry)

        let output = SearchToolsTool.format(task: Self.tagTask, matches: [match])

        #expect(output.contains("\(entry.block)\nExample: \(entry.qualifiedExample)"), "output was: \(output)")
        // The example names the qualified verb and its two required
        // parameters. The fixture names the second one `tag`, so the
        // expected text reads the parameter names off the fixture.
        let idParameter = NotesOperationTool.idParameter
        let tagParameter = NotesOperationTool.tagParameter
        let call = "tools.\(Self.tagNotePath)({ \(idParameter): \"\(idParameter)\", \(tagParameter): \"\(tagParameter)\" })"
        #expect(entry.qualifiedExample.contains(call), "example was: \(entry.qualifiedExample)")
        #expect(!output.contains("tools.\(Self.tagNoteVerbName)("), "output was: \(output)")
    }

    // MARK: - The selection prompt

    @Test("renderSummaryBlock() of a verb holds its banner and the verb description, not the parent description")
    func summaryBlockHoldsTheVerbDescription() throws {
        let registry = try Self.makeRegistry()
        let entry = try Self.entry(at: Self.tagNotePath, in: registry)
        let parent = NotesOperationTool()
        let verbDescription = try #require(
            parent.operationDescriptors.first { $0.opString == NotesOperationTool.tagNoteOp }?.description)

        let summary = entry.renderSummaryBlock()

        #expect(summary.hasPrefix("// tools.\(Self.tagNotePath)\n"), "summary was: \(summary)")
        #expect(summary.contains(verbDescription), "summary was: \(summary)")
        #expect(!summary.contains(parent.description), "summary was: \(summary)")
    }

    // MARK: - The did-you-mean hint

    @Test("a snippet that names tools.notes.tagNotes is told to call tools.notes.tagNote")
    func nearMissOnAVerbProposesTheVerb() async throws {
        let registry = try Self.makeRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: Self.nearMissSnippet))

        #expect(output.contains("tools.\(Self.nearMissPath) \(UnknownToolHint.missingPathPhrase)"), "output was: \(output)")
        #expect(output.contains("Call tools.\(Self.tagNotePath) instead"), "output was: \(output)")
        #expect(output.contains("declare function \(Self.tagNoteVerbName)("), "output was: \(output)")
    }
}
