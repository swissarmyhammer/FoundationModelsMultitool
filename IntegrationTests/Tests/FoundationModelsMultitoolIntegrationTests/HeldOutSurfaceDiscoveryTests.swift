import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The time limit of the held-out discovery test, in minutes.
///
/// The test resolves a 4B model and makes fifteen `searchTools` calls, and
/// each call is one grammar-constrained generation of a few tokens. Measured
/// on a warm machine on 2026-09-10, the whole test — the model load plus
/// forty-five such calls, three passes of the group at that time — took
/// 40.3 s. Six minutes stands far over that and over a cold load, and a run
/// that reaches it is parked rather than slow.
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

/// The gated discovery test over queries nobody chose the preamble with.
///
/// **The question this suite answers, which no other suite can.** The
/// selection preamble the tier runs was chosen by measurement against the ten
/// queries of card `^zqz1zan`, and `AgentSurfaceDiscoveryTests` grades it on
/// those same ten. That is a training set used as a test set: it shows the
/// wording works for the queries that selected it, and shows nothing about a
/// query nobody has seen. This suite drives the same nine-entry surface, the
/// same model and the same production mount with a group written from a task
/// description alone — see ``heldOutQueries`` for exactly how — so its printed
/// grade is evidence about queries the wording was never fitted to.
///
/// **The two groups never mix.** They are separate query lists, separate
/// suites and separate printed labels, and neither is ever reported as the
/// other. Keeping the ten is deliberate: they are the regression record of a
/// real failure, not a benchmark to retire.
///
/// **What it grades, and what it holds.** Every query declares the catalog
/// paths a reader of the nine tool descriptions says answer it. The suite
/// prints, for each query and for the group, how many declared paths the
/// model found and how many paths it returned that no reader declared. It
/// asserts nothing on those counts, because they measure the model. It holds
/// only what the code of this package controls: each call answers without an
/// error, each declared path is a path of the catalog, and each answer holds
/// only catalog paths, each one time, inside the limit
/// (``DiscoveryAnswerCheck``).
///
/// **The history of the counts.** When card `^kn9ay20` wrote this group, the
/// group found 9 of the 22 declared paths, and six queries found none. Card
/// `^p06rh7z` then wrote the nine tool descriptions again, so that each one
/// names the work a person brings and not the mechanism of the verb, and the
/// group found 16 on 2026-09-10. Card `^xr5w83f` removed the level of 15 and
/// the floor of one declared path for each query: on 2026-10-02 at least one
/// query found no declared path while the code was correct, because a model
/// or a prompt changed, not this package.
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
    @Test("queries written from a task description alone each answer only real catalog paths, one time each")
    func heldOutQueriesAnswerOnlyRealCatalogPaths() async throws {
        try await withLiveRouterFixture(name: heldOutScenarioName, profile: agentDiscoveryProfile) { fixture in
            try await makeFilesAndShellSurface(over: fixture)
                .driveGradedGroup(of: heldOutQueries, recordedBy: fixture, reportedAs: heldOutScenarioName)
        }
    }
}
