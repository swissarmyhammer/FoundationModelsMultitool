import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the branch part of the `LibGit2` layer: the names of the
/// local branches, and the branch that HEAD names.
///
/// Each test makes its own repository, thus the tests are independent and
/// they run in parallel safely.
@Suite("LibGit2BranchesTests")
struct LibGit2BranchesTests {

    /// The layer gives each local branch, and HEAD names the default branch.
    @Test("the layer gives each local branch and the branch of HEAD")
    func theLayerGivesEachLocalBranchAndTheBranchOfHead() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(Set(try opened.localBranchNames()) == [TemporaryGitRepository.defaultBranch, GitTestHistory.featureBranch])
        #expect(try opened.currentBranchName() == TemporaryGitRepository.defaultBranch)
    }

    /// A HEAD that names another branch gives that branch.
    @Test("a HEAD that names another branch gives that branch")
    func aHeadThatNamesAnotherBranchGivesThatBranch() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.pointHead(atBranch: GitTestHistory.featureBranch)

        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.currentBranchName() == GitTestHistory.featureBranch)
    }

    /// A detached HEAD names no branch.
    @Test("a detached HEAD names no branch")
    func aDetachedHeadNamesNoBranch() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.detachHead()

        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.currentBranchName() == nil)
        #expect(Set(try opened.localBranchNames()) == [TemporaryGitRepository.defaultBranch, GitTestHistory.featureBranch])
    }

    /// Only a HEAD that names a commit directly is detached: a HEAD on a
    /// branch is not, and the HEAD of a repository with no commit is not.
    @Test("only a HEAD that names a commit directly is detached")
    func onlyAHeadThatNamesACommitDirectlyIsDetached() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)
        let empty = try TemporaryGitRepository()
        let openedEmpty = try LibGit2Repository(discoveringFrom: empty.workDirectory)

        #expect(try !opened.isHeadDetached())
        #expect(try !openedEmpty.isHeadDetached())
        try repository.detachHead()
        #expect(try opened.isHeadDetached())
    }

    /// A repository with no commit has no branch, and its HEAD names no
    /// branch that exists.
    @Test("a repository with no commit has no branch")
    func aRepositoryWithNoCommitHasNoBranch() throws {
        let repository = try TemporaryGitRepository()

        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.localBranchNames().isEmpty)
        #expect(try opened.currentBranchName() == nil)
    }

    /// A local branch is there, and a name that no local branch has is not.
    @Test("the layer tells a local branch from an unknown name")
    func theLayerTellsALocalBranchFromAnUnknownName() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.hasLocalBranch(named: GitTestHistory.featureBranch))
        #expect(try !opened.hasLocalBranch(named: "no-such-branch"))
    }

    /// The main branch is `main`, else `master`, else none.
    @Test("the main branch is main, else master, else none")
    func theMainBranchIsMainElseMasterElseNone() {
        #expect(LibGit2Repository.mainBranchName(among: ["master", "main", "develop"]) == "main")
        #expect(LibGit2Repository.mainBranchName(among: ["develop", "master"]) == "master")
        #expect(LibGit2Repository.mainBranchName(among: ["develop"]) == nil)
    }
}
