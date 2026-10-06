// `GitShowTests` — the behavioral suite of the `tools.git.show` verb.
//
// The suite makes `ShowArguments` with the memberwise initializer and calls
// the `Show` verb directly, the way `GitBlameTests` calls its verb. Each test
// makes its own temporary repository, thus the tests are independent and they
// run in parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.show` verb (task `^w0yeya3`).
///
/// The card names each case: `HEAD`, an older commit, a branch name, an
/// unknown ref, an unknown path, a path outside the root, a binary file, and
/// content over the cap. A root in a subfolder, a folder path, and a root in no
/// repository are here too. Task `^5a8vaqk` adds a file in a folder that a
/// later commit removed, and such a path outside the root.
@Suite("GitShowTests")
struct GitShowTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitShowTests"

    /// The file that the tests show, relative to the work folder.
    private static let filePath = "src/a.txt"

    /// The text of the first commit of ``filePath``.
    private static let firstText = "one\ntwo\n"

    /// The text of the second commit of ``filePath``.
    private static let secondText = "one\nTWO\n"

    /// The ref that `show` reads when the call names no ref.
    private static let defaultRef = "HEAD"

    // MARK: - Refs

    /// With no ref, `show` reads the file at HEAD, and the result names the
    /// path relative to the root and the ref it read.
    @Test("show with no ref gives the file at HEAD")
    func showWithNoRefGivesTheFileAtHead() async throws {
        let repository = try Self.repositoryWithTwoCommits()

        let result = try await Self.show(Self.filePath, in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.path == Self.filePath)
        #expect(result.ref == Self.defaultRef)
        #expect(result.content == Self.secondText)
        #expect(!result.isCapped)
    }

    /// An older commit gives the file as that commit holds it, also when a
    /// later commit removed the file from the work folder.
    @Test("show at an older commit gives the file of that commit")
    func showAtAnOlderCommitGivesTheFileOfThatCommit() async throws {
        let repository = try Self.repositoryWithTwoCommits()
        try FileManager.default.removeItem(
            at: repository.workDirectory.appendingPathComponent(Self.filePath, isDirectory: false))
        try repository.commit(message: "remove")
        let context = GitContext(root: repository.workDirectory)

        let parent = try await Self.show(Self.filePath, in: context, ref: "HEAD~1")
        let grandparent = try await Self.show(Self.filePath, in: context, ref: "HEAD~2")

        #expect(parent.correction == nil)
        #expect(parent.ref == "HEAD~1")
        #expect(parent.content == Self.secondText)
        #expect(grandparent.content == Self.firstText)
    }

    /// A file in a folder that a later commit removed reads at an older ref.
    /// The file comes from the commit, not from the work folder, thus the
    /// absent folder is not a correction. At HEAD the commit holds no file
    /// at the path, and that is the correction.
    @Test("show of a file whose folder a later commit removed reads the older ref")
    func showOfAFileWhoseFolderALaterCommitRemovedReadsTheOlderRef() async throws {
        let (repository, _) = try GitTestHistory.makeRemovedFolder(
            firstText: Self.firstText, secondText: Self.secondText)
        let context = GitContext(root: repository.workDirectory)
        let path = GitTestHistory.removedFolderFile

        let parent = try await Self.show(path, in: context, ref: "HEAD~1")
        let grandparent = try await Self.show(path, in: context, ref: "HEAD~2")
        let head = try await Self.show(path, in: context)

        #expect(parent.correction == nil)
        #expect(parent.path == path)
        #expect(parent.content == Self.secondText)
        #expect(grandparent.content == Self.firstText)
        try Self.expectCorrection(head, contains: "holds no file at this path")
    }

    /// A branch name gives the file at the commit of that branch.
    @Test("show at a branch name gives the file of that branch")
    func showAtABranchNameGivesTheFileOfThatBranch() async throws {
        let repository = try Self.repositoryWithTwoCommits()

        let result = try await Self.show(
            Self.filePath, in: GitContext(root: repository.workDirectory), ref: GitTestHistory.featureBranch)

        #expect(result.correction == nil)
        #expect(result.content == Self.firstText)
    }

    /// A root in a subfolder takes a path relative to that root, and the
    /// result names the path relative to it too.
    @Test("a root in a subfolder shows a path relative to that root")
    func aRootInASubfolderShowsAPathRelativeToThatRoot() async throws {
        let repository = try Self.repositoryWithTwoCommits()
        let root = repository.workDirectory.appendingPathComponent("src", isDirectory: true)

        let result = try await Self.show("a.txt", in: GitContext(root: root))

        #expect(result.correction == nil)
        #expect(result.path == "a.txt")
        #expect(result.content == Self.secondText)
    }

    // MARK: - The cap

    /// A file longer than the cap gives its first ``Show/lineCap`` lines, and
    /// `isCapped` says that the cap cut the content.
    @Test("a file longer than the cap gives the cap and says so")
    func aFileLongerThanTheCapGivesTheCapAndSaysSo() async throws {
        let repository = try TemporaryGitRepository()
        let lines = (1...(Show.lineCap + 1)).map { "line \($0)\n" }
        try repository.write(lines.joined(), to: Self.filePath)
        try repository.commit(message: "long")

        let result = try await Self.show(Self.filePath, in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.isCapped)
        #expect(result.content == lines.prefix(Show.lineCap).joined())
    }

    // MARK: - Corrections

    /// A ref that names no commit is a correction that names the ref.
    @Test("an unknown ref is a correction")
    func anUnknownRefIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoCommits()

        let result = try await Self.show(
            Self.filePath, in: GitContext(root: repository.workDirectory), ref: "no-such-ref")

        try Self.expectCorrection(result, contains: "no-such-ref")
    }

    /// A path that the commit does not hold is a correction that names the
    /// whole path and the ref.
    @Test("an unknown path is a correction")
    func anUnknownPathIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoCommits()

        let result = try await Self.show("src/missing.txt", in: GitContext(root: repository.workDirectory))

        try Self.expectCorrection(result, contains: "src/missing.txt")
        try Self.expectCorrection(result, contains: Self.defaultRef)
    }

    /// A path that names a folder is a correction, not the folder listing.
    @Test("a folder path is a correction")
    func aFolderPathIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoCommits()

        let result = try await Self.show("src", in: GitContext(root: repository.workDirectory))

        try Self.expectCorrection(result, contains: "folder")
    }

    /// A path outside the root goes through the path guard of the context,
    /// and the refusal of the guard comes back as the correction: a `..` path
    /// and an absolute path in another folder.
    @Test("a path outside the root is a correction")
    func aPathOutsideTheRootIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoCommits()
        try repository.write("b\n", to: "b.txt")
        try repository.commit(message: "b")
        let context = GitContext(root: repository.workDirectory.appendingPathComponent("src", isDirectory: true))
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outsideFile = outside.appendingPathComponent("x.txt", isDirectory: false)
        try "x\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        for path in ["../b.txt", outsideFile.path] {
            let result = try await Self.show(path, in: context)

            let refusal = try #require(throws: PathViolation.self) {
                try context.pathGuard.validatePath(path).get()
            }
            try Self.expectCorrection(result, contains: refusal.message)
        }
    }

    /// A path outside the root is a correction also when its folders are
    /// absent: a removed folder of the repository above a root in a
    /// subfolder, and an absent folder in another folder.
    @Test("a path in an absent folder outside the root is a correction")
    func aPathInAnAbsentFolderOutsideTheRootIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeRemovedFolder(
            firstText: Self.firstText, secondText: Self.secondText)
        let context = GitContext(
            root: repository.workDirectory.appendingPathComponent(GitTestHistory.keptFolder, isDirectory: true))
        let removedFile = repository.workDirectory.appendingPathComponent(
            GitTestHistory.removedFolderFile, isDirectory: false)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outsideFile = outside.appendingPathComponent("gone/x.txt", isDirectory: false)

        for path in [removedFile.path, outsideFile.path] {
            let result = try await Self.show(path, in: context, ref: "HEAD~1")

            let refusal = try #require(throws: PathViolation.self) {
                try context.pathGuard.validatePath(path, absentFolders: .accepted).get()
            }
            #expect(refusal.message.contains("outside workspace"))
            try Self.expectCorrection(result, contains: refusal.message)
        }
    }

    /// A binary file at the ref is a correction, not text.
    @Test("a binary file is a correction")
    func aBinaryFileIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try Data([0x00, 0xFF, 0x00, 0x80]).write(
            to: repository.workDirectory.appendingPathComponent("blob.bin", isDirectory: false))
        try repository.commit(message: "binary")

        let result = try await Self.show("blob.bin", in: GitContext(root: repository.workDirectory))

        try Self.expectCorrection(result, contains: "binary")
    }

    /// A root in no repository is a correction.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let result = try await Self.show("a.txt", in: GitContext(root: outside))

        try Self.expectCorrection(result, contains: "not in a git repository")
    }

    // MARK: - Helpers

    /// Calls the `tools.git.show` verb over a context.
    ///
    /// - Parameters:
    ///   - path: The path to show.
    ///   - context: The context of the verb.
    ///   - ref: The ref, or `nil` for the default.
    /// - Returns: The result of the verb.
    private static func show(_ path: String, in context: GitContext, ref: String? = nil) async throws -> ShowResult {
        try await Show(context: context).call(arguments: ShowArguments(path: path, ref: ref))
    }

    /// A repository with ``firstText`` and then ``secondText`` committed to
    /// ``filePath``, and the branch `GitTestHistory.featureBranch` at the
    /// first commit.
    ///
    /// - Returns: The repository.
    /// - Throws: When a write, a commit, or the branch fails.
    private static func repositoryWithTwoCommits() throws -> TemporaryGitRepository {
        try GitTestHistory.makeTwoVersions(of: filePath, firstText: firstText, secondText: secondText)
    }

    /// Expects that `result` is a correction that holds `fragment`, with no
    /// content and no cap.
    ///
    /// - Parameters:
    ///   - result: The result of the verb.
    ///   - fragment: Text that the correction must hold.
    /// - Throws: When the result has no correction.
    private static func expectCorrection(_ result: ShowResult, contains fragment: String) throws {
        let correction = try #require(result.correction)
        #expect(correction.contains(fragment), "correction was: \(correction)")
        #expect(result.content == nil)
        #expect(!result.isCapped)
    }
}
