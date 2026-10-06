import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the merge-target part of the `LibGit2` layer: the branch that
/// a branch merges back to.
///
/// The cases are the ports of the six `test_find_merge_target_*` tests in
/// `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`, and the
/// case of a branch whose tip is in the history of `main`. Each test makes its
/// own repository, thus the tests are independent and they run in parallel
/// safely.
@Suite("LibGit2MergeTargetTests")
struct LibGit2MergeTargetTests {

    /// A branch made from `main` merges back to `main`.
    @Test("a branch made from main merges back to main")
    func aBranchMadeFromMainMergesBackToMain() throws {
        let repository = try Self.makeMain()
        try Self.commitOnNewBranch("issue/42", file: "fix.txt", in: repository)
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: "issue/42") == TemporaryGitRepository.defaultBranch)
    }

    /// A branch made from a feature branch merges back to that feature
    /// branch, not to `main`: the nearer merge-base wins.
    @Test("the nearer parent branch wins")
    func theNearerParentBranchWins() throws {
        let repository = try Self.makeMain()
        try Self.commitOnNewBranch("feature/myfeature", file: "feature.txt", in: repository)
        try Self.commitOnNewBranch("issue/99", file: "issue.txt", in: repository)
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: "issue/99") == "feature/myfeature")
    }

    /// A branch with the same first name part (`issue/`) is a sibling, not a
    /// parent, thus it is not a candidate.
    @Test("a sibling branch is not a candidate")
    func aSiblingBranchIsNotACandidate() throws {
        let repository = try Self.makeMain()
        try repository.createBranch(named: "issue/1")
        try Self.commitOnNewBranch("issue/2", file: "issue2.txt", in: repository)
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: "issue/2") == TemporaryGitRepository.defaultBranch)
    }

    /// `main` alone has no candidate, and the fallback is `main` itself, thus
    /// it has no merge target.
    @Test("main alone has no merge target")
    func mainAloneHasNoMergeTarget() throws {
        let repository = try Self.makeMain()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: TemporaryGitRepository.defaultBranch) == nil)
    }

    /// A branch with no history in common with another branch (an orphan)
    /// has no merge target.
    @Test("an orphan branch has no merge target")
    func anOrphanBranchHasNoMergeTarget() throws {
        let repository = try Self.makeMain()
        try repository.write("orphan content", to: "orphan.txt")
        try repository.createOrphanBranch(named: "orphan-branch", message: "Orphan commit")
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: "orphan-branch") == nil)
    }

    /// A branch name with no `/` has no sibling rule, thus `main` is its
    /// candidate and its merge target.
    @Test("a branch name with no slash merges back to main")
    func aBranchNameWithNoSlashMergesBackToMain() throws {
        let repository = try Self.makeMain()
        try Self.commitOnNewBranch("solo-branch", file: "solo.txt", in: repository)
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: "solo-branch") == TemporaryGitRepository.defaultBranch)
    }

    /// A branch whose tip is in the history of `main` is the merge target of
    /// `main`. The source behaves the same way, and the port keeps it.
    @Test("a branch whose tip is in the history of main is the target of main")
    func aBranchWhoseTipIsInTheHistoryOfMainIsTheTargetOfMain() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.mergeTarget(forBranch: TemporaryGitRepository.defaultBranch) == GitTestHistory.featureBranch)
    }

    // MARK: - Helpers

    /// Makes a repository with one commit on `main`.
    ///
    /// - Returns: The repository.
    /// - Throws: When the write or the commit fails.
    private static func makeMain() throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write("# Repo", to: "README.md")
        try repository.commit(message: "Initial commit")
        return repository
    }

    /// Makes the branch `name` at the commit of HEAD, points HEAD at it, and
    /// commits one new file on it.
    ///
    /// - Parameters:
    ///   - name: The name of the new branch.
    ///   - file: The path of the new file.
    ///   - repository: The repository.
    /// - Throws: When a branch call, the write, or the commit fails.
    private static func commitOnNewBranch(_ name: String, file: String, in repository: TemporaryGitRepository) throws {
        try repository.createBranch(named: name)
        try repository.pointHead(atBranch: name)
        try repository.write("\(file)\n", to: file)
        try repository.commit(message: "commit on \(name)")
    }
}
