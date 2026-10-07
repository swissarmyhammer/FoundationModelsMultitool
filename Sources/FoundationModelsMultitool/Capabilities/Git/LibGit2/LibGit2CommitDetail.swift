// `LibGit2CommitDetail` — the commit detail call of the `LibGit2` layer: the
// full message, the parents, and the line counts of each file that one commit
// changes.
//
// `tools.git.commit` shows the facts of one commit, the same as the `git_show`
// tool of docker-agent. The steps are:
//
// 1. Find the commit that the ref names (`commit(forRevision:)` in
//    `LibGit2Commit.swift`). A ref that names no object gives no detail.
// 2. Diff the tree of the first parent to the tree of the commit
//    (`firstParentDiff(of:limitedTo:)`). A root commit diffs from no tree,
//    thus each of its files is added. A merge commit diffs from its first
//    parent only, the same as `git show --first-parent`.
// 3. Find the renames with `git_diff_find_similar` and
//    `GIT_DIFF_FIND_RENAMES`. The flag is explicit, thus the `diff.renames`
//    setting of the host does not change the result.
// 4. Make one patch for each delta (`git_patch_from_diff`) and count its lines
//    (`git_patch_line_stats`). A binary file has no lines, thus it gives no
//    counts.
//
// The files stay in the order that the diff gives them. Each path is copied
// before the patch and the diff are freed.

import Foundation
import libgit2

/// The detail of one commit: its facts, its full message, its parents, and the
/// files that it changes against its first parent.
struct LibGit2CommitDetail: Equatable, Sendable {

    /// The sha, the author, the date, and the subject of the commit.
    let facts: LibGit2Commit

    /// The full message of the commit (`git_commit_message`): the subject, and
    /// the body after it.
    let message: String

    /// The 40-hex sha of each parent, the first parent first. Empty for a root
    /// commit.
    let parentShas: [String]

    /// The files that the commit changes against its first parent, in the
    /// order of the diff.
    let files: [LibGit2FileStat]
}

/// One file that a commit changes, with its line counts.
struct LibGit2FileStat: Equatable, Sendable {

    /// The path of the file after the commit, relative to the work folder. For
    /// a deleted file, the path before the commit.
    let path: String

    /// The path of the file before the commit, only for a renamed file.
    let oldPath: String?

    /// The change: `added`, `modified`, `deleted`, or `renamed`.
    let status: String

    /// The number of lines that the commit adds to the file, or `nil` for a
    /// binary file.
    let additions: Int?

    /// The number of lines that the commit removes from the file, or `nil` for
    /// a binary file.
    let deletions: Int?
}

extension LibGit2Repository {

    /// The status of a delta that ``statusNames`` does not hold, for example a
    /// change of the file type.
    private static let modifiedStatus = "modified"

    /// The status text of each delta kind that has a name of its own.
    private static let statusNames: [git_delta_t.RawValue: String] = [
        GIT_DELTA_ADDED.rawValue: "added",
        GIT_DELTA_MODIFIED.rawValue: modifiedStatus,
        GIT_DELTA_DELETED.rawValue: "deleted",
        GIT_DELTA_RENAMED.rawValue: "renamed",
    ]

    /// The version of `git_diff_find_options` that this layer fills.
    private static let findOptionsVersion = UInt32(GIT_DIFF_FIND_OPTIONS_VERSION)

    /// Reads the detail of the commit that `revision` names.
    ///
    /// - Parameter revision: A ref, as `git_revparse_single` reads it.
    /// - Returns: The detail, or `nil` when no object has that name.
    /// - Throws: ``LibGit2Error`` when the ref is not valid, when the object
    ///   that it names does not peel to a commit, or when a tree, the diff, or
    ///   a patch cannot be read.
    func commitDetail(forRevision revision: String) throws(LibGit2Error) -> LibGit2CommitDetail? {
        guard let commit = try commit(forRevision: revision) else { return nil }
        defer { git_commit_free(commit) }
        return LibGit2CommitDetail(
            facts: try Self.facts(of: commit),
            message: git_commit_message(commit).map { String(cString: $0) } ?? "",
            parentShas: Self.parentShas(of: commit),
            files: try fileStats(of: commit))
    }

    // MARK: - Steps

    /// The sha of each parent of an open commit, the first parent first.
    ///
    /// - Parameter commit: The open commit.
    /// - Returns: The 40-hex shas.
    private static func parentShas(of commit: OpaquePointer) -> [String] {
        (0..<git_commit_parentcount(commit))
            .compactMap { index in git_commit_parent_id(commit, index) }
            .map { id in String(cString: git_oid_tostr_s(id)) }
    }

    /// The files that an open commit changes against its first parent, with
    /// the renames found.
    ///
    /// - Parameter commit: The open commit.
    /// - Returns: The files, in the order of the diff.
    /// - Throws: ``LibGit2Error`` when a tree, the diff, or a patch cannot be
    ///   read.
    private func fileStats(of commit: OpaquePointer) throws(LibGit2Error) -> [LibGit2FileStat] {
        let diff = try firstParentDiff(of: commit, limitedTo: nil)
        defer { git_diff_free(diff) }
        var options = git_diff_find_options()
        try LibGit2.check(git_diff_find_options_init(&options, Self.findOptionsVersion))
        options.flags = GIT_DIFF_FIND_RENAMES.rawValue
        try LibGit2.check(git_diff_find_similar(diff, &options))
        return try (0..<git_diff_num_deltas(diff)).map { index throws(LibGit2Error) in
            try Self.fileStat(of: diff, at: index)
        }
    }

    /// The file and the line counts of one delta of a diff.
    ///
    /// - Parameters:
    ///   - diff: The diff.
    ///   - index: The index of the delta in the diff.
    /// - Returns: The file and its line counts.
    /// - Throws: ``LibGit2Error`` when the patch cannot be made, or when its
    ///   line counts cannot be read.
    private static func fileStat(of diff: OpaquePointer, at index: Int) throws(LibGit2Error) -> LibGit2FileStat {
        let patch = try LibGit2.makeHandle { patch in git_patch_from_diff(&patch, diff, index) }
        defer { git_patch_free(patch) }
        let delta = git_patch_get_delta(patch).pointee
        let counts = try lineCounts(of: patch, delta: delta)
        return LibGit2FileStat(
            path: String(cString: delta.new_file.path),
            oldPath: delta.status == GIT_DELTA_RENAMED ? String(cString: delta.old_file.path) : nil,
            status: statusNames[delta.status.rawValue] ?? modifiedStatus,
            additions: counts?.additions,
            deletions: counts?.deletions)
    }

    /// The number of lines that a patch adds and removes.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - delta: The delta of the patch. Its binary flag is set when the
    ///     patch loads the content of the file.
    /// - Returns: The counts, or `nil` for a binary file.
    /// - Throws: ``LibGit2Error`` when the counts cannot be read.
    private static func lineCounts(
        of patch: OpaquePointer,
        delta: git_diff_delta
    ) throws(LibGit2Error) -> (additions: Int, deletions: Int)? {
        guard delta.flags & GIT_DIFF_FLAG_BINARY.rawValue == 0 else { return nil }
        var additions = 0
        var deletions = 0
        try LibGit2.check(git_patch_line_stats(nil, &additions, &deletions, patch))
        return (additions, deletions)
    }
}
