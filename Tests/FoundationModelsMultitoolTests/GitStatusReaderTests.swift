import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the shared status reader of the git capability,
/// `GitContext.status()`: the uncommitted files below the root, with their
/// paths relative to the root.
///
/// `tools.git.status` reads through it, and the later `changes` and `diff`
/// verbs read the same uncommitted-file list. Thus this suite holds the
/// contract that the verbs share. Each test makes its own temporary
/// repository, thus the tests are independent and they run in parallel
/// safely.
@Suite("GitStatusReaderTests")
struct GitStatusReaderTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitStatusReaderTests"

    /// The reader gives the lists of the files below the root, relative to
    /// the root, and leaves out each file outside the root.
    @Test("the reader gives the files below the root relative to the root")
    func theReaderGivesTheFilesBelowTheRootRelativeToTheRoot() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "src/a.txt")
        try repository.write("b\n", to: "b.txt")
        try repository.commit(message: "first")
        try repository.write("a2\n", to: "src/a.txt")
        try repository.write("b2\n", to: "b.txt")
        try repository.write("n\n", to: "src/lib/n.txt")
        try repository.stage("src/lib/n.txt")
        let root = repository.workDirectory.appendingPathComponent("src", isDirectory: true)

        let status = try GitContext(root: root).status().get()

        #expect(status == GitStatus(staged: ["lib/n.txt"], unstaged: ["a.txt"], untracked: [], renamed: []))
        #expect(!status.isClean)
    }

    /// A status with no file in any list is clean.
    @Test("a status with no file is clean")
    func aStatusWithNoFileIsClean() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")

        let status = try GitContext(root: repository.workDirectory).status().get()

        #expect(status == GitStatus(staged: [], unstaged: [], untracked: [], renamed: []))
        #expect(status.isClean)
    }

    /// A clean status has no file in its list of all files. A port of
    /// `test_get_uncommitted_changes_clean_repo`.
    @Test("a clean status has no file in all files")
    func aCleanStatusHasNoFileInAllFiles() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("initial content", to: "initial.txt")
        try repository.commit(message: "Initial commit")

        #expect(try GitContext(root: repository.workDirectory).status().get().allFiles.isEmpty)
    }

    /// A staged new file is in the list of all files. A port of
    /// `test_get_uncommitted_changes_staged_files`.
    @Test("a staged file is in all files")
    func aStagedFileIsInAllFiles() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("initial", to: "initial.txt")
        try repository.commit(message: "Initial commit")
        try repository.write("staged content", to: "staged.txt")
        try repository.stage("staged.txt")

        #expect(try GitContext(root: repository.workDirectory).status().get().allFiles == ["staged.txt"])
    }

    /// A changed file that is not staged is in the list of all files. A port
    /// of `test_get_uncommitted_changes_unstaged_modifications`.
    @Test("an unstaged change is in all files")
    func anUnstagedChangeIsInAllFiles() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("original", to: "file.txt")
        try repository.commit(message: "Initial commit")
        try repository.write("modified", to: "file.txt")

        #expect(try GitContext(root: repository.workDirectory).status().get().allFiles == ["file.txt"])
    }

    /// A file that git does not track is in the list of all files. A port of
    /// `test_get_uncommitted_changes_untracked_files`.
    @Test("an untracked file is in all files")
    func anUntrackedFileIsInAllFiles() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("initial", to: "initial.txt")
        try repository.commit(message: "Initial commit")
        try repository.write("untracked content", to: "untracked.txt")

        #expect(try GitContext(root: repository.workDirectory).status().get().allFiles == ["untracked.txt"])
    }

    /// The list of all files holds each file of the four lists one time, in
    /// path order: a staged rename under its new path, and a file that is in
    /// two lists one time. A port of
    /// `test_get_uncommitted_changes_mixed_changes`, with a rename and a file
    /// in two lists added.
    @Test("all files holds each file one time in path order")
    func allFilesHoldsEachFileOneTimeInPathOrder() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("existing", to: "existing.txt")
        try repository.write("old name\n", to: "old.txt")
        try repository.commit(message: "Initial commit")
        try repository.write("untracked", to: "untracked.txt")
        try repository.write("modified", to: "existing.txt")
        try repository.stage("existing.txt")
        try repository.write("modified again", to: "existing.txt")
        try repository.write("staged", to: "staged.txt")
        try repository.stage("staged.txt")
        try FileManager.default.moveItem(
            at: repository.workDirectory.appendingPathComponent("old.txt"),
            to: repository.workDirectory.appendingPathComponent("new.txt"))
        try repository.stage("old.txt")
        try repository.stage("new.txt")

        let status = try GitContext(root: repository.workDirectory).status().get()

        #expect(status.allFiles == ["existing.txt", "new.txt", "staged.txt", "untracked.txt"])
    }

    /// A root in no repository is the correction of the context.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let rejection = try #require(throws: CorrectiveRejection.self) {
            try GitContext(root: outside).status().get()
        }

        #expect(rejection.correctiveMessage.contains("not in a git repository"))
    }
}
