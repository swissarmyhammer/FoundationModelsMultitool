// `GitBlobReader` — the shared reader of the git capability: the text of one
// file at one ref, or the correction that says why there is none.
//
// git.md § "Decisions", item 6: each verb that reads a file at a ref reads the
// blob through libgit2. `tools.git.show` reads through this reader, and
// `tools.git.diff` reads each `path@ref` side through it too. Thus the path
// rules, the binary rule, and the text of each correction are the same in the
// two verbs.
//
// git.md § "Decisions", item 8: the path argument goes through the
// `PathGuard` of `GitContext`, thus a path cannot go out of the root. The
// guard checks the path with `validatePath(_:absentFolders: .accepted)`, not
// with the `read` permission: the file at an older ref can be absent from the
// work folder, and a later commit can have removed its folders too. The guard
// then bounds the path from the deepest folder that the disk holds, and
// refuses an absent folder that is a dangling symlink (task `^5a8vaqk`).
//
// The reader gives the whole text, with no cap. Each verb applies its own cap
// to what it shows.
//
// A mistake that the model can correct does not throw: an unknown ref, an
// unknown path, a folder path, a binary file, a path outside the root, and a
// root in no repository each come back as a `CorrectiveRejection`. A libgit2
// failure of another kind comes back as a correction with the libgit2 text,
// the same as a failed blame.

import Foundation

/// The text of one file at one ref.
struct GitBlob: Equatable, Sendable {

    /// The path of the file, relative to the session root.
    let path: String

    /// The whole text of the file at the ref, with no cap.
    let text: String
}

extension GitContext {

    /// The ref that a verb reads when the call names no ref.
    static let defaultRef = "HEAD"

    /// The description of a file that is not in the work folder of the
    /// repository, before the `: path` suffix.
    static let outsideWorkFolderDescription = "The file is not in the work folder of the git repository"

    /// The description of a binary blob, before the `: path` suffix.
    private static let binaryDescription = "The file at the ref is binary, so it cannot be read as text"

    /// The description of a blob that libgit2 could not read, before the
    /// `: path` suffix.
    private static let unreadableDescription = "The file cannot be read from git"

    // MARK: The reader

    /// Reads the text of the file at `path` in the commit that `ref` names.
    ///
    /// - Parameters:
    ///   - path: The path of the file, absolute or relative to the root.
    ///   - ref: A ref: a branch, a tag, a sha, or a form such as `HEAD~1`.
    /// - Returns: The blob, or the correction for a root in no repository, a
    ///   path that the guard refuses, a path outside the work folder, an
    ///   unknown ref, an unknown path, a folder path, a binary file, or a
    ///   libgit2 failure.
    func blob(path: String, ref: String) -> Result<GitBlob, CorrectiveRejection> {
        repository.flatMap { location in
            repositoryPath(of: path, in: location).flatMap { repositoryPath in
                Self.readBlob(atPath: repositoryPath, ref: ref, in: location, requestedPath: path)
            }
        }
    }

    /// Sends a path argument through the path guard, and changes it into a
    /// repository path.
    ///
    /// The guard accepts a path whose folders are absent from the work
    /// folder, because the path names a file or a folder in the history of
    /// the repository. The path still cannot go out of the root.
    ///
    /// - Parameters:
    ///   - path: The path argument, absolute or relative to the root.
    ///   - location: The repository of the root.
    /// - Returns: The path relative to the work folder, as libgit2 reads it,
    ///   or the correction for a path that the guard refuses or that is not
    ///   in the work folder.
    func repositoryPath(of path: String, in location: GitRepositoryLocation) -> Result<String, CorrectiveRejection> {
        pathGuard.validatePath(path, absentFolders: .accepted)
            .mapError { violation in CorrectiveRejection(correctiveMessage: violation.correctiveMessage) }
            .flatMap { url in
                guard let repositoryPath = location.repositoryPath(ofFile: url) else {
                    return .failure(Self.pathRejection(Self.outsideWorkFolderDescription, path: path))
                }
                return .success(repositoryPath)
            }
    }

    /// The correction for a ref that names no commit.
    ///
    /// - Parameter ref: The ref of the call.
    /// - Returns: The correction, which names the ref and the forms that a ref
    ///   can take.
    static func unknownRefMessage(_ ref: String) -> String {
        "The ref `\(ref)` names no commit in the git repository. Give a branch, a tag, a sha, "
            + "or a form such as HEAD~1."
    }

    // MARK: Steps

    /// Reads the blob at a repository path through the `LibGit2` layer.
    ///
    /// - Parameters:
    ///   - repositoryPath: The path relative to the work folder.
    ///   - ref: The ref of the call.
    ///   - location: The repository of the root.
    ///   - path: The path argument, for the text of a correction.
    /// - Returns: The blob, or the correction.
    private static func readBlob(
        atPath repositoryPath: String,
        ref: String,
        in location: GitRepositoryLocation,
        requestedPath path: String
    ) -> Result<GitBlob, CorrectiveRejection> {
        let lookup: LibGit2BlobLookup
        do {
            lookup = try LibGit2Repository(discoveringFrom: location.workDirectory)
                .blob(atPath: repositoryPath, revision: ref)
        } catch {
            return .failure(pathRejection(unreadableDescription, path: "\(path) at the ref `\(ref)` (\(error))"))
        }
        switch lookup {
        case .found(let blob):
            return text(of: blob, path: location.rootRelativePath(fromRepositoryPath: repositoryPath) ?? path)
        case .unknownRevision:
            return .failure(CorrectiveRejection(correctiveMessage: unknownRefMessage(ref)))
        case .unknownPath:
            return .failure(pathRejection("The commit of the ref `\(ref)` holds no file at this path", path: path))
        case .notAFile:
            return .failure(
                pathRejection("The commit of the ref `\(ref)` holds a folder, not a file, at this path", path: path))
        }
    }

    /// The text of a blob, or the binary correction.
    ///
    /// A blob is binary when git sees it as binary (a NUL byte), or when its
    /// bytes are not UTF-8.
    ///
    /// - Parameters:
    ///   - blob: The blob.
    ///   - path: The path of the file, relative to the root.
    /// - Returns: The blob with its text, or the binary correction.
    private static func text(of blob: LibGit2Blob, path: String) -> Result<GitBlob, CorrectiveRejection> {
        guard !blob.isBinary, let text = String(data: blob.content, encoding: .utf8) else {
            return .failure(pathRejection(binaryDescription, path: path))
        }
        return .success(GitBlob(path: path, text: text))
    }

    /// A rejection in the `<description>: <path>` shape of the files
    /// capability.
    ///
    /// - Parameters:
    ///   - description: What went wrong.
    ///   - path: The requested path.
    /// - Returns: The rejection.
    private static func pathRejection(_ description: String, path: String) -> CorrectiveRejection {
        CorrectiveRejection(correctiveMessage: PathCorrective.pathErrorMessage(description: description, path: path))
    }
}
