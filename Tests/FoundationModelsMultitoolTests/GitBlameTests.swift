// `GitBlameTests` — the behavioral suite of the `tools.git.blame` verb.
//
// The suite makes `BlameArguments` with the memberwise initializer and calls
// the `Blame` verb directly, the way `FilesReadTests` calls its verb. Each
// test makes its own temporary repository, thus the tests are independent
// and they run in parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.blame` verb (task `^jmm1a0k`).
///
/// The card names each case: a file with lines from two commits, a line
/// range, a file with an uncommitted change, an untracked file, a bad range,
/// and a path outside the root. The line cap, a root in a subfolder, a root
/// in no repository, and a binary file are here too.
@Suite("GitBlameTests")
struct GitBlameTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitBlameTests"

    /// The file that the tests blame, relative to the work folder.
    private static let filePath = "src/a.txt"

    /// The lines of the first commit of ``filePath``.
    private static let firstLines = ["one", "two", "three"]

    /// The lines of the second commit of ``filePath``: only line 2 changes.
    private static let secondLines = ["one", "TWO", "three"]

    /// The name that `TemporaryGitRepository` records on each commit.
    private static let commitAuthor = "Test"

    /// The `state` of a line that a commit holds.
    private static let committedState = "committed"

    /// The `state` of a line that the work folder changed and no commit holds.
    private static let uncommittedState = "uncommitted"

    /// The `state` of a line of a file that git does not track.
    private static let untrackedState = "untracked"

    // MARK: - Whole file

    /// Each line names the commit that last changed it, its author and date,
    /// and its text; the path in the result is relative to the root.
    @Test("each line of a file from two commits names its own commit")
    func eachLineOfAFileFromTwoCommitsNamesItsOwnCommit() async throws {
        let repository = try TemporaryGitRepository()
        let (first, second) = try Self.commitTwice(in: repository)

        let result = try await Self.blame(Self.filePath, in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.path == Self.filePath)
        #expect(!result.isCapped)
        #expect(result.lines.map(\.line) == [1, 2, 3])
        #expect(result.lines.map(\.text) == Self.secondLines)
        #expect(result.lines.map(\.sha) == [first, second, first])
        #expect(result.lines.allSatisfy { $0.state == Self.committedState })
        #expect(result.lines.allSatisfy { $0.author == Self.commitAuthor })
        let date = try #require(result.lines[0].date)
        #expect((try? Date.ISO8601FormatStyle().parse(date)) != nil, "date was: \(date)")
    }

    /// A root in a subfolder of the work folder takes a path relative to
    /// that root, and the result names the path relative to it too.
    @Test("a root in a subfolder blames a path relative to that root")
    func aRootInASubfolderBlamesAPathRelativeToThatRoot() async throws {
        let repository = try TemporaryGitRepository()
        try Self.commitTwice(in: repository)
        let root = repository.workDirectory.appendingPathComponent("src", isDirectory: true)

        let result = try await Self.blame("a.txt", in: GitContext(root: root))

        #expect(result.correction == nil)
        #expect(result.path == "a.txt")
        #expect(result.lines.map(\.text) == Self.secondLines)
    }

    // MARK: - Line range

    /// `startLine` and `endLine` select the lines from one to the other,
    /// both included, with their numbers in the file.
    @Test("a line range gives only the lines in the range")
    func aLineRangeGivesOnlyTheLinesInTheRange() async throws {
        let repository = try TemporaryGitRepository()
        let (first, second) = try Self.commitTwice(in: repository)
        let context = GitContext(root: repository.workDirectory)

        let result = try await Self.blame(Self.filePath, in: context, startLine: 2, endLine: 3)

        #expect(result.correction == nil)
        #expect(result.lines.map(\.line) == [2, 3])
        #expect(result.lines.map(\.sha) == [second, first])
        #expect(result.lines.map(\.text) == ["TWO", "three"])
    }

    /// A `startLine` alone goes to the end of the file, and an `endLine`
    /// alone starts at the first line.
    @Test("one end of the range alone goes to the other end of the file")
    func oneEndOfTheRangeAloneGoesToTheOtherEndOfTheFile() async throws {
        let repository = try TemporaryGitRepository()
        try Self.commitTwice(in: repository)
        let context = GitContext(root: repository.workDirectory)

        let fromTwo = try await Self.blame(Self.filePath, in: context, startLine: 2)
        let toTwo = try await Self.blame(Self.filePath, in: context, endLine: 2)

        #expect(fromTwo.lines.map(\.line) == [2, 3])
        #expect(toTwo.lines.map(\.line) == [1, 2])
    }

    // MARK: - Lines with no commit

    /// A line that the work folder changed and no commit holds is
    /// `uncommitted`, with no sha, no author, and no date. The other lines
    /// keep their commit.
    @Test("a changed line that is not committed is uncommitted")
    func aChangedLineThatIsNotCommittedIsUncommitted() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.text(of: Self.firstLines), to: Self.filePath)
        let first = try repository.commit(message: "first")
        try repository.write(Self.text(of: Self.secondLines), to: Self.filePath)

        let result = try await Self.blame(Self.filePath, in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.lines.map(\.state) == [Self.committedState, Self.uncommittedState, Self.committedState])
        #expect(result.lines.map(\.sha) == [first, nil, first])
        #expect(result.lines[1].author == nil)
        #expect(result.lines[1].date == nil)
        #expect(result.lines[1].text == "TWO")
    }

    /// Each line of a file that git does not track is `untracked`, with no
    /// sha. Thus an untracked file is not a correction.
    @Test("each line of an untracked file is untracked")
    func eachLineOfAnUntrackedFileIsUntracked() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.text(of: Self.firstLines), to: "b.txt")
        try repository.commit(message: "first")
        try repository.write(Self.text(of: Self.secondLines), to: Self.filePath)

        let result = try await Self.blame(Self.filePath, in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.lines.map(\.state) == Array(repeating: Self.untrackedState, count: Self.secondLines.count))
        #expect(result.lines.allSatisfy { $0.sha == nil && $0.author == nil && $0.date == nil })
        #expect(result.lines.map(\.text) == Self.secondLines)
    }

    // MARK: - The line cap

    /// A file longer than the cap gives the first ``Blame/lineCap`` lines of
    /// the range, and `isCapped` says that the cap cut the result.
    @Test("a file longer than the cap gives the cap and says so")
    func aFileLongerThanTheCapGivesTheCapAndSaysSo() async throws {
        let repository = try TemporaryGitRepository()
        let lines = (1...(Blame.lineCap + 1)).map { "line \($0)" }
        try repository.write(Self.text(of: lines), to: Self.filePath)
        try repository.commit(message: "long")

        let result = try await Self.blame(Self.filePath, in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.isCapped)
        #expect(result.lines.count == Blame.lineCap)
        #expect(result.lines.last?.line == Blame.lineCap)
    }

    // MARK: - Corrections

    /// A `startLine` after the `endLine` is a correction, not a throw.
    @Test("a start line after the end line is a correction")
    func aStartLineAfterTheEndLineIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try Self.commitTwice(in: repository)

        let result = try await Self.blame(
            Self.filePath, in: GitContext(root: repository.workDirectory), startLine: 3, endLine: 2)

        try Self.expectCorrection(result, contains: "startLine")
    }

    /// A `startLine` or an `endLine` past the last line is a correction that
    /// names the number of lines.
    @Test("a line past the end of the file is a correction")
    func aLinePastTheEndOfTheFileIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try Self.commitTwice(in: repository)
        let context = GitContext(root: repository.workDirectory)

        let startPastEnd = try await Self.blame(Self.filePath, in: context, startLine: 4)
        let endPastEnd = try await Self.blame(Self.filePath, in: context, startLine: 1, endLine: 4)

        try Self.expectCorrection(startPastEnd, contains: "3 lines")
        try Self.expectCorrection(endPastEnd, contains: "3 lines")
    }

    /// A line number below 1 is a correction that names the valid range.
    @Test("a line number below 1 is a correction")
    func aLineNumberBelowOneIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try Self.commitTwice(in: repository)

        let result = try await Self.blame(Self.filePath, in: GitContext(root: repository.workDirectory), startLine: 0)

        try Self.expectCorrection(result, contains: "startLine")
    }

    /// A path outside the root goes through the path guard of the context,
    /// and the refusal of the guard comes back as the correction: a `..`
    /// path and an absolute path in another folder.
    @Test("a path outside the root is a correction")
    func aPathOutsideTheRootIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        try Self.commitTwice(in: repository)
        try repository.write("b\n", to: "b.txt")
        let context = GitContext(root: repository.workDirectory.appendingPathComponent("src", isDirectory: true))
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outsideFile = outside.appendingPathComponent("x.txt", isDirectory: false)
        try "x\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        for path in ["../b.txt", outsideFile.path] {
            let result = try await Self.blame(path, in: context)

            let refusal = try #require(throws: PathViolation.self) {
                try context.pathGuard.validate(path, for: .read).get()
            }
            try Self.expectCorrection(result, contains: refusal.message)
        }
    }

    /// A root in no repository is a correction.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try "x\n".write(
            to: outside.appendingPathComponent("a.txt", isDirectory: false), atomically: true, encoding: .utf8)

        let result = try await Self.blame("a.txt", in: GitContext(root: outside))

        try Self.expectCorrection(result, contains: "not in a git repository")
    }

    /// A file that is not UTF-8 text is a correction.
    @Test("a binary file is a correction")
    func aBinaryFileIsACorrection() async throws {
        let repository = try TemporaryGitRepository()
        let url = repository.workDirectory.appendingPathComponent("blob.bin", isDirectory: false)
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: url)

        let result = try await Self.blame("blob.bin", in: GitContext(root: repository.workDirectory))

        try Self.expectCorrection(result, contains: "binary")
    }

    // MARK: - Helpers

    /// Calls the `tools.git.blame` verb over a context.
    ///
    /// - Parameters:
    ///   - path: The path to blame.
    ///   - context: The context of the verb.
    ///   - startLine: The first line, or `nil`.
    ///   - endLine: The last line, or `nil`.
    /// - Returns: The result of the verb.
    private static func blame(
        _ path: String,
        in context: GitContext,
        startLine: Int? = nil,
        endLine: Int? = nil
    ) async throws -> BlameResult {
        try await Blame(context: context)
            .call(arguments: BlameArguments(path: path, startLine: startLine, endLine: endLine))
    }

    /// Commits ``firstLines`` and then ``secondLines`` to ``filePath``.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The sha of each commit.
    /// - Throws: When a write or a commit fails.
    @discardableResult
    private static func commitTwice(in repository: TemporaryGitRepository) throws -> (String, String) {
        try repository.write(text(of: firstLines), to: filePath)
        let first = try repository.commit(message: "first")
        try repository.write(text(of: secondLines), to: filePath)
        let second = try repository.commit(message: "second")
        return (first, second)
    }

    /// The text of `lines`, each with a newline after it.
    ///
    /// - Parameter lines: The lines.
    /// - Returns: The text.
    private static func text(of lines: [String]) -> String {
        lines.map { "\($0)\n" }.joined()
    }

    /// Expects that `result` is a correction that holds `fragment`, with no
    /// line and no cap.
    ///
    /// - Parameters:
    ///   - result: The result of the verb.
    ///   - fragment: Text that the correction must hold.
    /// - Throws: When the result has no correction.
    private static func expectCorrection(_ result: BlameResult, contains fragment: String) throws {
        let correction = try #require(result.correction)
        #expect(correction.contains(fragment), "correction was: \(correction)")
        #expect(result.lines.isEmpty)
        #expect(!result.isCapped)
    }
}
