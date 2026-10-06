// `Blame` — the `tools.git.blame` verb.
//
// git.md § "Verbs": `tools.git.blame` takes `path`, `startLine?`, and
// `endLine?`, and gives one row for each line. The source is `blame_lines` in
// `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`; the
// `LibGit2` layer (`LibGit2Blame.swift`) ports it, and this verb calls only
// that layer, never the C API (git.md § "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `blame`
// and the surface path renders as `tools.git.blame`.
//
// A blame the verb cannot make stays IN BAND, as a `correction` beside no
// line. It is never thrown: a bad line range, a path outside the root, a
// missing, unreadable, or binary file, a root in no repository, and a failed
// blame are each a mistake or a fact the model reads inside the turn, and a
// thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.blame`: the file to blame, and the lines to
/// blame.
@Generable
struct BlameArguments {

    /// The path of the file to blame.
    @Guide(description: "The path of the file to blame, absolute or relative to the session root.")
    var path: String

    /// The 1-based first line to blame, or `nil` for the first line.
    ///
    /// The guide carries ``lineRange``, thus a guided generator cannot write
    /// a value that the verb refuses.
    @Guide(
        description: "The 1-based first line to blame. Omit it to start at the first line.",
        .range(BlameArguments.lineRange))
    var startLine: Int?

    /// The 1-based last line to blame, included, or `nil` for the last line.
    ///
    /// The guide carries ``lineRange``, thus a guided generator cannot write
    /// a value that the verb refuses.
    @Guide(
        description: "The 1-based last line to blame; that line is included. Omit it to blame to the last line.",
        .range(BlameArguments.lineRange))
    var endLine: Int?
}

extension BlameArguments {

    /// The accepted `startLine` and `endLine` values: a 1-based line number
    /// up to the millionth line, the same bound as the `offset` of
    /// `tools.files.read`.
    ///
    /// The generation schema and the verb's own bound check read this one
    /// range, thus the two cannot disagree.
    static let lineRange = ReadArguments.offsetRange
}

/// One line of `tools.git.blame`: the line, its text, and the commit that
/// last changed it.
@Generable(description: "one line of the file and the commit that last changed it.")
struct BlameLine {

    /// The 1-based number of the line in the file.
    @Guide(description: "The 1-based number of the line in the file.")
    var line: Int

    /// The sha of the commit that last changed the line, or `nil` when no
    /// commit holds the line.
    @Guide(description: "The full sha of the commit that last changed the line; null when state is not committed.")
    var sha: String?

    /// The author of that commit, or `nil` when no commit holds the line.
    @Guide(description: "The author name of that commit; null when state is not committed.")
    var author: String?

    /// The author date of that commit in ISO 8601 (UTC), or `nil` when no
    /// commit holds the line.
    @Guide(description: "The author date of that commit in ISO 8601 (UTC); null when state is not committed.")
    var date: String?

    /// The text of the line, with no newline.
    @Guide(description: "The text of the line, with no newline.")
    var text: String

    /// Where the line comes from: a ``BlameLineState`` raw value.
    @Guide(
        description:
            "committed: a commit holds the line. uncommitted: the work folder changed the line, or git tracks "
            + "the file but no commit holds it yet. untracked: git does not track the file.")
    var state: String
}

/// The result of `tools.git.blame`: one row for each line of the range, or
/// the correction that says why there is none.
///
/// `correction` and the lines are exclusive. A blame that answers lines
/// carries no correction, and a correction carries no line and no cap.
@Generable(description: "one row for each line of the range, or the correction that says why there is none.")
struct BlameResult {

    /// The path of the file, relative to the session root.
    @Guide(description: "The path of the file, relative to the session root.")
    var path: String

    /// The rows, in line order.
    @Guide(description: "One row for each line of the range, in line order.")
    var lines: [BlameLine]

    /// Whether the range had more lines than the cap, thus `lines` holds only
    /// the first lines of the range.
    @Guide(
        description:
            "True when the range had more lines than the cap; ask again with startLine after the last line "
            + "to read the next lines.")
    var isCapped: Bool

    /// Why the blame answered no line, or `nil` when the lines stand.
    @Guide(description: "Why the blame answered no line; null when the lines stand.")
    var correction: String?
}

/// Where one line comes from, as the `state` field of a ``BlameLine`` writes
/// it.
enum BlameLineState: String {

    /// A commit holds the line.
    case committed

    /// No commit holds the line: the work folder changed it, or git tracks
    /// the file but no commit holds it yet.
    case uncommitted

    /// git does not track the file.
    case untracked
}

extension Blame {

    // MARK: Bounds

    /// The largest number of rows in one result. A longer range gives its
    /// first `lineCap` lines and sets `isCapped`.
    static let lineCap = 1_000

    /// The bound on `startLine`: a 1-based line number in
    /// ``BlameArguments/lineRange``.
    private static let startLineBound = BoundParameter(
        parameterName: "startLine",
        typeDescription: "1-based line number",
        range: BlameArguments.lineRange
    )

    /// The bound on `endLine`: a 1-based line number in
    /// ``BlameArguments/lineRange``.
    private static let endLineBound = BoundParameter(
        parameterName: "endLine",
        typeDescription: "1-based line number",
        range: BlameArguments.lineRange
    )

    // MARK: Corrective text

    /// The description of a non-UTF-8 (binary) file, before the `: path`
    /// suffix.
    private static let binaryDescription =
        "The file is not valid UTF-8 text and appears to be binary, so it cannot be blamed"

    /// The description of a blame that libgit2 could not make, before the
    /// `: path` suffix.
    private static let failedBlameDescription = "git blame failed"

    // MARK: Execution

    /// Blames the lines of the file, or answers the correction that says why
    /// there is none.
    ///
    /// Checks the line bounds and the order of `startLine` and `endLine`,
    /// then the repository of the root, then the path through the context's
    /// ``PathGuard``, then reads and UTF-8-decodes the file, checks the range
    /// against its line count, and blames it through the `LibGit2` layer.
    /// Each recoverable failure comes back as the `correction` field of the
    /// result; nothing here throws.
    ///
    /// - Parameter arguments: The file and the line range.
    /// - Returns: One row for each line of the range, or the correction.
    func call(arguments: BlameArguments) async throws -> BlameResult {
        let corrective = { (message: String) in Self.corrective(message, path: arguments.path) }
        if let message = Self.rangeViolation(arguments) { return corrective(message) }
        return context.repository.resolve(corrective: corrective) { location in
            context.pathGuard.validate(arguments.path, for: .read).resolve(corrective: corrective) { url in
                PathCorrective.readData(at: url, path: arguments.path).resolve(corrective: corrective) { data in
                    Self.blame(data, at: url, in: location, arguments: arguments)
                        .resolve(corrective: corrective) { $0 }
                }
            }
        }
    }

    // MARK: Steps

    /// Blames the file bytes that the path guard let through.
    ///
    /// - Parameters:
    ///   - data: The bytes of the file.
    ///   - url: The URL that the path guard gave.
    ///   - location: The repository of the root.
    ///   - arguments: The arguments of the call.
    /// - Returns: The result with its rows, or the correction for a binary
    ///   file, a file outside the work folder, a range past the end, or a
    ///   failed blame.
    private static func blame(
        _ data: Data,
        at url: URL,
        in location: GitRepositoryLocation,
        arguments: BlameArguments
    ) -> Result<BlameResult, CorrectiveRejection> {
        guard let text = String(data: data, encoding: .utf8) else {
            return pathFailure(binaryDescription, path: arguments.path)
        }
        guard let repositoryPath = location.repositoryPath(ofFile: url) else {
            return pathFailure(GitContext.outsideWorkFolderDescription, path: arguments.path)
        }
        let lines = GitPatch.lines(of: text).map(\.text)
        return window(of: arguments, lineCount: lines.count).flatMap { window in
            let attributions: [LibGit2LineBlame]
            do {
                attributions = try LibGit2Repository(discoveringFrom: location.workDirectory)
                    .blameLines(atPath: repositoryPath, content: data, lineCount: lines.count)
            } catch {
                return pathFailure(failedBlameDescription, path: "\(arguments.path) (\(error))")
            }
            let rows = window.prefix(lineCap).map { index in
                row(number: index + 1, text: lines[index], attribution: attributions[index])
            }
            return .success(
                BlameResult(
                    path: location.rootRelativePath(fromRepositoryPath: repositoryPath) ?? arguments.path,
                    lines: rows, isCapped: window.count > lineCap, correction: nil))
        }
    }

    /// The correction for a line bound out of range, or for a `startLine`
    /// after the `endLine`.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The correction, or `nil` when the range is acceptable
    ///   before the file is read.
    private static func rangeViolation(_ arguments: BlameArguments) -> String? {
        if let message = startLineBound.violation(arguments.startLine) { return message }
        if let message = endLineBound.violation(arguments.endLine) { return message }
        guard let startLine = arguments.startLine, let endLine = arguments.endLine, startLine > endLine else {
            return nil
        }
        return "The `startLine` parameter (\(startLine)) is after the `endLine` parameter (\(endLine)). "
            + "Give a startLine that is not after the endLine."
    }

    /// The 0-based indices of the lines that the range selects.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - lineCount: The number of lines in the file.
    /// - Returns: The indices, or the correction for a `startLine` or an
    ///   `endLine` past the last line.
    private static func window(
        of arguments: BlameArguments,
        lineCount: Int
    ) -> Result<Range<Int>, CorrectiveRejection> {
        for (name, value) in [("startLine", arguments.startLine), ("endLine", arguments.endLine)] {
            if let value, value > lineCount {
                return .failure(
                    CorrectiveRejection(
                        correctiveMessage:
                            "The `\(name)` parameter (\(value)) is past the end of \(arguments.path), "
                            + "which has \(lineCount) lines."))
            }
        }
        return .success(((arguments.startLine ?? 1) - 1)..<(arguments.endLine ?? lineCount))
    }

    /// The row of one line.
    ///
    /// - Parameters:
    ///   - number: The 1-based number of the line.
    ///   - text: The text of the line.
    ///   - attribution: Where the line comes from.
    /// - Returns: The row.
    private static func row(number: Int, text: String, attribution: LibGit2LineBlame) -> BlameLine {
        let (state, commit) = stateAndCommit(of: attribution)
        return BlameLine(
            line: number, sha: commit?.sha, author: commit?.author, date: commit?.formattedDate,
            text: text, state: state.rawValue)
    }

    /// The state of a line, and the commit that holds it.
    ///
    /// - Parameter attribution: Where the line comes from.
    /// - Returns: The state, and the commit, or `nil` when no commit holds the
    ///   line.
    private static func stateAndCommit(
        of attribution: LibGit2LineBlame
    ) -> (state: BlameLineState, commit: LibGit2Commit?) {
        switch attribution {
        case .committed(let commit): (.committed, commit)
        case .uncommitted: (.uncommitted, nil)
        case .untracked: (.untracked, nil)
        }
    }

    // MARK: Corrective results

    /// A failure in the `<description>: <path>` shape of the files
    /// capability.
    ///
    /// - Parameters:
    ///   - description: What went wrong.
    ///   - path: The requested path.
    /// - Returns: The failure.
    private static func pathFailure(_ description: String, path: String) -> Result<BlameResult, CorrectiveRejection> {
        .failure(
            CorrectiveRejection(
                correctiveMessage: PathCorrective.pathErrorMessage(description: description, path: path)))
    }

    /// A result that carries only a correction: no line and no cap.
    ///
    /// - Parameters:
    ///   - message: The correction the model reads and acts on.
    ///   - path: The requested path.
    /// - Returns: The corrective ``BlameResult``.
    private static func corrective(_ message: String, path: String) -> BlameResult {
        BlameResult(path: path, lines: [], isCapped: false, correction: message)
    }
}

/// Gives the commit that last changed each line of a file.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const rows = await tools.git.blame({ path: "Sources/App/main.swift", startLine: 40, endLine: 60 });
/// ```
///
/// The contract: one row for each line of the range, with the line number,
/// the text, and a `state`. A `committed` row names the sha, the author, and
/// the author date of the commit that last changed the line. A line that the
/// work folder changed, and each line of a staged file that no commit holds,
/// is `uncommitted`. Each line of a file that git does not track is
/// `untracked`. A result holds at most ``lineCap`` rows, with an honest
/// `isCapped` flag. The path is bounded through the session's ``PathGuard``. A
/// bad range, a path outside the root, a missing or binary file, a root in no
/// repository, and a failed blame each come back as a `correction`, not as an
/// error.
struct Blame: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.blame`.
    let name = "blame"

    /// The usage instructions, as the model reads them.
    let description = """
        blame tells which commit last changed each line of a file, and who made it and when. \
        It gives one row for each line from startLine to endLine (1-based, both included); omit \
        them to blame the whole file. Each row has the line number, the text, and a state: \
        committed rows name the sha, the author, and the date; uncommitted rows are lines that \
        no commit holds yet; untracked rows are lines of a file that git does not track. A result \
        holds at most \(Blame.lineCap) rows; when isCapped is true, ask again with startLine after the last \
        row. A bad range, a path outside the session root, a missing or binary file, and a root \
        in no git repository each come back as a correction rather than as an error — read it, \
        correct the call, and ask again.
        """

    /// The session context this verb blames against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Blame(context:)`.
    let context: GitContext
}
