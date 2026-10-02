import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The label the printed result and skip lines carry.
private let agentSurfaceScenarioName = "agentSurfaceDiscovery"

/// Eight of the ten `task` strings the `acp-agent` gave to `searchTools` on
/// the SWE-bench instance `astropy__astropy-12907`, in the order it gave
/// them, each beside the catalog paths a reader says answer it.
///
/// Read out of the unified log of that run and recorded on card `^zqz1zan`.
/// That card numbers the ten strings 1 to 10 in the order the agent gave
/// them. A printed `q` number is the position in this array, and not the
/// number of the card.
///
/// **Eight of the ten.** Card `^3vtvrzg` removed the two strings that
/// declare the same paths, with the same kind of phrase, as a string that
/// stays. Each one cost a selection call of approximately 6.5 s on the CI
/// runner `mini` and proved nothing the kept string does not:
///
/// - "run pytest tests, execute" (card number 5, `shell.execute`), the same
///   as "run a shell command or python script, execute code" (card number 4).
/// - "apply changes to a file, save file contents" (card number 8,
///   `files.write`, `files.edit` and `files.patch`), the same as "write file,
///   edit file, create file" (card number 6).
///
/// **This group is a regression record, and it is not a held-out set.** The
/// preamble the selection tier runs was chosen by measurement against these
/// strings, so the printed counts show that the wording works for the
/// queries that selected it and show nothing about a query nobody has seen.
/// `heldOutQueries` holds the group that answers that second question, and
/// `RetrievalTextSurfaceDiscoveryTests` drives both groups under their own
/// labels.
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
        task: "write file, edit file, create file",
        correctPaths: ["files.write", "files.edit", "files.patch"]),
    GradedDiscoveryQuery(
        task: "edit code, modify source file, patch",
        correctPaths: ["files.edit", "files.patch"]),
    GradedDiscoveryQuery(
        task: "file operations: create, write, append, delete, move",
        correctPaths: ["files.write", "files.edit", "files.patch", "shell.execute"]),
    GradedDiscoveryQuery(
        task: "create a new text file with given content on disk",
        correctPaths: ["files.write", "files.patch"]),
]

/// The gated discovery test over the surface the `acp-agent` had.
///
/// **Where this suite comes from.** Card `^zqz1zan`: on 2026-09-09 the agent
/// ran with `tools.files` on and writable and `tools.shell` on, made ten
/// `searchTools` calls, and got an empty answer for eight of them — every
/// query for a way to write, edit or run. The main session never saw the
/// write, edit or shell verb, and the run ended with an empty patch. This
/// suite builds that surface, mounts `searchTools` through the production
/// path, and drives eight of the same ten queries (see
/// ``agentSurfaceQueries``) through the selection tier on the agent's own
/// flash model.
///
/// **The one selection suite over this surface.** Until card `^3vtvrzg`,
/// `HeldOutSurfaceDiscoveryTests` drove the twelve ``heldOutQueries`` over
/// the same surface, on the same model, through the same mount and the same
/// checks (81.0 s on the CI runner `mini`, run `37048824337`). Card `^xr5w83f`
/// removed each assertion on a score, so the two suites held the same
/// properties, and the difference between a regression record and a
/// held-out group was only in the printed counts. This suite now proves those
/// properties for the surface. `RetrievalTextSurfaceDiscoveryTests` still
/// drives the held-out group, and holds each path it declares to be a path
/// of the catalog.
///
/// **What it holds.** Only what the code of this package controls: each call
/// answers without an error, and each answer holds only paths the catalog
/// defines, each one time, inside the limit of the call
/// (``DiscoveryAnswerCheck``). Each path a query declares correct must be a
/// path of the catalog, so the printed grade reads real paths. How many
/// correct and wrong paths the model selects is a measurement of the model,
/// and the suite prints it and asserts nothing on it. Card `^xr5w83f` removed
/// the earlier assertions on it: a group level of 19 correct paths, one
/// correct path for each query, and a write, edit or shell path among the
/// matches of queries 4 to 9. Each of them failed when a model or a prompt
/// changed, also when the code was correct. On CI run 36951032341 the group
/// found 18 correct and 1 wrong path, against 19 correct and 3 wrong paths on
/// 2026-09-29.
///
/// **What card `^kn9ay20` added.** Every query declares the catalog paths a
/// reader says answer it, so the printed line shows how many correct paths
/// the run found and not only whether it found any, and how many paths it
/// returned that no reader declared. That card also drove the group three
/// times in one test; card `^3vtvrzg` removed the repetition, because every
/// pass of two CI runs printed the same answers (see `DiscoveryGroupGrade`).
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
/// against each other here — three passes of the ten queries each, on the
/// same model and the same catalog. The ranker default answered 30 of 30 and
/// held the write, edit or shell verb in every one of queries 4 to 9, so the
/// local constant is gone and the tier takes the default.
///
/// **What it prints.** One line per query with the matched paths, the correct
/// and wrong halves of them, the declared correct set and the raw ids the
/// selection model answered, read off the Router recording the same way
/// `SelectionForkPerCallTests` reads its fork trace; one line closing the
/// group with its totals; and one line with the size of the catalog the model
/// held. Those lines are what the card asks to be pasted; nothing asserts on
/// the correct or the wrong counts.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated searchTools discovery over the agent's files-and-shell surface",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct AgentSurfaceDiscoveryTests {
    @Test("the recorded queries each answer only real catalog paths, one time each, inside the limit")
    func agentQueriesAnswerOnlyRealCatalogPaths() async throws {
        try await withLiveRouterFixture(name: agentSurfaceScenarioName, profile: agentDiscoveryProfile) { fixture in
            try await makeFilesAndShellSurface(over: fixture)
                .driveGradedGroup(of: agentSurfaceQueries, recordedBy: fixture, reportedAs: agentSurfaceScenarioName)
        }
    }
}
