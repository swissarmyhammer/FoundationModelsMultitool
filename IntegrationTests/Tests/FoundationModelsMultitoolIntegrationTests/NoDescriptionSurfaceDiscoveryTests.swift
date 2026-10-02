import Foundation
import FoundationModelsMetadataRegistry
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// The label the printed result lines carry.
private let noDescriptionScenarioName = "noDescriptionSurfaceDiscovery"

/// The name of the shell store directory inside the session root.
private let noDescriptionShellStoreDirectoryName = ".shell"

/// The domain whose server publishes no description.
///
/// One domain, and not every domain: the reading is about what a summary
/// block holds when the description is gone, and a catalog above the
/// selection budget would add slicing to the same reading for no gain.
private let noDescriptionDomain = LargeCatalogDomain.database

/// The queries this suite drives, each with the verbs a reader says answer
/// it.
///
/// Each query is written the way a person writes it, and never as the name of
/// the verb: a query that spelled `run_query` would be answered by the banner
/// alone, and the reading would say nothing about the text under it.
private let noDescriptionQueries = [
    GradedDiscoveryQuery(
        task: "read the rows a SQL statement answers, against the reporting database",
        correctPaths: ["database.run_query"]),
    GradedDiscoveryQuery(
        task: "which columns does the customers table have, and what is its primary key",
        correctPaths: ["database.describe_table"]),
    GradedDiscoveryQuery(
        task: "this statement is far too slow, find out what the planner does with it",
        correctPaths: ["database.explain_query"]),
]

/// The gated discovery test over a surface of tools that publish no
/// description.
///
/// **What this suite establishes.** An MCP server is permitted to publish no
/// description for a tool, and `MCPTool.description` then carries the empty
/// string. Card `^0z0te3n` made the selection prompt hold the description of
/// each tool and nothing else, so such a tool left the `// tools.<path>`
/// banner standing alone: the selection model had to pick it from a path.
/// `APISurface.Entry.summaryBlock` now writes a sentence in its place, which
/// names the verb and the names of its arguments.
///
/// **What it measures.** The catalog of the shipped text: each entry reads
/// its own `summaryBlock`, through the conformance of `APISurface.Entry`, so
/// the searcher reads what a host gives the selection tier. Each query is
/// driven one time, on one model.
///
/// **One text, not three.** Card `^cfyj4gc` measured three texts here: the
/// banner alone, the banner and the name of the tool, and the shipped
/// sentence. The first two are texts this test built and the package never
/// renders, so the checks on them proved nothing about the code. Card
/// `^3vtvrzg` removed them: they cost 6 of the 9 selection calls of this
/// suite, approximately 23 s of its 37.6 s on the CI runner `mini` (run
/// `37048824337`).
///
/// **What it holds.** Only what the code of this package controls: each
/// search answers without an error, each declared path is a path of the
/// catalog, and each answer holds only catalog paths, each one time, inside
/// the limit (``DiscoveryAnswerCheck``). How many declared paths the text
/// finds is a measurement of the model: the suite prints it and asserts
/// nothing on it. Card `^xr5w83f` removed the earlier floor, that the shipped
/// text find at least one declared path over the run, because that floor
/// failed when the model changed, also when the code was correct.
///
/// **Why the plumbing probe model.** `agentFlashModel` is reserved to
/// `AgentSurfaceDiscoveryTests` by a written rule on that constant — "no
/// other suite may take this constant" — so this suite reads the flash slot
/// of ``plumbingProbeProfile``.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated searchTools discovery over a surface of tools with no description",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct NoDescriptionSurfaceDiscoveryTests {
    @Test("the shipped text for a tool with no description gives answers of real catalog paths, one time each")
    func theShippedTextForAToolWithNoDescriptionAnswersRealCatalogPaths() async throws {
        try await withLiveRouterFixture(
            name: noDescriptionScenarioName, profile: plumbingProbeProfile
        ) { fixture in
            // The mount stands in the `MCPTestServer` product, the same one
            // the over-budget suites read, with the description turned off.
            let mounted = try await makeLargeCatalogSurface(
                root: LiveRouterFixture.makeTempDir(),
                shellStoreDirectoryName: noDescriptionShellStoreDirectoryName,
                domains: [noDescriptionDomain],
                describing: false)
            let entries = mounted.registry.surface.entries
            let selection = try #require(
                try SearchToolsTool.makeSelection(
                    fixture.discoverySeams.selection, ids: entries.map(\.path)),
                "the profile resolved no librarian, so no selection could be measured"
            )
            reportGatedResult(
                scenario: noDescriptionScenarioName,
                line: "entries=\(entries.count) domain=\(noDescriptionDomain.serverName) "
                    + "queries=\(noDescriptionQueries.count)")
            let check = DiscoveryAnswerCheck(surfaceOf: mounted.registry)
            check.expectEveryDeclaredPathIsInTheCatalog(of: noDescriptionQueries)

            let searcher = MetadataSearcher(
                items: entries, mode: .selection, embedder: nil, selection: selection)
            let group = try await measure(through: searcher, limit: check.limit)
            check.expectNoFault(in: group, answering: noDescriptionQueries)
            withExtendedLifetime(mounted.servers) {}
        }
    }
}

/// Drives each query of this suite through `searcher` one time, prints one
/// line for each query and one line for the whole group, and answers the
/// grade of the group.
///
/// The grading is `DiscoveryGrade`, the same one the other gated discovery
/// suites read, so a line of this suite reads like a line of theirs.
///
/// - Parameters:
///   - searcher: the searcher over the shipped text.
///   - limit: how many matches each search asks for. The whole catalog, so
///     the reading is the order the model answered in and never a cut this
///     test made.
/// - Returns: the grade of each query, in the order this suite lists them.
/// - Throws: what the search throws.
private func measure(
    through searcher: MetadataSearcher<APISurface.Entry>,
    limit: Int
) async throws -> DiscoveryGroupGrade {
    let grades = try await noDescriptionQueries.mappedInOrder { query in
        let matches = try await searcher.search(
            intent: query.task, limit: limit)
        let grade = DiscoveryGrade(query: query, matchedPaths: matches.map(\.id))
        reportGatedResult(
            scenario: noDescriptionScenarioName,
            line: "matches=\(grade.matchedPaths.count) correct=\(grade.correctCount) "
                + "wrong=\(grade.wrongCount) paths=\(grade.matchedPaths) "
                + "query=\"\(query.task)\"")
        return grade
    }
    let group = DiscoveryGroupGrade(grades: grades)
    reportGatedResult(
        scenario: noDescriptionScenarioName,
        line: "correctTotal=\(group.correctCount) wrongTotal=\(group.wrongCount)")
    return group
}

private extension Sequence {

    /// Maps every element with an asynchronous transform, one element at a
    /// time and in the order the sequence lists them.
    ///
    /// `map` takes no asynchronous transform, and a task group would run the
    /// elements together. Each element here is one model call over one shared
    /// searcher, and the printed lines must stand in query order, so this
    /// walks the head and then the tail and joins the two answers. It builds
    /// the array from those answers, and never by mutating an empty one.
    ///
    /// - Parameter transform: what to make of one element.
    /// - Returns: what `transform` answered for each element, in sequence
    ///   order.
    /// - Throws: whatever `transform` throws, unchanged.
    func mappedInOrder<Transformed>(
        by transform: (Element) async throws -> Transformed
    ) async rethrows -> [Transformed] {
        let elements = Array(self)
        guard let head = elements.first else { return [] }
        let tail = elements.dropFirst()
        return try await [transform(head)] + tail.mappedInOrder(by: transform)
    }
}
