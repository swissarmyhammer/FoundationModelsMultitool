// `GitBranchesTests` — the behavioral suite of the `tools.git.branches` verb.
//
// The suite makes `BranchesArguments` with the memberwise initializer and
// calls the `Branches` verb directly, the way `GitLogTests` calls its verb.
// Each test makes its own temporary repository, thus the tests are
// independent and they run in parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.branches` verb (task `^bck92pn`).
///
/// The card names each case: the current branch, a second branch, a detached
/// HEAD, `main` against `master`, and a root in no repository. A repository
/// with no commit is here too.
@Suite("GitBranchesTests")
struct GitBranchesTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitBranchesTests"

    /// The older name of the main branch.
    private static let masterBranch = "master"

    /// A branch name that is not a main-branch name.
    private static let developBranch = "develop"

    /// The verb gives each local branch in name order, the branch of HEAD,
    /// and `main` as the main branch.
    @Test("the verb gives each branch, the current branch, and main")
    func theVerbGivesEachBranchTheCurrentBranchAndMain() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.branches == [GitTestHistory.featureBranch, TemporaryGitRepository.defaultBranch])
        #expect(result.current == TemporaryGitRepository.defaultBranch)
        #expect(result.main == TemporaryGitRepository.defaultBranch)
    }

    /// A HEAD that names a second branch makes that branch current, and the
    /// main branch stays `main`.
    @Test("a HEAD on a second branch makes that branch current")
    func aHeadOnASecondBranchMakesThatBranchCurrent() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.pointHead(atBranch: GitTestHistory.featureBranch)

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.current == GitTestHistory.featureBranch)
        #expect(result.main == TemporaryGitRepository.defaultBranch)
    }

    /// A detached HEAD makes no branch current, and each branch stays in the
    /// list.
    @Test("a detached HEAD makes no branch current")
    func aDetachedHeadMakesNoBranchCurrent() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.detachHead()

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.current == nil)
        #expect(result.branches == [GitTestHistory.featureBranch, TemporaryGitRepository.defaultBranch])
    }

    /// With no `main` branch, `master` is the main branch.
    @Test("with no main branch, master is the main branch")
    func withNoMainBranchMasterIsTheMainBranch() async throws {
        let repository = try Self.makeRepository(withOnlyBranch: Self.masterBranch)

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.branches == [Self.masterBranch])
        #expect(result.current == Self.masterBranch)
        #expect(result.main == Self.masterBranch)
    }

    /// With `main` and `master` both, `main` is the main branch.
    @Test("with main and master both, main is the main branch")
    func withMainAndMasterBothMainIsTheMainBranch() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.createBranch(named: Self.masterBranch)

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.main == TemporaryGitRepository.defaultBranch)
    }

    /// With neither `main` nor `master`, there is no main branch.
    @Test("with neither main nor master, there is no main branch")
    func withNeitherMainNorMasterThereIsNoMainBranch() async throws {
        let repository = try Self.makeRepository(withOnlyBranch: Self.developBranch)

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.branches == [Self.developBranch])
        #expect(result.main == nil)
    }

    /// A repository with no commit has no branch, no current branch, and no
    /// main branch, and it is not a correction.
    @Test("a repository with no commit has no branch")
    func aRepositoryWithNoCommitHasNoBranch() async throws {
        let repository = try TemporaryGitRepository()

        let result = try await Self.branches(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.branches.isEmpty)
        #expect(result.current == nil)
        #expect(result.main == nil)
    }

    /// A root in no repository is a correction, not a thrown error.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let result = try await Self.branches(in: GitContext(root: outside))

        let correction = try #require(result.correction)
        #expect(correction.contains("not in a git repository"), "correction was: \(correction)")
        #expect(result.branches.isEmpty)
        #expect(result.current == nil)
        #expect(result.main == nil)
    }

    // MARK: - Helpers

    /// Makes a repository with one commit, whose one branch is `name`, and
    /// whose HEAD names that branch.
    ///
    /// - Parameter name: The name of the one branch.
    /// - Returns: The repository.
    /// - Throws: When a write, a commit, or a branch call fails.
    private static func makeRepository(withOnlyBranch name: String) throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")
        try repository.createBranch(named: name)
        try repository.pointHead(atBranch: name)
        try repository.deleteBranch(named: TemporaryGitRepository.defaultBranch)
        return repository
    }

    /// Calls the `tools.git.branches` verb over a context.
    ///
    /// - Parameter context: The context of the verb.
    /// - Returns: The result of the verb.
    private static func branches(in context: GitContext) async throws -> BranchesResult {
        try await Branches(context: context).call(arguments: BranchesArguments())
    }
}
