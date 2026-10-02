import Foundation
import FoundationModelsMetadataRegistry
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
import ScenarioGrading

/// The label the printed result and skip lines carry.
private let overBudgetScenarioName = "overBudgetSurfaceDiscovery"

/// The name of the shell store directory inside the session root.
private let overBudgetShellStoreDirectoryName = ".shell"

/// The `task` strings this suite drives.
///
/// One, because the card asks for one surface above the budget and a short
/// run, and because one query already reaches across the whole catalog: the
/// tier prompts every slice for each query, in order, and splices what each
/// slice answers. The string asks for a verb of the files capability, which
/// stands at the head of the catalog.
///
/// Card `^3vtvrzg` removed a second string, "run a SQL query against the
/// database and read the rows", which asked for a verb far below the head.
/// It went through the same two slices and the same splice as the string
/// that stays, so it proved nothing more, and it cost 10.8 s on the CI
/// runner `mini` (run `37048824337`).
private let overBudgetQueries = [
    "read the contents of a file on disk"
]

/// The gated discovery test over a surface above the selection budget.
///
/// **What this suite establishes.** `AgentSurfaceDiscoveryTests` drives a
/// nine-entry surface, whose assembled prefix measured about 7,600 characters
/// against a 32,000-character budget when card `^46j5hqw` read it. Card
/// `^p06rh7z` wrote the nine tool descriptions again after that reading, so
/// the size today is not that number; each under-budget run prints the size
/// it assembled, and the surface stays far under the budget. Every run of it
/// therefore takes the under-budget path of
/// `SelectionTier.search(intent:limit:)`. This suite takes the other path.
/// It mounts the files and shell capabilities beside
/// four connected MCP servers of ten verbs each — the shape a host builds
/// when it connects an issue tracker, a database, an observability stack and
/// a delivery pipeline — and that catalog assembles a prefix above the
/// budget, which the tier then splits into slices and prompts one at a time.
///
/// **The budget is untouched.** The path is reached by making the surface
/// large through the mount a host really uses, never by lowering
/// `SelectionConfig.defaultCapacityCharacterLimit`. A test that lowered the
/// budget would measure the test.
///
/// **What it holds.** What this package owns, and nothing about how well a
/// model picks: the surface is above the budget, each call answers without
/// an error, and each answer holds only paths the catalog really defines,
/// each one time, inside the limit of the call (``DiscoveryAnswerCheck``).
/// How many paths a query matches is a reading of the model, and an empty
/// answer is a valid answer. Card `^xr5w83f` removed the earlier assertion
/// that the two queries together answer at least one match. On 2026-10-02
/// the probe model answered `{"ids": []}` for each slice of each query,
/// although the slice that holds `files.read` showed that path in its
/// catalog, its prompt and its grammar. The code gave that empty answer
/// unchanged. Thus that assertion measured the model, not this package. The
/// order rule for matches that come from more than one slice is written on
/// `SearchToolsTool.format(task:matches:sample:)` and held, deterministically
/// and with no model, by `OverBudgetSelectionOrderTests` in the root
/// package.
///
/// **Why the plumbing probe model.** The verdict does not depend on how well
/// the model selects, so the suite takes `plumbingProbeProfile` — see that
/// constant for the plumbing-versus-intelligence test a suite must pass to
/// take it.
///
/// **What it prints.** The entry count and the prefix size of the surface
/// against the budget, then one line per call with its match count, its
/// slice count, its elapsed time, its matched paths and the raw ids each
/// slice's model answered. Nothing asserts on the time or on the counts: the
/// time is there because an over-budget search costs one model call for each
/// slice, and nothing else reports that; the raw ids are there so that a
/// reader can tell an empty model answer from an answer the code lost.
///
/// Packaged like every gated suite: in the nested `IntegrationTests`
/// package, out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated searchTools discovery over a surface above the selection budget",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct OverBudgetSurfaceDiscoveryTests {
    @Test("a surface above the budget answers spliced-once, unique, in-limit matches from its slices")
    func anOverBudgetSurfaceAnswersUsableMatches() async throws {
        try await withLiveRouterFixture(name: overBudgetScenarioName, profile: plumbingProbeProfile) { fixture in
            // The mount stands in the `MCPTestServer` product, which the root
            // package's `OverBudgetSelectionOrderTests` calls too — see
            // `makeLargeCatalogSurface(root:shellStoreDirectoryName:)`.
            let mounted = try await makeLargeCatalogSurface(
                root: LiveRouterFixture.makeTempDir(),
                shellStoreDirectoryName: overBudgetShellStoreDirectoryName)
            // The production mount, never a reimplementation of its wiring:
            // the same call `CLIRunner.runDemo` makes, with the profile's
            // flash slot as the librarian and its embedding handle beside it,
            // through the same `RouterDiscoverySeams` adapter.
            let seams = fixture.discoverySeams
            let searchTools = try #require(
                mounted.registry
                    .makeSessionTools(selection: seams.selection, embedder: seams.embedder)
                    .compactMap { $0 as? SearchToolsTool }
                    .first
            )
            reportOverBudgetCatalogSize(of: mounted.registry)
            #expect(
                selectionPrefix(of: mounted.registry).count > SelectionConfig.defaultCapacityCharacterLimit,
                "the surface is at or under the budget, so this suite measures the under-budget path"
            )

            let check = DiscoveryAnswerCheck(surfaceOf: mounted.registry)
            var countedSelections = 0
            let clock = ContinuousClock()
            for query in overBudgetQueries {
                let start = clock.now
                let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: query))
                let elapsed = clock.now - start
                let selections = try NativeTranscript.selections(in: fixture.transcriptEvents(), slot: .flash)
                let sliceSelections = selections.dropFirst(countedSelections)
                countedSelections = selections.count

                let paths = catalogPaths(in: feedback)
                report(
                    overBudgetLine: "matches=\(paths.count) slices=\(sliceSelections.count) elapsed=\(elapsed) "
                        + "paths=\(paths) selection=\(sliceSelections.map(\.ids)) query=\"\(query)\""
                )
                check.expectNoFault(in: paths, answering: query)
            }
            withExtendedLifetime(mounted.servers) {}
        }
    }
}

/// Prints the size of the catalog the selection model holds, against the
/// budget it is measured by.
///
/// - Parameter registry: the registry whose surface the selection tier
///   assembles its prefix from.
private func reportOverBudgetCatalogSize(of registry: MultiTool.Registry) {
    let entries = registry.surface.entries
    report(
        overBudgetLine: "entries=\(entries.count) prefixCharacters=\(selectionPrefix(of: registry).count) "
            + "budget=\(SelectionConfig.defaultCapacityCharacterLimit)"
    )
}

/// Prints one `RESULT` line of this suite under this suite's own label.
///
/// - Parameter line: the reading to print after the label.
private func report(overBudgetLine line: String) {
    reportGatedResult(scenario: overBudgetScenarioName, line: line)
}
