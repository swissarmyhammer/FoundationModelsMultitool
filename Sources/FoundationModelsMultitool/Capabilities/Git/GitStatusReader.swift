// `GitStatusReader` — the shared status reader of the git capability: the
// uncommitted files below the root, or the correction that says why there is
// no list.
//
// `tools.git.status` reads through this reader. The later `changes` and
// `diff` verbs need the same uncommitted-file list, thus they read through it
// too, and the lists, the root rule, and the text of each correction are the
// same in each verb.
//
// git.md § "Decisions", item 8: each path in a result is relative to the root,
// and the root is the boundary of the capability. libgit2 reads the status of
// the whole work folder; the reader keeps only the files below the root, and
// changes each path into a root path (`GitRepositoryLocation`).
//
// git.md § "Decisions", item 10: the reader calls only the `LibGit2` layer
// (`LibGit2Status.swift`), never the C API. A root in no repository and a
// status that libgit2 cannot read each come back as a `CorrectiveRejection`,
// never as a thrown error.

import Foundation

/// The uncommitted files below the root, in four lists.
///
/// A file can be in two lists, for example a staged change with a second
/// change that is not staged.
struct GitStatus: Equatable, Sendable {

    /// The files with a change in the index: new, changed, or removed.
    let staged: [String]

    /// The files with a change in the work folder that is not in the index,
    /// and the files with a merge conflict.
    let unstaged: [String]

    /// The files in the work folder that git does not track.
    let untracked: [String]

    /// The files with a staged rename, under their new paths.
    let renamed: [String]

    /// Whether no file below the root differs from HEAD: each list is empty.
    var isClean: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && renamed.isEmpty
    }
}

extension GitContext {

    /// The description of a status that libgit2 could not read, before the
    /// `: <libgit2 error>` suffix.
    private static let failedStatusDescription = "git status failed"

    /// Reads the uncommitted files below the root.
    ///
    /// - Returns: The status, with each path relative to the root, or the
    ///   correction for a root in no repository and for a status that libgit2
    ///   cannot read.
    func status() -> Result<GitStatus, CorrectiveRejection> {
        repository.flatMap(Self.readStatus(in:))
    }

    // MARK: Steps

    /// Reads the status of the repository through the `LibGit2` layer, and
    /// keeps the files below the root.
    ///
    /// - Parameter location: The repository of the root.
    /// - Returns: The status, or the correction for a failed read.
    private static func readStatus(in location: GitRepositoryLocation) -> Result<GitStatus, CorrectiveRejection> {
        let status: LibGit2Status
        do {
            status = try LibGit2Repository(discoveringFrom: location.workDirectory).status()
        } catch {
            return .failure(CorrectiveRejection(correctiveMessage: "\(failedStatusDescription): \(error)"))
        }
        let paths = { (group: LibGit2StatusGroup) in
            status.paths(in: group).compactMap(location.rootRelativePath(fromRepositoryPath:))
        }
        return .success(
            GitStatus(staged: paths(.staged), unstaged: paths(.unstaged), untracked: paths(.untracked), renamed: paths(.renamed)))
    }
}
