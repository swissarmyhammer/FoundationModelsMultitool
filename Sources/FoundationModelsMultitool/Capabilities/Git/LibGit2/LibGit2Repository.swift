// `LibGit2Repository` — one open libgit2 repository, and the owner of its
// `git_repository *`.
//
// git.md § "Decisions", item 10: the libgit2 objects are not `Sendable`. Each
// verb opens, uses, and frees them inside one call, and `GitContext` holds
// the path of the repository, not an open handle. Thus this type is a class
// with no `Sendable` conformance: its `deinit` frees the handle one time, when
// the last reference goes, and the compiler stops a handle that tries to
// cross a task boundary.

import Foundation
import libgit2

/// One open libgit2 repository.
///
/// The repository frees its `git_repository *` in `deinit`. Open it, use it,
/// and let it go inside one verb call.
final class LibGit2Repository {

    /// The `git_repository_open_flag_t` set of the search: no flag.
    ///
    /// With no flag, `git_repository_open_ext` searches each parent folder
    /// (no `GIT_REPOSITORY_OPEN_NO_SEARCH`), stops at a file system boundary
    /// (no `GIT_REPOSITORY_OPEN_CROSS_FS`), and does not read the `GIT_DIR`
    /// environment (no `GIT_REPOSITORY_OPEN_FROM_ENV`). Thus the root alone
    /// decides the repository, and not the environment of the host.
    private static let discoveryFlags: UInt32 = 0

    /// The open `git_repository *`. This instance owns it.
    private let handle: OpaquePointer

    /// Opens the repository that contains `directory`.
    ///
    /// The search starts at `directory` and goes up through each parent
    /// folder, the same as the `git` command does (see ``discoveryFlags``).
    /// Thus a subfolder of a work folder opens the repository above it.
    ///
    /// - Parameter directory: The folder to start the search at.
    /// - Throws: ``LibGit2Error`` when libgit2 cannot start, or when no
    ///   repository contains `directory` (``LibGit2Error/isNotFound``), or
    ///   when the repository cannot be opened.
    init(discoveringFrom directory: URL) throws(LibGit2Error) {
        try LibGit2.start()
        handle = try LibGit2.makeHandle { handle in
            git_repository_open_ext(&handle, directory.path, Self.discoveryFlags, nil)
        }
    }

    deinit {
        git_repository_free(handle)
    }

    /// The work folder of the repository, or `nil` for a bare repository.
    ///
    /// libgit2 gives the real path of the folder (for example
    /// `/private/var/...` on macOS). Compare it with a path from `realpath`,
    /// not with a path from `URL.resolvingSymlinksInPath()`, which removes
    /// the `/private` prefix.
    var workDirectory: URL? {
        git_repository_workdir(handle).map { URL(fileURLWithPath: String(cString: $0), isDirectory: true) }
    }
}
