// `Log` — the `tools.git.log` verb.
//
// git.md § "Verbs": `tools.git.log` takes `ref?`, `path?`, and `limit?`, and
// gives the commits with sha, author, date, and subject. The source MCP tool
// has no log; the revwalk is new. The `LibGit2` layer (`LibGit2Log.swift`)
// walks the commits, and this verb calls only that layer, never the C API
// (git.md § "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `log` and
// the surface path renders as `tools.git.log`.
//
// The limit is the cap of the result: at most `limit` commits, and `isCapped`
// says that more commits stand behind them. The path goes through the
// `PathGuard` of the context, the same as the path of `tools.git.show`.
//
// A log the verb cannot make stays IN BAND, as a `correction` beside no
// commit. It is never thrown: a limit out of range, an unknown ref, a path
// outside the root, a root in no repository, and a failed walk are each a
// mistake or a fact the model reads inside the turn, and a thrown error would
// end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.log`: where the log starts, the path that each
/// commit must change, and the largest number of commits.
@Generable
struct LogArguments {

    /// The ref to start the log at, or `nil` for HEAD.
    @Guide(
        description:
            "The ref to start the log at: a branch, a tag, a sha, or a form such as HEAD~1. "
            + "Omit it to start at HEAD.")
    var ref: String?

    /// The path that each commit must change, or `nil` for each commit.
    @Guide(
        description:
            "Give only the commits that change this file or a file below this folder, absolute or "
            + "relative to the session root. Omit it to give each commit.")
    var path: String?

    /// The largest number of commits, or `nil` for ``Log/defaultLimit``.
    ///
    /// The guide carries ``limitRange``, thus a guided generator cannot write
    /// a value that the verb refuses.
    @Guide(
        description: "The largest number of commits to give, newest first. Omit it to give the default number.",
        .range(LogArguments.limitRange))
    var limit: Int?
}

extension LogArguments {

    /// The accepted `limit` values: one commit up to 200 commits.
    ///
    /// The generation schema and the verb's own bound check read this one
    /// range, thus the two cannot disagree.
    static let limitRange = 1...200
}

/// One commit of `tools.git.log`.
@Generable(description: "one commit of the log.")
struct LogCommit {

    /// The full sha of the commit.
    @Guide(description: "The full sha of the commit.")
    var sha: String

    /// The first characters of the sha.
    @Guide(description: "The short form of the sha: its first characters.")
    var shortSha: String

    /// The author of the commit.
    @Guide(description: "The author name of the commit.")
    var author: String

    /// The author date of the commit in ISO 8601 (UTC).
    @Guide(description: "The author date of the commit in ISO 8601 (UTC).")
    var date: String

    /// The subject of the commit: the first line of its message.
    @Guide(description: "The subject of the commit: the first line of its message.")
    var subject: String
}

/// The result of `tools.git.log`: the commits, newest first, or the
/// correction that says why there is none.
///
/// `correction` and the commits are exclusive. A log that answers commits
/// carries no correction, and a correction carries no commit and no cap.
@Generable(description: "the commits, newest first, or the correction that says why there is none.")
struct LogResult {

    /// The commits, newest first.
    @Guide(description: "The commits, newest first.")
    var commits: [LogCommit]

    /// Whether more commits stand behind the last one, thus the limit cut the
    /// log.
    @Guide(
        description:
            "True when more commits stand behind the last one; ask again with a larger limit, or with the "
            + "sha of the last commit as ref, to read more.")
    var isCapped: Bool

    /// Why the log answered no commit, or `nil` when the commits stand.
    @Guide(description: "Why the log answered no commit; null when the commits stand.")
    var correction: String?
}

extension Log {

    // MARK: Bounds

    /// The number of commits when the call names no limit.
    static let defaultLimit = 20

    /// The bound on `limit`: a commit count in ``LogArguments/limitRange``.
    private static let limitBound = BoundParameter(
        parameterName: "limit",
        typeDescription: "commit count",
        range: LogArguments.limitRange
    )

    // MARK: Corrective text

    /// The description of a walk that libgit2 could not make, before the
    /// `: ref` suffix.
    private static let failedLogDescription = "git log failed"

    // MARK: Execution

    /// Walks the commits of the ref, or answers the correction that says why
    /// there is none.
    ///
    /// Checks the limit bound, then the repository of the root, then the path
    /// through the context's ``PathGuard``, and walks the commits through the
    /// `LibGit2` layer. Each recoverable failure comes back as the
    /// `correction` field of the result; nothing here throws.
    ///
    /// - Parameter arguments: The ref, the path, and the limit.
    /// - Returns: The commits, newest first, or the correction.
    func call(arguments: LogArguments) async throws -> LogResult {
        if let message = Self.limitBound.violation(arguments.limit) { return Self.corrective(message) }
        let ref = arguments.ref ?? GitContext.defaultRef
        let limit = arguments.limit ?? Self.defaultLimit
        return context.repository.resolve(corrective: Self.corrective) { location in
            repositoryPath(of: arguments.path, in: location).resolve(corrective: Self.corrective) { path in
                Self.log(from: ref, touching: path, limit: limit, in: location)
                    .resolve(corrective: Self.corrective) { $0 }
            }
        }
    }

    // MARK: Steps

    /// Sends the optional path argument through the path guard.
    ///
    /// - Parameters:
    ///   - path: The path argument, or `nil`.
    ///   - location: The repository of the root.
    /// - Returns: The repository path, `nil` for no path argument, or the
    ///   correction for a path that the guard refuses.
    private func repositoryPath(
        of path: String?,
        in location: GitRepositoryLocation
    ) -> Result<String?, CorrectiveRejection> {
        guard let path else { return .success(nil) }
        return context.repositoryPath(of: path, in: location).map { $0 }
    }

    /// Walks the commits through the `LibGit2` layer.
    ///
    /// - Parameters:
    ///   - ref: The ref to start at.
    ///   - path: The repository path that each commit must change, or `nil`.
    ///   - limit: The largest number of commits.
    ///   - location: The repository of the root.
    /// - Returns: The result with its commits, or the correction for an
    ///   unknown ref or a failed walk.
    private static func log(
        from ref: String,
        touching path: String?,
        limit: Int,
        in location: GitRepositoryLocation
    ) -> Result<LogResult, CorrectiveRejection> {
        GitContext.read(at: ref, in: location, failedDescription: failedLogDescription) {
            repository throws(LibGit2Error) in
            try repository.log(fromRevision: ref, touching: path, limit: limit)
        }
        .map { log in LogResult(commits: log.commits.map(row), isCapped: log.hasMore, correction: nil) }
    }

    /// The row of one commit.
    ///
    /// - Parameter commit: The facts of the commit.
    /// - Returns: The row.
    private static func row(_ commit: LibGit2Commit) -> LogCommit {
        LogCommit(
            sha: commit.sha, shortSha: commit.shortSha, author: commit.author,
            date: commit.formattedDate, subject: commit.subject)
    }

    // MARK: Corrective results

    /// A result that carries only a correction: no commit and no cap.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``LogResult``.
    private static func corrective(_ message: String) -> LogResult {
        LogResult(commits: [], isCapped: false, correction: message)
    }
}

/// Gives the commits that a ref reaches, newest first.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const history = await tools.git.log({ path: "Sources/App/main.swift", limit: 5 });
/// ```
///
/// The contract: at most `limit` commits (``defaultLimit`` when the call names
/// none), newest first, each with the sha, the short sha, the author, the
/// author date in ISO 8601, and the subject. The ref is a branch, a tag, a
/// sha, or a form such as `HEAD~1`; with no ref, the log starts at HEAD. A
/// path keeps only the commits that change the file at the path, or a file
/// below the folder at the path. `isCapped` says that more commits stand
/// behind the last one. The path is bounded through the session's
/// ``PathGuard``. A limit out of range, an unknown ref, a path outside the
/// root, a root in no repository, and a failed walk each come back as a
/// `correction`, not as an error.
struct Log: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.log`.
    let name = "log"

    /// The usage instructions, as the model reads them.
    let description = """
        log gives the commits that a ref reaches, newest first: each with the sha, the short \
        sha, the author, the date, and the subject. ref is a branch, a tag, a sha, or a form \
        such as HEAD~1; omit it to start at HEAD. path keeps only the commits that change that \
        file or a file below that folder. limit is the largest number of commits \
        (\(LogArguments.limitRange.lowerBound) to \(LogArguments.limitRange.upperBound), \
        \(Log.defaultLimit) when omitted); when isCapped is true, more commits stand behind the \
        last one. A limit out of range, an unknown ref, a path outside the session root, and a \
        root in no git repository each come back as a correction rather than as an error — read \
        it, correct the call, and ask again.
        """

    /// The session context this verb walks against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Log(context:)`.
    let context: GitContext
}
