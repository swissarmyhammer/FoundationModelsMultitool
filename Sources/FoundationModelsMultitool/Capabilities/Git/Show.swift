// `Show` — the `tools.git.show` verb.
//
// git.md § "Verbs": `tools.git.show` takes `path` and `ref?`, and gives the
// content of the file at the ref. The source MCP tool has no such verb; the
// blob read is new. This verb reads through the shared reader of the
// capability (`GitBlobReader.swift`), which `tools.git.diff` reads through for
// `path@ref` too, and the reader calls only the `LibGit2` layer, never the C
// API (git.md § "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `show`
// and the surface path renders as `tools.git.show`.
//
// The content has a line cap, in the pattern of `tools.files.read`: a file
// longer than the cap gives its first lines, and `isCapped` says so. The cap
// counts lines in git's line model (`GitPatch.lines(of:)`), the same as
// `tools.git.blame`.
//
// A file the verb cannot show stays IN BAND, as a `correction` beside no
// content. It is never thrown: an unknown ref, an unknown path, a folder path,
// a binary file, a path outside the root, and a root in no repository are each
// a mistake or a fact the model reads inside the same answer. A thrown error
// would end the answer instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.show`: the file to show, and the ref to read it
/// at.
@Generable
struct ShowArguments {

    /// The path of the file to show, or `nil` for the whole commit.
    @Guide(
        description:
            "The path of the file to show, absolute or relative to the session root. "
            + "Omit it to show the whole commit: its message and its patch.")
    var path: String?

    /// The ref to read the file at, or `nil` for HEAD.
    @Guide(
        description:
            "The ref to read the file at: a branch, a tag, a sha, or a form such as HEAD~1. "
            + "Omit it to read the file at HEAD.")
    var ref: String?
}

/// The result of `tools.git.show`: the content of the file at the ref, or the
/// correction that says why there is none.
///
/// `correction` and the content are exclusive. A show that answers content
/// carries no correction, and a correction carries no content and no cap.
@Generable(description: "the content of the file at the ref, or the correction that says why there is none.")
struct ShowResult {

    /// The path of the file, relative to the session root.
    @Guide(description: "The path of the file, relative to the session root.")
    var path: String

    /// The ref that the verb read the file at.
    @Guide(description: "The ref that the file was read at.")
    var ref: String

    /// The text of the file at the ref, or `nil` with a correction.
    @Guide(description: "The text of the file at the ref; null when there is a correction.")
    var content: String?

    /// Whether the file had more lines than the cap, thus `content` holds only
    /// the first lines of the file.
    @Guide(description: "True when the file had more lines than the cap; content holds only the first lines.")
    var isCapped: Bool

    /// Why the show answered no content, or `nil` when the content stands.
    @Guide(description: "Why the show answered no content; null when the content stands.")
    var correction: String?
}

extension Show {

    // MARK: Bounds

    /// The largest number of lines in one result. A longer file gives its
    /// first `lineCap` lines and sets `isCapped`.
    static let lineCap = 1_000

    /// The text that ends a line in git's line model.
    private static let lineTerminator = "\n"

    /// The path of a result that shows the whole commit: the root.
    private static let wholeCommitPath = "."

    /// The description of a commit read that libgit2 could not make, before
    /// the `: ref` suffix.
    private static let failedShowDescription = "git show failed"

    // MARK: Execution

    /// Reads the file at the ref, or answers the correction that says why
    /// there is no content.
    ///
    /// Reads the file through the shared reader of the context, which checks
    /// the repository of the root, the path through the context's
    /// ``PathGuard``, the ref, the path in the commit of the ref, and the
    /// binary rule. Then it caps the text. Each recoverable failure comes back
    /// as the `correction` field of the result; nothing here throws.
    ///
    /// - Parameter arguments: The file and the ref.
    /// - Returns: The content of the file at the ref, or the correction.
    func call(arguments: ShowArguments) async throws -> ShowResult {
        let ref = arguments.ref ?? GitContext.defaultRef
        guard let path = arguments.path else { return commitResult(ref: ref) }
        let corrective = { (message: String) in Self.corrective(message, path: path, ref: ref) }
        return context.blob(path: path, ref: ref).resolve(corrective: corrective) { blob in
            Self.cappedResult(of: blob.text, path: blob.path, ref: ref)
        }
    }

    // MARK: Steps

    /// The whole commit of the ref, as `git show <ref>` prints it: the
    /// header, the message, and the patch of the files below the root.
    ///
    /// SWE-bench run bench24-1023b, django__django-14999: the model called
    /// `tools.git.show({ sha })` with no path, and wanted the commit.
    ///
    /// - Parameter ref: The ref of the call.
    /// - Returns: The text of the commit, or the correction.
    private func commitResult(ref: String) -> ShowResult {
        let corrective = { (message: String) in Self.corrective(message, path: Self.wholeCommitPath, ref: ref) }
        return context.repository.resolve(corrective: corrective) { location in
            let rootPath = location.repositoryPath(fromRootRelativePath: Self.wholeCommitPath)
            let limit = rootPath == Self.wholeCommitPath ? nil : rootPath
            return GitContext.read(at: ref, in: location, failedDescription: Self.failedShowDescription) {
                repository throws(LibGit2Error) in
                guard let detail = try repository.commitDetail(forRevision: ref),
                    let patch = try repository.commitPatch(forRevision: ref, limitedTo: limit)
                else { return nil }
                return Self.commitText(of: detail, patch: patch)
            }
            .resolve(corrective: corrective) { text in Self.cappedResult(of: text, path: Self.wholeCommitPath, ref: ref) }
        }
    }

    /// The text of a commit in the form of `git show`: the `commit`,
    /// `Author:`, and `Date:` lines, the message with each line indented by
    /// four spaces, and the patch.
    ///
    /// - Parameters:
    ///   - detail: The detail that the `LibGit2` layer gave.
    ///   - patch: The patch of the commit.
    /// - Returns: The text.
    private static func commitText(of detail: LibGit2CommitDetail, patch: String) -> String {
        let message = detail.message.split(separator: "\n", omittingEmptySubsequences: false)
            .reversed().drop(while: \.isEmpty).reversed()
            .map { line in line.isEmpty ? "" : "    " + line }
        let header = [
            "commit \(detail.facts.sha)", "Author: \(detail.facts.author)", "Date:   \(detail.facts.formattedDate)", "",
        ]
        return (header + message + [""]).joined(separator: lineTerminator) + lineTerminator + patch
    }

    /// The result for a text, cut to ``lineCap`` lines.
    ///
    /// - Parameters:
    ///   - text: The file, or the whole commit.
    ///   - path: The path of the result.
    ///   - ref: The ref of the call.
    /// - Returns: The result with its content and an honest `isCapped` flag.
    private static func cappedResult(of text: String, path: String, ref: String) -> ShowResult {
        let lines = GitPatch.lines(of: text)
        guard lines.count > lineCap else {
            return ShowResult(path: path, ref: ref, content: text, isCapped: false, correction: nil)
        }
        let content = lines.prefix(lineCap).map { line in line.text + (line.isTerminated ? lineTerminator : "") }
        return ShowResult(path: path, ref: ref, content: content.joined(), isCapped: true, correction: nil)
    }

    // MARK: Corrective results

    /// A result that carries only a correction: no content and no cap.
    ///
    /// - Parameters:
    ///   - message: The correction the model reads and acts on.
    ///   - path: The requested path.
    ///   - ref: The ref of the call.
    /// - Returns: The corrective ``ShowResult``.
    private static func corrective(_ message: String, path: String, ref: String) -> ShowResult {
        ShowResult(path: path, ref: ref, content: nil, isCapped: false, correction: message)
    }
}

/// Gives the content of a file at a ref.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const old = await tools.git.show({ path: "Sources/App/main.swift", ref: "HEAD~1" });
/// ```
///
/// The contract: the text of the file as the commit of the ref holds it, and
/// the path relative to the root. The ref is a branch, a tag, a sha, or a form
/// such as `HEAD~1`; with no ref, the verb reads HEAD. A file that a later
/// commit removed from the work folder is readable at an older ref. A result
/// holds at most ``lineCap`` lines, with an honest `isCapped` flag. The path is
/// bounded through the session's ``PathGuard``. An unknown ref, an unknown
/// path, a folder path, a binary file, a path outside the root, and a root in
/// no repository each come back as a `correction`, not as an error.
struct Show: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.show`.
    let name = "show"

    /// The usage instructions, as the model reads them.
    let description = """
        show gives the content of a file as a commit holds it: the file at a branch, a tag, a \
        sha, or a form such as HEAD~1. Omit ref to read the file at HEAD. Omit path to show the \
        whole commit, as git show prints it: the header, the message, and the patch of each \
        file, with path ".". To compare it with the \
        work folder, use tools.git.diff: a path with no ref reads the work folder. A file that \
        a later commit removed can be read at an older ref. A result holds at most \
        \(Show.lineCap) lines; when isCapped is true, content holds only the first lines. An \
        unknown ref, a path that the commit does not hold, a folder, a binary file, a path \
        outside the session root, and a root in no git repository each come back as a \
        correction rather than as an error — read it, correct the call, and ask again.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Show(context:)`.
    let context: GitContext
}
