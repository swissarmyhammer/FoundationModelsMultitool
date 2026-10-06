// `GitLogTests` — the behavioral suite of the `tools.git.log` verb.
//
// The suite makes `LogArguments` with the memberwise initializer and calls the
// `Log` verb directly, the way `GitBlameTests` calls its verb. Each test makes
// its own temporary repository, thus the tests are independent and they run in
// parallel safely.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.log` verb (task `^w0yeya3`).
///
/// The card names each case: no arguments, `limit`, `path`, a branch, and an
/// unknown ref. The default limit, a limit out of range, a path in a root in
/// a subfolder, a path outside the root, and a root in no repository are here
/// too. Most tests read the history of `GitTestHistory.makeThreeCommits()`.
/// Task `^5a8vaqk` adds a path in a folder that a later commit removed, and
/// such a path outside the root.
@Suite("GitLogTests")
struct GitLogTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitLogTests"

    /// The name that `TemporaryGitRepository` records on each commit.
    private static let commitAuthor = "Test"

    /// The number of hex characters in a short sha.
    private static let shortShaLength = 7

    // MARK: - Commits

    /// With no argument, the log gives each commit of HEAD, newest first, with
    /// the sha, the short sha, the author, the ISO 8601 date, and the subject.
    @Test("log with no argument gives each commit of HEAD newest first")
    func logWithNoArgumentGivesEachCommitOfHeadNewestFirst() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.log(in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(!result.isCapped)
        #expect(result.commits.map(\.sha) == shas.reversed())
        #expect(result.commits.map(\.shortSha) == shas.reversed().map { String($0.prefix(Self.shortShaLength)) })
        #expect(result.commits.map(\.subject) == ["third", "second", "first"])
        #expect(result.commits.allSatisfy { $0.author == Self.commitAuthor })
        let date = try #require(result.commits.first?.date)
        #expect((try? Date.ISO8601FormatStyle().parse(date)) != nil, "date was: \(date)")
    }

    /// A limit below the length of the history gives the newest commits, and
    /// `isCapped` says that more commits stand behind them.
    @Test("a limit gives the newest commits and says that the cap cut the log")
    func aLimitGivesTheNewestCommitsAndSaysThatTheCapCutTheLog() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.log(in: GitContext(root: repository.workDirectory), limit: 2)

        #expect(result.correction == nil)
        #expect(result.isCapped)
        #expect(result.commits.map(\.sha) == Array(shas.reversed().prefix(2)))
    }

    /// With no limit, the log gives at most ``Log/defaultLimit`` commits.
    @Test("with no limit the log gives at most the default limit")
    func withNoLimitTheLogGivesAtMostTheDefaultLimit() async throws {
        let repository = try TemporaryGitRepository()
        for number in 0...Log.defaultLimit {
            try repository.write("\(number)\n", to: "a.txt")
            try repository.commit(message: "commit \(number)")
        }

        let result = try await Self.log(in: GitContext(root: repository.workDirectory))

        #expect(result.isCapped)
        #expect(result.commits.count == Log.defaultLimit)
    }

    /// A path keeps only the commits that change that path.
    @Test("a path keeps only the commits that change it")
    func aPathKeepsOnlyTheCommitsThatChangeIt() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.log(in: GitContext(root: repository.workDirectory), path: "a.txt")

        #expect(result.correction == nil)
        #expect(result.commits.map(\.sha) == [shas[2], shas[0]])
    }

    /// A path whose folder a later commit removed keeps the commits that
    /// change it, the removal too. The absent folder is not a correction,
    /// for the file and for the folder itself.
    @Test("a path whose folder a later commit removed keeps the commits that change it")
    func aPathWhoseFolderALaterCommitRemovedKeepsTheCommitsThatChangeIt() async throws {
        let (repository, shas) = try GitTestHistory.makeRemovedFolder(firstText: "1\n", secondText: "2\n")
        let context = GitContext(root: repository.workDirectory)

        for path in [GitTestHistory.removedFolderFile, GitTestHistory.removedFolder] {
            let result = try await Self.log(in: context, path: path)

            #expect(result.correction == nil, "path: \(path)")
            #expect(result.commits.map(\.sha) == shas.reversed(), "path: \(path)")
        }
    }

    /// A path in a root in a subfolder is relative to that root.
    @Test("a path in a root in a subfolder is relative to that root")
    func aPathInARootInASubfolderIsRelativeToThatRoot() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()
        let root = repository.workDirectory.appendingPathComponent("src", isDirectory: true)

        let result = try await Self.log(in: GitContext(root: root), path: "b.txt")

        #expect(result.correction == nil)
        #expect(result.commits.map(\.sha) == [shas[1]])
    }

    /// A branch name starts the log at the commit of that branch.
    @Test("a branch name starts the log at that branch")
    func aBranchNameStartsTheLogAtThatBranch() async throws {
        let (repository, shas) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.log(
            in: GitContext(root: repository.workDirectory), ref: GitTestHistory.featureBranch)

        #expect(result.correction == nil)
        #expect(result.commits.map(\.sha) == [shas[1], shas[0]])
    }

    // MARK: - Corrections

    /// A ref that names no commit is a correction that names the ref.
    @Test("an unknown ref is a correction")
    func anUnknownRefIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()

        let result = try await Self.log(in: GitContext(root: repository.workDirectory), ref: "no-such-ref")

        try Self.expectCorrection(result, contains: "no-such-ref")
    }

    /// A limit out of its range is a correction that names the range.
    @Test("a limit out of range is a correction")
    func aLimitOutOfRangeIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        let context = GitContext(root: repository.workDirectory)

        let belowRange = try await Self.log(in: context, limit: LogArguments.limitRange.lowerBound - 1)
        let aboveRange = try await Self.log(in: context, limit: LogArguments.limitRange.upperBound + 1)

        try Self.expectCorrection(belowRange, contains: "limit")
        try Self.expectCorrection(aboveRange, contains: "\(LogArguments.limitRange.upperBound)")
    }

    /// A path outside the root goes through the path guard of the context,
    /// and the refusal of the guard comes back as the correction.
    @Test("a path outside the root is a correction")
    func aPathOutsideTheRootIsACorrection() async throws {
        let (repository, _) = try GitTestHistory.makeThreeCommits()
        let context = GitContext(root: repository.workDirectory.appendingPathComponent("src", isDirectory: true))
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        for path in ["../a.txt", outside.path] {
            let result = try await Self.log(in: context, path: path)

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
        let (repository, _) = try GitTestHistory.makeRemovedFolder(firstText: "1\n", secondText: "2\n")
        let context = GitContext(
            root: repository.workDirectory.appendingPathComponent(GitTestHistory.keptFolder, isDirectory: true))
        let removedFile = repository.workDirectory.appendingPathComponent(
            GitTestHistory.removedFolderFile, isDirectory: false)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outsideFile = outside.appendingPathComponent("gone/x.txt", isDirectory: false)

        for path in [removedFile.path, outsideFile.path] {
            let result = try await Self.log(in: context, path: path)

            let refusal = try #require(throws: PathViolation.self) {
                try context.pathGuard.validatePath(path, absentFolders: .accepted).get()
            }
            #expect(refusal.message.contains("outside workspace"))
            try Self.expectCorrection(result, contains: refusal.message)
        }
    }

    /// A root in no repository is a correction.
    @Test("a root in no repository is a correction")
    func aRootInNoRepositoryIsACorrection() async throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let result = try await Self.log(in: GitContext(root: outside))

        try Self.expectCorrection(result, contains: "not in a git repository")
    }

    // MARK: - Helpers

    /// Calls the `tools.git.log` verb over a context.
    ///
    /// - Parameters:
    ///   - context: The context of the verb.
    ///   - ref: The ref, or `nil` for the default.
    ///   - path: The path, or `nil` for each commit.
    ///   - limit: The limit, or `nil` for the default.
    /// - Returns: The result of the verb.
    private static func log(
        in context: GitContext,
        ref: String? = nil,
        path: String? = nil,
        limit: Int? = nil
    ) async throws -> LogResult {
        try await Log(context: context).call(arguments: LogArguments(ref: ref, path: path, limit: limit))
    }

    /// Expects that `result` is a correction that holds `fragment`, with no
    /// commit and no cap.
    ///
    /// - Parameters:
    ///   - result: The result of the verb.
    ///   - fragment: Text that the correction must hold.
    /// - Throws: When the result has no correction.
    private static func expectCorrection(_ result: LogResult, contains fragment: String) throws {
        let correction = try #require(result.correction)
        #expect(correction.contains(fragment), "correction was: \(correction)")
        #expect(result.commits.isEmpty)
        #expect(!result.isCapped)
    }
}
