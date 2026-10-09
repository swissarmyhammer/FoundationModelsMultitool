// `RemoveDirectory` — the `tools.files.removeDirectory` verb.
//
// Before this verb, the files capability could not remove a directory, thus
// the model had to use `tools.shell.execute`. This verb closes that gap, in
// the pattern of `Capabilities/Files/Write.swift`: a plain
// `FoundationModels.Tool` that holds the `FileContext` it works against.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `removeDirectory` and
// the surface path renders as `tools.files.removeDirectory`.
//
// The `PathGuard` rule `FileOperation.delete` accepts only a regular file,
// thus this verb does its own directory checks. It validates the path, then
// refuses a missing path, a regular file, and a root of the session, and it
// removes a symlink as a link only. The rule `FileOperation.directory` then
// refuses any other entry that is not a directory.
//
// A directory the verb cannot remove stays IN BAND, as a `correction` beside
// empty envelope fields. It is never thrown: each refusal is a mistake the
// model corrects inside the turn, and a thrown error would end the turn
// instead.

import Foundation
import FoundationModels
import FoundationModelsExtras

/// The arguments of `tools.files.removeDirectory`: the directory to remove,
/// and whether to remove a directory that is not empty.
@Generable
struct RemoveDirectoryArguments {

    /// The path of the directory to remove.
    @Guide(description: "The path of the directory to remove, absolute or relative to the session root.")
    var path: String

    /// Whether to remove a directory that is not empty; `nil` removes only an empty one.
    @Guide(
        description:
            "Whether to remove the directory with each file and folder in it. Omit it, or give false, to remove only an empty directory."
    )
    var recursive: Bool?
}

/// The result of `tools.files.removeDirectory`: the directory's absolute
/// path, whether this call removed it, and how many files the removal
/// deleted, or the correction that says why nothing was removed.
///
/// A call that lands carries no correction. A correction carries an empty
/// `path` and `removed: false`.
@Generable(
    description:
        "the directory's absolute path, whether this call removed it, and how many files the removal deleted, or the correction that says why nothing was removed."
)
struct RemoveDirectoryResult {

    /// The absolute path of the removed directory, resolved through the session's path guard. Empty on a correction.
    var path: String

    /// Whether this call removed the directory. `false` on a correction.
    var removed: Bool

    /// The number of regular files that the removal deleted. Zero for an
    /// empty directory and for a symlink. A removal that fails part of the
    /// way through gives a correction with the number of files it deleted.
    var filesRemoved: Int

    /// Why nothing was removed, or `nil` when the envelope stands.
    var correction: String?
}

extension RemoveDirectory {

    /// The entry that the verb removes, after the checks.
    private enum Target {
        /// A symlink, which the verb removes as a link only. The URL is the
        /// location of the link, not its target.
        case link(URL)
        /// A directory, which the verb removes with its contents when the
        /// call permits it. The URL is the canonical directory.
        case directory(URL)
    }

    // MARK: Defaults

    /// Whether the verb removes a directory that is not empty when the call omits `recursive`.
    private static let removesRecursivelyByDefault = false

    // MARK: Corrective messages

    /// The corrective message for a call on a read-only session.
    private static let readOnlySessionMessage =
        "The session is read-only, so the `removeDirectory` verb cannot remove a directory."

    /// The description of a path with nothing at it, before the `: path` suffix.
    private static let missingDescription = "Nothing is at the path, so there is no directory to remove"

    /// The description of a path that is a regular file, before the `: path` suffix.
    private static let regularFileDescription =
        "The path is a file, not a directory. To delete a file, use tools.files.patch with a `*** Delete File:` hunk"

    /// The description of a path that is a root of the session, before the `: path` suffix.
    private static let rootDescription =
        "The path is the session root or a workspace root, and the verb never removes a root"

    /// The description of a directory that is not empty, before the `: path` suffix.
    private static let notEmptyDescription =
        "The directory is not empty. To remove it with each file and folder in it, give recursive: true"

    /// The description of a directory that could not be removed, before the `: path` suffix.
    private static let removalFailureDescription = "The directory could not be removed completely"

    /// The description of a symlink that could not be removed, before the `: path` suffix.
    private static let linkFailureDescription = "The symlink could not be removed"

    /// A result carrying only a correction: empty path, nothing removed.
    ///
    /// - Parameters:
    ///   - message: the correction the model reads and acts on.
    ///   - filesRemoved: the number of files that a failed removal deleted; zero by default.
    /// - Returns: the corrective ``RemoveDirectoryResult``.
    private static func corrective(_ message: String, filesRemoved: Int = 0) -> RemoveDirectoryResult {
        RemoveDirectoryResult(path: "", removed: false, filesRemoved: filesRemoved, correction: message)
    }

    /// A path violation that carries a `<description>: <path>` message.
    ///
    /// - Parameters:
    ///   - description: the leading description of what went wrong.
    ///   - path: the requested path.
    /// - Returns: the corrective ``PathViolation``.
    private static func violation(_ description: String, path: String) -> PathViolation {
        PathViolation(PathCorrective.pathErrorMessage(description: description, path: path))
    }

    // MARK: Checks

    /// The entry to remove, or the violation that says why nothing is removed.
    ///
    /// A symlink comes back as a ``Target/link(_:)`` at the location the
    /// path guard bounds. Any other path goes through
    /// ``PathGuard/validatePath(_:absentFolders:)`` and the directory checks
    /// of ``directoryTarget(at:path:pathGuard:)``.
    ///
    /// - Parameters:
    ///   - path: the requested path.
    ///   - pathGuard: the guard of the session.
    /// - Returns: `.success` with the entry to remove, or `.failure` with a corrective ``PathViolation``.
    private static func target(of path: String, pathGuard: PathGuard) -> Result<Target, PathViolation> {
        if let link = pathGuard.validateSymlinkLocation(path) {
            return link.map(Target.link)
        }
        return pathGuard.validatePath(path).flatMap { url in
            directoryTarget(at: url, path: path, pathGuard: pathGuard)
        }
    }

    /// The directory at a validated URL, or the violation that refuses it.
    ///
    /// Refuses a path with nothing at it, a regular file (with the name of
    /// the verb that deletes a file), any other entry that is not a
    /// directory, and a root of the session.
    ///
    /// - Parameters:
    ///   - url: the resolved, validated URL.
    ///   - path: the requested path, echoed in a correction.
    ///   - pathGuard: the guard of the session.
    /// - Returns: `.success` with the directory, or `.failure` with a corrective ``PathViolation``.
    private static func directoryTarget(at url: URL, path: String, pathGuard: PathGuard) -> Result<Target, PathViolation> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(violation(missingDescription, path: path))
        }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile != true else {
            return .failure(violation(regularFileDescription, path: path))
        }
        guard !pathGuard.isRoot(url) else {
            return .failure(violation(rootDescription, path: path))
        }
        return pathGuard.checkPermission(url, for: .directory).map { Target.directory(url) }
    }

    /// Whether a directory holds no entry.
    ///
    /// - Parameter url: the directory to read.
    /// - Returns: `true` when the directory holds no entry; `false` when it
    ///   holds one, or when it cannot be read.
    private static func isEmptyDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty ?? false
    }

    // MARK: Change recording

    /// The delete changes of the files under a directory, captured before the removal.
    ///
    /// The old text of each file is gone after the removal, thus the verb
    /// reads it before. That text is `nil` when the file cannot be read or
    /// is not decodable text, thus the rendered patch reports the file as
    /// binary.
    ///
    /// - Parameter files: the absolute paths of the regular files under the directory.
    /// - Returns: one ``FileChangeKind/delete`` change for each file.
    private static func deleteChanges(of files: [String]) -> [FileChange] {
        files.map { file in
            FileChange(kind: .delete, path: file, oldContent: AtomicWriter.decodedText(at: URL(fileURLWithPath: file)))
        }
    }

    // MARK: Execution

    /// Removes a symlink, and never its target.
    ///
    /// - Parameters:
    ///   - url: the location of the link.
    ///   - path: the requested path, echoed in a correction.
    /// - Returns: the envelope, or the correction.
    private static func removeLink(at url: URL, path: String) -> RemoveDirectoryResult {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return corrective(PathCorrective.pathErrorMessage(description: linkFailureDescription, path: path))
        }
        return RemoveDirectoryResult(path: url.path, removed: true, filesRemoved: 0, correction: nil)
    }

    /// Removes a directory, and records a delete change for each file it held.
    ///
    /// A directory that is not empty needs `recursive`. The regular files
    /// under the directory are listed before the removal: their number is
    /// `filesRemoved`, and their old text goes to the session's
    /// ``FileChangeJournal`` when it records. When the removal fails part of
    /// the way through, the journal gets the changes of the files that are
    /// gone, and the correction gives their number.
    ///
    /// - Parameters:
    ///   - url: the canonical directory.
    ///   - recursive: whether a directory that is not empty may be removed.
    ///   - path: the requested path, echoed in a correction.
    ///   - toolContext: the ambient context the journal commits through.
    /// - Returns: the envelope, or the correction.
    private func removeDirectory(
        at url: URL,
        recursive: Bool,
        path: String,
        toolContext: ToolContext?
    ) async -> RemoveDirectoryResult {
        guard recursive || Self.isEmptyDirectory(url) else {
            return Self.corrective(PathCorrective.pathErrorMessage(description: Self.notEmptyDescription, path: path))
        }
        let files = FileWalker.collectFiles(walkRoot: url, respectGitIgnore: false)
        let changes = context.changes.isRecording ? Self.deleteChanges(of: files) : []
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let gone = Set(files.filter { !FileManager.default.fileExists(atPath: $0) })
            await context.changes.commit(changes.filter { gone.contains($0.path) }, through: toolContext)
            return Self.corrective(
                PathCorrective.pathErrorMessage(description: Self.removalFailureDescription, path: path),
                filesRemoved: gone.count
            )
        }
        await context.changes.commit(changes, through: toolContext)
        return RemoveDirectoryResult(path: url.path, removed: true, filesRemoved: files.count, correction: nil)
    }

    /// Removes the directory and answers the envelope, or the correction
    /// that says why nothing was removed.
    ///
    /// Rejects a read-only session, then finds the entry through
    /// ``target(of:pathGuard:)``, then removes a link as a link or a
    /// directory with ``removeDirectory(at:recursive:path:toolContext:)``.
    /// Each recoverable failure comes back as the `correction` field of the
    /// result; nothing here throws.
    ///
    /// **The ambient context is read one time, at the start.** eventplan.md
    /// § "The ambient context" makes that rule mandatory: work that inherits
    /// no task local sees none, so a second read of the ambient context
    /// after an `await` would find `nil`. The value captured here is what
    /// the commit posts through.
    ///
    /// - Parameter arguments: What directory to remove, and whether to remove its contents.
    /// - Returns: The envelope, or the correction.
    func call(arguments: RemoveDirectoryArguments) async throws -> RemoveDirectoryResult {
        let toolContext = ToolContext.current
        if context.readOnly { return Self.corrective(Self.readOnlySessionMessage) }
        let recursive = arguments.recursive ?? Self.removesRecursivelyByDefault
        return await Self.target(of: arguments.path, pathGuard: context.pathGuard)
            .resolveAsync(corrective: { Self.corrective($0) }) { target in
                switch target {
                case .link(let url):
                    return Self.removeLink(at: url, path: arguments.path)
                case .directory(let url):
                    return await removeDirectory(
                        at: url, recursive: recursive, path: arguments.path, toolContext: toolContext
                    )
                }
            }
    }
}

/// Removes a directory under the session root: an empty one by default, or
/// a whole tree with `recursive: true`.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const gone = await tools.files.removeDirectory({ path: "build/cache", recursive: true });
/// ```
///
/// The contract: the path is bounded through the session's ``PathGuard``.
/// A directory that is not empty needs `recursive: true`. A symlink to a
/// directory is removed as a link only, and its target stays. The result
/// carries `filesRemoved`, the number of regular files that the removal
/// deleted. When the session's ``FileChangeJournal`` records, the verb
/// records one ``FileChangeKind/delete`` change for each removed file, with
/// its old text. A read-only session, a missing path, a regular file, a root
/// of the session, a path outside the root, and a failed removal each come
/// back as a `correction` rather than as an error.
///
/// The context it works against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct RemoveDirectory: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.removeDirectory`.
    let name = "removeDirectory"

    /// The usage instructions, as the model reads them.
    let description = """
        removeDirectory removes a directory: use it in place of tools.shell.execute to delete a \
        folder. An empty directory needs only the path. A directory that holds files or folders \
        needs recursive: true, which removes the whole tree. A symlink to a directory is removed \
        as a link only, and its target stays. The result carries the absolute path, removed, and \
        filesRemoved — the number of files that the removal deleted. To delete one file, use \
        tools.files.patch. A missing path, a file at the path, the session root, a path outside \
        the session root, a read-only session, and a failed removal each come back as a \
        correction rather than as an error — read it, correct the call, and ask again.
        """

    /// The session context this verb works against, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `RemoveDirectory(context:)`.
    let context: FileContext
}
