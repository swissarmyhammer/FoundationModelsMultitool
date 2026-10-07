// `Commit` — the `tools.git.commit` verb.
//
// git.md § "Verbs": `tools.git.commit` takes `ref?`, and gives the facts of
// one commit: the author, the date, the full message, the parents, and the
// changed files with their line counts. It is the same as the `git_show` tool
// of docker-agent. The `LibGit2` layer (`LibGit2CommitDetail.swift`) reads the
// commit, and this verb calls only that layer, never the C API (git.md §
// "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `commit`
// and the surface path renders as `tools.git.commit`.
//
// Each path is relative to the root, and a file outside the root is not in
// the list (git.md § "Decisions", item 8), the same as in `tools.git.status`.
// A rename from outside the root is a new file below the root, and a rename
// from the root to a path outside the root is a removal of the old path. The
// list has a cap, and `isCapped` says that the cap cut it.
//
// A commit the verb cannot read stays IN BAND, as a `correction` beside no
// commit. It is never thrown: an unknown ref, a ref that names no commit, a
// root in no repository, and a failed read are each a mistake or a fact the
// model reads inside the turn, and a thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.commit`: the ref of the commit to show.
@Generable
struct CommitArguments {

    /// The ref of the commit, or `nil` for HEAD.
    @Guide(
        description:
            "The ref of the commit to show: a branch, a tag, a sha, or a form such as HEAD~1. "
            + "Omit it to show HEAD.")
    var ref: String?
}

/// One file that the commit of `tools.git.commit` changes.
@Generable(description: "one file that the commit changes, with its line counts.")
struct CommitFile {

    /// The path of the file after the commit, relative to the session root.
    @Guide(
        description:
            "The path of the file after the commit, relative to the session root. For a deleted file, "
            + "the path before the commit.")
    var path: String

    /// The path of the file before the commit, only for a rename.
    @Guide(description: "The path before the commit, relative to the session root; null when the file is not renamed.")
    var oldPath: String?

    /// The change: added, modified, deleted, or renamed.
    @Guide(description: "The change: added, modified, deleted, or renamed.")
    var status: String

    /// The number of lines that the commit adds, or `nil` for a binary file.
    @Guide(description: "The number of lines that the commit adds to the file; null for a binary file.")
    var additions: Int?

    /// The number of lines that the commit removes, or `nil` for a binary
    /// file.
    @Guide(description: "The number of lines that the commit removes from the file; null for a binary file.")
    var deletions: Int?
}

/// The result of `tools.git.commit`: the facts of one commit, or the
/// correction that says why there is none.
///
/// `correction` and the facts are exclusive. A result that answers a commit
/// carries no correction, and a correction carries empty facts, no parent, no
/// file, and no cap.
@Generable(description: "the facts of one commit, or the correction that says why there is none.")
struct CommitResult {

    /// The full sha of the commit.
    @Guide(description: "The full sha of the commit; empty when there is a correction.")
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

    /// The full message of the commit: the subject, and the body after it.
    @Guide(description: "The full message of the commit: the subject, and the body after it.")
    var message: String

    /// The full sha of each parent, the first parent first.
    @Guide(description: "The full sha of each parent, the first parent first; empty for the first commit.")
    var parents: [String]

    /// The files below the root that the commit changes against its first
    /// parent.
    @Guide(description: "The files below the session root that the commit changes against its first parent.")
    var files: [CommitFile]

    /// Whether the commit changes more files than the cap, thus `files` holds
    /// only the first files.
    @Guide(description: "True when the commit changes more files than the cap; files holds only the first files.")
    var isCapped: Bool

    /// Why the verb answered no commit, or `nil` when the commit stands.
    @Guide(description: "Why the verb answered no commit; null when the commit stands.")
    var correction: String?
}

extension Commit {

    // MARK: Bounds

    /// The largest number of files in one result. A commit that changes more
    /// files gives its first `fileCap` files and sets `isCapped`.
    static let fileCap = 200

    // MARK: Corrective text

    /// The description of a read that libgit2 could not make, before the
    /// `: ref` suffix.
    private static let failedCommitDescription = "git commit failed"

    // MARK: Execution

    /// Reads the commit of the ref, or answers the correction that says why
    /// there is none.
    ///
    /// Checks the repository of the root, then reads the commit through the
    /// `LibGit2` layer, and keeps the files below the root. Each recoverable
    /// failure comes back as the `correction` field of the result; nothing
    /// here throws.
    ///
    /// - Parameter arguments: The ref.
    /// - Returns: The facts of the commit, or the correction.
    func call(arguments: CommitArguments) async throws -> CommitResult {
        let ref = arguments.ref ?? GitContext.defaultRef
        return context.repository.resolve(corrective: Self.corrective) { location in
            GitContext.read(at: ref, in: location, failedDescription: Self.failedCommitDescription) {
                repository throws(LibGit2Error) in
                try repository.commitDetail(forRevision: ref)
            }
            .resolve(corrective: Self.corrective) { detail in Self.result(of: detail, in: location) }
        }
    }

    // MARK: Steps

    /// The result of a commit detail, with the files below the root and the
    /// cap.
    ///
    /// - Parameters:
    ///   - detail: The detail that the `LibGit2` layer gave.
    ///   - location: The repository of the root.
    /// - Returns: The result with its facts and an honest `isCapped` flag.
    private static func result(of detail: LibGit2CommitDetail, in location: GitRepositoryLocation) -> CommitResult {
        let files = detail.files.compactMap { stat in file(of: stat, in: location) }
        return CommitResult(
            sha: detail.facts.sha, shortSha: detail.facts.shortSha, author: detail.facts.author,
            date: detail.facts.formattedDate, message: detail.message, parents: detail.parentShas,
            files: Array(files.prefix(fileCap)), isCapped: files.count > fileCap, correction: nil)
    }

    /// The file of one changed file, as the root sees it.
    ///
    /// A file below the root keeps its status, with each path relative to the
    /// root. A rename from outside the root is added: the root did not hold
    /// the old path. A rename from the root to a path outside the root is
    /// deleted at its old path: the root does not hold the new path. The line
    /// counts are the counts of the commit for that file.
    ///
    /// - Parameters:
    ///   - stat: The file that the `LibGit2` layer gave.
    ///   - location: The repository of the root.
    /// - Returns: The file, or `nil` when no path of it is below the root.
    private static func file(of stat: LibGit2FileStat, in location: GitRepositoryLocation) -> CommitFile? {
        let oldPath = stat.oldPath.flatMap(location.rootRelativePath(fromRepositoryPath:))
        guard let path = location.rootRelativePath(fromRepositoryPath: stat.path) else {
            return oldPath.map { oldPath in
                file(of: stat, path: oldPath, oldPath: nil, status: LibGit2FileStat.deletedStatus)
            }
        }
        let isRenameIntoTheRoot = stat.oldPath != nil && oldPath == nil
        let status = isRenameIntoTheRoot ? LibGit2FileStat.addedStatus : stat.status
        return file(of: stat, path: path, oldPath: oldPath, status: status)
    }

    /// The file of one changed file, with its paths and its status as the
    /// root sees them, and its line counts.
    ///
    /// - Parameters:
    ///   - stat: The file that the `LibGit2` layer gave.
    ///   - path: The path relative to the root.
    ///   - oldPath: The old path relative to the root, or `nil`.
    ///   - status: The status as the root sees it.
    /// - Returns: The file.
    private static func file(
        of stat: LibGit2FileStat,
        path: String,
        oldPath: String?,
        status: String
    ) -> CommitFile {
        CommitFile(
            path: path, oldPath: oldPath, status: status, additions: stat.additions, deletions: stat.deletions)
    }

    // MARK: Corrective results

    /// A result that carries only a correction: empty facts, no parent, no
    /// file, and no cap.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``CommitResult``.
    private static func corrective(_ message: String) -> CommitResult {
        CommitResult(
            sha: "", shortSha: "", author: "", date: "", message: "", parents: [], files: [], isCapped: false,
            correction: message)
    }
}

/// Gives the facts of one commit: the author, the date, the full message, the
/// parents, and the changed files with their line counts.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const commit = await tools.git.commit({ ref: "HEAD~1" });
/// ```
///
/// The contract: the sha, the short sha, the author, the author date in ISO
/// 8601, the full message, the sha of each parent, and the files that the
/// commit changes against its first parent, each with its status and its line
/// counts. The ref is a branch, a tag, a sha, or a form such as `HEAD~1`; with
/// no ref, the verb reads HEAD. Each path is relative to the root, and a file
/// outside the root is not in the list. A result holds at most ``fileCap``
/// files, with an honest `isCapped` flag. The verb only reads. An unknown ref,
/// a ref that names no commit, a root in no repository, and a failed read each
/// come back as a `correction`, not as an error.
struct Commit: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.commit`.
    let name = "commit"

    /// The usage instructions, as the model reads them.
    let description = """
        commit only reads: it shows one commit and changes nothing. It gives the sha, the short \
        sha, the author, the date, the full message, the sha of each parent, and the files that \
        the commit changes against its first parent, each with its status (added, modified, \
        deleted, or renamed) and the number of lines it adds and removes (null for a binary \
        file). ref is a branch, a tag, a sha, or a form such as HEAD~1; omit it to show HEAD. \
        Each path is relative to the session root, and a file outside the session root is not \
        in the list. A result holds at most \(Commit.fileCap) files; when isCapped is true, files \
        holds only the first files. An unknown ref, a ref that names no commit, and a root in \
        no git repository each come back as a correction rather than as an error — read it, \
        correct the call, and ask again.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Commit(context:)`.
    let context: GitContext
}
