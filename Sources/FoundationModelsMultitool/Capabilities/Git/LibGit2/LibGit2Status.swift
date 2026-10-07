// `LibGit2Status` — the status calls of the `LibGit2` layer: the files of the
// index and of the work folder that differ from HEAD, in four groups.
//
// A port of `get_status` in `../swissarmyhammer/crates/swissarmyhammer-git/
// src/operations.rs`. The options are the same as the source: untracked files
// are in the list, each file in a new folder has its own entry (not one entry
// for the folder), and ignored files are not in the list. One option is new:
// `GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX`, which git.md § "Spike result"
// proved. The source does not find renames, thus its `renamed` bucket stays
// empty; with this option, a staged rename is one renamed file, the same as
// `git status`.
//
// The groups are the four lists of `tools.git.status`. The source has eight
// buckets; each flag of a bucket goes to one group here (see
// ``LibGit2StatusGroup/flags``). A file can be in two groups, for example a
// staged change with a second change that is not staged.
//
// git.md § "Spike result", the free table: each entry and each
// `git_diff_delta` belong to the status list, thus the layer copies each path
// before it frees the list.

import Foundation
import libgit2

/// One group of the files that differ from HEAD.
enum LibGit2StatusGroup: CaseIterable, Sendable {

    /// A change that is in the index: a new, changed, or removed file, or a
    /// changed file type.
    case staged

    /// A change that is in the work folder and not in the index: a changed or
    /// removed file, a changed file type, or a file with a merge conflict.
    ///
    /// A conflicted file is here because the work folder must change before
    /// the file can be staged.
    case unstaged

    /// A file in the work folder that git does not track.
    case untracked

    /// A rename that is in the index. The file has its new path, and
    /// ``LibGit2StatusEntry/oldPath`` holds its old path.
    case renamed

    /// The libgit2 status flags that put a file in this group.
    var flags: UInt32 {
        switch self {
        case .staged:
            GIT_STATUS_INDEX_NEW.rawValue | GIT_STATUS_INDEX_MODIFIED.rawValue
                | GIT_STATUS_INDEX_DELETED.rawValue | GIT_STATUS_INDEX_TYPECHANGE.rawValue
        case .unstaged:
            GIT_STATUS_WT_MODIFIED.rawValue | GIT_STATUS_WT_DELETED.rawValue
                | GIT_STATUS_WT_TYPECHANGE.rawValue | GIT_STATUS_CONFLICTED.rawValue
        case .untracked:
            GIT_STATUS_WT_NEW.rawValue
        case .renamed:
            GIT_STATUS_INDEX_RENAMED.rawValue
        }
    }
}

/// One file that differs from HEAD.
struct LibGit2StatusEntry: Equatable, Sendable {

    /// The path relative to the work folder. For a rename, the new path.
    let path: String

    /// The path relative to the work folder before a staged rename, or `nil`
    /// when the index holds no rename of the file.
    internal let oldPath: String?

    /// The libgit2 status flags of the file (`git_status_t`).
    let flags: UInt32
}

/// The files of the index and of the work folder that differ from HEAD.
struct LibGit2Status: Equatable, Sendable {

    /// The files, in the order of libgit2 (by path).
    let entries: [LibGit2StatusEntry]

    /// The paths of the files in one group.
    ///
    /// - Parameter group: The group.
    /// - Returns: The paths relative to the work folder, in the order of
    ///   ``entries``.
    func paths(in group: LibGit2StatusGroup) -> [String] {
        entries.filter { entry in entry.flags & group.flags != 0 }.map(\.path)
    }

    /// The old path of each staged rename, keyed by its new path. Each path
    /// is relative to the work folder.
    ///
    /// libgit2 gives each new path one time. If two entries have the same
    /// new path, the first entry stands.
    internal var oldPathsOfRenamedFiles: [String: String] {
        Dictionary(
            entries.compactMap { entry in entry.oldPath.map { oldPath in (entry.path, oldPath) } },
            uniquingKeysWith: { first, _ in first })
    }
}

extension LibGit2Repository {

    /// The version of `git_status_options` that this layer fills.
    private static let statusOptionsVersion = UInt32(GIT_STATUS_OPTIONS_VERSION)

    /// The `git_status_opt_t` flags of the status: untracked files, one entry
    /// for each file in a new folder, and staged renames. Ignored files are
    /// not in the list.
    private static let statusFlags =
        GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue
        | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue

    /// The files of the index and of the work folder that differ from HEAD.
    ///
    /// A repository with no commit compares the index with no tree, thus each
    /// staged file is a new file.
    ///
    /// - Returns: The status.
    /// - Throws: ``LibGit2Error`` when the status cannot be read.
    func status() throws(LibGit2Error) -> LibGit2Status {
        var options = git_status_options()
        try LibGit2.check(git_status_options_init(&options, Self.statusOptionsVersion))
        options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        options.flags = Self.statusFlags
        let list = try LibGit2.makeHandle { list in git_status_list_new(&list, handle, &options) }
        defer { git_status_list_free(list) }
        let entries = (0..<git_status_list_entrycount(list)).compactMap { index in
            git_status_byindex(list, index).flatMap { entry in Self.statusEntry(of: entry.pointee) }
        }
        return LibGit2Status(entries: entries)
    }

    /// Copies the paths and the flags of one status entry.
    ///
    /// The path is the new path of the index change, or, when the index has
    /// no change, the new path of the work folder change. libgit2 fills both
    /// paths of a delta, thus a removed file has its path too.
    ///
    /// - Parameter entry: The entry, which the status list owns.
    /// - Returns: The copy, or `nil` for an entry with no delta.
    private static func statusEntry(of entry: git_status_entry) -> LibGit2StatusEntry? {
        guard let delta = entry.head_to_index ?? entry.index_to_workdir, let path = delta.pointee.new_file.path else {
            return nil
        }
        return LibGit2StatusEntry(
            path: String(cString: path), oldPath: renameOldPath(of: entry), flags: entry.status.rawValue)
    }

    /// Copies the old path of a staged rename: the old file of the HEAD to
    /// index delta.
    ///
    /// - Parameter entry: The entry, which the status list owns.
    /// - Returns: The old path, or `nil` when the entry is not a staged
    ///   rename.
    private static func renameOldPath(of entry: git_status_entry) -> String? {
        guard entry.status.rawValue & GIT_STATUS_INDEX_RENAMED.rawValue != 0,
            let oldPath = entry.head_to_index?.pointee.old_file.path
        else {
            return nil
        }
        return String(cString: oldPath)
    }
}
