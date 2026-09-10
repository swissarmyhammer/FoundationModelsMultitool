import Foundation
import FoundationModelsMetadataRegistry
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// The time limit of the no-description discovery test, in minutes.
///
/// The test resolves the plumbing probe model and then drives three texts
/// over three queries for ``discoveryRoundCount`` rounds, and each of those
/// twenty-seven searches is one grammar-constrained generation. Ten minutes
/// stands over the model load plus that many generations, and a run that
/// reaches it is parked rather than slow.
private let noDescriptionTimeLimitMinutes = 10

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

/// One candidate text for the selection block of a tool that gives no
/// description.
///
/// Card `^cfyj4gc` names two candidates — the name of the tool alone, and the
/// names of its arguments — and asks for both to be measured. ``banner`` is
/// the third reading, and it is the defect itself: it is what the surface
/// rendered before this card, when an empty description left the banner
/// standing alone under the heading.
private enum NoDescriptionCandidate: String, CaseIterable, Sendable {

    /// The banner alone — what the defect gives the selection model.
    case banner

    /// The banner, then the name of the tool.
    case name

    /// The banner, then the sentence the surface now renders, which names the
    /// verb and the names of its arguments.
    case arguments

    /// The selection block this candidate gives for `entry`.
    ///
    /// An entry that publishes a description keeps the text the surface
    /// renders for it, whichever candidate is under measurement. Only an
    /// entry with no description varies, thus the three readings differ in
    /// the one text this card decides and in nothing else. An entry rewritten
    /// under every candidate would measure the described entries beside it.
    ///
    /// - Parameter entry: the catalog entry to render.
    /// - Returns: the text the selection model reads for that entry.
    func summaryBlock(of entry: APISurface.Entry) -> String {
        let described = entry.descriptor.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard described.isEmpty else { return entry.summaryBlock }
        switch self {
        case .banner:
            return "// tools.\(entry.path)"
        case .name:
            return "// tools.\(entry.path)\n\(entry.descriptor.name)"
        case .arguments:
            return entry.summaryBlock
        }
    }
}

/// One catalog entry under one candidate text.
///
/// The searcher reads the whole item, so a candidate is measured by giving
/// the same entry a different ``renderSummaryBlock()`` and nothing else. The
/// block the main session would read is the entry's own, unchanged, because
/// no rule of this card reaches it.
private struct NoDescriptionItem: SearchableMetadata {

    /// The entry this item stands for.
    let entry: APISurface.Entry

    /// The candidate whose text this item's summary block holds.
    let candidate: NoDescriptionCandidate

    /// The entry's fully-qualified call path.
    var id: String { entry.id }

    /// The entry's own full block, unchanged.
    func renderBlock() -> String { entry.renderBlock() }

    /// The candidate's text for this entry.
    func renderSummaryBlock() -> String { candidate.summaryBlock(of: entry) }
}

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
/// **What it measures.** The same catalog, three times, under the three texts
/// of ``NoDescriptionCandidate``: the banner alone, which is the reading
/// before this card; the name of the tool; and the sentence the surface now
/// renders. Each text is driven over the same queries, for the same number of
/// rounds, on the same model, so the printed totals are comparable.
///
/// **What it holds.** One floor, and no ranking: the shipped text must find
/// at least one declared path over the whole run. A tool that never answers
/// any query is the defect the card names, and a level over that floor is a
/// claim about a model that this suite does not make.
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
    .timeLimit(.minutes(noDescriptionTimeLimitMinutes))
)
struct NoDescriptionSurfaceDiscoveryTests {
    @Test("a tool that publishes no description is still selected from the text the surface writes")
    func aToolWithNoDescriptionIsStillSelected() async throws {
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
                    librarian: fixture.profile.flash, ids: entries.map(\.path)),
                "the profile resolved no librarian, so no selection could be measured"
            )
            reportGatedResult(
                scenario: noDescriptionScenarioName,
                line: "entries=\(entries.count) domain=\(noDescriptionDomain.serverName) "
                    + "queries=\(noDescriptionQueries.count) rounds=\(discoveryRoundCount)")

            let readings = try await NoDescriptionCandidate.allCases.mappedInOrder {
                candidate in
                let items = entries.map { NoDescriptionItem(entry: $0, candidate: candidate) }
                let searcher = await MetadataSearcher(
                    items: items, mode: .selection, embedder: nil, selection: selection)
                let total = try await measure(
                    candidate: candidate, through: searcher, limit: entries.count)
                return (candidate, total)
            }
            let totals = Dictionary(uniqueKeysWithValues: readings)

            let shipped = totals[.arguments]?.correct ?? 0
            reportGatedResult(
                scenario: noDescriptionScenarioName,
                line: NoDescriptionCandidate.allCases
                    .map {
                        "\($0.rawValue)=\(totals[$0]?.correct ?? 0)/\(totals[$0]?.wrong ?? 0)"
                    }
                    .joined(separator: " "))
            #expect(
                shipped > 0,
                """
                over \(discoveryRoundCount) rounds of \(noDescriptionQueries.count) queries the \
                selection model found no declared path for a tool that publishes no description, \
                so the text the surface writes in place of a description carries no signal
                """
            )
            withExtendedLifetime(mounted.servers) {}
        }
    }
}

/// Drives every query of this suite through `searcher` for
/// ``discoveryRoundCount`` rounds, prints one line for each round, and
/// answers how many declared paths the whole run found.
///
/// The grading is `DiscoveryGrade`, the same one the other gated discovery
/// suites read, so a line of this suite reads like a line of theirs.
///
/// - Parameters:
///   - candidate: the text under measurement, which labels each printed line.
///   - searcher: the searcher over that text.
///   - limit: how many matches each search asks for. The whole catalog, so
///     the reading is the order the model answered in and never a cut this
///     test made.
/// - Returns: how many declared paths the run found over every round, and how
///   many paths it answered that no query declares.
/// - Throws: what the search throws.
private func measure(
    candidate: NoDescriptionCandidate,
    through searcher: MetadataSearcher<NoDescriptionItem>,
    limit: Int
) async throws -> (correct: Int, wrong: Int) {
    let rounds = try await (1...discoveryRoundCount).mappedInOrder { number in
        try await measureOneRound(
            number: number, candidate: candidate, through: searcher, limit: limit)
    }
    return (
        correct: rounds.reduce(0) { $0 + $1.correctCount },
        wrong: rounds.reduce(0) { $0 + $1.wrongCount }
    )
}

/// Drives every query of this suite through `searcher` one time, prints one
/// line for each query and one line for the round, and answers the graded
/// round.
///
/// - Parameters:
///   - number: the one-based number of this round, which labels each printed
///     line.
///   - candidate: the text under measurement, which labels each printed line.
///   - searcher: the searcher over that text.
///   - limit: how many matches each search asks for.
/// - Returns: the grade of each query of this round, in the order this suite
///   lists them.
/// - Throws: what the search throws.
private func measureOneRound(
    number: Int,
    candidate: NoDescriptionCandidate,
    through searcher: MetadataSearcher<NoDescriptionItem>,
    limit: Int
) async throws -> DiscoveryRound {
    let grades = try await noDescriptionQueries.mappedInOrder { query in
        let matches = try await searcher.search(
            intent: query.task, limit: limit)
        let grade = DiscoveryGrade(query: query, matchedPaths: matches.map(\.id))
        reportGatedResult(
            scenario: noDescriptionScenarioName,
            line: "candidate=\(candidate.rawValue) round=\(number) "
                + "matches=\(grade.matchedPaths.count) correct=\(grade.correctCount) "
                + "wrong=\(grade.wrongCount) paths=\(grade.matchedPaths) "
                + "query=\"\(query.task)\"")
        return grade
    }
    let round = DiscoveryRound(number: number, grades: grades)
    reportGatedResult(
        scenario: noDescriptionScenarioName,
        line: "candidate=\(candidate.rawValue) round=\(number) "
            + "correctTotal=\(round.correctCount) wrongTotal=\(round.wrongCount)")
    return round
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
        _ transform: (Element) async throws -> Transformed
    ) async rethrows -> [Transformed] {
        let elements = Array(self)
        guard let head = elements.first else { return [] }
        let tail = elements.dropFirst()
        return try await [transform(head)] + tail.mappedInOrder(transform)
    }
}
