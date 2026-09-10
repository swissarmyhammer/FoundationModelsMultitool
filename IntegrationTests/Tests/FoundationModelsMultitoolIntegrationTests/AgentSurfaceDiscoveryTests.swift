import Foundation
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool
import ScenarioGrading

/// The time limit of the agent-surface discovery test, in minutes.
///
/// The test resolves a 4B model and makes ten `searchTools` calls, and each
/// call is one grammar-constrained generation of a few tokens. Measured on the
/// SWE-bench run the card records, each selection took 1.1 s to 2.4 s. Five
/// minutes stands far over the model load plus ten such calls, and a run that
/// reaches it is parked rather than slow.
private let agentSurfaceTimeLimitMinutes = 5

/// The label the printed result and skip lines carry.
private let agentSurfaceScenarioName = "agentSurfaceDiscovery"

/// The name of the shell store directory inside the session root.
private let shellStoreDirectoryName = ".shell"

/// The ten `task` strings the `acp-agent` gave to `searchTools` on the
/// SWE-bench instance `astropy__astropy-12907`, in the order it gave them.
///
/// Read out of the unified log of that run and recorded on card `^zqz1zan`.
/// The numbers that card assigns them are one-based positions in this array.
let agentSurfaceQueries = [
    "Search the astropy codebase for files, read code, and run tests",
    "list files and read file contents",
    "grep search for text pattern in files",
    "run a shell command or python script, execute code",
    "run pytest tests, execute",
    "write file, edit file, create file",
    "edit code, modify source file, patch",
    "apply changes to a file, save file contents",
    "file operations: create, write, append, delete, move",
    "create a new text file with given content on disk",
]

/// The one-based numbers of the queries that must answer with at least one
/// match — queries 4 to 9 of the card. Each of them asks for a way to run a
/// command or to change a file, and the surface holds a verb for each.
let agentSurfaceQueriesThatMustAnswer = 4...9

/// The catalog paths at least one of which must be among the matches of every
/// query in `agentSurfaceQueriesThatMustAnswer`: the write verb, the edit
/// verb, and the shell's run-plane verb.
let agentSurfaceMutatingPaths: Set<String> = ["files.write", "files.edit", "shell.execute"]

/// The gated discovery test over the surface the `acp-agent` had.
///
/// **What this suite establishes.** Card `^zqz1zan`: on 2026-09-09 the agent
/// ran with `tools.files` on and writable and `tools.shell` on, made ten
/// `searchTools` calls, and got an empty answer for eight of them — every
/// query for a way to write, edit or run. The main session never saw the
/// write, edit or shell verb, and the run ended with an empty patch. This
/// suite builds that surface, mounts `searchTools` through the production
/// path, drives the same ten queries through the selection tier on the
/// agent's own flash model, and holds queries 4 to 9 to answering with the
/// write, edit or shell entry among the matches.
///
/// **Why the flash model is pinned here.** The selection tier's answer is a
/// property of the model that gives it: the 27B the CLI ships selects where
/// the 4B the agent ships answered empty. `agentFlashModel` states the pin
/// and the rule that no other suite takes it.
///
/// **What the fix was, as this suite measured it.** Before the fix this
/// suite reproduced the agent's log exactly: two of ten queries answered,
/// eight `{"ids":[]}`. The catalog, the grammar and the prompt shape were the
/// same in both runs; the one change between RED and GREEN is the selection
/// preamble, which tells the model to prefer the closest candidates over an
/// empty answer. With it, the same model answers all ten.
///
/// That wording lived in this package as `SearchToolsTool.selectionPreamble`
/// until card `^46j5hqw`. Ranker card `^zxm99zs` moved the deciding sentence
/// into `String.selectionDefault`, and `^46j5hqw` measured the two wordings
/// against each other here — three rounds of the ten queries each, on the
/// same model and the same catalog. The ranker default answered 30 of 30 and
/// held the write, edit or shell verb in every one of queries 4 to 9, so the
/// local constant is gone and the tier takes the default.
///
/// **What it prints.** One line per query with the matched paths and the raw
/// ids the selection model answered, read off the Router recording the same
/// way `SelectionForkPerCallTests` reads its fork trace, and one line with
/// the size of the catalog the model held. Those lines are what the card
/// asks to be pasted; nothing asserts on them.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated searchTools discovery over the agent's files-and-shell surface",
    .serialized,
    .timeLimit(.minutes(agentSurfaceTimeLimitMinutes))
)
struct AgentSurfaceDiscoveryTests {
    @Test("queries 4 to 9 of the agent each find the write, edit or shell entry on the agent's flash model")
    func agentQueriesFindTheWriteEditAndShellEntries() async throws {
        try await withLiveRouterFixture(name: agentSurfaceScenarioName, profile: agentDiscoveryProfile) { fixture in
            let root = LiveRouterFixture.makeTempDir()
            let registry = try MultiTool.Builder()
                .withFiles(root: root, readOnly: false)
                .withShell(storeDirectory: root.appendingPathComponent(shellStoreDirectoryName, isDirectory: true))
                .buildRegistry()
            // The production mount, never a reimplementation of its wiring:
            // the same call the agent's `ToolCatalog.sessionSurface` makes,
            // with the profile's embedding handle passed the way the card's
            // fix asks every host to pass it.
            let searchTools = try #require(
                registry.makeSessionTools(librarian: fixture.profile.flash, embedder: fixture.profile.embedding)
                    .compactMap { $0 as? SearchToolsTool }
                    .first
            )
            reportCatalogSize(of: registry)

            var matchedPaths: [[String]] = []
            for query in agentSurfaceQueries {
                let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: query))
                matchedPaths.append(catalogPaths(in: feedback))
            }
            let selections = try NativeTranscript.selections(in: fixture.transcriptEvents(), slot: .flash)

            for (index, query) in agentSurfaceQueries.enumerated() {
                let number = index + 1
                let paths = matchedPaths[index]
                let rawIDs = index < selections.count ? selections[index].ids : []
                reportDiscoveryLine("q\(number) matches=\(paths.count) paths=\(paths) selection=\(rawIDs) query=\"\(query)\"")
                guard agentSurfaceQueriesThatMustAnswer.contains(number) else { continue }
                #expect(
                    !paths.isEmpty,
                    "query \(number) \"\(query)\" answered no match; the surface holds \(agentSurfaceMutatingPaths.sorted())"
                )
                #expect(
                    !agentSurfaceMutatingPaths.isDisjoint(with: paths),
                    "query \(number) \"\(query)\" matched \(paths), none of \(agentSurfaceMutatingPaths.sorted())"
                )
            }
        }
    }
}

/// Prints the size of the catalog the selection model holds in its
/// instructions for `registry` — the number the card asks for.
///
/// - Parameter registry: the registry whose surface the selection tier
///   assembles its prefix from.
private func reportCatalogSize(of registry: MultiTool.Registry) {
    let entries = registry.surface.entries
    let prefix = SelectionTier.assemblePrefix(
        preamble: .selectionDefault, catalog: MetadataIndex(items: entries))
    reportDiscoveryLine(
        "entries=\(entries.count) prefixCharacters=\(prefix.count) "
            + "budget=\(SelectionConfig.defaultCapacityCharacterLimit) ids=\(entries.map(\.path))"
    )
}

/// Prints one `RESULT` line of this suite under this suite's own label.
///
/// - Parameter line: the reading to print after the label.
private func reportDiscoveryLine(_ line: String) {
    reportGatedResult(scenario: agentSurfaceScenarioName, line: line)
}
