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
// a mistake or a fact the model reads inside the turn, and a thrown error
// would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.show`: the file to show, and the ref to read it
/// at.
@Generable
struct ShowArguments {

    /// The path of the file to show.
    @Guide(description: "The path of the file to show, absolute or relative to the session root.")
    var path: String

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
        let corrective = { (message: String) in Self.corrective(message, path: arguments.path, ref: ref) }
        return context.blob(path: arguments.path, ref: ref).resolve(corrective: corrective) { blob in
            Self.cappedResult(of: blob, ref: ref)
        }
    }

    // MARK: Steps

    /// The result for a blob, with the text cut to ``lineCap`` lines.
    ///
    /// - Parameters:
    ///   - blob: The blob that the reader gave.
    ///   - ref: The ref of the call.
    /// - Returns: The result with its content and an honest `isCapped` flag.
    private static func cappedResult(of blob: GitBlob, ref: String) -> ShowResult {
        let lines = GitPatch.lines(of: blob.text)
        guard lines.count > lineCap else {
            return ShowResult(path: blob.path, ref: ref, content: blob.text, isCapped: false, correction: nil)
        }
        let content = lines.prefix(lineCap).map { line in line.text + (line.isTerminated ? lineTerminator : "") }
        return ShowResult(path: blob.path, ref: ref, content: content.joined(), isCapped: true, correction: nil)
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
        sha, or a form such as HEAD~1. Omit ref to read the file at HEAD; tools.files.read \
        reads the file in the work folder instead. A file that a later commit removed can be \
        read at an older ref. A result holds at most \(Show.lineCap) lines; when isCapped is \
        true, content holds only the first lines. An unknown ref, a path that the commit does \
        not hold, a folder, a binary file, a path outside the session root, and a root in no \
        git repository each come back as a correction rather than as an error — read it, \
        correct the call, and ask again.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Show(context:)`.
    let context: GitContext
}
