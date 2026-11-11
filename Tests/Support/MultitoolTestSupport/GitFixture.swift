// `GitFixture` — libgit2 steps that make a repository in a folder that a test
// made already.
//
// The rule of the user: no test starts the `git` binary. `TemporaryGitRepository`
// makes its own temporary folder. Some suites make their files first, in a
// folder that `TestScratch` owns, and then make that folder into a
// repository. These steps are for those suites. They start libgit2 and check
// each call through the `LibGit2` layer of the library, the same as
// `TemporaryGitRepository`.

import Foundation
import libgit2

@testable import FoundationModelsMultitool

/// The libgit2 steps that make a folder into a repository, and that stage its
/// files.
///
/// A namespace, not a value: each step opens the repository, does its work,
/// and frees each libgit2 object before it returns.
enum GitFixture {

    /// The `is_bare` flag value that makes `git_repository_init` write a
    /// repository with a work folder.
    private static let workFolderRepositoryFlag: UInt32 = 0

    /// Makes an empty repository with a work folder in `directory`. The files
    /// that the folder holds already stay, and stay untracked.
    ///
    /// - Parameter directory: The folder that becomes the work folder. It
    ///   must exist.
    /// - Throws: ``LibGit2Error`` when libgit2 cannot make the repository.
    static func initRepository(at directory: URL) throws {
        try LibGit2.start()
        let repository = try LibGit2.makeHandle { repository in
            git_repository_init(&repository, directory.path, workFolderRepositoryFlag)
        }
        git_repository_free(repository)
    }

    /// Adds each file of the work folder that the ignore rules do not
    /// exclude to the index, and writes the index. No commit is made.
    ///
    /// - Parameter directory: The work folder of the repository, or a folder
    ///   in it.
    /// - Throws: ``LibGit2Error`` when no repository contains `directory`, or
    ///   when a libgit2 call fails.
    static func stageAll(in directory: URL) throws {
        let repository = try LibGit2Repository(discoveringFrom: directory)
        let index = try LibGit2.makeHandle { index in git_repository_index(&index, repository.handle) }
        defer { git_index_free(index) }
        try LibGit2.check(git_index_add_all(index, nil, GIT_INDEX_ADD_DEFAULT.rawValue, nil, nil))
        try LibGit2.check(git_index_write(index))
    }
}
