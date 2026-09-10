import Foundation
import FoundationModelsMetadataRegistry
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
import ScenarioGrading

/// The time limit of the over-budget discovery test, in minutes.
///
/// The test resolves the plumbing probe model and makes two `searchTools`
/// calls, and each call is one grammar-constrained generation for each slice
/// of the catalog. Six minutes stands over the model load plus a handful of
/// such generations, and a run that reaches it is parked rather than slow.
private let overBudgetTimeLimitMinutes = 6

/// The label the printed result and skip lines carry.
private let overBudgetScenarioName = "overBudgetSurfaceDiscovery"

/// The name of the shell store directory inside the session root.
private let overBudgetShellStoreDirectoryName = ".shell"

/// The two `task` strings this suite drives.
///
/// Two, because the card asks for one surface above the budget and a short
/// run, and because the two together reach across the catalog: the first
/// asks for a verb of the files capability, which stands at the head of the
/// catalog, and the second for a verb of a connected platform server, which
/// stands far below it.
private let overBudgetQueries = [
    "read the contents of a file on disk",
    "run a SQL query against the database and read the rows",
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
/// model picks: every match is spliced one time, no id is repeated, the
/// count obeys the limit of the call, every matched path is a path the
/// catalog really defines, and the two queries together answer at least one
/// match, so the result is one a model can act on. The order rule for
/// matches that come from more than one slice is written on
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
/// slice count and its elapsed time. Nothing asserts on the time: the
/// reading is there because an over-budget search costs one model call for
/// each slice, and nothing else reports that.
///
/// Packaged like every gated suite: in the nested `IntegrationTests`
/// package, out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated searchTools discovery over a surface above the selection budget",
    .serialized,
    .timeLimit(.minutes(overBudgetTimeLimitMinutes))
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
            let entries = mounted.registry.surface.entries
            let catalogPathSet = Set(entries.map(\.path))
            // The production mount, never a reimplementation of its wiring:
            // the same call `CLIRunner.runDemo` makes, with the profile's
            // flash slot as the librarian and its embedding handle beside it.
            let searchTools = try #require(
                mounted.registry
                    .makeSessionTools(librarian: fixture.profile.flash, embedder: fixture.profile.embedding)
                    .compactMap { $0 as? SearchToolsTool }
                    .first
            )
            reportOverBudgetCatalogSize(of: mounted.registry)
            #expect(
                selectionPrefix(of: mounted.registry).count > SelectionConfig.defaultCapacityCharacterLimit,
                "the surface is at or under the budget, so this suite measures the under-budget path"
            )

            var matchedPathCount = 0
            var countedSelections = 0
            let clock = ContinuousClock()
            for query in overBudgetQueries {
                let start = clock.now
                let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: query))
                let elapsed = clock.now - start
                let selections = try NativeTranscript.selections(in: fixture.transcriptEvents(), slot: .flash)
                let slices = selections.count - countedSelections
                countedSelections = selections.count

                let paths = catalogPaths(in: feedback)
                matchedPathCount += paths.count
                reportOverBudgetLine(
                    "matches=\(paths.count) slices=\(slices) elapsed=\(elapsed) paths=\(paths) query=\"\(query)\""
                )

                #expect(Set(paths).count == paths.count, "\"\(query)\" spliced a repeated id: \(paths)")
                #expect(paths.count <= entries.count, "\"\(query)\" answered more matches than the limit of the call")
                #expect(
                    catalogPathSet.isSuperset(of: paths),
                    "\"\(query)\" spliced a path the catalog does not define: \(paths)"
                )
            }
            #expect(matchedPathCount > 0, "both queries answered no match at all, so nothing above was measured")
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
    reportOverBudgetLine(
        "entries=\(entries.count) prefixCharacters=\(selectionPrefix(of: registry).count) "
            + "budget=\(SelectionConfig.defaultCapacityCharacterLimit)"
    )
}

/// Prints one `RESULT` line of this suite under this suite's own label.
///
/// - Parameter line: the reading to print after the label.
private func reportOverBudgetLine(_ line: String) {
    reportGatedResult(scenario: overBudgetScenarioName, line: line)
}
