import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the discovery search over the verbs of the environment
/// capability (task `^pykbc2k`).
///
/// Each verb is its own `APISurface.Entry`, and the searcher indexes the
/// block of each entry: the banner `// tools.environment.<verb>` and the
/// description of the verb. A model that asks for an environment variable,
/// the operating system, the date, or the time must find the verb that
/// answers it.
///
/// The git capability and the files capability stand beside the environment
/// capability, the same as in `GitSearchTests`. Thus each query has
/// distractors to miss the environment verbs among. The searcher has no
/// selection tier and no embedder, thus the ranking is the keyword signals
/// alone, and the unit target needs no model. The environment capability
/// reads ``InjectedEnvironment``, thus no verb can read the real process.
@Suite("EnvironmentSearchTests")
struct EnvironmentSearchTests {

    /// One query and the environment verb that the searcher must rank first
    /// for it.
    struct VerbQuery: Sendable, CustomTestStringConvertible {

        /// The words that the model searches with.
        let query: String

        /// The path of the verb that must come first.
        let firstPath: String

        /// The query, as the test report names the case.
        var testDescription: String { query }
    }

    /// The path of `tools.environment.variables`.
    private static let variablesPath = "environment.variables"

    /// The path of `tools.environment.os`.
    private static let operatingSystemPath = "environment.os"

    /// The path of `tools.environment.now`.
    private static let nowPath = "environment.now"

    /// The queries, each with the verb that answers it.
    static let verbQueries = [
        VerbQuery(query: "environment variable", firstPath: variablesPath),
        VerbQuery(query: "operating system", firstPath: operatingSystemPath),
        VerbQuery(query: "current date", firstPath: nowPath),
        VerbQuery(query: "what time is it", firstPath: nowPath),
    ]

    /// The number of matches that each test reads: the first one only.
    private static let firstMatchOnly = 1

    // MARK: - Helpers

    /// A registry with the environment capability over the injected context,
    /// and the git capability and the files capability over one temporary
    /// repository.
    ///
    /// - Parameter repository: The repository whose work folder is the root
    ///   of the git capability and of the files capability.
    /// - Returns: The registry.
    /// - Throws: What `InjectedEnvironment.context()` or `buildRegistry()`
    ///   throws.
    private static func makeRegistry(over repository: TemporaryGitRepository) throws -> MultiTool.Registry {
        try MultiTool.Builder()
            .withEnvironment(context: InjectedEnvironment.context())
            .withGit(root: repository.workDirectory)
            .withFiles(root: repository.workDirectory)
            .buildRegistry()
    }

    // MARK: - Tests

    /// Each query ranks the environment verb that answers it first.
    @Test("a search for what an environment verb answers ranks that verb first", arguments: verbQueries)
    func aSearchRanksTheVerbThatAnswersItFirst(_ verbQuery: VerbQuery) async throws {
        let repository = try TemporaryGitRepository()
        let registry = try Self.makeRegistry(over: repository)
        let searcher = SearchToolsTool.makeSearcher(over: registry.surface.entries, selection: nil, embedder: nil)

        let paths = try await searcher.search(intent: verbQuery.query, limit: Self.firstMatchOnly).map(\.id)

        #expect(paths == [verbQuery.firstPath], "the matches for \"\(verbQuery.query)\" were \(paths)")
    }
}
