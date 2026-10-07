import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The snippet of git.md § "Goal", through a real `MultiTool` and with no
/// model (task `^xd2dbd1`).
///
/// The registry comes from `MultiTool.Builder().withGit(root:)`, the public
/// mount of a host. The snippet goes through `MultiTool.call(arguments:)`: the
/// JSC interpreter, the `tools.git` bindings, and `ToolInvoker`. The
/// repository is ``GitScenarioHistory``: the work folder renames one function
/// of one committed file, thus `tools.git.changes` gives that one file, and the
/// snippet diffs it against HEAD.
///
/// The test reads only a temporary repository and starts no other process,
/// thus it is a unit test. The live model scenario of `IntegrationTests/`
/// reads the same repository.
@Suite("GitGoalSnippetTests")
struct GitGoalSnippetTests {

    /// The snippet of git.md § "Goal", word for word.
    private static let goalSnippet = """
        const changes = await tools.git.changes({});
        const diffs = await Promise.all(
          changes.files.slice(0, 5).map(path => tools.git.diff({ left: `${path}@HEAD`, right: path })));
        return { branch: changes.branch, parent: changes.parentBranch, diffs };
        """

    /// The goal snippet reads the branch of HEAD and gives one diff with no
    /// correction for the one changed file, and that diff names the renamed
    /// function.
    @Test("the goal snippet gives the branch and one diff that names the renamed function")
    func theGoalSnippetGivesTheBranchAndTheDiff() async throws {
        let repository = try GitScenarioHistory.make()
        let registry = try MultiTool.Builder().withGit(root: repository.workDirectory).buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.goalSnippet))

        let result = try RunOutput.decoded(GoalSnippetOutput.self, from: output)
        #expect(result.branch == TemporaryGitRepository.defaultBranch, "the output was \(output)")
        #expect(result.parent == nil, "the output was \(output)")
        let diff = try #require(result.diffs.first, "the output was \(output)")
        #expect(result.diffs.count == 1, "the output was \(output)")
        #expect(diff.correction == nil, "the output was \(output)")
        #expect(
            diff.changes.contains {
                $0.entityName == GitScenarioHistory.renamedFunctionName && $0.filePath == GitScenarioHistory.geometryPath
            },
            "the output was \(output)")
    }
}

/// The value that the goal snippet returns.
private struct GoalSnippetOutput: Decodable {

    /// The branch that `tools.git.changes` read.
    let branch: String

    /// The parent branch, or `nil` when the branch has none.
    let parent: String?

    /// The diff of each changed file.
    let diffs: [SnippetDiff]
}

/// One result of `tools.git.diff`, with the fields that the test reads.
private struct SnippetDiff: Decodable {

    /// The changes, one for each entity.
    let changes: [SnippetChange]

    /// The correction, or `nil` when the changes stand.
    let correction: String?
}

/// One change of ``SnippetDiff``, with the fields that the test reads.
private struct SnippetChange: Decodable {

    /// The name of the entity.
    let entityName: String

    /// The path of the file that holds the entity, relative to the root.
    let filePath: String
}
