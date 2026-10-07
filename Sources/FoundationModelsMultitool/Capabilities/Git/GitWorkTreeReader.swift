// `GitWorkTreeReader` — the work folder reader of the git capability: the text
// of one file in the work folder, or the correction that says why there is
// none.
//
// `tools.git.diff` reads each side with no ref through this reader: a file
// side of the file mode with no `@ref`, and the new side of each file of the
// automatic mode. A side with a ref reads the commit through the blob reader
// (`GitBlobReader.swift`) instead. The two readers give the same `GitBlob`,
// thus the diff reads the two sides in one way.
//
// git.md § "Decisions", item 8: the path argument goes through the
// `PathGuard` of `GitContext` with the `read` permission, the same as
// `tools.files.read`, thus a path cannot go out of the root and a symlink is
// refused. The path of the result is relative to the root.
//
// The text rule is the rule of `tools.files.read`: the bytes must be UTF-8.
//
// A mistake that the model can correct does not throw: a path that the guard
// refuses, a file that cannot be read, a file that is not UTF-8 text, and a
// root in no repository each come back as a `CorrectiveRejection`.

import Foundation

extension GitContext {

    /// The description of a work folder file that is not UTF-8 text, before
    /// the `: path` suffix.
    private static let workTreeBinaryDescription =
        "The file in the work folder is not valid UTF-8 text and appears to be binary, so it cannot be read as text"

    /// Reads the text of the file at `path` in the work folder.
    ///
    /// - Parameter path: The path of the file, absolute or relative to the
    ///   root.
    /// - Returns: The file with its path relative to the root, or the
    ///   correction for a root in no repository, a path that the guard
    ///   refuses, a path outside the work folder, a file that cannot be read,
    ///   or a file that is not UTF-8 text.
    internal func workTreeFile(path: String) -> Result<GitBlob, CorrectiveRejection> {
        repository.flatMap { location in
            pathGuard.validate(path, for: .read)
                .mapError { violation in CorrectiveRejection(correctiveMessage: violation.correctiveMessage) }
                .flatMap { url in Self.readWorkTreeFile(at: url, in: location, requestedPath: path) }
        }
    }

    // MARK: Steps

    /// Reads a file that the guard accepted.
    ///
    /// - Parameters:
    ///   - url: The URL that the guard gave.
    ///   - location: The repository of the root.
    ///   - path: The path argument, for the text of a correction.
    /// - Returns: The file, or the correction.
    private static func readWorkTreeFile(
        at url: URL,
        in location: GitRepositoryLocation,
        requestedPath path: String
    ) -> Result<GitBlob, CorrectiveRejection> {
        guard let rootPath = location.repositoryPath(ofFile: url).flatMap(location.rootRelativePath(fromRepositoryPath:))
        else {
            return .failure(pathRejection(outsideWorkFolderDescription, path: path))
        }
        return PathCorrective.readData(at: url, path: path)
            .mapError { failure in CorrectiveRejection(correctiveMessage: failure.correctiveMessage) }
            .flatMap { data in
                guard let text = String(data: data, encoding: .utf8) else {
                    return .failure(pathRejection(workTreeBinaryDescription, path: path))
                }
                return .success(GitBlob(path: rootPath, text: text))
            }
    }
}
