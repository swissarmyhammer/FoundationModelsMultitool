import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the blame part of the `LibGit2` layer: one attribution for
/// each line of the content, the same as `blame_lines` of
/// `swissarmyhammer-git` (`LineBlame`).
///
/// A line comes from a commit, from a change that is not committed, or from
/// a file that git does not track. Each test makes its own temporary
/// repository, thus the tests are independent and they run in parallel
/// safely.
@Suite("LibGit2BlameTests")
struct LibGit2BlameTests {

    /// The file that the tests blame.
    private static let filePath = "src/a.txt"

    /// The text of the first commit of ``filePath``.
    private static let firstText = "one\ntwo\nthree\n"

    /// The text of the second commit of ``filePath``: only line 2 changes.
    private static let secondText = "one\nTWO\nthree\n"

    /// The text of the third commit of ``filePath``: only line 3 changes.
    private static let thirdText = "one\nTWO\nTHREE\n"

    /// The number of lines in ``firstText``, ``secondText``, and
    /// ``thirdText``.
    private static let lineCount = 3

    /// The name that `TemporaryGitRepository` records on each commit.
    private static let commitAuthor = "Test"

    /// The largest time, in seconds, between a commit of a test and the
    /// check of its date.
    private static let commitDateTolerance: TimeInterval = 600

    /// Each line comes from the last commit that changed it, not from the
    /// newest commit of the file.
    @Test("each line comes from the last commit that changed it")
    func eachLineComesFromTheLastCommitThatChangedIt() throws {
        let repository = try TemporaryGitRepository()
        let (first, second) = try Self.commitTwice(in: repository)

        let lines = try Self.blame(Self.secondText, in: repository)

        let commits = lines.map(Self.commit)
        #expect(commits.map { $0?.sha } == [first, second, first])
        #expect(commits.map { $0?.author } == Array(repeating: Self.commitAuthor, count: Self.lineCount))
        let date = try #require(commits[0]?.date)
        #expect(abs(date.timeIntervalSinceNow) < Self.commitDateTolerance)
    }

    /// A line that the work folder changed and that is not committed has no
    /// commit. The other lines keep their commit.
    @Test("a changed line that is not committed is uncommitted")
    func aChangedLineThatIsNotCommittedIsUncommitted() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstText, to: Self.filePath)
        let first = try repository.commit(message: "first")
        try repository.write(Self.secondText, to: Self.filePath)

        let lines = try Self.blame(Self.secondText, in: repository)

        #expect(lines[0] == lines[2])
        #expect(Self.commit(lines[0])?.sha == first)
        #expect(lines[1] == .uncommitted)
    }

    /// A file that is in neither the index nor the tree of HEAD has no
    /// history: each line is untracked.
    @Test("each line of a file that git does not track is untracked")
    func eachLineOfAFileThatGitDoesNotTrackIsUntracked() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstText, to: "b.txt")
        try repository.commit(message: "first")
        try repository.write(Self.secondText, to: Self.filePath)

        let lines = try Self.blame(Self.secondText, in: repository)

        #expect(lines == Array(repeating: .untracked, count: Self.lineCount))
    }

    /// A file that is in the index, and in no commit, is tracked but has no
    /// commit to blame: each line is uncommitted.
    @Test("each line of a staged file that is in no commit is uncommitted")
    func eachLineOfAStagedFileThatIsInNoCommitIsUncommitted() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstText, to: "b.txt")
        try repository.commit(message: "first")
        try repository.write(Self.secondText, to: Self.filePath)
        try repository.stage(Self.filePath)

        let lines = try Self.blame(Self.secondText, in: repository)

        #expect(lines == Array(repeating: .uncommitted, count: Self.lineCount))
    }

    /// A staged file in a repository with no commit (HEAD names a branch with
    /// no commit) is uncommitted too, not a blame failure.
    @Test("each line of a staged file in a repository with no commit is uncommitted")
    func eachLineOfAStagedFileInARepositoryWithNoCommitIsUncommitted() throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.secondText, to: Self.filePath)
        try repository.stage(Self.filePath)

        let lines = try Self.blame(Self.secondText, in: repository)

        #expect(lines == Array(repeating: .uncommitted, count: Self.lineCount))
    }

    /// A content with no line gives no attribution, and reads nothing.
    @Test("a content with no line gives no attribution")
    func aContentWithNoLineGivesNoAttribution() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("", to: Self.filePath)

        let lines = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blameLines(atPath: Self.filePath, content: Data(), lineCount: 0)

        #expect(lines.isEmpty)
    }

    // MARK: - At a revision

    /// At an earlier commit, the line comes from the commit at or before that
    /// commit. The later commit that changed the line, and the work folder
    /// that holds the later text, have no effect.
    @Test("a blame at a revision ignores a later commit and the work folder")
    func aBlameAtARevisionIgnoresALaterCommitAndTheWorkFolder() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()
        try repository.write("changed\n", to: "a.txt")

        let lines = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blameLines(atPath: "a.txt", revision: shas[1], lineCount: 1)

        #expect(lines.map { Self.commit($0)?.sha } == [shas[0]])
    }

    /// Each commit changes one line. At the second commit, each line comes
    /// from the last commit at or before the second commit that changed it.
    @Test("each line at a revision comes from the last commit at or before it")
    func eachLineAtARevisionComesFromTheLastCommitAtOrBeforeIt() throws {
        let repository = try TemporaryGitRepository()
        let (first, second, _) = try Self.commitThrice(in: repository)

        let lines = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blameLines(atPath: Self.filePath, revision: second, lineCount: Self.lineCount)

        #expect(lines.map { Self.commit($0)?.sha } == [first, second, first])
    }

    /// A revision that names no commit throws the not-found error.
    @Test("a revision that names no commit throws not found")
    func aRevisionThatNamesNoCommitThrowsNotFound() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        let error = try #require(throws: LibGit2Error.self) {
            try opened.blameLines(atPath: "a.txt", revision: "no-such-ref", lineCount: 1)
        }

        #expect(error.isNotFound)
    }

    /// A path that the commit of the revision does not hold throws.
    @Test("a path that the revision does not hold throws")
    func aPathThatTheRevisionDoesNotHoldThrows() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(throws: LibGit2Error.self) {
            try opened.blameLines(atPath: "src/b.txt", revision: shas[0], lineCount: 1)
        }
    }

    // MARK: - Helpers

    /// Blames ``filePath`` of `repository` against `text`.
    ///
    /// - Parameters:
    ///   - text: The content of the file, with ``lineCount`` lines.
    ///   - repository: The repository.
    /// - Returns: One attribution for each line.
    /// - Throws: ``LibGit2Error`` when the blame fails.
    private static func blame(_ text: String, in repository: TemporaryGitRepository) throws -> [LibGit2LineBlame] {
        try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blameLines(atPath: filePath, content: Data(text.utf8), lineCount: lineCount)
    }

    /// Commits ``firstText``, then ``secondText``, then ``thirdText`` to
    /// ``filePath``. Each commit after the first changes one line.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The sha of each commit.
    /// - Throws: When a write or a commit fails.
    private static func commitThrice(in repository: TemporaryGitRepository) throws -> (String, String, String) {
        let (first, second) = try commitTwice(in: repository)
        try repository.write(thirdText, to: filePath)
        let third = try repository.commit(message: "third")
        return (first, second, third)
    }

    /// Commits ``firstText`` and then ``secondText`` to ``filePath``.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The sha of each commit.
    /// - Throws: When a write or a commit fails.
    private static func commitTwice(in repository: TemporaryGitRepository) throws -> (String, String) {
        try repository.write(firstText, to: filePath)
        let first = try repository.commit(message: "first")
        try repository.write(secondText, to: filePath)
        let second = try repository.commit(message: "second")
        return (first, second)
    }

    /// The commit of `line`, or `nil` when no commit holds it.
    ///
    /// - Parameter line: The attribution.
    /// - Returns: The commit.
    private static func commit(_ line: LibGit2LineBlame) -> LibGit2Commit? {
        guard case .committed(let commit) = line else { return nil }
        return commit
    }
}
