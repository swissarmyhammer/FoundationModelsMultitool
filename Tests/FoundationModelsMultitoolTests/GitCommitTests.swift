// `GitCommitTests` — the behavioral suite of the `tools.git.commit` verb.
//
// The suite makes `CommitArguments` with the memberwise initializer and calls
// the `Commit` verb directly, the way `GitLogTests` calls its verb. Each test
// makes its own temporary repository, thus the tests are independent and they
// run in parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.commit` verb (task `^0rtkdbt`).
///
/// The card names each case: HEAD with no argument, a sha, a tag, `HEAD~1`,
/// an unknown ref, and a file outside the root. A rename across the root, the
/// cap of the files list, a ref that names no commit, and a root in no
/// repository are here too.
@Suite("GitCommitTests")
struct GitCommitTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitCommitTests"

    /// The name that `TemporaryGitRepository` records on each commit.
    private static let commitAuthor = "Test"

    /// The number of hex characters in a short sha.
    private static let shortShaLength = 7

    /// The subfolder that the tests use as a root below the work folder.
    private static let rootFolder = "src"

    // MARK: - Commits

    /// With no argument, the verb gives HEAD: the sha, the short sha, the
    /// author, the ISO 8601 date, the full message, the parents, and each
    /// changed file with its line counts.
    @Test("commit with no argument gives HEAD with its full message and its files with counts")
    func commitWithNoArgumentGivesHeadWithItsFullMessageAndItsFilesWithCounts() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("1\n2\n", to: "a.txt")
        let first = try repository.commit(message: "first")
        try repository.write("1\n3\n4\n", to: "a.txt")
        try repository.write("new\n", to: "new.txt")
        let message = "the subject\n\nthe body of the message\n"
        let second = try repository.commit(message: message)

        let result = try await Self.commit(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.sha == second)
        #expect(result.shortSha == String(second.prefix(Self.shortShaLength)))
        #expect(result.author == Self.commitAuthor)
        #expect((try? Date.ISO8601FormatStyle().parse(result.date)) != nil, "date was: \(result.date)")
        #expect(result.message == message)
        #expect(result.parents == [first])
        #expect(Self.summaries(of: result) == ["a.txt modified +2 -1", "new.txt added +1 -0"])
        #expect(!result.isCapped)
    }

    /// A sha gives the commit that it names, with that commit's parents and
    /// files.
    @Test("a sha gives that commit")
    func aShaGivesThatCommit() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.commit(in: GitContext(root: repository.workDirectory), ref: shas[1])

        #expect(result.correction == nil)
        #expect(result.sha == shas[1])
        #expect(result.message == "second")
        #expect(result.parents == [shas[0]])
        #expect(Self.summaries(of: result) == ["src/b.txt added +1 -0"])
    }

    /// A tag and a form such as `HEAD~1` each give the commit that they name.
    /// A root commit has no parent.
    @Test("a tag and HEAD~1 give their commits")
    func aTagAndHeadTildeOneGiveTheirCommits() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()
        try TestSupport.runGit(["tag", "v1", shas[0]], in: repository.workDirectory)
        let context = GitContext(root: repository.workDirectory)

        let tagged = try await Self.commit(in: context, ref: "v1")
        let parent = try await Self.commit(in: context, ref: "HEAD~1")

        #expect(tagged.correction == nil)
        #expect(tagged.sha == shas[0])
        #expect(tagged.parents.isEmpty)
        #expect(Self.summaries(of: tagged) == ["a.txt added +1 -0"])
        #expect(parent.correction == nil)
        #expect(parent.sha == shas[1])
    }

    // MARK: - The root

    /// A file outside the root is not in the files list, and each path is
    /// relative to the root.
    @Test("a file outside the root is not in files")
    func aFileOutsideTheRootIsNotInFiles() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.write("b\n", to: "\(Self.rootFolder)/b.txt")
        try repository.commit(message: "both")

        let result = try await Self.commit(in: Self.subfolderContext(of: repository))

        #expect(result.correction == nil)
        #expect(Self.summaries(of: result) == ["b.txt added +1 -0"])
    }

    /// A rename from outside the root into the root is a new file below the
    /// root, the same as in `tools.git.status`: the root did not hold the old
    /// path.
    @Test("a rename into the root is an added file with no old path")
    func aRenameIntoTheRootIsAnAddedFileWithNoOldPath() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("one\ntwo\n", to: "old.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: "old.txt", to: "\(Self.rootFolder)/new.txt")
        try repository.commit(message: "rename")

        let result = try await Self.commit(in: Self.subfolderContext(of: repository))

        #expect(result.correction == nil)
        #expect(Self.summaries(of: result) == ["new.txt added +0 -0"])
    }

    /// A rename from the root to a path outside the root is a removal of the
    /// old path, the same as in `tools.git.status`: the root does not hold the
    /// new path.
    @Test("a rename out of the root is a deleted file at the old path")
    func aRenameOutOfTheRootIsADeletedFileAtTheOldPath() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("one\ntwo\n", to: "\(Self.rootFolder)/old.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: "\(Self.rootFolder)/old.txt", to: "moved.txt")
        try repository.commit(message: "rename")

        let result = try await Self.commit(in: Self.subfolderContext(of: repository))

        #expect(result.correction == nil)
        #expect(Self.summaries(of: result) == ["old.txt deleted +0 -0"])
    }

    /// A rename inside the root keeps the renamed status and gives the old
    /// path relative to the root.
    @Test("a rename inside the root gives the old path relative to the root")
    func aRenameInsideTheRootGivesTheOldPathRelativeToTheRoot() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("one\ntwo\n", to: "\(Self.rootFolder)/old.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: "\(Self.rootFolder)/old.txt", to: "\(Self.rootFolder)/new.txt")
        try repository.commit(message: "rename")

        let result = try await Self.commit(in: Self.subfolderContext(of: repository))

        #expect(result.correction == nil)
        #expect(Self.summaries(of: result) == ["old.txt -> new.txt renamed +0 -0"])
    }

    // MARK: - The cap

    /// A commit that changes more files than the cap gives the first files,
    /// and `isCapped` says that the cap cut the list.
    @Test("a commit with more files than the cap gives the first files and says that the cap cut the list")
    func aCommitWithMoreFilesThanTheCapGivesTheFirstFiles() async throws {
        let repository = try TemporaryGitRepository()
        for number in 0...Commit.fileCap {
            try repository.write("\(number)\n", to: "file\(number).txt")
        }
        try repository.commit(message: "many")

        let result = try await Self.commit(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.isCapped)
        #expect(result.files.count == Commit.fileCap)
    }

    // MARK: - Corrections

    /// A ref that names no object is a correction that names the ref.
    @Test("an unknown ref is a correction")
    func anUnknownRefIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.commit(in: GitContext(root: repository.workDirectory), ref: "no-such-ref")

        try Self.expectCorrection(result, contains: "no-such-ref")
    }

    /// A ref that names an object that is not a commit, such as a file, is a
    /// correction that says that the read failed.
    @Test("a ref that names no commit is a correction")
    func aRefThatNamesNoCommitIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.commit(in: GitContext(root: repository.workDirectory), ref: "HEAD:a.txt")

        try Self.expectCorrection(result, contains: "git commit failed")
    }

    /// A root in no repository is a correction.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let result = try await Self.commit(in: GitContext(root: outside))

        try Self.expectCorrection(result, contains: "not in a git repository")
    }

    // MARK: - Helpers

    /// Calls the `tools.git.commit` verb over a context.
    ///
    /// - Parameters:
    ///   - context: The context of the verb.
    ///   - ref: The ref, or `nil` for HEAD.
    /// - Returns: The result of the verb.
    private static func commit(in context: GitContext, ref: String? = nil) async throws -> CommitResult {
        try await Commit(context: context).call(arguments: CommitArguments(ref: ref))
    }

    /// The context of a root in the ``rootFolder`` subfolder of a repository.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The context.
    private static func subfolderContext(of repository: TemporaryGitRepository) -> GitContext {
        GitContext(root: repository.workDirectory.appendingPathComponent(rootFolder, isDirectory: true))
    }

    /// One line of text for each file of a result: the old path when there is
    /// one, the path, the status, and the line counts.
    ///
    /// - Parameter result: The result of the verb.
    /// - Returns: The lines, in the order of the files.
    private static func summaries(of result: CommitResult) -> [String] {
        result.files.map { file in
            let paths = file.oldPath.map { "\($0) -> \(file.path)" } ?? file.path
            let additions = file.additions.map(String.init) ?? "?"
            let deletions = file.deletions.map(String.init) ?? "?"
            return "\(paths) \(file.status) +\(additions) -\(deletions)"
        }
    }

    /// Expects that `result` is a correction that holds `fragment`, with no
    /// commit, no file, and no cap.
    ///
    /// - Parameters:
    ///   - result: The result of the verb.
    ///   - fragment: Text that the correction must hold.
    /// - Throws: When the result has no correction.
    private static func expectCorrection(_ result: CommitResult, contains fragment: String) throws {
        let correction = try #require(result.correction)
        #expect(correction.contains(fragment), "correction was: \(correction)")
        #expect(result.sha.isEmpty)
        #expect(result.parents.isEmpty)
        #expect(result.files.isEmpty)
        #expect(!result.isCapped)
    }
}
