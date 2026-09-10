import Foundation
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// The time limit of the retrieval-text measurement, in minutes.
///
/// The test resolves the embedding model, embeds the nine catalog texts one
/// time for each of the three settings, and then makes one query embed for
/// each of the twenty-five queries of each setting. Nothing here generates,
/// so the whole run is one model load and 78 embed calls. Measured on a warm
/// machine on 2026-09-10, all of it took 3.4 s. Ten minutes stands far over
/// that and over a cold load, and a run that reaches it is parked rather
/// than slow.
private let retrievalTextTimeLimitMinutes = 10

/// The label the printed result and skip lines carry.
private let retrievalTextScenarioName = "retrievalTextChoice"

/// How many places at the top of a ranking count as found.
///
/// A host reads the first few answers, so a declared tool that ranks below
/// them is not much better than one the ranking missed. Three is the number
/// every count and every level of this suite reads.
private let retrievalTextTopPlaces = 3

/// The one place at the top of a ranking that the counts read on its own.
///
/// `bestRankOne` on each closing line counts the queries whose best declared
/// path took this place.
private let retrievalTextFirstPlace = 1

/// How many places after the point each printed mean carries.
///
/// Two places separate the settings — the 2026-09-10 measurement read means of
/// 1.80, 1.87 and 2.13 on the held-out group — and a third place would only
/// print noise, because the ranks behind the mean are whole numbers.
private let meanBestRankPlacesAfterThePoint = 2

/// How many of the ten agent-surface queries the shipped setting must answer
/// with a declared-correct path in the first ``retrievalTextTopPlaces``
/// places.
///
/// The 2026-09-10 measurement read 10 of 10, and this level holds that
/// reading. See ``GradedDiscoveryGroup/shippedTopPlaceLevel`` for why a level
/// of this kind may be raised and never lowered.
private let shippedAgentSurfaceTopPlaceLevel = 10

/// How many of the fifteen held-out queries the shipped setting must answer
/// with a declared-correct path in the first ``retrievalTextTopPlaces``
/// places.
///
/// The 2026-09-10 measurement read 13 of 15, and this level holds that
/// reading. See ``GradedDiscoveryGroup/shippedTopPlaceLevel`` for why a level
/// of this kind may be raised and never lowered.
private let shippedHeldOutTopPlaceLevel = 13

/// Which text each half of the retrieval tier reads.
///
/// The registry gives one `renderBlock()` to both halves, so a setting that
/// reads two different texts needs an instrument here — see
/// ``SubstitutingTextEmbedding`` — and never a mechanism in this package.
/// Card `^kvefc5z` names these three and no others.
private enum RetrievalTextSetting: String, CaseIterable, Sendable {

    /// The full block for keyword ranking and for the embedder. What the
    /// package ships, and what the protocol default gives.
    case blockBoth = "block/block"

    /// The banner and the description alone for both halves.
    case descriptionBoth = "description/description"

    /// The full block for keyword ranking, the description for the embedder.
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

/// The setting the package ships, and the only one this suite holds to a
/// level.
///
/// The other two are instruments. A level on an instrument would hold the
/// package to a path it does not take.
private let shippedRetrievalTextSetting = RetrievalTextSetting.blockBoth

/// One catalog entry presented to the registry with the text one setting
/// gives the keyword half.
///
/// The registry indexes and embeds whatever `renderBlock()` answers, so this
/// wrapper is how a setting changes the keyword text without touching
/// `APISurface.Entry`'s own conformance, which card `^0z0te3n` settled.
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
/// This is the measurement instrument of the `block/description` setting,
/// and it is deliberately not a mechanism this package ships. The registry
/// hands the embedder the same text it indexes, so the only way to embed a
/// different text is to swap it on the way in. A text with no entry in
/// ``substitutions`` — every query is one — travels unchanged.
private struct SubstitutingTextEmbedding: TextEmbedding {

    /// The embedder every call travels to.
    let base: any TextEmbedding

    /// What to embed instead, keyed by the text the registry hands over.
    let substitutions: [String: String]

    /// The length of every vector ``base`` produces.
    var dimension: Int { base.dimension }

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

    /// The rank of each declared-correct path, in path order.
    let ranks: [DeclaredPathRank]

    /// The best place any declared-correct path took, or `nil` when the
    /// answer ranked none of them.
    var bestRank: Int? { ranks.compactMap(\.rank).min() }

    /// Whether a declared-correct path stands in the first
    /// ``retrievalTextTopPlaces`` places.
    var foundNearTheTop: Bool { (bestRank ?? .max) <= retrievalTextTopPlaces }
}

/// One named group of graded queries, with the standard the shipped setting
/// holds on it.
private struct GradedDiscoveryGroup: Sendable {

    /// The label the printed lines carry.
    let name: String

    /// The queries of the group, in the order the group lists them.
    let queries: [GradedDiscoveryQuery]

    /// How many queries of this group the shipped setting must answer with a
    /// declared-correct path in the first ``retrievalTextTopPlaces`` places.
    ///
    /// A level, not a floor, and it sits at the measurement rather than
    /// under it. Nothing here samples: the embedder and the two keyword
    /// signals answer the same way every run, so the value a settling run
    /// measured is the value every run holds. It may be raised by a later
    /// measurement and never lowered to make a run green.
    let shippedTopPlaceLevel: Int
}

/// The two graded groups this measurement drives, in report order.
///
/// Both lists are taken from the suites that own them — the ten of card
/// `^zqz1zan` and the fifteen of card `^kn9ay20` — so no query is written
/// twice. The levels are the 2026-09-10 measurement of the shipped setting,
/// printed as `bestRankTopThree` on each closing line.
private let retrievalTextGroups = [
    GradedDiscoveryGroup(
        name: "agentSurface",
        queries: agentSurfaceQueries,
        shippedTopPlaceLevel: shippedAgentSurfaceTopPlaceLevel
    ),
    GradedDiscoveryGroup(
        name: "heldOut",
        queries: heldOutQueries,
        shippedTopPlaceLevel: shippedHeldOutTopPlaceLevel
    ),
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
/// the same twenty-five queries. The selection tier is switched off in every
/// one of them — each searcher runs in `.retrieval` mode with no
/// `SelectionConfig` — so the ranking is the retrieval tier's alone and no
/// model picks anything. Each query asks for the whole catalog, so a
/// declared-correct path any signal ranked has a place to report.
///
/// **What it holds.** Every query of every setting must rank at least one
/// declared-correct path, and the shipped setting must additionally hold
/// each group's ``GradedDiscoveryGroup/shippedTopPlaceLevel``. The other two
/// settings are instruments: they are measured and printed, and no level
/// holds them.
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
    .timeLimit(.minutes(retrievalTextTimeLimitMinutes))
)
struct RetrievalTextSurfaceDiscoveryTests {
    @Test("every setting ranks a declared tool for every query, and the shipped setting holds its level")
    func everySettingRanksADeclaredToolForEveryQuery() async throws {
        try await withLiveRouterFixture(name: retrievalTextScenarioName, profile: plumbingProbeProfile) { fixture in
            let entries = try makeFilesAndShellSurface(over: fixture).registry.surface.entries
            reportTextSizes(of: entries)
            let embedder = try #require(SearchToolsTool.makeEmbedding(from: fixture.profile.embedding))

            for setting in RetrievalTextSetting.allCases {
                let searcher = makeRetrievalSearcher(for: setting, over: entries, embedder: embedder)
                for group in retrievalTextGroups {
                    let readings = try await measure(
                        group: group, through: searcher, over: entries.count, in: setting)
                    expectEveryQueryRanksADeclaredPath(readings, of: group, in: setting)
                    if setting == shippedRetrievalTextSetting {
                        expectTheShippedSettingHoldsItsLevel(readings, of: group, in: setting)
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
        ranks: query.correctPaths.sorted().map { path in
            DeclaredPathRank(path: path, rank: order.firstIndex(of: path).map { $0 + 1 })
        }
    )
}

/// Holds every query of one group, in one setting, to ranking at least one
/// of the catalog paths it declares correct.
///
/// This is the floor under the whole measurement: a setting that leaves a
/// query with no declared path anywhere in the ranking has lost that query,
/// whatever its other numbers say.
///
/// - Parameters:
///   - readings: the readings of the group, in query order.
///   - group: the group the readings came from.
///   - setting: the setting the readings were measured in.
private func expectEveryQueryRanksADeclaredPath(
    _ readings: [RetrievalRankReading],
    of group: GradedDiscoveryGroup,
    in setting: RetrievalTextSetting
) {
    for (index, reading) in readings.enumerated() {
        let query = group.queries[index]
        #expect(
            reading.bestRank != nil,
            """
            setting \(setting.rawValue) group \(group.name) query \(index + 1) "\(query.task)" \
            ranked none of \(query.correctPaths.sorted())
            """
        )
    }
}

/// Holds one group of the shipped setting to the level the group states.
///
/// The caller applies this to ``shippedRetrievalTextSetting`` alone. A level
/// on either instrument would hold the package to a path it does not take.
///
/// - Parameters:
///   - readings: the readings of the group, in query order.
///   - group: the group the readings came from.
///   - setting: the setting the readings were measured in.
private func expectTheShippedSettingHoldsItsLevel(
    _ readings: [RetrievalRankReading],
    of group: GradedDiscoveryGroup,
    in setting: RetrievalTextSetting
) {
    let found = readings.filter(\.foundNearTheTop).count
    #expect(
        found >= group.shippedTopPlaceLevel,
        """
        setting \(setting.rawValue) group \(group.name) answered \(found) of \(readings.count) queries \
        with a declared path in the first \(retrievalTextTopPlaces) places, \
        under the level of \(group.shippedTopPlaceLevel)
        """
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
    let means = "meanBestRank=\(format(meanBestRank(of: readings))) "
        + "declaredRanked=\(declaredRanks.count)/\(declared.count) "
        + "declaredTopThree=\(declaredRanks.filter { $0 <= retrievalTextTopPlaces }.count)"
    return "\(counts) \(means)"
}

/// Renders one mean to ``meanBestRankPlacesAfterThePoint`` places, or a dash
/// when there is none.
///
/// - Parameter value: the mean to render.
/// - Returns: the rendered mean.
private func format(_ value: Double?) -> String {
    let specifier = "%.\(meanBestRankPlacesAfterThePoint)f"
    return value.map { String(format: specifier, $0) } ?? "-"
}

/// Prints how long the two texts of each entry are, over the whole surface.
///
/// The block total is the size of the one embed batch a first search pays
/// today, and the summary total is what it would pay if the embedder read
/// the description. That is the cost half of the question card `^kvefc5z`
/// asks.
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
