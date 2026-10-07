import Foundation
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the discovery search over the verbs of the git capability
/// (task `^xd2dbd1`, work item 5).
///
/// Each verb is its own `APISurface.Entry`, and the searcher indexes the
/// block of each entry: the banner `// tools.git.<verb>` and the description
/// of the verb. A model that asks for "git", "diff", "blame", or "branch"
/// must find the verbs of the capability.
///
/// The files capability stands beside the git capability. Thus each query has
/// distractors to miss the git verbs among. The searcher is the one that
/// `SearchToolsTool.makeSearcher(over:selection:embedder:)` builds, with no
/// selection tier and no embedder. Thus the ranking is the keyword signals
/// alone, and the unit target needs no model.
@Suite("GitSearchTests")
struct GitSearchTests {

    /// The first segment of the path of each git verb, with its separator.
    private static let gitPathPrefix = "git."

    /// The path of each verb of the git capability, in render order.
    private static let gitVerbPaths = ["blame", "show", "log", "status", "branches", "changes", "diff"]
        .map { gitPathPrefix + $0 }

    /// One query and the git verb that the searcher must rank first for it.
    struct VerbQuery: Sendable, CustomTestStringConvertible {

        /// The words that the model searches with.
        let query: String

        /// The path of the verb that must come first.
        let firstPath: String

        /// The query, as the test report names the case.
        var testDescription: String { query }
    }

    /// The queries that name one verb, each with the verb that answers it.
    static let verbQueries = [
        VerbQuery(query: "diff", firstPath: "git.diff"),
        VerbQuery(query: "blame", firstPath: "git.blame"),
        VerbQuery(query: "branch", firstPath: "git.branches"),
    ]

    /// The query that names the capability.
    private static let capabilityQuery = "git"

    // MARK: - Helpers

    /// A registry with the git capability and the files capability over one
    /// temporary repository.
    ///
    /// - Parameter repository: The repository whose work folder is the root
    ///   of both capabilities.
    /// - Returns: The registry.
    /// - Throws: What `buildRegistry()` throws.
    private static func makeRegistry(over repository: TemporaryGitRepository) throws -> MultiTool.Registry {
        try MultiTool.Builder()
            .withGit(root: repository.workDirectory)
            .withFiles(root: repository.workDirectory)
            .buildRegistry()
    }

    /// The matches that the discovery searcher gives for `query` over the
    /// entries of `registry`, best first.
    ///
    /// - Parameters:
    ///   - query: The words to search for.
    ///   - registry: The registry whose entries the searcher indexes.
    ///   - limit: The largest number of matches.
    /// - Returns: The paths of the matches, best first.
    /// - Throws: What the search throws.
    private static func matchedPaths(
        for query: String, in registry: MultiTool.Registry, limit: Int
    ) async throws -> [String] {
        let searcher = SearchToolsTool.makeSearcher(over: registry.surface.entries, selection: nil, embedder: nil)
        return try await searcher.search(intent: query, limit: limit).map(\.id)
    }

    // MARK: - Tests

    /// A query with the word of one verb ranks that verb first.
    @Test("a search for the word of a git verb ranks that verb first", arguments: verbQueries)
    func aSearchForTheWordOfAVerbRanksThatVerbFirst(_ verbQuery: VerbQuery) async throws {
        let repository = try TemporaryGitRepository()
        let registry = try Self.makeRegistry(over: repository)

        let paths = try await Self.matchedPaths(for: verbQuery.query, in: registry, limit: 1)

        #expect(paths == [verbQuery.firstPath], "the matches for \"\(verbQuery.query)\" were \(paths)")
    }

    /// A query with the noun of the capability finds each git verb, and ranks
    /// no entry that does not say "git" above a git verb.
    ///
    /// The test does not ask for the git verbs alone at the top. `files.glob`
    /// says "git" in its own text (its `respectGitIgnore` argument), and the
    /// keyword signals rank it among the git verbs. Task `^xd2dbd1` measured
    /// that `files.glob` stands between the git verbs for this query.
    @Test("a search for git finds each git verb, and ranks no entry without the word git above one")
    func aSearchForGitFindsEachGitVerb() async throws {
        let repository = try TemporaryGitRepository()
        let registry = try Self.makeRegistry(over: repository)
        let blocksByPath = Dictionary(uniqueKeysWithValues: registry.surface.entries.map { ($0.path, $0.block) })

        let paths = try await Self.matchedPaths(
            for: Self.capabilityQuery, in: registry, limit: registry.surface.entries.count)

        #expect(Set(Self.gitVerbPaths).isSubset(of: paths), "the matches for \"\(Self.capabilityQuery)\" were \(paths)")
        let lastGitVerbIndex = try #require(paths.lastIndex(where: Self.gitVerbPaths.contains))
        let entriesWithoutTheWord = try paths[...lastGitVerbIndex].filter { path in
            let block = try #require(blocksByPath[path], "no entry at \(path)")
            return !Tokenizer.tokenize(text: block).contains(Self.capabilityQuery)
        }
        #expect(entriesWithoutTheWord.isEmpty, "the matches for \"\(Self.capabilityQuery)\" were \(paths)")
    }
}
