// `GitStatusReader` — the shared status reader of the git capability: the
// uncommitted files below the root, or the correction that says why there is
// no list.
//
// `tools.git.status` and `tools.git.changes` read through this reader. The
// later `diff` verb needs the same uncommitted-file list, thus it reads
// through it too, and the lists, the root rule, and the text of each
// correction are the same in each verb.
//
// git.md § "Decisions", item 8: each path in a result is relative to the root,
// and the root is the boundary of the capability. libgit2 reads the status of
// the whole work folder; the reader keeps only the files below the root, and
// changes each path into a root path (`GitRepositoryLocation`). A staged
// rename from below the root to a path outside the root keeps its old path,
// as a staged removal (task `^pt6fyf0`); its new path is never given.
//
// The status also gives the branch that HEAD names (task `^fn56vsp`). The
// reader reads it through `LibGit2Repository.currentBranchName()`, the same
// call that `tools.git.branches` makes, thus the two verbs agree. A HEAD that
// libgit2 cannot read gives a `nil` branch beside the lists, not a
// correction: the lists stand without the branch. That failure is unexpected,
// thus the reader asserts and writes an `error` log record; it never
// silences the failure.
//
// git.md § "Decisions", item 10: the reader calls only the `LibGit2` layer
// (`LibGit2Status.swift`), never the C API. A root in no repository and a
// status that libgit2 cannot read each come back as a `CorrectiveRejection`,
// never as a thrown error.

import Foundation
import Logging

/// The uncommitted files below the root, in four lists, and the branch that
/// HEAD names.
///
/// A file can be in two lists, for example a staged change with a second
/// change that is not staged.
struct GitStatus: Equatable, Sendable {

    /// The files with a change in the index: new, changed, or removed.
    ///
    /// A staged rename from below the root to a path outside the root is a
    /// removal here, under its old path: the root does not hold the new
    /// path (git.md § "Decisions", item 8).
    let staged: [String]

    /// The files with a change in the work folder that is not in the index,
    /// and the files with a merge conflict.
    let unstaged: [String]

    /// The files in the work folder that git does not track.
    let untracked: [String]

    /// The files with a staged rename, under their new paths.
    let renamed: [String]

    /// The old path of each staged rename, keyed by its new path in
    /// ``renamed``.
    ///
    /// A rename from a path outside the root has no entry: the root is the
    /// boundary of the capability (git.md § "Decisions", item 8), thus no
    /// verb reads that path, and the file is new below the root.
    internal let oldPathsOfRenamedFiles: [String: String]

    /// The branch that HEAD names, or `nil`.
    ///
    /// `nil` for a detached HEAD and for a repository with no commit, the
    /// same as the `current` field of `tools.git.branches`, because both read
    /// `LibGit2Repository.currentBranchName()`. `nil` also when libgit2
    /// cannot read HEAD: the lists stand without the branch.
    let branch: String?

    /// Whether no file below the root differs from HEAD: each list is empty.
    var isClean: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && renamed.isEmpty
    }

    /// Each file of the four lists, in path order, one time each.
    ///
    /// A port of `get_uncommitted_changes` of the `changes` operation of the
    /// source: the staged, unstaged, renamed, and untracked files, sorted,
    /// with no file two times. `tools.git.changes` adds this list to its
    /// result.
    var allFiles: [String] {
        Set(staged + unstaged + untracked + renamed).sorted()
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
    /// The branch comes from the same open repository, thus the reader
    /// discovers the repository one time. A failure to read the branch gives
    /// a `nil` branch and keeps the lists, and is recorded
    /// (``currentBranchName(of:)``).
    ///
    /// - Parameter location: The repository of the root.
    /// - Returns: The status, or the correction for a failed read.
    private static func readStatus(in location: GitRepositoryLocation) -> Result<GitStatus, CorrectiveRejection> {
        let repository: LibGit2Repository
        let status: LibGit2Status
        do {
            repository = try LibGit2Repository(discoveringFrom: location.workDirectory)
            status = try repository.status()
        } catch {
            return .failure(CorrectiveRejection(correctiveMessage: "\(failedStatusDescription): \(error)"))
        }
        let paths = { (group: LibGit2StatusGroup) in
            status.paths(in: group).compactMap(location.rootRelativePath(fromRepositoryPath:))
        }
        return .success(
            GitStatus(
                staged: paths(.staged) + removalsOfRenamesOutOfTheRoot(of: status, in: location),
                unstaged: paths(.unstaged), untracked: paths(.untracked), renamed: paths(.renamed),
                oldPathsOfRenamedFiles: rootRelativeRenames(of: status, in: location),
                branch: currentBranchName(of: repository)))
    }

    /// The branch that HEAD names, or `nil` when libgit2 cannot read HEAD.
    ///
    /// HEAD is always readable in a repository whose status libgit2 read,
    /// thus a failure here is unexpected. The failure stops a debug build,
    /// and an `error` log record tells of it in a release build. The status
    /// then gives a `nil` branch and keeps its lists, and the `branch` Guide
    /// of `tools.git.status` tells the model that `nil` can mean this.
    ///
    /// - Parameter repository: The open repository of the status.
    /// - Returns: The name, without `refs/heads/`, or `nil` for a detached
    ///   HEAD, for a repository with no commit, and for a HEAD that libgit2
    ///   cannot read.
    private static func currentBranchName(of repository: LibGit2Repository) -> String? {
        do {
            return try repository.currentBranchName()
        } catch {
            assertionFailure("HEAD could not be read: \(error)")
            MultitoolTelemetry.logger.log(
                .gitBranchReadFailed, level: .error, metadata: MultitoolTelemetry.errorMetadata(of: error))
            return nil
        }
    }

    /// The old path of each staged rename from below the root to a path
    /// outside the root, relative to the root, in path order.
    ///
    /// For the root, such a rename is a staged removal of the old path: the
    /// root held the file, and the root does not hold the new path. libgit2
    /// gives no separate removal entry for the old path of a rename, thus
    /// without this list no list holds the file, and the status is clean.
    /// The new path is outside the root, thus no list gives it (git.md §
    /// "Decisions", item 8).
    ///
    /// - Parameters:
    ///   - status: The status of the repository.
    ///   - location: The repository of the root.
    /// - Returns: The old root path of each rename out of the root.
    private static func removalsOfRenamesOutOfTheRoot(
        of status: LibGit2Status, in location: GitRepositoryLocation
    ) -> [String] {
        status.oldPathsOfRenamedFiles
            .filter { newPath, _ in location.rootRelativePath(fromRepositoryPath: newPath) == nil }
            .compactMap { _, oldPath in location.rootRelativePath(fromRepositoryPath: oldPath) }
            .sorted()
    }

    /// The old path of each staged rename, keyed by its new path, with each
    /// path relative to the root.
    ///
    /// A rename keeps its entry only when both paths are below the root. A
    /// rename from outside the root has no entry, thus no verb reads the old
    /// path (git.md § "Decisions", item 8). Two repository paths never give
    /// the same root path, thus no entry replaces another.
    ///
    /// - Parameters:
    ///   - status: The status of the repository.
    ///   - location: The repository of the root.
    /// - Returns: The old root path of each rename, keyed by its new root
    ///   path.
    private static func rootRelativeRenames(
        of status: LibGit2Status, in location: GitRepositoryLocation
    ) -> [String: String] {
        let renames = status.oldPathsOfRenamedFiles.compactMap { newPath, oldPath -> (String, String)? in
            guard let rootNewPath = location.rootRelativePath(fromRepositoryPath: newPath),
                let rootOldPath = location.rootRelativePath(fromRepositoryPath: oldPath)
            else {
                return nil
            }
            return (rootNewPath, rootOldPath)
        }
        return Dictionary(renames, uniquingKeysWith: { first, _ in first })
    }
}
