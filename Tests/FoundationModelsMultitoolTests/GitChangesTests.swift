// `GitChangesTests` — the behavioral suite of the `tools.git.changes` verb.
//
// The suite makes `ChangesArguments` with the memberwise initializer and
// calls the `Changes` verb directly, the way `GitBranchesTests` calls its
// verb. Each test makes its own temporary repository, thus the tests are
// independent and they run in parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.changes` verb (task `^zdb38q4`).
///
/// The cases are the ports of the `test_git_changes_*` tests of
/// `../swissarmyhammer/crates/swissarmyhammer-tools/src/mcp/tools/git/changes/mod.rs`
/// that apply to a verb with no `op` field, and the cases that the card adds:
/// a bad range, an unknown branch, a detached HEAD, and a root in a subfolder.
@Suite("GitChangesTests")
struct GitChangesTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitChangesTests"

    /// The range of the last commit, which the verb uses on a clean branch
    /// with no parent.
    private static let lastCommitRange = "HEAD~1..HEAD"

    /// The issue branch of the parent tests.
    private static let issueBranch = "issue/test-feature"

    /// A branch on `main` with one commit only: no parent, and the range of
    /// the last commit names no commit, thus there is no file and no range.
    /// A port of `test_git_changes_tool_execute_main_branch`.
    @Test("main with one commit only has no file and no range")
    func mainWithOneCommitOnlyHasNoFileAndNoRange() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("content1", to: "file1.txt")
        try repository.write("content2", to: "file2.txt")
        try repository.commit(message: "Initial commit")

        let result = try await Self.changes(
            in: repository.workDirectory, branch: TemporaryGitRepository.defaultBranch)

        #expect(result.correction == nil)
        #expect(result.branch == TemporaryGitRepository.defaultBranch)
        #expect(result.parentBranch == nil)
        #expect(result.range == nil)
        #expect(result.files.isEmpty)
    }

    /// With no branch argument, the verb reads the branch of HEAD. A port of
    /// `test_git_changes_tool_execute_default_branch`.
    @Test("with no branch argument the verb reads the branch of HEAD")
    func withNoBranchArgumentTheVerbReadsTheBranchOfHead() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("content1", to: "file1.txt")
        try repository.commit(message: "Initial commit")

        let result = try await Self.changes(in: repository.workDirectory)

        #expect(result.correction == nil)
        #expect(result.branch == TemporaryGitRepository.defaultBranch)
        #expect(result.parentBranch == nil)
    }

    /// An issue branch made from `main` has `main` as its parent, and gives
    /// the files of its own commits only. A port of
    /// `test_git_changes_tool_execute_issue_branch`.
    @Test("an issue branch gives the files of its own commits")
    func anIssueBranchGivesTheFilesOfItsOwnCommits() async throws {
        let repository = try Self.makeBranch(Self.issueBranch, files: ["feature1.txt", "feature2.txt"])

        let result = try await Self.changes(in: repository.workDirectory, branch: Self.issueBranch)

        #expect(result.correction == nil)
        #expect(result.branch == Self.issueBranch)
        #expect(result.parentBranch == TemporaryGitRepository.defaultBranch)
        #expect(result.range == nil)
        #expect(result.files == ["feature1.txt", "feature2.txt"])
    }

    /// A feature branch finds `main` as its parent. A port of
    /// `test_git_changes_tool_feature_branch_detects_parent`.
    @Test("a feature branch finds main as its parent")
    func aFeatureBranchFindsMainAsItsParent() async throws {
        let branch = "feature/new-feature"
        let repository = try Self.makeBranch(branch, files: ["feature1.txt", "feature2.txt"])

        let result = try await Self.changes(in: repository.workDirectory, branch: branch)

        #expect(result.parentBranch == TemporaryGitRepository.defaultBranch)
        #expect(result.files == ["feature1.txt", "feature2.txt"])
    }

    /// A feature branch with commits and uncommitted files gives both: the
    /// committed files since the parent, and each uncommitted file. A port of
    /// `test_git_changes_tool_includes_uncommitted_changes`.
    @Test("a branch with uncommitted files gives the committed and the uncommitted files")
    func aBranchWithUncommittedFilesGivesTheCommittedAndTheUncommittedFiles() async throws {
        let branch = "test-uncommitted"
        let repository = try Self.makeBranch(branch, files: ["committed_on_branch.txt"])
        try repository.write("uncommitted content", to: "uncommitted.txt")
        try repository.write("staged content", to: "staged.txt")
        try repository.stage("staged.txt")

        let result = try await Self.changes(in: repository.workDirectory, branch: branch)

        #expect(result.correction == nil)
        #expect(result.parentBranch == TemporaryGitRepository.defaultBranch)
        #expect(result.files == ["committed_on_branch.txt", "staged.txt", "uncommitted.txt"])
    }

    /// `main` with a dirty tree gives the uncommitted files only, not the
    /// files of the last commit. A port of
    /// `test_git_changes_tool_main_branch_includes_uncommitted`.
    @Test("main with a dirty tree gives the uncommitted files only")
    func mainWithADirtyTreeGivesTheUncommittedFilesOnly() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("content1", to: "file1.txt")
        try repository.commit(message: "Initial commit")
        try repository.write("content2", to: "file2.txt")
        try repository.commit(message: "Second commit")
        try repository.write("uncommitted", to: "uncommitted.txt")

        let result = try await Self.changes(
            in: repository.workDirectory, branch: TemporaryGitRepository.defaultBranch)

        #expect(result.parentBranch == nil)
        #expect(result.range == nil)
        #expect(result.files == ["uncommitted.txt"])
    }

    /// `main` with a clean tree gives the files of the last commit, and says
    /// that it used the range of the last commit. A port of
    /// `test_git_changes_clean_main_defaults_to_last_commit`.
    @Test("main with a clean tree gives the files of the last commit")
    func mainWithACleanTreeGivesTheFilesOfTheLastCommit() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("base content", to: "base.txt")
        try repository.commit(message: "Initial commit")
        try repository.write("recent content", to: "recent.txt")
        try repository.commit(message: "Recent commit")

        let result = try await Self.changes(in: repository.workDirectory)

        #expect(result.correction == nil)
        #expect(result.branch == TemporaryGitRepository.defaultBranch)
        #expect(result.parentBranch == nil)
        #expect(result.range == Self.lastCommitRange)
        #expect(result.files == ["recent.txt"])
    }

    /// A range argument comes before the parent rule. A port of
    /// `test_git_changes_range_takes_precedence`.
    @Test("a range argument comes before the parent rule")
    func aRangeArgumentComesBeforeTheParentRule() async throws {
        let branch = "feature/test"
        let repository = try Self.makeBranch(branch, files: ["feature1.txt"])
        try repository.write("feature content", to: "feature.txt")
        try repository.commit(message: "Feature commit")

        let result = try await Self.changes(in: repository.workDirectory, range: Self.lastCommitRange)

        #expect(result.correction == nil)
        #expect(result.branch == branch)
        #expect(result.parentBranch == TemporaryGitRepository.defaultBranch)
        #expect(result.range == Self.lastCommitRange)
        #expect(result.files == ["feature.txt"])
    }

    /// A range argument with one ref is the range from that ref to HEAD.
    @Test("a range argument with one ref reads to HEAD")
    func aRangeArgumentWithOneRefReadsToHead() async throws {
        let repository = try TemporaryGitRepository()
        for name in ["a.txt", "b.txt", "c.txt"] {
            try repository.write("\(name)\n", to: name)
            try repository.commit(message: "add \(name)")
        }

        let result = try await Self.changes(in: repository.workDirectory, range: "HEAD~2")

        #expect(result.range == "HEAD~2")
        #expect(result.files == ["b.txt", "c.txt"])
    }

    /// A range that names no commit is a correction, not a thrown error.
    @Test("a bad range is a correction")
    func aBadRangeIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")

        let result = try await Self.changes(in: repository.workDirectory, range: "no-such-ref..HEAD")

        let correction = try #require(result.correction)
        #expect(correction.contains("no-such-ref..HEAD"), "correction was: \(correction)")
        #expect(result.files.isEmpty)
        #expect(result.range == nil)
    }

    /// A branch that is not a local branch is a correction that names it. The
    /// source falls back to the uncommitted files; the card asks for a
    /// correction. A port of `test_git_changes_tool_invalid_branch`.
    @Test("an unknown branch is a correction")
    func anUnknownBranchIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("initial content", to: "initial.txt")
        try repository.commit(message: "Initial commit")

        let result = try await Self.changes(in: repository.workDirectory, branch: "non-existent-branch")

        let correction = try #require(result.correction)
        #expect(correction.contains("non-existent-branch"), "correction was: \(correction)")
        #expect(result.branch == "non-existent-branch")
        #expect(result.parentBranch == nil)
        #expect(result.files.isEmpty)
    }

    /// A repository with no commit has no branch `main`, thus the call is a
    /// correction with no file. A port of
    /// `test_git_changes_tool_empty_repository`.
    @Test("a repository with no commit is a correction with no file")
    func aRepositoryWithNoCommitIsACorrectionWithNoFile() async throws {
        let repository = try TemporaryGitRepository()

        let result = try await Self.changes(
            in: repository.workDirectory, branch: TemporaryGitRepository.defaultBranch)

        #expect(result.correction != nil)
        #expect(result.files.isEmpty)
    }

    /// A detached HEAD with no branch argument is a correction: there is no
    /// current branch to read.
    @Test("a detached HEAD with no branch argument is a correction")
    func aDetachedHeadWithNoBranchArgumentIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.detachHead()

        let result = try await Self.changes(in: repository.workDirectory)

        let correction = try #require(result.correction)
        #expect(correction.contains("branch"), "correction was: \(correction)")
        #expect(result.files.isEmpty)
    }

    /// A root in no repository is a correction, not a thrown error. A port of
    /// `test_git_changes_tool_execute_no_git_ops` and of
    /// `test_git_changes_tool_non_git_directory`.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let result = try await Self.changes(in: outside, branch: TemporaryGitRepository.defaultBranch)

        let correction = try #require(result.correction)
        #expect(correction.contains("not in a git repository"), "correction was: \(correction)")
        #expect(result.files.isEmpty)
    }

    /// With the root in a subfolder, each file is relative to the root, and a
    /// file outside the root is in no list: committed or uncommitted.
    @Test("a root in a subfolder gives the files below the root only")
    func aRootInASubfolderGivesTheFilesBelowTheRootOnly() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("base\n", to: "base.txt")
        try repository.commit(message: "Initial commit")
        try repository.createBranch(named: Self.issueBranch)
        try repository.pointHead(atBranch: Self.issueBranch)
        try repository.write("in\n", to: "src/in.txt")
        try repository.write("out\n", to: "out.txt")
        try repository.commit(message: "Issue commit")
        try repository.write("dirty in\n", to: "src/dirty.txt")
        try repository.write("dirty out\n", to: "dirty-out.txt")
        let root = repository.workDirectory.appendingPathComponent("src", isDirectory: true)

        let result = try await Self.changes(in: root)

        #expect(result.correction == nil)
        #expect(result.branch == Self.issueBranch)
        #expect(result.parentBranch == TemporaryGitRepository.defaultBranch)
        #expect(result.files == ["dirty.txt", "in.txt"])
    }

    // MARK: - Helpers

    /// Makes a repository with one commit on `main` (`base.txt`), and the
    /// branch `name` from it with one commit that writes `files`. HEAD names
    /// the branch.
    ///
    /// - Parameters:
    ///   - name: The name of the branch.
    ///   - files: The paths of the files of the branch commit.
    /// - Returns: The repository.
    /// - Throws: When a write, a commit, or a branch call fails.
    private static func makeBranch(_ name: String, files: [String]) throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write("base content", to: "base.txt")
        try repository.commit(message: "Initial commit")
        try repository.createBranch(named: name)
        try repository.pointHead(atBranch: name)
        for file in files {
            try repository.write("\(file)\n", to: file)
        }
        try repository.commit(message: "Add features")
        return repository
    }

    /// Calls the `tools.git.changes` verb over a root.
    ///
    /// - Parameters:
    ///   - root: The root of the context.
    ///   - branch: The branch argument, or `nil`.
    ///   - range: The range argument, or `nil`.
    /// - Returns: The result of the verb.
    private static func changes(in root: URL, branch: String? = nil, range: String? = nil) async throws -> ChangesResult {
        try await Changes(context: GitContext(root: root)).call(arguments: ChangesArguments(branch: branch, range: range))
    }
}
