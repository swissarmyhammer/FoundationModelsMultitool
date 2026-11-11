// `GitFixture` — the libgit2 steps that make a repository and that stage its
// files, for the test helpers.
//
// The rule of the user: no test starts the `git` binary. `TemporaryGitRepository`
// makes its own temporary folder. Some suites make their files first, in a
// folder that `TestScratch` owns, and then make that folder into a
// repository. These steps are for those suites, and `TemporaryGitRepository`
// uses the same steps, thus the two helpers make and stage a repository with
// one implementation. The steps start libgit2 and check each call through the
// `LibGit2` layer of the library.

import Foundation
import libgit2

@testable import FoundationModelsMultitool

/// The libgit2 steps that make a folder into a repository, and that stage its
/// files.
///
/// A namespace, not a value: each step that opens the repository frees each
/// libgit2 object before it returns.
enum GitFixture {

    /// The `is_bare` flag value that makes `git_repository_init` write a
    /// repository with a work folder.
    private static let workFolderRepositoryFlag: UInt32 = 0

    /// The commit id that ``addGitlink(at:in:)`` records. A gitlink names a
    /// commit of another repository, thus no object of this repository must
    /// have the id.
    private static let gitlinkCommitID = "0123456789abcdef0123456789abcdef01234567"

    /// Makes an empty repository with a work folder in `directory`. The files
    /// that the folder holds already stay, and stay untracked.
    ///
    /// - Parameter directory: The folder that becomes the work folder. It
    ///   must exist.
    /// - Throws: ``LibGit2Error`` when libgit2 cannot make the repository.
    static func initRepository(at directory: URL) throws {
        git_repository_free(try makeRepository(at: directory))
    }

    /// Starts libgit2, and makes an empty repository with a work folder in
    /// `directory`.
    ///
    /// - Parameter directory: The folder that becomes the work folder. It
    ///   must exist.
    /// - Returns: The repository. The caller owns it and frees it.
    /// - Throws: ``LibGit2Error`` when libgit2 cannot make the repository.
    static func makeRepository(at directory: URL) throws(LibGit2Error) -> OpaquePointer {
        try LibGit2.start()
        return try LibGit2.makeHandle { repository in
            git_repository_init(&repository, directory.path, workFolderRepositoryFlag)
        }
    }

    /// Stages each change of the work folder, and writes the index. No commit
    /// is made.
    ///
    /// - Parameter directory: The work folder of the repository, or a folder
    ///   in it.
    /// - Throws: ``LibGit2Error`` when no repository contains `directory`, or
    ///   when a libgit2 call fails.
    static func stageAll(in directory: URL) throws {
        try LibGit2Repository(discoveringFrom: directory).withIndex(stageWorkFolder(in:))
    }

    /// Adds each new and changed file of the work folder that the ignore
    /// rules do not exclude to `index`, removes each file that the work
    /// folder no longer holds, and writes the index.
    ///
    /// - Parameter index: The open index of the repository. The caller keeps
    ///   it and frees it.
    /// - Throws: ``LibGit2Error`` when a libgit2 call fails.
    static func stageWorkFolder(in index: OpaquePointer) throws(LibGit2Error) {
        try LibGit2.check(git_index_add_all(index, nil, GIT_INDEX_ADD_DEFAULT.rawValue, nil, nil))
        try LibGit2.check(git_index_update_all(index, nil, nil, nil))
        try LibGit2.check(git_index_write(index))
    }

    /// Adds a gitlink entry (the index entry of a submodule) at `path` to the
    /// index, and writes the index. The work folder does not change.
    ///
    /// - Parameters:
    ///   - path: The path of the entry, relative to the work folder.
    ///   - directory: The work folder of the repository, or a folder in it.
    /// - Throws: ``LibGit2Error`` when no repository contains `directory`, or
    ///   when a libgit2 call fails.
    static func addGitlink(at path: String, in directory: URL) throws {
        var commitID = git_oid()
        try LibGit2.check(git_oid_fromstr(&commitID, gitlinkCommitID))
        try LibGit2Repository(discoveringFrom: directory).withIndex { index throws(LibGit2Error) in
            try LibGit2.check(
                path.withCString { cPath in
                    var entry = git_index_entry()
                    entry.path = cPath
                    entry.mode = GIT_FILEMODE_COMMIT.rawValue
                    entry.id = commitID
                    return git_index_add(index, &entry)
                })
            try LibGit2.check(git_index_write(index))
        }
    }
}
