// `LibGit2ListedFiles` — the file listing of the `LibGit2` layer: the files
// that the file listing of the git command line gives with `--cached --others
// --exclude-standard`, read in the process.
//
// The rule of the user: no git command line. In the App Sandbox the
// `/usr/bin/git` shim refuses to run, and a Mac with no developer tools has no
// git. Thus `FileWalker` reads the listing here, through libgit2, and starts
// no child process.
//
// The listing has two parts. Each entry of the index is in it (the `--cached`
// part), also an entry whose file the work folder no longer holds. Each file
// of the work folder that the index does not hold and that the ignore rules
// do not exclude is in it too (the `--others --exclude-standard` part). The
// status list gives that second part: the work folder side only, with each
// file of a new folder as its own entry.
//
// The free rules are the same as in `LibGit2Status.swift`: each index entry
// and each status entry belong to their owner, thus the layer copies each
// path before it frees the owner.

import Foundation
import libgit2

extension LibGit2Repository {

    /// The `git_status_opt_t` flags of the listing: untracked files, and one
    /// entry for each file in a new folder. Ignored files are not in the
    /// list.
    private static let listingStatusFlags =
        GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue

    /// The folder of the repository data (the `.git` folder of a work
    /// folder).
    ///
    /// libgit2 gives the real path of the folder, the same as
    /// ``workDirectory``.
    var repositoryDirectory: URL {
        URL(fileURLWithPath: String(cString: git_repository_path(handle)), isDirectory: true)
    }

    /// The tracked files and the untracked files that the ignore rules do not
    /// exclude.
    ///
    /// The paths of the index come first, in the order of the index. The
    /// untracked paths come next, in the order of libgit2. Each path is in
    /// the list one time.
    ///
    /// - Returns: The paths relative to the work folder.
    /// - Throws: ``LibGit2Error`` when the index or the status cannot be
    ///   read.
    func listedFiles() throws(LibGit2Error) -> [String] {
        var seen = Set<String>()
        return try (indexPaths() + untrackedPaths()).filter { path in seen.insert(path).inserted }
    }

    /// The path of each entry of the index.
    ///
    /// A file with a merge conflict has an entry for each stage, thus its
    /// path can be in this list more than one time.
    ///
    /// - Returns: The paths relative to the work folder, in the order of the
    ///   index.
    /// - Throws: ``LibGit2Error`` when the index cannot be read.
    private func indexPaths() throws(LibGit2Error) -> [String] {
        let index = try LibGit2.makeHandle { index in git_repository_index(&index, handle) }
        defer { git_index_free(index) }
        return (0..<git_index_entrycount(index)).compactMap { position in
            git_index_get_byindex(index, position).flatMap { entry in entry.pointee.path.map { String(cString: $0) } }
        }
    }

    /// The path of each file of the work folder that the index does not hold
    /// and that the ignore rules do not exclude.
    ///
    /// - Returns: The paths relative to the work folder, in the order of
    ///   libgit2 (by path).
    /// - Throws: ``LibGit2Error`` when the status cannot be read.
    private func untrackedPaths() throws(LibGit2Error) -> [String] {
        var options = git_status_options()
        try LibGit2.check(git_status_options_init(&options, Self.statusOptionsVersion))
        options.show = GIT_STATUS_SHOW_WORKDIR_ONLY
        options.flags = Self.listingStatusFlags
        let list = try LibGit2.makeHandle { list in git_status_list_new(&list, handle, &options) }
        defer { git_status_list_free(list) }
        return (0..<git_status_list_entrycount(list)).compactMap { position in
            git_status_byindex(list, position).flatMap { entry in Self.untrackedPath(of: entry.pointee) }
        }
    }

    /// Copies the path of one status entry when the entry is an untracked
    /// file.
    ///
    /// - Parameter entry: The entry, which the status list owns.
    /// - Returns: The path, or `nil` when the entry is not an untracked file.
    private static func untrackedPath(of entry: git_status_entry) -> String? {
        guard entry.status.rawValue & GIT_STATUS_WT_NEW.rawValue != 0,
            let path = entry.index_to_workdir?.pointee.new_file.path
        else {
            return nil
        }
        return String(cString: path)
    }
}
