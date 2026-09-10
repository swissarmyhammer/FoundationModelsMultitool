import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The time limit of the agent-surface discovery test, in minutes.
///
/// The test resolves a 4B model and makes ten `searchTools` calls in each of
/// ``discoveryRoundCount`` rounds, and each call is one grammar-constrained
/// generation of a few tokens. Measured on a warm machine on 2026-09-10, the
/// model load plus thirty such calls took 24.4 s. Five minutes stands far over
/// that and over a cold load, and a run that reaches it is parked rather than
/// slow.
private let agentSurfaceTimeLimitMinutes = 5

/// The label the printed result and skip lines carry.
private let agentSurfaceScenarioName = "agentSurfaceDiscovery"

/// The ten `task` strings the `acp-agent` gave to `searchTools` on the
/// SWE-bench instance `astropy__astropy-12907`, in the order it gave them,
/// each beside the catalog paths a reader says answer it.
///
/// Read out of the unified log of that run and recorded on card `^zqz1zan`.
/// The numbers that card assigns them are one-based positions in this array.
///
/// **This group is a regression record, and it is not a held-out set.** The
/// preamble the selection tier runs was chosen by measurement against these
/// same ten strings, so a pass here shows that the wording works for the
/// queries that selected it and shows nothing about a query nobody has seen.
/// `HeldOutSurfaceDiscoveryTests` carries the group that answers that second
/// question. The two groups never mix, and each is reported under its own
/// label.
///
/// The correct paths were declared by reading the nine tool descriptions of
/// the surface: `files.glob` finds files by pattern, `files.read` reads one,
/// `files.grep` searches file text, `files.write` writes a file whole,
/// `files.edit` changes lines of an existing file, `files.patch` adds, updates,
/// deletes or renames files in one envelope, `shell.execute` runs a command,
/// `shell.getLines` reads the captured output of one run, and
/// `shell.grepHistory` searches the captured output of every run.
let agentSurfaceQueries = [
    GradedDiscoveryQuery(
        task: "Search the astropy codebase for files, read code, and run tests",
        correctPaths: ["files.glob", "files.grep", "files.read", "shell.execute"]),
    GradedDiscoveryQuery(
        task: "list files and read file contents",
        correctPaths: ["files.glob", "files.read"]),
    GradedDiscoveryQuery(
        task: "grep search for text pattern in files",
        correctPaths: ["files.grep"]),
    GradedDiscoveryQuery(
        task: "run a shell command or python script, execute code",
        correctPaths: ["shell.execute"]),
    GradedDiscoveryQuery(
        task: "run pytest tests, execute",
        correctPaths: ["shell.execute"]),
    GradedDiscoveryQuery(
        task: "write file, edit file, create file",
        correctPaths: ["files.write", "files.edit", "files.patch"]),
    GradedDiscoveryQuery(
        task: "edit code, modify source file, patch",
        correctPaths: ["files.edit", "files.patch"]),
    GradedDiscoveryQuery(
        task: "apply changes to a file, save file contents",
        correctPaths: ["files.write", "files.edit", "files.patch"]),
    GradedDiscoveryQuery(
        task: "file operations: create, write, append, delete, move",
        correctPaths: ["files.write", "files.edit", "files.patch", "shell.execute"]),
    GradedDiscoveryQuery(
        task: "create a new text file with given content on disk",
        correctPaths: ["files.write", "files.patch"]),
]

/// The one-based numbers of the queries that must answer with at least one
/// match — queries 4 to 9 of the card. Each of them asks for a way to run a
/// command or to change a file, and the surface holds a verb for each.
let agentSurfaceQueriesThatMustAnswer = 4...9

/// The catalog paths at least one of which must be among the matches of every
/// query in `agentSurfaceQueriesThatMustAnswer`: the write verb, the edit
/// verb, and the shell's run-plane verb.
let agentSurfaceMutatingPaths: Set<String> = ["files.write", "files.edit", "shell.execute"]

/// How many declared-correct paths one whole round of ``agentSurfaceQueries``
/// must find over its ten queries.
///
/// A level, not a floor. The per-query assertion below is a floor — each query
/// finds at least one correct path — and a run that answered one correct path
/// for every query while burying it under wrong ones would clear it. This
/// number holds the whole round to the standard a settling run measured: on
/// 2026-09-10 three rounds on `agentFlashModel` each scored 19 correct paths
/// of the 25 this group declares, and each returned the same 3 undeclared
/// paths, so the level is the value every round held. The tier answers
/// identically round to round here — it decodes under a grammar — which is why
/// the level sits at the measurement rather than under it. It is a regression
/// guard, and it may be raised by a later measurement and never lowered to
/// make a run green.
let agentSurfaceRoundCorrectLevel = 19

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
/// **What card `^kn9ay20` added.** Three things the one-pass, floor-only
/// version could not see. The group now runs ``discoveryRoundCount`` rounds,
/// so a stochastic model's variation is in the printed record rather than
/// hidden behind one lucky pass. Every query declares the catalog paths a
/// reader says answer it, so the run is graded on how many correct paths it
/// found and not only on whether it found any. And the count of paths it
/// returned that no reader declared is printed for every query — a reading
/// only, until a level for it is known.
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
/// **What it prints.** One line per query per round with the matched paths,
/// the correct and wrong halves of them, the declared correct set and the raw
/// ids the selection model answered, read off the Router recording the same
/// way `SelectionForkPerCallTests` reads its fork trace; one line closing each
/// round with its totals; and one line with the size of the catalog the model
/// held. Those lines are what the card asks to be pasted; nothing asserts on
/// the wrong counts.
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
    @Test("the ten recorded queries find the write, edit or shell entry and hold the correct-path level in every round")
    func agentQueriesFindTheWriteEditAndShellEntries() async throws {
        try await withLiveRouterFixture(name: agentSurfaceScenarioName, profile: agentDiscoveryProfile) { fixture in
            let surface = try makeFilesAndShellSurface(over: fixture)
            reportCatalogSize(of: surface.registry, reportedAs: agentSurfaceScenarioName)

            let rounds = try await gradeDiscoveryRounds(
                of: agentSurfaceQueries,
                through: surface.searchTools,
                recordedBy: fixture,
                reportedAs: agentSurfaceScenarioName)

            for round in rounds {
                expectEveryQueryFindsACorrectPath(in: round, of: agentSurfaceQueries)
                expectTheMutatingQueriesAnswer(in: round)
                #expect(
                    round.correctCount >= agentSurfaceRoundCorrectLevel,
                    """
                    round \(round.number) found \(round.correctCount) correct paths, \
                    under the level of \(agentSurfaceRoundCorrectLevel)
                    """
                )
            }
        }
    }
}

/// Holds queries 4 to 9 of one round to answering at least one match, and to
/// holding the write, edit or shell entry among those matches.
///
/// This is the assertion card `^zqz1zan` put here, kept whole: it is the
/// regression guard over the failure that card records, and the grading card
/// `^kn9ay20` added to it rather than replacing it.
///
/// - Parameter round: the round to hold.
private func expectTheMutatingQueriesAnswer(in round: DiscoveryRound) {
    for number in agentSurfaceQueriesThatMustAnswer {
        let query = agentSurfaceQueries[number - 1]
        let paths = round.grades[number - 1].matchedPaths
        #expect(
            !paths.isEmpty,
            """
            round \(round.number) query \(number) "\(query.task)" answered no match; \
            the surface holds \(agentSurfaceMutatingPaths.sorted())
            """
        )
        #expect(
            !agentSurfaceMutatingPaths.isDisjoint(with: paths),
            """
            round \(round.number) query \(number) "\(query.task)" matched \(paths), \
            none of \(agentSurfaceMutatingPaths.sorted())
            """
        )
    }
}
