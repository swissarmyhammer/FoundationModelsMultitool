// `MakeDirectory` — the `tools.files.makeDirectory` verb.
//
// Before this verb, the files capability could not make a directory. A
// `write` to a path whose parent folder is absent gets the "Parent directory
// does not exist" correction (`PathGuard.AbsentFolderRule.refused`), thus the
// model had to use `tools.shell.execute`. This verb closes that gap, in the
// pattern of `Capabilities/Files/Write.swift`: a plain `FoundationModels.Tool`
// that holds the `FileContext` it works against.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `makeDirectory` and
// the surface path renders as `tools.files.makeDirectory`.
//
// A directory the verb cannot make stays IN BAND, as a `correction` beside
// empty envelope fields. It is never thrown: a read-only session, a path
// outside the root, an absent parent with `parents: false`, a file at the
// path, and a failed create are each a mistake the model corrects inside the
// turn, and a thrown error would end the turn instead.
//
// The verb records no change in the session's `FileChangeJournal`: a patch
// cannot show an empty directory. Thus it also does not read the ambient
// `ToolContext`.

import Foundation
import FoundationModels

/// The arguments of `tools.files.makeDirectory`: the directory to make, and
/// whether to make its absent parent folders.
@Generable
struct MakeDirectoryArguments {

    /// The path of the directory to make.
    @Guide(description: "The path of the directory to make, absolute or relative to the session root.")
    var path: String

    /// Whether to make each absent parent folder; `nil` makes them.
    @Guide(description: "Whether to make each absent parent folder too. Omit it, or give true, to make them.")
    var parents: Bool?
}

/// The result of `tools.files.makeDirectory`: the directory's absolute path
/// and whether this call made it, or the correction that says why nothing
/// was made.
///
/// `correction` and the envelope are exclusive. A call that lands carries no
/// correction, and a correction carries an empty `path` and `created: false`.
@Generable(
    description: "the directory's absolute path and whether this call made it, or the correction that says why nothing was made."
)
struct MakeDirectoryResult {

    /// The absolute path of the directory, resolved through the session's path guard. Empty on a correction.
    var path: String

    /// Whether this call made the directory. `false` when the directory was
    /// already there, and on a correction.
    var created: Bool

    /// Why nothing was made, or `nil` when the envelope stands.
    var correction: String?
}

extension MakeDirectory {

    // MARK: Defaults

    /// Whether the verb makes each absent parent folder when the call omits `parents`.
    private static let makesParentsByDefault = true

    // MARK: Corrective messages

    /// The corrective message for a call on a read-only session.
    private static let readOnlySessionMessage =
        "The session is read-only, so the `makeDirectory` verb cannot make a directory."

    /// The description of a path that validated but whose directory could not be made, before the `: path` suffix.
    private static let createFailureDescription = "The directory could not be made"

    /// A result carrying only a correction: empty path, nothing created.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``MakeDirectoryResult``.
    private static func corrective(_ message: String) -> MakeDirectoryResult {
        MakeDirectoryResult(path: "", created: false, correction: message)
    }

    // MARK: Execution

    /// Makes the directory at an already-validated URL, or answers that it
    /// was already there.
    ///
    /// The path guard has already refused a path where a file (not a
    /// directory) is, through ``FileOperation/directory``. A directory that
    /// is already there is not an error: the result carries `created: false`
    /// and no correction. A create that fails comes back as a correction.
    ///
    /// - Parameters:
    ///   - url: the resolved, already-validated directory URL.
    ///   - parents: whether to make each absent parent folder.
    ///   - path: the requested path, echoed in a correction.
    /// - Returns: the envelope, or the correction.
    private static func makeDirectory(at url: URL, parents: Bool, path: String) -> MakeDirectoryResult {
        if FileWalker.isDirectory(url.path) {
            return MakeDirectoryResult(path: url.path, created: false, correction: nil)
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: parents)
        } catch {
            return corrective(PathCorrective.pathErrorMessage(description: createFailureDescription, path: path))
        }
        return MakeDirectoryResult(path: url.path, created: true, correction: nil)
    }

    /// Makes the directory and answers the envelope, or the correction that
    /// says why nothing was made.
    ///
    /// Rejects a read-only session, then validates the path via the
    /// context's ``PathGuard`` for a directory — accepting absent parent
    /// folders only when `parents` is `true` — then makes the directory.
    /// Each recoverable failure comes back as the `correction` field of the
    /// result; nothing here throws.
    ///
    /// - Parameter arguments: What directory to make, and whether to make its parents.
    /// - Returns: The envelope, or the correction.
    func call(arguments: MakeDirectoryArguments) async throws -> MakeDirectoryResult {
        if context.readOnly { return Self.corrective(Self.readOnlySessionMessage) }
        let parents = arguments.parents ?? Self.makesParentsByDefault
        return context.pathGuard
            .validate(arguments.path, for: .directory, absentFolders: parents ? .accepted : .refused)
            .resolve(corrective: Self.corrective) { url in
                Self.makeDirectory(at: url, parents: parents, path: arguments.path)
            }
    }
}

/// Makes a directory under the session root, with its absent parent folders
/// by default.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const made = await tools.files.makeDirectory({ path: "src/feature/tests" });
/// ```
///
/// The contract: the path is bounded through the session's ``PathGuard``.
/// When `parents` is `true` (the default) each absent parent folder is made
/// too; when it is `false` an absent parent is a correction. A directory that
/// is already there gives `created: false` and no correction, thus the call
/// is safe to repeat. A read-only session, a path outside the root, a file at
/// the path, and a failed create each come back as a `correction` rather than
/// as an error. The verb records nothing in the session's
/// ``FileChangeJournal``, because a patch cannot show an empty directory.
///
/// The context it works against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct MakeDirectory: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.makeDirectory`.
    let name = "makeDirectory"

    /// The usage instructions, as the model reads them.
    let description = """
        makeDirectory makes a directory: use it before tools.files.write puts a file in a folder \
        that is not there yet, because write does not make absent folders. By default it also \
        makes each absent parent folder; give parents: false to make only the last folder. A \
        directory that is already there is not an error: the result says created: false. The \
        result carries the absolute path and created. A path outside the session root, a file at \
        the path, a read-only session, and a failed create each come back as a correction rather \
        than as an error — read it, correct the call, and ask again.
        """

    /// The session context this verb works against, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `MakeDirectory(context:)`.
    let context: FileContext
}
