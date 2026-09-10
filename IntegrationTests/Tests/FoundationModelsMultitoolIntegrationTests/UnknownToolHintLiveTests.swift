import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The time limit of the did-you-mean hint test, in minutes.
///
/// The test resolves the plumbing probe profile, embeds the nine-entry catalog
/// one time, and resolves three wrong paths. It generates nothing at all: the
/// hint searcher runs in `.retrieval` mode with no selection tier, so the only
/// model work is the catalog embed and one query embed for each guess that
/// reaches tier 2. Measured on a warm machine on 2026-09-10, the whole suite
/// took 2.7 s, and eight cases took the same 2.7 s — the resolution is the
/// cost, and the cases are free beside it. Four minutes stands far over that
/// and over a cold load, which is the one slow part, and a run that reaches it
/// is parked rather than slow.
private let unknownToolHintTimeLimitMinutes = 4

/// The label the printed result and skip lines carry.
private let unknownToolHintScenarioName = "unknownToolHint"

/// One wrong `tools.*` path this suite drives, and what the package promises
/// the hint answers for it.
struct ImaginedToolPath: Sendable {

    /// What shape of wrong path this is, in words, for the printed line.
    let shape: String

    /// The path the snippet called, without its `tools.` prefix — a path the
    /// files-and-shell surface does not define.
    let imaginedPath: String

    /// The tier that must answer ``imaginedPath``, which is what says *which*
    /// ranker the case measures: `.nameResemblance` is the dependency-free
    /// tier 1, and `.catalogRelevance` is the hint searcher this card is
    /// about.
    let tier: UnknownToolHint.SuggestionTier

    /// The catalog path the hint must name first, or `nil` when the shape
    /// declares no one right answer.
    ///
    /// A declaration, never a measurement: it is written by a reader of the
    /// nine tool descriptions who asks what a model reaching for
    /// ``imaginedPath`` was trying to do.
    let bestPath: String?
}

/// The three shapes of wrong path card `^2rwvx3h` asks for, each beside the
/// tier that must answer it and the entry it must name.
///
/// **Why exactly these three.** A model gets a `tools.*` name wrong in three
/// ways, and the two tiers of `UnknownToolHint` divide them:
///
/// 1. **A spelling mistake.** `files.raed` shares its stem with `files.read`,
///    so tier 1's trigram overlap settles it with no model at all. This case
///    measures that tier 2 is not reached where tier 1 can answer.
/// 2. **A wrong noun.** `process.spawn` is the right work — start a program
///    and let it run — under a noun the catalog never uses. It shares no
///    trigram with any entry, so tier 1 rejects it, and the hint searcher of
///    this card is the only tier that can reach `shell.execute`. It reaches it
///    through what the entry is *for*: card `^p06rh7z` rewrote that
///    description to open "execute runs one command, and it is how you do
///    everything the file verbs cannot", which is the text this case ranks
///    against.
/// 3. **Nothing of this surface.** `weather.getForecast` is a real-looking
///    name for work no entry of a files-and-shell surface does. No path is
///    declared for it, because no reader can declare one. What the package
///    promises here is that the hint invents no name, and every case asserts
///    that.
///
/// **What the tier-2 ranking answered, measured 2026-09-10 on the shipped
/// embedder.** Eight guesses were driven to choose the wrong-noun case, and
/// the readings are recorded here rather than thrown away:
///
///     guess                       named
///     process.spawn               shell.execute
///     terminal.runShellCommand    shell.execute
///     terminal.runCommand         shell.getLines
///     bash.run                    shell.getLines
///     terminal.runTests           shell.getLines
///     document.fetchText          files.patch
///     weather.getForecast         shell.getLines
///
/// Every one of the seven named a real entry, which is the promise this suite
/// holds. Three of them named the wrong entry of the right capability:
/// `terminal.runCommand` asks to run a command and is answered with the verb
/// that reads what a command printed. Card `^pwn02m4` owns that miss. This
/// suite prints each answer and asserts nothing about it beyond the declared
/// cases, so a later fix is measured here rather than argued.
let imaginedToolPaths = [
    ImaginedToolPath(
        shape: "a spelling mistake",
        imaginedPath: "files.raed",
        tier: .nameResemblance,
        bestPath: "files.read"),
    ImaginedToolPath(
        shape: "a wrong noun",
        imaginedPath: "process.spawn",
        tier: .catalogRelevance,
        bestPath: "shell.execute"),
    ImaginedToolPath(
        shape: "nothing of this surface",
        imaginedPath: "weather.getForecast",
        tier: .catalogRelevance,
        bestPath: nil),
]

/// The gated did-you-mean test over the surface the `acp-agent` had.
///
/// **What this suite establishes.** `UnknownToolHint` answers a snippet that
/// called a `tools.*` path the catalog does not hold. Every other test of that
/// path is a unit test with a scripted searcher, so nothing measured the hint
/// with a real catalog and a real embedder behind it — and the ranker is
/// exactly where a scripted searcher says nothing. This suite mounts the
/// nine-entry files-and-shell surface through the production call, takes the
/// bundle's own `hintSearcher` off the holder that mount vends, and resolves
/// three wrong paths against it.
///
/// **It never goes through `searchTools`.** That tool forwards to the other
/// searcher of the bundle — `.auto` mode with a selection tier — and the two
/// suites that grade it are `AgentSurfaceDiscoveryTests` and
/// `HeldOutSurfaceDiscoveryTests`. The searcher here is the retrieval-only one
/// a repair costs, and it is reached the one way a run reaches it:
/// `UnknownToolHint.hint(message:snippet:surface:searcher:)`.
///
/// **What it holds.** For each of the three shapes: the tier that answered,
/// every path the hint named, and every path the hint *text* named are all
/// checked. A named path must be a path the surface really defines, in the
/// resolution and in the text a model reads alike; the two shapes that declare
/// a right answer must name it first; and a tier that answers nothing must
/// name nothing, which is the promise that a guess resembling no entry gets no
/// wrong name.
///
/// **A guess that resembles nothing still gets a name, and the suite records
/// that.** The retrieval tier carries no absolute floor — the type
/// documentation of `UnknownToolHint` says so at `relevanceSuggestionLimit` —
/// so tier 2 answers its best-ranked entry rather than nothing, and
/// `weather.getForecast` was answered with `shell.getLines` on 2026-09-10.
/// `noMatch` is therefore what a *failed ranking* reads as here, and what the
/// third shape holds is the promise a host can rely on: whatever the hint
/// names is a path the surface really defines.
///
/// **Why the plumbing probe model.** No verdict here depends on how well a
/// model generates: this path generates nothing. The ranking is the embedder's,
/// and every profile of this target names the same `CLIRunner.embeddingModel`,
/// so the reading is the same under any of them and the suite takes the
/// cheapest generation weights to resolve. See `plumbingProbeModel` for the
/// plumbing-versus-intelligence test a suite must pass to take it.
///
/// **What it prints.** One line for each shape with the imagined path, the
/// tier that answered, the paths the hint named and the paths its text named,
/// and one line with the size of the catalog behind them.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated did-you-mean hints over the agent's files-and-shell surface",
    .serialized,
    .timeLimit(.minutes(unknownToolHintTimeLimitMinutes))
)
struct UnknownToolHintLiveTests {
    @Test("three shapes of wrong tools.* path each answer with a tool the surface really defines")
    func wrongPathsAnswerWithRealTools() async throws {
        try await withLiveRouterFixture(name: unknownToolHintScenarioName, profile: plumbingProbeProfile) { fixture in
            let surface = try makeFilesAndShellSurface(over: fixture)
            let catalogPathSet = Set(surface.registry.surface.entries.map(\.path))
            reportCatalogSize(of: surface.registry, reportedAs: unknownToolHintScenarioName)

            for imagined in imaginedToolPaths {
                let resolution = try #require(
                    await UnknownToolHint.hint(
                        message: unknownPathMessage(for: imagined.imaginedPath),
                        snippet: unknownPathSnippet(for: imagined.imaginedPath),
                        surface: surface.registry.surface,
                        searcher: surface.hintSearcher
                    )
                )
                let namedInText = catalogPaths(in: resolution.text)
                reportGatedResult(
                    scenario: unknownToolHintScenarioName,
                    line: hintLine(for: imagined, resolution: resolution, namedInText: namedInText))
                expectTheHintNamesRealTools(
                    resolution, namedInText: namedInText, of: catalogPathSet, for: imagined)
            }
        }
    }
}

/// The exception message a snippet's wrong `tools.*` call throws, in the shape
/// JavaScriptCore words it.
///
/// - Parameter imaginedPath: the path the snippet called.
/// - Returns: the message text `UnknownToolHint` scans.
private func unknownPathMessage(for imaginedPath: String) -> String {
    "TypeError: tools.\(imaginedPath) is not a function"
}

/// The `runCode` snippet that called a wrong `tools.*` path and nothing else.
///
/// It names no real path on purpose. `UnknownToolHint` reads the snippet to
/// decide the closing directive, and a snippet that also reached for a real
/// entry proves the model already holds real names — a different case, and one
/// this suite does not drive.
///
/// - Parameter imaginedPath: the path the snippet called.
/// - Returns: the snippet source, without the `tools.*` glue preamble.
private func unknownPathSnippet(for imaginedPath: String) -> String {
    "const answer = await tools.\(imaginedPath)();"
}

/// Holds one resolved hint to naming only tools the surface really defines,
/// to the tier the shape declares, and to the entry the shape declares.
///
/// - Parameters:
///   - resolution: the hint the package answered.
///   - namedInText: the catalog paths the hint text spliced, in text order.
///   - catalogPathSet: every path the driven surface defines.
///   - imagined: the shape that was driven.
private func expectTheHintNamesRealTools(
    _ resolution: UnknownToolHint.Resolution,
    namedInText: [String],
    of catalogPathSet: Set<String>,
    for imagined: ImaginedToolPath
) {
    #expect(
        resolution.tier == imagined.tier,
        """
        "\(imagined.imaginedPath)" (\(imagined.shape)) was answered by \(resolution.tier.rawValue), \
        and the shape declares \(imagined.tier.rawValue)
        """
    )
    #expect(
        catalogPathSet.isSuperset(of: resolution.suggestedPaths),
        """
        "\(imagined.imaginedPath)" was answered with \(resolution.suggestedPaths), \
        which the surface does not define
        """
    )
    #expect(
        catalogPathSet.isSuperset(of: namedInText),
        """
        the hint text for "\(imagined.imaginedPath)" named \(namedInText), \
        which the surface does not define
        """
    )
    #expect(
        namedInText == resolution.suggestedPaths,
        """
        the hint text for "\(imagined.imaginedPath)" named \(namedInText), \
        and the resolution names \(resolution.suggestedPaths)
        """
    )
    #expect(
        resolution.suggestedPaths.isEmpty == (resolution.tier == .noMatch),
        """
        "\(imagined.imaginedPath)" was answered by \(resolution.tier.rawValue) \
        with \(resolution.suggestedPaths)
        """
    )
    #expect(
        resolution.text.contains("tools.\(imagined.imaginedPath) \(UnknownToolHint.missingPathPhrase)"),
        "the hint for \"\(imagined.imaginedPath)\" does not say the path is not in the catalog"
    )
    if let bestPath = imagined.bestPath {
        #expect(
            resolution.suggestedPaths.first == bestPath,
            """
            "\(imagined.imaginedPath)" (\(imagined.shape)) was answered with \
            \(resolution.suggestedPaths), and the shape declares \(bestPath) first
            """
        )
    }
}

/// The printed line of one resolved hint.
///
/// Built in named pieces because one chained interpolation of this length
/// times the type checker out.
///
/// - Parameters:
///   - imagined: the shape that was driven.
///   - resolution: the hint the package answered.
///   - namedInText: the catalog paths the hint text spliced, in text order.
/// - Returns: the line to print.
private func hintLine(
    for imagined: ImaginedToolPath, resolution: UnknownToolHint.Resolution, namedInText: [String]
) -> String {
    let answer =
        "imagined=\(resolution.imaginedPath) tier=\(resolution.tier.rawValue) "
        + "suggested=\(resolution.suggestedPaths) namedInText=\(namedInText)"
    let declared = "declaredTier=\(imagined.tier.rawValue) declaredBest=\(imagined.bestPath ?? "none")"
    return "\(answer) \(declared) directive=\(resolution.directive) shape=\"\(imagined.shape)\""
}
