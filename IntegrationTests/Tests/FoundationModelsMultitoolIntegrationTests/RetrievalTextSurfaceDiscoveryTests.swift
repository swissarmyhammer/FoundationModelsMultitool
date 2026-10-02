import Foundation
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// The label the printed result and skip lines carry.
private let retrievalTextScenarioName = "retrievalTextChoice"

/// How many places at the top of a ranking count as found.
///
/// A host reads the first few answers, so a declared tool that ranks below
/// them is not much better than one the ranking missed. Three is the number
/// every printed count of this suite reads.
private let retrievalTextTopPlaces = 3

/// The one place at the top of a ranking that the counts read on its own.
///
/// `bestRankOne` on each closing line counts the queries whose best declared
/// path took this place.
private let retrievalTextFirstPlace = 1

/// How many places after the point each printed mean carries.
///
/// Two places separate the settings — the 2026-09-29 measurement read means of
/// 1.60, 1.67 and 1.87 on the held-out group — and a third place would only
/// print noise, because the ranks behind the mean are whole numbers.
private let meanBestRankPlacesAfterThePoint = 2

/// Which text each half of the retrieval tier reads.
///
/// The suite presents each setting to the registry through
/// ``RetrievalTextEntry`` and ``SubstitutingTextEmbedding``, and never
/// through the conformance of `APISurface.Entry`. Thus every setting reads
/// the same way whatever the package ships. Card `^kvefc5z` names these
/// three and no others.
private enum RetrievalTextSetting: String, CaseIterable, Sendable {

    /// The full block for keyword ranking and for the embedder. What the
    /// package shipped before card `^a9ketxt`, and what the protocol defaults
    /// give.
    case blockBoth = "block/block"

    /// The banner and the description alone for both halves.
    case descriptionBoth = "description/description"

    /// The full block for keyword ranking, the description for the embedder.
    /// What the package ships since card `^a9ketxt`.
    case blockThenDescription = "block/description"

    /// The text this setting gives the keyword half for `entry`.
    ///
    /// - Parameter entry: the catalog entry to render.
    /// - Returns: the text BM25 and the trigram index read.
    func keywordText(of entry: APISurface.Entry) -> String {
        switch self {
        case .blockBoth, .blockThenDescription:
            entry.block
        case .descriptionBoth:
            entry.summaryBlock
        }
    }

    /// The text this setting gives the embedder for `entry`.
    ///
    /// - Parameter entry: the catalog entry to render.
    /// - Returns: the text the embedder reads.
    func embeddingText(of entry: APISurface.Entry) -> String {
        switch self {
        case .blockBoth:
            entry.block
        case .descriptionBoth, .blockThenDescription:
            entry.summaryBlock
        }
    }
}

/// One catalog entry presented to the registry with the text one setting
/// gives the keyword half.
///
/// This wrapper overrides `renderBlock()` alone, so the protocol defaults
/// make the registry index and embed that same text. Thus the conformance of
/// `APISurface.Entry` has no effect on what a setting measures.
private struct RetrievalTextEntry: SearchableMetadata {

    /// The catalog entry behind this item.
    let entry: APISurface.Entry

    /// The text this item hands the keyword half.
    let keywordText: String

    /// The entry's fully-qualified `tools.*` call path.
    var id: String { entry.path }

    /// The text the keyword half reads.
    ///
    /// - Returns: ``keywordText``.
    func renderBlock() -> String { keywordText }
}

/// An embedder that swaps one text for another before it embeds.
///
/// This is the measurement instrument of the `block/description` setting.
/// ``RetrievalTextEntry`` makes the registry embed the same text it indexes,
/// so this instrument swaps the text on the way in. The package itself
/// ships this setting through `renderEmbeddedText(from:)`, not through this
/// type. A text with no entry in ``substitutions`` — every query is one —
/// travels unchanged.
private struct SubstitutingTextEmbedding: TextEmbedding {

    /// The embedder every call travels to.
    let base: any TextEmbedding

    /// What to embed instead, keyed by the text the registry hands over.
    let substitutions: [String: String]

    /// Embeds `texts`, with every substituted text swapped first.
    ///
    /// - Parameter texts: the texts the registry asks for.
    /// - Returns: one vector for each text, in the same order.
    /// - Throws: whatever ``base`` throws.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await base.embed(texts.map { substitutions[$0] ?? $0 })
    }
}

/// Where one declared-correct path stands in one ranked answer.
private struct DeclaredPathRank: Sendable {

    /// The catalog path a reader declared correct for the query.
    let path: String

    /// The one-based place the path took, or `nil` when no signal ranked it.
    let rank: Int?
}

/// What one query scored in one setting.
private struct RetrievalRankReading: Sendable {

    /// Every path the answer ranked, best first.
    let rankedPaths: [String]

    /// The rank of each declared-correct path, in path order.
    let ranks: [DeclaredPathRank]

    /// The best place any declared-correct path took, or `nil` when the
    /// answer ranked none of them.
    var bestRank: Int? { ranks.compactMap(\.rank).min() }

    /// Whether a declared-correct path stands in the first
    /// ``retrievalTextTopPlaces`` places.
    var foundNearTheTop: Bool { (bestRank ?? .max) <= retrievalTextTopPlaces }
}

/// One named group of graded queries.
private struct GradedDiscoveryGroup: Sendable {

    /// The label the printed lines carry.
    let name: String

    /// The queries of the group, in the order the group lists them.
    let queries: [GradedDiscoveryQuery]
}

/// Twelve `task` strings nobody chose the selection preamble with, each
/// beside the catalog paths a reader says answer it.
///
/// **Where they are driven.** Until card `^3vtvrzg`,
/// `HeldOutSurfaceDiscoveryTests` also drove them through the selection tier.
/// That suite held the same properties over the same surface, on the same
/// model and through the same mount as `AgentSurfaceDiscoveryTests`, so card
/// `^3vtvrzg` removed it (81.0 s on the CI runner `mini`, run `37048824337`).
/// This suite is their one user now: it ranks them in each retrieval setting,
/// and holds each path they declare to be a path of the catalog.
///
/// **Twelve of the fifteen.** The group had fifteen strings. Card `^3vtvrzg`
/// removed three that test the same tool, with the same declared paths and
/// the same kind of phrase, as a string that stays:
///
/// - "open a file and look at one region of it closely" (`files.read`), the
///   same as "i need to read the source file where the defect lives".
/// - "run only the one test that reproduces the bug" and "run a shell command
///   in the project directory" (`shell.execute`), the same kind of "run …"
///   phrase as "i want to run the project test suite now".
///
/// **How these were written, which is the whole value of the group.** A model
/// wrote them in a context of its own, with no file, no repository and no tool
/// call at all. It was given a task description and nothing else: an
/// autonomous coding agent works on a checkout of a Python library; for one
/// episode it must find where a reported defect lives, read the code around
/// it, change the source, confirm the fix by running the test suite, and
/// between episodes inspect the workspace, look at logs and clean up scratch
/// output; it holds no fixed tool list, and before it can act it must ask a
/// discovery service for capabilities by writing a short phrase saying what it
/// wants to do. The instruction told it to write from the work, and forbade
/// any dotted identifier, camelCase name or brand name of any kind. No tool
/// name of this surface was in that context, so no phrase can copy one.
///
/// That is what makes this group different from ``agentSurfaceQueries``.
/// Those chose the wording the selection tier runs, so a reading of that
/// wording on them grades an answer against its own answer key. Nothing chose
/// anything with these strings.
///
/// The correct paths were declared afterwards, once the phrases were fixed, by
/// a reader of the nine tool descriptions of the surface. The declaration
/// therefore cannot have steered the wording.
private let heldOutQueries = [
    GradedDiscoveryQuery(
        task: "show me the files and folders in this checkout",
        correctPaths: ["files.glob", "shell.execute"]),
    GradedDiscoveryQuery(
        task: "i need to read the source file where the defect lives",
        correctPaths: ["files.read"]),
    GradedDiscoveryQuery(
        task: "find every place in the code that mentions this function name",
        correctPaths: ["files.grep"]),
    GradedDiscoveryQuery(
        task: "change a few lines in an existing source file",
        correctPaths: ["files.edit", "files.patch"]),
    GradedDiscoveryQuery(
        task: "rewrite the whole contents of a module",
        correctPaths: ["files.write", "files.patch"]),
    GradedDiscoveryQuery(
        task: "create a new file to hold a regression test",
        correctPaths: ["files.write", "files.patch"]),
    GradedDiscoveryQuery(
        task: "i want to run the project test suite now",
        correctPaths: ["shell.execute"]),
    GradedDiscoveryQuery(
        task: "i need to see what the failing test printed",
        correctPaths: ["shell.getLines", "shell.grepHistory"]),
    GradedDiscoveryQuery(
        task: "read the log file that the last run wrote",
        correctPaths: ["files.read", "shell.getLines"]),
    GradedDiscoveryQuery(
        task: "delete a leftover temporary directory",
        correctPaths: ["shell.execute"]),
    GradedDiscoveryQuery(
        task: "remove a scratch file i made earlier",
        correctPaths: ["files.patch", "shell.execute"]),
    GradedDiscoveryQuery(
        task: "check which source files i have changed so far",
        correctPaths: ["shell.execute"]),
]

/// The two graded groups this measurement drives, in report order.
///
/// The recorded queries of card `^zqz1zan` (``agentSurfaceQueries``) and the
/// held-out queries of card `^kn9ay20` (``heldOutQueries``), each written in
/// one place, so no query is written twice.
private let retrievalTextGroups = [
    GradedDiscoveryGroup(name: "agentSurface", queries: agentSurfaceQueries),
    GradedDiscoveryGroup(name: "heldOut", queries: heldOutQueries),
]

/// The gated measurement that decides which text the retrieval tier reads.
///
/// **The question.** Card `^0z0te3n` made the selection prompt hold the
/// description of each tool alone. It changed one half of the path. The
/// keyword index and the embedder still read the full block, with every
/// `@param` line and the `declare function` line in it. Nobody decided
/// that; it is what the default of `SearchableMetadata` gives when a
/// consumer overrides `renderSummaryBlock()` and not `renderBlock()`.
///
/// **How it is answered.** Three settings, named by ``RetrievalTextSetting``,
/// over the same nine-entry files-and-shell surface, the same embedder and
/// the same twenty queries. The selection tier is switched off in every
/// one of them — each searcher runs in `.retrieval` mode with no
/// `SelectionConfig` — so the ranking is the retrieval tier's alone and no
/// model picks anything. Each query asks for the whole catalog, so a
/// declared-correct path any signal ranked has a place to report.
///
/// **What it holds.** Only what the code of this package controls, in every
/// setting: each search answers without an error, each declared path is a
/// path of the catalog, and each ranking holds only catalog paths, each one
/// time, inside the limit (``DiscoveryAnswerCheck``). Where the declared paths
/// rank is a measurement of the embedder and of the text: the suite prints it
/// and asserts nothing on it. Card `^xr5w83f` removed the earlier fixed
/// levels — a declared path ranked for each query, and 10 of 10 and 14 of 15
/// queries with a declared path in the first three places for the shipped
/// setting — because a change of the embedding model can move those numbers
/// while the code is correct.
///
/// **What it prints.** One line for each query of each setting, with the
/// place each declared-correct path took; and one line closing each group of
/// each setting, with the counts the choice rests on. The numbers of the
/// settling run stand in the doc comment of
/// `APISurface+SearchableMetadata.swift`, beside the choice they made.
///
/// **Why the plumbing profile.** Nothing here generates. The reading is the
/// embedder's, and every profile of this target names the same
/// `CLIRunner.embeddingModel`, so this suite passes the test
/// `plumbingProbeProfile` states: it grades plumbing, not capability.
///
/// Packaged like every gated suite: in the nested `IntegrationTests`
/// package, out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated retrieval-text measurement over the agent's files-and-shell surface",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct RetrievalTextSurfaceDiscoveryTests {
    @Test("every setting ranks only real catalog paths, one time each, for every query")
    func everySettingRanksOnlyRealCatalogPaths() async throws {
        try await withLiveRouterFixture(name: retrievalTextScenarioName, profile: plumbingProbeProfile) { fixture in
            let registry = try makeFilesAndShellSurface(over: fixture).registry
            let entries = registry.surface.entries
            reportTextSizes(of: entries)
            let embedder = fixture.discoverySeams.embedder
            let check = DiscoveryAnswerCheck(surfaceOf: registry)
            for group in retrievalTextGroups {
                check.expectEveryDeclaredPathIsInTheCatalog(of: group.queries)
            }

            for setting in RetrievalTextSetting.allCases {
                let searcher = makeRetrievalSearcher(for: setting, over: entries, embedder: embedder)
                for group in retrievalTextGroups {
                    let readings = try await measure(
                        group: group, through: searcher, over: check.limit, in: setting)
                    for (reading, query) in zip(readings, group.queries) {
                        check.expectNoFault(in: reading.rankedPaths, answering: query.task)
                    }
                }
            }
        }
    }
}

/// Builds the retrieval-only searcher one setting reads with.
///
/// `.retrieval` mode and a `nil` selection tier are what switch the model out
/// of the answer: the ranking is the fused BM25, trigram and cosine ranking
/// and nothing else.
///
/// - Parameters:
///   - setting: which text each half reads.
///   - entries: the catalog entries to index.
///   - embedder: the profile's embedding handle, presented to the registry.
/// - Returns: the searcher of that setting.
private func makeRetrievalSearcher(
    for setting: RetrievalTextSetting,
    over entries: [APISurface.Entry],
    embedder: any TextEmbedding
) -> MetadataSearcher<RetrievalTextEntry> {
    let items = entries.map {
        RetrievalTextEntry(entry: $0, keywordText: setting.keywordText(of: $0))
    }
    let swapped = entries
        .filter { setting.keywordText(of: $0) != setting.embeddingText(of: $0) }
        .map { (setting.keywordText(of: $0), setting.embeddingText(of: $0)) }
    let indexEmbedder: any TextEmbedding =
        swapped.isEmpty
        ? embedder
        : SubstitutingTextEmbedding(
            base: embedder, substitutions: Dictionary(uniqueKeysWithValues: swapped))
    return MetadataSearcher(
        index: MetadataIndex(items: items), mode: .retrieval, embedder: indexEmbedder, selection: nil)
}

/// Drives one group through one setting's searcher and prints one line for
/// each query.
///
/// Every query asks for the whole catalog, so a declared-correct path is
/// absent from a reading only when no signal ranked it at all.
///
/// - Parameters:
///   - group: the queries to drive, in the order the group lists them.
///   - searcher: the retrieval-only searcher of one setting.
///   - catalogCount: how many entries the catalog holds, which is the limit
///     each query asks for.
///   - setting: the setting the searcher was built for, for the printed
///     label.
/// - Returns: one reading for each query, in query order.
/// - Throws: whatever the search throws.
private func measure(
    group: GradedDiscoveryGroup,
    through searcher: MetadataSearcher<RetrievalTextEntry>,
    over catalogCount: Int,
    in setting: RetrievalTextSetting
) async throws -> [RetrievalRankReading] {
    var readings: [RetrievalRankReading] = []
    for (index, query) in group.queries.enumerated() {
        let matches = try await searcher.search(intent: query.task, limit: catalogCount)
        let reading = rankReading(of: query, in: matches.map(\.id))
        readings.append(reading)
        reportGatedResult(
            scenario: retrievalTextScenarioName,
            line: readingLine(setting: setting, group: group, number: index + 1, query: query, reading: reading)
        )
    }
    reportGatedResult(
        scenario: retrievalTextScenarioName,
        line: groupLine(setting: setting, group: group, readings: readings)
    )
    return readings
}

/// Reads the place of each declared-correct path off one ranked answer.
///
/// - Parameters:
///   - query: the query the answer came back for.
///   - order: the ids of the answer, best first.
/// - Returns: the reading of that query.
private func rankReading(of query: GradedDiscoveryQuery, in order: [String]) -> RetrievalRankReading {
    RetrievalRankReading(
        rankedPaths: order,
        ranks: query.correctPaths.sorted().map { path in
            DeclaredPathRank(path: path, rank: order.firstIndex(of: path).map { $0 + 1 })
        }
    )
}

/// The best place any declared-correct path took, over the queries that
/// ranked one, as a mean.
///
/// - Parameter readings: the readings to average.
/// - Returns: the mean best rank, or `nil` when no query ranked a declared
///   path.
private func meanBestRank(of readings: [RetrievalRankReading]) -> Double? {
    let best = readings.compactMap(\.bestRank)
    return best.isEmpty ? nil : Double(best.reduce(0, +)) / Double(best.count)
}

/// The printed line of one graded query of one setting.
///
/// Built in named pieces because one chained interpolation of this length
/// times the type checker out.
///
/// - Parameters:
///   - setting: the setting the reading was measured in.
///   - group: the group the query belongs to.
///   - number: the one-based position of the query in its group.
///   - query: the query that was driven.
///   - reading: what the answer scored.
/// - Returns: the line to print.
private func readingLine(
    setting: RetrievalTextSetting,
    group: GradedDiscoveryGroup,
    number: Int,
    query: GradedDiscoveryQuery,
    reading: RetrievalRankReading
) -> String {
    let ranks = reading.ranks
        .map { "\($0.path):\($0.rank.map(String.init) ?? "-")" }
        .joined(separator: " ")
    let head = "setting=\(setting.rawValue) group=\(group.name) q\(number) "
        + "best=\(reading.bestRank.map(String.init) ?? "-")"
    return "\(head) ranks=[\(ranks)] query=\"\(query.task)\""
}

/// The printed line that closes one group of one setting.
///
/// - Parameters:
///   - setting: the setting the readings were measured in.
///   - group: the group the readings came from.
///   - readings: the readings of the group, in query order.
/// - Returns: the line to print.
private func groupLine(
    setting: RetrievalTextSetting,
    group: GradedDiscoveryGroup,
    readings: [RetrievalRankReading]
) -> String {
    let declared = readings.flatMap(\.ranks)
    let declaredRanks = declared.compactMap(\.rank)
    let counts = "setting=\(setting.rawValue) group=\(group.name) queries=\(readings.count) "
        + "bestRankOne=\(readings.filter { $0.bestRank == retrievalTextFirstPlace }.count) "
        + "bestRankTopThree=\(readings.filter(\.foundNearTheTop).count)"
    let means = "meanBestRank=\(renderedMean(of: meanBestRank(of: readings))) "
        + "declaredRanked=\(declaredRanks.count)/\(declared.count) "
        + "declaredTopThree=\(declaredRanks.filter { $0 <= retrievalTextTopPlaces }.count)"
    return "\(counts) \(means)"
}

/// Renders one mean to ``meanBestRankPlacesAfterThePoint`` places, or a dash
/// when there is none.
///
/// - Parameter value: the mean to render.
/// - Returns: the rendered mean.
private func renderedMean(of value: Double?) -> String {
    let specifier = "%.\(meanBestRankPlacesAfterThePoint)f"
    return value.map { String(format: specifier, $0) } ?? "-"
}

/// Prints how long the two texts of each entry are, over the whole surface.
///
/// The block total is the size of the one embed batch a first search pays
/// when the embedder reads the full block, and the summary total is the size
/// it pays when the embedder reads the description, as the package ships
/// since card `^a9ketxt`. That is the cost half of the question card
/// `^kvefc5z` asks.
///
/// - Parameter entries: the catalog entries of the mounted surface.
private func reportTextSizes(of entries: [APISurface.Entry]) {
    let blockTotal = entries.reduce(0) { $0 + $1.block.count }
    let summaryTotal = entries.reduce(0) { $0 + $1.summaryBlock.count }
    reportGatedResult(
        scenario: retrievalTextScenarioName,
        line: "entries=\(entries.count) blockCharacters=\(blockTotal) summaryCharacters=\(summaryTotal)"
    )
}
