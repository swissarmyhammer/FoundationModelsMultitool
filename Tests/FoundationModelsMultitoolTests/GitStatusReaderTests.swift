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
