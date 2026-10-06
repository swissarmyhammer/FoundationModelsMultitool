import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the log part of the `LibGit2` layer: the commits that a ref
/// reaches, newest first, with a limit and an optional path filter.
///
/// Each test makes its own repository with the history of
/// `GitTestHistory.makeThreeCommits()`, thus the tests are independent and
/// they run in parallel safely.
@Suite("LibGit2LogTests")
struct LibGit2LogTests {

    /// The ref of the newest commit.
    private static let headRevision = "HEAD"

    /// A limit that holds every commit of the history.
    private static let wholeHistoryLimit = 10

    /// The name that `TemporaryGitRepository` records on each commit.
    private static let commitAuthor = "Test"

    /// The largest time, in seconds, between a commit of a test and the check
    /// of its date.
    private static let commitDateTolerance: TimeInterval = 600

    /// The log of HEAD names each commit, newest first, with its author, its
    /// date, and the first line of its message.
    @Test("the log of HEAD gives each commit newest first")
    func theLogOfHeadGivesEachCommitNewestFirst() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let log = try #require(try Self.log(of: repository, limit: Self.wholeHistoryLimit))

        #expect(log.commits.map(\.sha) == shas.reversed())
        #expect(log.commits.map(\.subject) == ["third", "second", "first"])
        #expect(log.commits.allSatisfy { $0.author == Self.commitAuthor })
        #expect(log.commits.allSatisfy { abs($0.date.timeIntervalSinceNow) < Self.commitDateTolerance })
        #expect(!log.hasMore)
    }

    /// A limit below the length of the history gives the newest commits, and
    /// says that more commits stand behind them. A limit equal to the length
    /// says that no more commits stand behind them.
    @Test("a limit gives the newest commits and says when more stand behind them")
    func aLimitGivesTheNewestCommitsAndSaysWhenMoreStandBehindThem() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let short = try #require(try Self.log(of: repository, limit: 2))
        let exact = try #require(try Self.log(of: repository, limit: shas.count))

        #expect(short.commits.map(\.sha) == Array(shas.reversed().prefix(2)))
        #expect(short.hasMore)
        #expect(exact.commits.count == shas.count)
        #expect(!exact.hasMore)
    }

    /// A path keeps only the commits that change the file at that path.
    @Test("a file path keeps only the commits that change the file")
    func aFilePathKeepsOnlyTheCommitsThatChangeTheFile() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let log = try #require(try Self.log(of: repository, path: "a.txt", limit: Self.wholeHistoryLimit))

        #expect(log.commits.map(\.sha) == [shas[2], shas[0]])
    }

    /// A folder path keeps the commits that change a file below the folder.
    @Test("a folder path keeps the commits that change a file below it")
    func aFolderPathKeepsTheCommitsThatChangeAFileBelowIt() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let log = try #require(try Self.log(of: repository, path: "src", limit: Self.wholeHistoryLimit))

        #expect(log.commits.map(\.sha) == [shas[1]])
    }

    /// A branch name starts the log at the commit of that branch.
    @Test("a branch name starts the log at the commit of that branch")
    func aBranchNameStartsTheLogAtTheCommitOfThatBranch() throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let log = try #require(
            try Self.log(of: repository, revision: GitTestHistory.featureBranch, limit: Self.wholeHistoryLimit))

        #expect(log.commits.map(\.sha) == [shas[1], shas[0]])
    }

    /// The subject is the first line of the commit message, not the body.
    @Test("the subject is the first line of the message")
    func theSubjectIsTheFirstLineOfTheMessage() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("x\n", to: "a.txt")
        try repository.commit(message: "the subject\n\nthe body of the message\n")

        let log = try #require(try Self.log(of: repository, limit: Self.wholeHistoryLimit))

        #expect(log.commits.map(\.subject) == ["the subject"])
    }

    /// A ref that names no object gives no log, not a thrown error.
    @Test("a ref that names no object gives no log")
    func aRefThatNamesNoObjectGivesNoLog() throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let log = try Self.log(of: repository, revision: "no-such-ref", limit: Self.wholeHistoryLimit)

        #expect(log == nil)
    }

    // MARK: - Helpers

    /// Reads the log of `repository`.
    ///
    /// - Parameters:
    ///   - repository: The repository.
    ///   - revision: The ref to start at.
    ///   - path: The path that each commit must change, or `nil`.
    ///   - limit: The largest number of commits.
    /// - Returns: The log, or `nil` when the ref names no object.
    /// - Throws: ``LibGit2Error`` when the walk fails.
    private static func log(
        of repository: TemporaryGitRepository,
        revision: String = headRevision,
        path: String? = nil,
        limit: Int
    ) throws -> LibGit2Log? {
        try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .log(fromRevision: revision, touching: path, limit: limit)
    }
}
