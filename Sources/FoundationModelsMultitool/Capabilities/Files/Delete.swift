// `Delete` — the `tools.files.delete` verb.
//
// SWE-bench run bench24-1023b, django__django-13933 seq 4183: the model
// called `tools.files.delete({ path })` to remove a scratch test file it had
// made. There was no such verb (a file could only go through a `*** Delete
// File:` hunk of `tools.files.patch`), and the failure took the rest of the
// snippet — a test run — down with it. This verb deletes one file, in the
// pattern of `Capabilities/Files/RemoveDirectory.swift`: a plain
// `FoundationModels.Tool` that holds the `FileContext` it works against.
//
// A path the verb cannot delete stays IN BAND, as a `correction` beside
// empty envelope fields. It is never thrown, thus a refused delete never
// takes the rest of the snippet down with it.

import Foundation
import FoundationModels
import FoundationModelsExtras

/// The arguments of `tools.files.delete`: the file to delete, and whether a
/// directory may be deleted.
@Generable
struct DeleteArguments {

    /// The path of the file to delete.
    @Guide(description: "The path of the file to delete, absolute or relative to the session root.")
    var path: String

    /// Whether the path may name an empty directory; `nil` deletes only a file.
    @Guide(
        description:
            "Whether the path may name an empty directory, which is then deleted. Omit it to delete only a file.")
    var directory: Bool?
}

/// The result of `tools.files.delete`: the deleted path and whether this
/// call deleted it, or the correction that says why nothing was deleted.
///
/// A call that lands carries no correction. A correction carries an empty
/// `path` and `deleted: false`.
@Generable(
    description:
        "the deleted path's absolute path and whether this call deleted it, or the correction that says why nothing was deleted."
)
struct DeleteResult {

    /// The absolute path of the deleted entry. Empty on a correction.
    var path: String

    /// Whether this call deleted the entry. `false` on a correction.
    var deleted: Bool

    /// Why nothing was deleted, or `nil` when the envelope stands.
    var correction: String?
}

extension Delete {

    // MARK: Corrective messages

    /// The corrective message for a call on a read-only session.
    private static let readOnlySessionMessage =
        "The session is read-only, so the `delete` verb cannot delete a file."

    /// The description of a path with nothing at it, before the `: path` suffix.
    private static let missingDescription = "Nothing is at the path, so there is nothing to delete"

    /// The description of a directory without the `directory` flag, before the `: path` suffix.
    private static let directoryDescription =
        "The path is a directory. To delete an empty directory, give directory: true; "
        + "to delete a directory with what it holds, use tools.files.removeDirectory with recursive: true"

    /// The description of a path inside a `.git` folder, before the `: path` suffix.
    private static let gitInternalDescription =
        "The path is inside a .git folder, and the verb never deletes the internals of a repository"

    /// The description of a path the host exclude patterns name, before the `: path` suffix.
    private static let excludedDescription = "The path is one the host keeps for itself, and the verb never deletes it"

    /// The description of a file that could not be deleted, before the `: path` suffix.
    private static let deleteFailureDescription = "The file could not be deleted"

    /// The name of the folder that holds the internals of a git repository.
    private static let gitFolderName = ".git"

    /// A result carrying only a correction: empty path, nothing deleted.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``DeleteResult``.
    private static func corrective(_ message: String) -> DeleteResult {
        DeleteResult(path: "", deleted: false, correction: message)
    }

    /// The `<description>: <path>` correction.
    private static func corrective(_ description: String, path: String) -> DeleteResult {
        corrective(PathCorrective.pathErrorMessage(description: description, path: path))
    }

    // MARK: Checks

    /// The correction that refuses `url` before any deletion, or `nil`.
    ///
    /// Refuses an entry inside a `.git` folder, and one the host exclude
    /// patterns name.
    ///
    /// - Parameters:
    ///   - url: the resolved URL to delete.
    ///   - isFolder: whether the entry is a directory.
    ///   - path: the requested path, echoed in a correction.
    /// - Returns: the correction, or `nil` when the entry may be deleted.
    private func refusal(of url: URL, isFolder: Bool, path: String) -> DeleteResult? {
        // Read under the root, thus a root that itself stands in a `.git`
        // folder (a worktree of git's own) does not refuse every path.
        let root = FileWalker.canonicalDirectory(context.root).path
        let relative = FileWalker.relativePath(ofAbsolute: url.path, under: root)
        if (relative ?? url.path).split(separator: "/").contains(Substring(Self.gitFolderName)) {
            return Self.corrective(Self.gitInternalDescription, path: path)
        }
        if let relative {
            let excluded =
                isFolder
                ? context.excludePatterns.excludes(folderPath: relative)
                : context.excludePatterns.excludes(relativePath: relative)
            if excluded { return Self.corrective(Self.excludedDescription, path: path) }
        }
        return nil
    }

    // MARK: Execution

    /// Deletes one regular file, or a symlink as a link, and records the
    /// delete change.
    ///
    /// - Parameters:
    ///   - url: the resolved URL to delete.
    ///   - path: the requested path, echoed in a correction.
    ///   - toolContext: the ambient context the journal commits through.
    /// - Returns: the envelope, or the correction.
    private func deleteFile(at url: URL, path: String, toolContext: ToolContext?) async -> DeleteResult {
        let changes =
            context.changes.isRecording
            ? [FileChange(kind: .delete, path: url.path, oldContent: AtomicWriter.decodedText(at: url))] : []
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return Self.corrective(Self.deleteFailureDescription, path: path)
        }
        await context.changes.commit(changes, through: toolContext)
        return DeleteResult(path: url.path, deleted: true, correction: nil)
    }

    /// Deletes the file and answers the envelope, or the correction that says
    /// why nothing was deleted.
    ///
    /// Rejects a read-only session, then bounds the path through the
    /// context's ``PathGuard`` (a symlink at its own location, as
    /// `removeDirectory` does). A missing path, a directory without
    /// `directory: true`, an entry inside `.git`, and an entry the host
    /// exclude patterns name each come back as a correction. An empty
    /// directory with `directory: true` goes to `removeDirectory`, which
    /// refuses one that is not empty.
    ///
    /// The ambient context is read one time, at the start, for the reason
    /// `RemoveDirectory.call(arguments:)` gives.
    ///
    /// - Parameter arguments: What to delete.
    /// - Returns: The envelope, or the correction.
    func call(arguments: DeleteArguments) async throws -> DeleteResult {
        let toolContext = ToolContext.current
        if context.readOnly { return Self.corrective(Self.readOnlySessionMessage) }
        let path = arguments.path
        if let link = context.pathGuard.validateSymlinkLocation(path) {
            switch link {
            case .failure(let violation): return Self.corrective(violation.correctiveMessage)
            case .success(let url):
                if let refusal = refusal(of: url, isFolder: false, path: path) { return refusal }
                return await deleteFile(at: url, path: path, toolContext: toolContext)
            }
        }
        let url: URL
        switch context.pathGuard.validatePath(path) {
        case .failure(let violation): return Self.corrective(violation.correctiveMessage)
        case .success(let resolved): url = resolved
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Self.corrective(Self.missingDescription, path: path)
        }
        if FileWalker.isDirectory(url.path) {
            guard arguments.directory == true else { return Self.corrective(Self.directoryDescription, path: path) }
            if let refusal = refusal(of: url, isFolder: true, path: path) { return refusal }
            let removed = try await RemoveDirectory(context: context)
                .call(arguments: RemoveDirectoryArguments(path: path, recursive: false))
            return DeleteResult(path: removed.path, deleted: removed.removed, correction: removed.correction)
        }
        if let refusal = refusal(of: url, isFolder: false, path: path) { return refusal }
        if case .failure(let violation) = context.pathGuard.checkPermission(url, for: .delete) {
            return Self.corrective(violation.correctiveMessage)
        }
        return await deleteFile(at: url, path: path, toolContext: toolContext)
    }
}

/// Deletes one file under the session root, or, with `directory: true`, an
/// empty directory.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const gone = await tools.files.delete({ path: "tests/test_scratch.py" });
/// ```
///
/// The contract: the path is bounded through the session's ``PathGuard``. A
/// symlink is deleted as a link, and its target stays. When the session's
/// ``FileChangeJournal`` records, the verb records one
/// ``FileChangeKind/delete`` change with the old text. A read-only session,
/// a missing path, a directory without `directory: true` (or one that is not
/// empty), a path outside the root, an entry inside `.git`, an entry the
/// host exclude patterns name, and a failed delete each come back as a
/// `correction` rather than as an error.
///
/// The context it works against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct Delete: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.delete`.
    let name = "delete"

    /// The usage instructions, as the model reads them.
    let description = """
        delete deletes one file: use it in place of tools.shell.execute to remove a file, for \
        example a scratch test you made. With directory: true the path may also name an empty \
        directory; to delete a directory with what it holds, use tools.files.removeDirectory with \
        recursive: true. A symlink is deleted as a link only. The result carries the absolute path \
        and deleted. A missing path, a path outside the session root, a path inside .git, a path \
        the host keeps for itself, a read-only session, and a failed delete each come back as a \
        correction rather than as an error — read it, correct the call, and ask again.
        """

    /// The session context this verb works against, which the files capability owns.
    let context: FileContext
}
