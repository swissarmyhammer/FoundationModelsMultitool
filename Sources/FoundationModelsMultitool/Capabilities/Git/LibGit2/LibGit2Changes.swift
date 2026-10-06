// `LibGit2Changes` — the change calls of the `LibGit2` layer: the files that a
// branch changed since the merge-base with its parent, and the files of a
// range.
//
// A port of `get_changed_files_from_parent` and `get_changed_files_from_range`
// in `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`. The
// steps are the ones that git.md § "Spike result" proved: `git_merge_base`,
// `git_commit_tree`, and `git_diff_tree_to_tree`.
//
// The rules are the same as the source:
//
// 1. A range is split at its first `..`: `from..to`. A range with no `..` is
//    one ref, and the range is `ref..HEAD`.
// 2. The tree diff has no rename detection. Thus a renamed file is two
//    deltas, and each delta gives its new path: the old path of a removed
//    file, and the new path of an added file.
// 3. The paths come back in path order, one time each.
//
// git.md § "Spike result", the free table: each `git_diff_delta` belongs to
// the diff, thus the layer copies each path before it frees the diff.

import Foundation
import libgit2

extension LibGit2Repository {

    /// The text between the two ends of a range.
    private static let rangeSeparator = ".."

    /// The ref at the end of a range that names one ref only.
    private static let headRevision = "HEAD"

    /// The files that the branch `branch` changed since the merge-base with
    /// the branch `parent`.
    ///
    /// The diff runs from the tree of the merge-base to the tree of the tip
    /// of `branch`. Thus a commit of `parent` after the merge-base does not
    /// put a file in the list.
    ///
    /// - Parameters:
    ///   - branch: The name of the local branch to read.
    ///   - parent: The name of the local branch that `branch` came from.
    /// - Returns: The paths relative to the work folder, in path order.
    /// - Throws: ``LibGit2Error`` when a branch is not a local branch
    ///   (``LibGit2Error/isNotFound``), when the two branches have no history
    ///   in common, or when a tree or the diff cannot be read.
    func changedPaths(onBranch branch: String, sinceMergeBaseWith parent: String) throws(LibGit2Error) -> [String] {
        var branchID = try requiredBranchCommitID(named: branch)
        var parentID = try requiredBranchCommitID(named: parent)
        var mergeBase = git_oid()
        try LibGit2.check(git_merge_base(&mergeBase, handle, &branchID, &parentID))
        return try changedPaths(from: mergeBase, to: branchID)
    }

    /// The files that the range `range` changed.
    ///
    /// - Parameter range: `from..to`, or one ref that is the range
    ///   `ref..HEAD`. Each end is a ref, as `git_revparse_single` reads it.
    /// - Returns: The paths relative to the work folder, in path order, or
    ///   `nil` when an end of the range names no object.
    /// - Throws: ``LibGit2Error`` when an end is not a valid ref, when an end
    ///   does not peel to a commit, or when a tree or the diff cannot be read.
    func changedPaths(inRange range: String) throws(LibGit2Error) -> [String]? {
        let (from, to) = Self.ends(of: range)
        guard let fromID = try commitID(forRevision: from), let toID = try commitID(forRevision: to) else {
            return nil
        }
        return try changedPaths(from: fromID, to: toID)
    }

    // MARK: - Steps

    /// The two ends of a range.
    ///
    /// - Parameter range: `from..to`, or one ref.
    /// - Returns: The text before and after the first `..`, or the ref and
    ///   `HEAD` for a range with no `..`.
    private static func ends(of range: String) -> (from: String, to: String) {
        guard let separator = range.range(of: rangeSeparator) else { return (range, headRevision) }
        return (String(range[..<separator.lowerBound]), String(range[separator.upperBound...]))
    }

    /// The id of the commit that the local branch `name` names, or an error.
    ///
    /// - Parameter name: The branch name, without `refs/heads/`.
    /// - Returns: The id.
    /// - Throws: ``LibGit2Error`` with `GIT_ENOTFOUND` when no local branch
    ///   has that name, or the error of the branch read.
    private func requiredBranchCommitID(named name: String) throws(LibGit2Error) -> git_oid {
        guard let id = try branchCommitID(named: name) else {
            throw LibGit2Error(code: GIT_ENOTFOUND.rawValue, message: "no local branch has the name '\(name)'")
        }
        return id
    }

    /// The files that differ between the trees of two commits.
    ///
    /// - Parameters:
    ///   - oldID: The id of the old commit.
    ///   - newID: The id of the new commit.
    /// - Returns: The new path of each delta, in path order, one time each.
    /// - Throws: ``LibGit2Error`` when a commit, a tree, or the diff cannot be
    ///   read.
    private func changedPaths(from oldID: git_oid, to newID: git_oid) throws(LibGit2Error) -> [String] {
        let oldTree = try tree(ofCommitWithID: oldID)
        defer { git_tree_free(oldTree) }
        let newTree = try tree(ofCommitWithID: newID)
        defer { git_tree_free(newTree) }
        let diff = try LibGit2.makeHandle { diff in git_diff_tree_to_tree(&diff, handle, oldTree, newTree, nil) }
        defer { git_diff_free(diff) }
        let paths = (0..<git_diff_num_deltas(diff)).compactMap { index in
            git_diff_get_delta(diff, index)?.pointee.new_file.path.map { String(cString: $0) }
        }
        return Set(paths).sorted()
    }

    /// The tree of the commit with the id `id`.
    ///
    /// - Parameter id: The id of the commit.
    /// - Returns: The tree. The caller frees it with `git_tree_free`.
    /// - Throws: ``LibGit2Error`` when the commit or its tree cannot be read.
    private func tree(ofCommitWithID id: git_oid) throws(LibGit2Error) -> OpaquePointer {
        try withCommit(id: id) { commit throws(LibGit2Error) in
            try LibGit2.makeHandle { tree in git_commit_tree(&tree, commit) }
        }
    }
}
