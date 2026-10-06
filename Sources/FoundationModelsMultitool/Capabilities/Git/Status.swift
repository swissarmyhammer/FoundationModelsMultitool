// `Status` — the `tools.git.status` verb.
//
// git.md § "Verbs": `tools.git.status` takes no argument, and gives the
// staged, unstaged, untracked, and renamed files. The source is `get_status`
// of `swissarmyhammer-git`. This verb reads through the shared status reader of
// the capability (`GitStatusReader.swift`), which the later `changes` and
// `diff` verbs read through too, and the reader calls only the `LibGit2`
// layer, never the C API (git.md § "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `status`
// and the surface path renders as `tools.git.status`.
//
// Each path is relative to the root, and a file outside the root is in no
// list (git.md § "Decisions", item 8). The card names the field `clean`; the
// field is `isClean`, because a Boolean member reads as an assertion
// (`swift/naming-clarity`).
//
// A status the verb cannot read stays IN BAND, as a `correction` beside no
// file. It is never thrown: a root in no repository and a status that libgit2
// cannot read are each a fact the model reads inside the turn, and a thrown
// error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.status`: none. The verb reads the whole root.
@Generable
struct StatusArguments {}

/// The result of `tools.git.status`: the uncommitted files below the root, or
/// the correction that says why there is no list.
///
/// `correction` and the lists are exclusive. A status that answers lists
/// carries no correction, and a correction carries no file and is not clean.
@Generable(description: "the uncommitted files below the session root, or the correction that says why there is no list.")
struct StatusResult {

    /// The files with a change in the index.
    @Guide(description: "The files with a change in the index (new, changed, or removed), relative to the session root.")
    var staged: [String]

    /// The files with a change in the work folder that is not in the index.
    @Guide(
        description:
            "The files with a change in the work folder that is not staged, and the files with a merge conflict, "
            + "relative to the session root.")
    var unstaged: [String]

    /// The files that git does not track.
    @Guide(description: "The files that git does not track, relative to the session root.")
    var untracked: [String]

    /// The files with a staged rename, under their new paths.
    @Guide(description: "The files with a staged rename, under their new paths, relative to the session root.")
    var renamed: [String]

    /// Whether no file below the root differs from HEAD.
    @Guide(description: "True when no file below the session root differs from HEAD: each list is empty.")
    var isClean: Bool

    /// Why the status answered no list, or `nil` when the lists stand.
    @Guide(description: "Why the status answered no list; null when the lists stand.")
    var correction: String?
}

extension Status {

    // MARK: Execution

    /// Reads the uncommitted files below the root, or answers the correction
    /// that says why there is no list.
    ///
    /// Reads through the shared reader of the context, which checks the
    /// repository of the root and keeps only the files below the root. Each
    /// recoverable failure comes back as the `correction` field of the
    /// result; nothing here throws.
    ///
    /// - Parameter arguments: None.
    /// - Returns: The lists, or the correction.
    func call(arguments: StatusArguments) async throws -> StatusResult {
        context.status().resolve(corrective: Self.corrective, then: Self.result(of:))
    }

    // MARK: Steps

    /// The result of a status.
    ///
    /// - Parameter status: The status that the reader gave.
    /// - Returns: The result with its lists.
    private static func result(of status: GitStatus) -> StatusResult {
        StatusResult(
            staged: status.staged, unstaged: status.unstaged, untracked: status.untracked, renamed: status.renamed,
            isClean: status.isClean, correction: nil)
    }

    // MARK: Corrective results

    /// A result that carries only a correction: no file, and not clean.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``StatusResult``.
    private static func corrective(_ message: String) -> StatusResult {
        StatusResult(staged: [], unstaged: [], untracked: [], renamed: [], isClean: false, correction: message)
    }
}

/// Gives the uncommitted files below the session root.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const status = await tools.git.status({});
/// ```
///
/// The contract: four lists of paths relative to the root (staged, unstaged,
/// untracked, and renamed), and `isClean`, which is true when each list is
/// empty. A file outside the root is in no list. A staged rename is in
/// `renamed` under its new path. A file with a merge conflict is in
/// `unstaged`. A root in no repository comes back as a `correction`, not as
/// an error.
struct Status: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.status`.
    let name = "status"

    /// The usage instructions, as the model reads them.
    let description = """
        status gives the files below the session root that differ from HEAD, in four lists of \
        paths relative to the session root: staged (a change in the index), unstaged (a change \
        in the work folder that is not staged, or a merge conflict), untracked (a file that git \
        does not track), and renamed (a staged rename, under its new path). isClean is true when \
        each list is empty. A file outside the session root is in no list. A root in no git \
        repository comes back as a correction rather than as an error — read it and act on it.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Status(context:)`.
    let context: GitContext
}
