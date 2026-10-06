// `LibGit2Branches` — the branch calls of the `LibGit2` layer: the names of the
// local branches, and the branch that HEAD names.
//
// A port of `list_local_branches` and `get_current_branch` in
// `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`. The steps
// are the ones that git.md § "Spike result" proved: `git_branch_iterator_new`,
// `git_branch_next` until `GIT_ITEROVER`, `git_branch_name`, and
// `git_repository_head`.
//
// One step differs from the source. The source gives the short name of HEAD,
// and that name is `HEAD` for a detached HEAD. This layer gives no branch for
// a detached HEAD: it reads the name only when HEAD is a branch
// (`git_reference_is_branch`). A HEAD that names a branch with no commit (a
// new repository) gives no branch, the same as the source.
//
// git.md § "Spike result", the free table: the text of `git_branch_name`
// belongs to the reference, thus the layer copies it before it frees the
// reference.

import Foundation
import libgit2

extension LibGit2Repository {

    /// The text of the ``LibGit2Error`` for a branch with no name.
    ///
    /// `git_branch_name` gives a name for each local branch. The guard stays,
    /// thus a later libgit2 that breaks that promise gives this text and not
    /// a crash.
    private static let missingBranchNameText = "the branch has no name"

    /// The names of the local branches, in the order of libgit2.
    ///
    /// - Returns: The names, without `refs/heads/`. Empty for a repository
    ///   with no commit.
    /// - Throws: ``LibGit2Error`` when the branches cannot be read.
    func localBranchNames() throws(LibGit2Error) -> [String] {
        let iterator = try LibGit2.makeHandle { iterator in git_branch_iterator_new(&iterator, handle, GIT_BRANCH_LOCAL) }
        defer { git_branch_iterator_free(iterator) }
        var names: [String] = []
        while let branch = try Self.nextBranch(of: iterator) {
            defer { git_reference_free(branch) }
            names.append(try Self.name(ofBranch: branch))
        }
        return names
    }

    /// The name of the branch that HEAD names.
    ///
    /// - Returns: The name, without `refs/heads/`, or `nil` for a detached
    ///   HEAD and for a HEAD that names a branch with no commit.
    /// - Throws: ``LibGit2Error`` when HEAD cannot be read.
    func currentBranchName() throws(LibGit2Error) -> String? {
        let head: OpaquePointer
        do {
            head = try LibGit2.makeHandle { head in git_repository_head(&head, handle) }
        } catch where error.code == GIT_EUNBORNBRANCH.rawValue {
            return nil
        }
        defer { git_reference_free(head) }
        guard git_reference_is_branch(head) == LibGit2.trueValue else { return nil }
        return try Self.name(ofBranch: head)
    }

    // MARK: - Steps

    /// The next branch of a branch iterator.
    ///
    /// - Parameter iterator: The iterator.
    /// - Returns: The branch, or `nil` at the end. The caller frees the
    ///   branch.
    /// - Throws: ``LibGit2Error`` when the next branch cannot be read.
    private static func nextBranch(of iterator: OpaquePointer) throws(LibGit2Error) -> OpaquePointer? {
        do {
            return try LibGit2.makeHandle { branch in
                var type = GIT_BRANCH_LOCAL
                return git_branch_next(&branch, &type, iterator)
            }
        } catch where error.code == GIT_ITEROVER.rawValue {
            return nil
        }
    }

    /// The name of a branch.
    ///
    /// - Parameter branch: The reference of the branch. The caller keeps it
    ///   and frees it.
    /// - Returns: A copy of the name, without `refs/heads/`.
    /// - Throws: ``LibGit2Error`` when the reference is not a branch, or has
    ///   no name.
    private static func name(ofBranch branch: OpaquePointer) throws(LibGit2Error) -> String {
        var name: UnsafePointer<CChar>?
        try LibGit2.check(git_branch_name(&name, branch))
        guard let name else { throw LibGit2Error(code: GIT_ERROR.rawValue, message: missingBranchNameText) }
        return String(cString: name)
    }
}
