import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The time limit of the held-out discovery test, in minutes.
///
/// The test resolves a 4B model and makes fifteen `searchTools` calls in each
/// of ``discoveryRoundCount`` rounds, and each call is one grammar-constrained
/// generation of a few tokens. Measured on a warm machine on 2026-09-10, the
/// whole test — the model load plus forty-five such calls — took 40.3 s. Six
/// minutes stands far over that and over a cold load, and a run that reaches
/// it is parked rather than slow.
private let heldOutTimeLimitMinutes = 6

/// The label the printed result and skip lines carry.
private let heldOutScenarioName = "heldOutSurfaceDiscovery"

/// Fifteen `task` strings nobody chose the selection preamble with, each
/// beside the catalog paths a reader says answer it.
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
/// That is what makes this group different from the ten of card `^zqz1zan`.
/// Those ten chose the wording the selection tier runs, so grading that
/// wording on them grades an answer against its own answer key. Nothing chose
/// anything with these fifteen.
///
/// The correct paths were declared afterwards, once the phrases were fixed, by
/// a reader of the nine tool descriptions of the surface. The declaration
/// therefore cannot have steered the wording.
let heldOutQueries = [
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
        task: "open a file and look at one region of it closely",
        correctPaths: ["files.read"]),
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
        task: "run only the one test that reproduces the bug",
        correctPaths: ["shell.execute"]),
    GradedDiscoveryQuery(
        task: "i need to see what the failing test printed",
        correctPaths: ["shell.getLines", "shell.grepHistory"]),
    GradedDiscoveryQuery(
        task: "run a shell command in the project directory",
        correctPaths: ["shell.execute"]),
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

/// How many declared-correct paths one whole round of ``heldOutQueries`` must
/// find over its fifteen queries.
///
/// A level, not a floor. The per-query assertion is a floor — each query finds
/// at least one correct path — and a run that answered one correct path for
/// every query while burying it under wrong ones would clear it.
///
/// **This level is the standard the surface owes a host, and the model meets
/// it today.** It is set at one declared path for each of the fifteen
/// queries, which is the least a group of this shape can score while every
/// query is still answered. Measured on 2026-09-10, all three rounds scored
/// 16 of the 22 declared paths, which is over this level, and each round
/// returned 2 undeclared paths. Every query found a declared path, and the
/// suite passes.
///
/// **The history, because it is why this group exists.** When card `^kn9ay20`
/// wrote this group, all three rounds scored 9 of the 22 declared paths and
/// returned 8 undeclared ones, and six queries found no declared path in any
/// round. That red result was the defect the group was written to find. The
/// level was not lowered to 9, because a level at 9 makes the defect the
/// standard. Card `^p06rh7z` then wrote the nine tool descriptions again, so
/// that each one names the work a person brings and not the mechanism of the
/// verb, and that text is what the selection prompt and the retrieval tier
/// read. The queries, the declared paths and this level did not change: the
/// card corrected the cause, and not the measurement.
///
/// **Why this level stays at 15 while the measurement is 16.** The number
/// comes from the shape of the group, and not from the score of one model on
/// one day. ``agentSurfaceRoundCorrectLevel`` can stand at its measurement,
/// because those ten queries are the record of one failure that is now
/// corrected. These fifteen queries are held out, so a level at the score of
/// today makes a later, honest change of model or of wording look like a
/// defect. Two runs on 2026-09-10 scored 16 in each of their rounds, and a
/// later card can lift this level to 16 on that record. The level is never
/// lowered to make a run green. Card `^fdaxnjw` holds this decision.
let heldOutRoundCorrectLevel = 15

/// The gated discovery test over queries nobody chose the preamble with.
///
/// **The question this suite answers, which no other suite can.** The
/// selection preamble the tier runs was chosen by measurement against the ten
/// queries of card `^zqz1zan`, and `AgentSurfaceDiscoveryTests` grades it on
/// those same ten. That is a training set used as a test set: it shows the
/// wording works for the queries that selected it, and shows nothing about a
/// query nobody has seen. This suite drives the same nine-entry surface, the
/// same model and the same production mount with a group written from a task
/// description alone — see ``heldOutQueries`` for exactly how — so a pass here
/// is evidence about queries the wording was never fitted to.
///
/// **The two groups never mix.** They are separate query lists, separate
/// suites, separate levels and separate printed labels, and neither is ever
/// reported as the other. Keeping the ten is deliberate: they are the
/// regression record of a real failure, not a benchmark to retire.
///
/// **What it grades.** Every query declares the catalog paths a reader of the
/// nine tool descriptions says answer it. Each round is held to two things:
/// every query finds at least one declared path, and the round finds at least
/// ``heldOutRoundCorrectLevel`` of them over the whole group. The count of
/// paths a query returned that no reader declared is printed for every query
/// and asserted on nowhere — card `^kn9ay20` asks for that reading until a
/// level for it is known.
///
/// **Why the flash model is pinned here.** The same reason
/// `AgentSurfaceDiscoveryTests` pins it: the selection tier's answer is a
/// property of the model that gives it, and the claim under test is about the
/// 4B the `acp-agent` ships. `agentFlashModel` states the pin.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated searchTools discovery over held-out queries",
    .serialized,
    .timeLimit(.minutes(heldOutTimeLimitMinutes))
)
struct HeldOutSurfaceDiscoveryTests {
    @Test("queries written from a task description alone each find a declared tool, and hold the level in every round")
    func heldOutQueriesFindTheirDeclaredTools() async throws {
        try await withLiveRouterFixture(name: heldOutScenarioName, profile: agentDiscoveryProfile) { fixture in
            let surface = try makeFilesAndShellSurface(over: fixture)
            reportCatalogSize(of: surface.registry, reportedAs: heldOutScenarioName)

            let rounds = try await gradeDiscoveryRounds(
                of: heldOutQueries,
                through: surface.searchTools,
                recordedBy: fixture,
                reportedAs: heldOutScenarioName)

            for round in rounds {
                expectEveryQueryFindsACorrectPath(in: round, of: heldOutQueries)
                #expect(
                    round.correctCount >= heldOutRoundCorrectLevel,
                    """
                    round \(round.number) found \(round.correctCount) correct paths, \
                    under the level of \(heldOutRoundCorrectLevel)
                    """
                )
            }
        }
    }
}
