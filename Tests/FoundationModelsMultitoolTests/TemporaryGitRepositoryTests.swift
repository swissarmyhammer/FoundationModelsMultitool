import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `TemporaryGitRepository`, the test helper that makes one git
/// repository for one test with libgit2 only.
///
/// Each test reads the files that git writes under `.git/`, and not the
/// helper, thus a helper that writes the wrong ref fails here.
@Suite("TemporaryGitRepositoryTests")
struct TemporaryGitRepositoryTests {

    /// The file that the tests commit.
    private static let filePath = "src/a.txt"

    /// The text of ``filePath``.
    private static let fileText = "one\ntwo\n"

    /// The branch that the branch test makes.
    private static let featureBranch = "feature"

    /// The full ref name of the default branch of the helper.
    private static var defaultBranchRef: String {
        "refs/heads/\(TemporaryGitRepository.defaultBranch)"
    }

    /// The text of `.git/HEAD` when HEAD names the default branch of the
    /// helper.
    private static var expectedHead: String {
        "ref: \(defaultBranchRef)\n"
    }

    /// The folder of a fresh repository holds a `.git` folder whose HEAD
    /// names the default branch of the helper, whatever `init.defaultBranch`
    /// the host sets (spike fact 2 of git.md).
    @Test("a new repository names the default branch of the helper in HEAD")
    func aNewRepositoryNamesTheDefaultBranchInHead() throws {
        let repository = try TemporaryGitRepository()

        let head = try String(contentsOf: Self.gitFile(repository, "HEAD"), encoding: .utf8)

        #expect(head == Self.expectedHead)
    }

    /// `write` puts the text in the work folder, and makes each parent
    /// folder that is missing.
    @Test("write puts the text in the work folder")
    func writePutsTheTextInTheWorkFolder() throws {
        let repository = try TemporaryGitRepository()

        try repository.write(Self.fileText, to: Self.filePath)

        let url = repository.workDirectory.appendingPathComponent(Self.filePath, isDirectory: false)
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.fileText)
    }

    /// `commit` moves the default branch to the new commit, thus the ref file
    /// of that branch holds the sha that `commit` gives.
    @Test("commit moves the default branch to the new commit")
    func commitMovesTheDefaultBranchToTheNewCommit() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.fileText, to: Self.filePath)

        let sha = try repository.commit(message: "first")

        let tip = try String(contentsOf: Self.gitFile(repository, Self.defaultBranchRef), encoding: .utf8)
        #expect(tip == "\(sha)\n")
    }

    /// A second commit gives a new sha, and moves the default branch to it.
    @Test("a second commit moves the default branch to a new sha")
    func aSecondCommitMovesTheDefaultBranchToANewSha() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.fileText, to: Self.filePath)
        let first = try repository.commit(message: "first")
        try repository.write("three\n", to: Self.filePath)

        let second = try repository.commit(message: "second")

        let tip = try String(contentsOf: Self.gitFile(repository, Self.defaultBranchRef), encoding: .utf8)
        #expect(second != first)
        #expect(tip == "\(second)\n")
    }

    /// `createBranch` makes a branch at the commit HEAD names.
    @Test("createBranch makes a branch at the HEAD commit")
    func createBranchMakesABranchAtTheHeadCommit() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.fileText, to: Self.filePath)
        let sha = try repository.commit(message: "first")

        try repository.createBranch(named: Self.featureBranch)

        let tip = try String(
            contentsOf: Self.gitFile(repository, "refs/heads/\(Self.featureBranch)"), encoding: .utf8)
        #expect(tip == "\(sha)\n")
    }

    /// `stage` writes the file into the index (`.git/index`), and makes no
    /// commit: the default branch has no ref file yet.
    @Test("stage writes the file into the index and makes no commit")
    func stageWritesTheFileIntoTheIndexAndMakesNoCommit() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.fileText, to: Self.filePath)

        try repository.stage(Self.filePath)

        let index = try Data(contentsOf: Self.gitFile(repository, "index"))
        #expect(index.range(of: Data(Self.filePath.utf8)) != nil)
        #expect(!FileManager.default.fileExists(atPath: Self.gitFile(repository, Self.defaultBranchRef).path))
    }

    /// The URL of a file under the `.git` folder of `repository`.
    ///
    /// - Parameters:
    ///   - repository: The repository.
    ///   - path: The path below `.git/`.
    /// - Returns: The URL of that file.
    private static func gitFile(_ repository: TemporaryGitRepository, _ path: String) -> URL {
        repository.workDirectory
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent(path, isDirectory: false)
    }
}
