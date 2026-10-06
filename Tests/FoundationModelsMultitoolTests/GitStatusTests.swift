// `GitStatusTests` — the behavioral suite of the `tools.git.status` verb.
//
// The suite makes `StatusArguments` with the memberwise initializer and calls
// the `Status` verb directly, the way `GitLogTests` calls its verb. Each test
// makes its own temporary repository, thus the tests are independent and they
// run in parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.status` verb (task `^bck92pn`).
///
/// The card names each case: a clean repository, one file of each kind, a
/// root in a subfolder, and a root in no repository.
@Suite("GitStatusTests")
struct GitStatusTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitStatusTests"

    /// The subfolder that a test uses as a root.
    private static let rootFolder = "src"

    /// A repository with no change after its last commit is clean, and each
    /// list is empty.
    @Test("a clean repository is clean and lists no file")
    func aCleanRepositoryIsCleanAndListsNoFile() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.status(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.isClean)
        #expect(result.staged.isEmpty)
        #expect(result.unstaged.isEmpty)
        #expect(result.untracked.isEmpty)
        #expect(result.renamed.isEmpty)
    }

    /// One file of each kind goes in its own list, and the repository is not
    /// clean.
    @Test("one file of each kind goes in its own list")
    func oneFileOfEachKindGoesInItsOwnList() async throws {
        let repository = try Self.makeOneFileOfEachKind(in: "")

        let result = try await Self.status(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(!result.isClean)
        #expect(result.staged == ["staged.txt"])
        #expect(result.unstaged == ["changed.txt"])
        #expect(result.untracked == ["untracked.txt"])
        #expect(result.renamed == ["renamed.txt"])
    }

    /// A root in a subfolder gives each path relative to the root, and leaves
    /// out each file outside the root.
    @Test("a root in a subfolder lists only its own files, relative to it")
    func aRootInASubfolderListsOnlyItsOwnFilesRelativeToIt() async throws {
        let repository = try Self.makeOneFileOfEachKind(in: "\(Self.rootFolder)/")
        try repository.write("outside\n", to: "outside.txt")
        let root = repository.workDirectory.appendingPathComponent(Self.rootFolder, isDirectory: true)

        let result = try await Self.status(in: GitContext(root: root))

        #expect(result.correction == nil)
        #expect(result.staged == ["staged.txt"])
        #expect(result.unstaged == ["changed.txt"])
        #expect(result.untracked == ["untracked.txt"])
        #expect(result.renamed == ["renamed.txt"])
    }

    /// A root in a subfolder is clean when each change is outside the root.
    @Test("a root in a subfolder is clean when each change is outside it")
    func aRootInASubfolderIsCleanWhenEachChangeIsOutsideIt() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        try repository.write("changed\n", to: "a.txt")
        try repository.write("untracked\n", to: "u.txt")
        let root = repository.workDirectory.appendingPathComponent(Self.rootFolder, isDirectory: true)

        let result = try await Self.status(in: GitContext(root: root))

        #expect(result.correction == nil)
        #expect(result.isClean)
    }

    /// A root in no repository is a correction, not a thrown error.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let result = try await Self.status(in: GitContext(root: outside))

        let correction = try #require(result.correction)
        #expect(correction.contains("not in a git repository"), "correction was: \(correction)")
        #expect(!result.isClean)
        #expect(result.staged.isEmpty)
        #expect(result.unstaged.isEmpty)
        #expect(result.untracked.isEmpty)
        #expect(result.renamed.isEmpty)
    }

    // MARK: - Helpers

    /// Makes a repository with one uncommitted file of each kind, each in
    /// the folder `folder`:
    ///
    /// - `staged.txt`: a new file in the index.
    /// - `changed.txt`: a committed file with a change that is not staged.
    /// - `untracked.txt`: a file that git does not track.
    /// - `renamed.txt`: a staged rename of the committed file `original.txt`.
    ///
    /// - Parameter folder: The folder of the files, relative to the work
    ///   folder: empty, or a folder name with a `/` after it.
    /// - Returns: The repository.
    /// - Throws: When a write, a move, a stage, or a commit fails.
    private static func makeOneFileOfEachKind(in folder: String) throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write("changed\n", to: "\(folder)changed.txt")
        try repository.write("the text of the renamed file\n", to: "\(folder)original.txt")
        try repository.commit(message: "first")
        try repository.write("staged\n", to: "\(folder)staged.txt")
        try repository.stage("\(folder)staged.txt")
        try repository.write("changed again\n", to: "\(folder)changed.txt")
        try repository.write("untracked\n", to: "\(folder)untracked.txt")
        try FileManager.default.moveItem(
            at: repository.workDirectory.appendingPathComponent("\(folder)original.txt"),
            to: repository.workDirectory.appendingPathComponent("\(folder)renamed.txt"))
        try repository.stage("\(folder)original.txt")
        try repository.stage("\(folder)renamed.txt")
        return repository
    }

    /// Calls the `tools.git.status` verb over a context.
    ///
    /// - Parameter context: The context of the verb.
    /// - Returns: The result of the verb.
    private static func status(in context: GitContext) async throws -> StatusResult {
        try await Status(context: context).call(arguments: StatusArguments())
    }
}
