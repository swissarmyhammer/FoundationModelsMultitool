import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the shared blob reader of the git capability,
/// `GitContext.blob(path:ref:)`: the text of one file at one ref, or the
/// correction that says why there is none.
///
/// `tools.git.show` and `tools.git.diff` (for `path@ref`) both read through
/// it, thus this suite holds the contract that both verbs share: the whole
/// text with no cap, the path relative to the root, and a binary blob as a
/// correction. Each test makes its own temporary repository, thus the tests
/// are independent and they run in parallel safely.
@Suite("GitBlobReaderTests")
struct GitBlobReaderTests {

    /// The ref of the newest commit.
    private static let headRevision = "HEAD"

    /// The reader gives the whole text of the file at the ref, and the path
    /// relative to the root.
    @Test("the reader gives the whole text and the root path")
    func theReaderGivesTheWholeTextAndTheRootPath() throws {
        let repository = try TemporaryGitRepository()
        let text = (1...(Show.lineCap + 1)).map { "line \($0)\n" }.joined()
        try repository.write(text, to: "src/a.txt")
        try repository.commit(message: "first")
        let root = repository.workDirectory.appendingPathComponent("src", isDirectory: true)

        let blob = try GitContext(root: root).blob(path: "./a.txt", ref: Self.headRevision).get()

        #expect(blob == GitBlob(path: "a.txt", text: text))
    }

    /// A blob that git sees as binary is a correction, also when its bytes
    /// are valid UTF-8 (a NUL byte is valid UTF-8).
    @Test("a binary blob is a correction")
    func aBinaryBlobIsACorrection() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("text\u{0}with a NUL byte\n", to: "a.bin")
        try repository.commit(message: "first")

        let blob = GitContext(root: repository.workDirectory).blob(path: "a.bin", ref: Self.headRevision)

        let rejection = try #require(throws: CorrectiveRejection.self) { try blob.get() }
        #expect(rejection.correctiveMessage.contains("binary"), "was: \(rejection.correctiveMessage)")
    }
}
