import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the commit detail part of the `LibGit2` layer: the full
/// message, the parents, and the line counts of each file that one commit
/// changes against its first parent.
///
/// Each test makes its own repository, thus the tests are independent and
/// they run in parallel safely.
@Suite("LibGit2CommitDetailTests")
struct LibGit2CommitDetailTests {

    /// The ref of the newest commit.
    private static let headRevision = "HEAD"

    /// The branch that the merge test makes and merges into
    /// `TemporaryGitRepository.defaultBranch`.
    private static let sideBranch = "side"

    /// The `-c` options that give the `git` binary an identity, thus a commit
    /// and a merge do not depend on the host configuration.
    private static let gitIdentity = ["-c", "user.name=Test", "-c", "user.email=test@example.invalid"]

    /// The detail of a commit with a body gives the whole message: the
    /// subject, the blank line, and the body.
    @Test("the message is the full message with the body")
    func theMessageIsTheFullMessageWithTheBody() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("x\n", to: "a.txt")
        let message = "the subject\n\nthe body of the message\n"
        let sha = try repository.commit(message: message)

        let detail = try #require(try Self.detail(of: repository))

        #expect(detail.message == message)
        #expect(detail.facts.sha == sha)
        #expect(detail.facts.subject == "the subject")
    }

    /// A commit that adds, changes, and removes a file gives each file with
    /// its status and its line counts, in path order.
    @Test("a normal commit gives the status and the line counts of each file")
    func aNormalCommitGivesTheStatusAndTheLineCountsOfEachFile() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("1\n2\n", to: "a.txt")
        try repository.write("gone\n", to: "gone.txt")
        let first = try repository.commit(message: "first")
        try repository.write("1\n3\n4\n", to: "a.txt")
        try FileManager.default.removeItem(at: repository.workDirectory.appendingPathComponent("gone.txt"))
        try repository.write("new\n", to: "new.txt")
        try repository.commit(message: "second")

        let detail = try #require(try Self.detail(of: repository))

        #expect(detail.parentShas == [first])
        #expect(
            detail.files == [
                LibGit2FileStat(path: "a.txt", oldPath: nil, status: "modified", additions: 2, deletions: 1),
                LibGit2FileStat(path: "gone.txt", oldPath: nil, status: "deleted", additions: 0, deletions: 1),
                LibGit2FileStat(path: "new.txt", oldPath: nil, status: "added", additions: 1, deletions: 0),
            ])
    }

    /// A commit with no parent diffs from no tree, thus each file is added.
    @Test("a root commit lists each file as added")
    func aRootCommitListsEachFileAsAdded() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let detail = try #require(try Self.detail(of: repository, revision: shas[0]))

        #expect(detail.parentShas.isEmpty)
        #expect(
            detail.files == [
                LibGit2FileStat(path: "a.txt", oldPath: nil, status: "added", additions: 1, deletions: 0)
            ])
    }

    /// A merge commit diffs from its first parent only, thus a file that only
    /// the second parent added is not in the list.
    @Test("a merge commit uses only its first parent")
    func aMergeCommitUsesOnlyItsFirstParent() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")
        try repository.createBranch(named: Self.sideBranch)
        try repository.write("main\n", to: "main.txt")
        let mainTip = try repository.commit(message: "second")
        try Self.git(["checkout", "--quiet", Self.sideBranch], in: repository)
        try repository.write("side\n", to: "side.txt")
        try Self.git(["add", "side.txt"], in: repository)
        try Self.git(Self.gitIdentity + ["commit", "--quiet", "-m", "side"], in: repository)
        try Self.git(["checkout", "--quiet", TemporaryGitRepository.defaultBranch], in: repository)
        try Self.git(
            Self.gitIdentity + ["merge", "--quiet", "--no-ff", "-m", "merge", Self.sideBranch], in: repository)

        let sideTip = try #require(try Self.detail(of: repository, revision: Self.sideBranch)).facts.sha

        let detail = try #require(try Self.detail(of: repository))

        #expect(detail.parentShas == [mainTip, sideTip])
        #expect(
            detail.files == [
                LibGit2FileStat(path: "side.txt", oldPath: nil, status: "added", additions: 1, deletions: 0)
            ])
    }

    /// A moved file is one renamed file with its old path, not a removal and
    /// an addition.
    @Test("a rename gives the renamed status and the old path")
    func aRenameGivesTheRenamedStatusAndTheOldPath() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("one\ntwo\nthree\n", to: "old.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: "old.txt", to: "moved/new.txt")
        try repository.commit(message: "rename")

        let detail = try #require(try Self.detail(of: repository))

        #expect(
            detail.files == [
                LibGit2FileStat(path: "moved/new.txt", oldPath: "old.txt", status: "renamed", additions: 0, deletions: 0)
            ])
    }

    /// A binary file has no lines, thus it gives no line counts.
    @Test("a binary file gives no line counts")
    func aBinaryFileGivesNoLineCounts() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("\u{0}\u{1}\u{2}binary\u{0}", to: "data.bin")
        try repository.commit(message: "binary")

        let detail = try #require(try Self.detail(of: repository))

        #expect(
            detail.files == [
                LibGit2FileStat(path: "data.bin", oldPath: nil, status: "added", additions: nil, deletions: nil)
            ])
    }

    /// A ref that names no object gives no detail, not a thrown error.
    @Test("an unknown revision gives no detail")
    func anUnknownRevisionGivesNoDetail() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let detail = try Self.detail(of: repository, revision: "no-such-ref")

        #expect(detail == nil)
    }

    // MARK: - Helpers

    /// Reads the detail of one commit of `repository`.
    ///
    /// - Parameters:
    ///   - repository: The repository.
    ///   - revision: The ref of the commit.
    /// - Returns: The detail, or `nil` when the ref names no object.
    /// - Throws: ``LibGit2Error`` when the read fails.
    private static func detail(
        of repository: TemporaryGitRepository,
        revision: String = headRevision
    ) throws -> LibGit2CommitDetail? {
        try LibGit2Repository(discoveringFrom: repository.workDirectory).commitDetail(forRevision: revision)
    }

    /// Runs the `git` binary in the work folder of `repository`.
    ///
    /// - Parameters:
    ///   - arguments: The `git` subcommand and its arguments.
    ///   - repository: The repository.
    /// - Throws: When the process cannot start.
    private static func git(_ arguments: [String], in repository: TemporaryGitRepository) throws {
        try TestSupport.runGit(arguments, in: repository.workDirectory)
    }
}
