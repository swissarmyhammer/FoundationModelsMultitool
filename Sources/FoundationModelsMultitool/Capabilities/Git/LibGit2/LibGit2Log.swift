// `LibGit2Log` — the log calls of the `LibGit2` layer: the commits that a ref
// reaches, newest first, with a limit and an optional path filter.
//
// git.md § "Verbs": `tools.git.log` is a new verb (a revwalk); the source MCP
// tool has no log. The steps are the ones that the spike proved (git.md §
// "Spike result"):
//
// 1. `git_revwalk_new`, sorted topological and by time, pushed at the commit
//    that the ref names (`LibGit2Commit.swift`). Thus a commit comes before
//    each of its parents, and the newest commit comes first.
// 2. For a path filter, a tree diff from the first parent to the commit with
//    `git_diff_options.pathspec` (`firstParentDiff(of:limitedTo:)` in
//    `LibGit2Commit.swift`). A commit with no delta does not change the
//    path, and the walk goes on past it. A root commit diffs from no tree. A
//    merge commit diffs from its first parent only. Thus a merge that brings
//    in a change of the path from its second parent is in the log too. The
//    `git` command does not show that merge by default (history
//    simplification), but the commit that made the change is in both logs.
//
// The pathspec has `GIT_DIFF_DISABLE_PATHSPEC_MATCH`: the path is a literal
// path, not a glob, thus a `*` in a file name matches only that name. A folder
// path still matches each file below the folder.
//
// The walk reads one commit more than the limit. That commit tells whether
// more commits stand behind the limit, and the layer does not give it.

import Foundation
import libgit2

/// The commits of one log, newest first.
struct LibGit2Log: Equatable, Sendable {

    /// The commits, newest first, at most the limit.
    let commits: [LibGit2Commit]

    /// Whether more commits that match stand behind the last one, thus the
    /// limit cut the log.
    let hasMore: Bool
}

extension LibGit2Repository {

    /// The sort of the walk: each commit before its parents, and the newest
    /// first.
    private static let newestFirstSorting = GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue

    /// The commits that `revision` reaches, newest first.
    ///
    /// - Parameters:
    ///   - revision: A ref, as `git_revparse_single` reads it.
    ///   - path: A path relative to the work folder, as libgit2 reads it. Only
    ///     the commits that change the file at the path, or a file below the
    ///     folder at the path, go into the log. `nil` keeps each commit.
    ///   - limit: The largest number of commits in the log.
    /// - Returns: The log, or `nil` when the ref names no object.
    /// - Throws: ``LibGit2Error`` when the ref is not valid, when the object
    ///   that it names does not peel to a commit, or when the walk fails.
    func log(fromRevision revision: String, touching path: String?, limit: Int) throws(LibGit2Error) -> LibGit2Log? {
        guard let start = try commit(forRevision: revision) else { return nil }
        var startID = git_commit_id(start).pointee
        git_commit_free(start)
        let walk = try LibGit2.makeHandle { walk in git_revwalk_new(&walk, handle) }
        defer { git_revwalk_free(walk) }
        try LibGit2.check(git_revwalk_sorting(walk, Self.newestFirstSorting))
        try LibGit2.check(git_revwalk_push(walk, &startID))
        let commits = try commits(of: walk, touching: path, upTo: limit + 1)
        return LibGit2Log(commits: Array(commits.prefix(limit)), hasMore: commits.count > limit)
    }

    // MARK: - The walk

    /// Reads the commits of a walk until it ends or holds `count` commits.
    ///
    /// - Parameters:
    ///   - walk: The walk, sorted and pushed.
    ///   - path: The path that each commit must change, or `nil`.
    ///   - count: The largest number of commits to read.
    /// - Returns: The commits, in the order of the walk.
    /// - Throws: ``LibGit2Error`` when the walk or a commit read fails.
    private func commits(
        of walk: OpaquePointer,
        touching path: String?,
        upTo count: Int
    ) throws(LibGit2Error) -> [LibGit2Commit] {
        var commits: [LibGit2Commit] = []
        var id = git_oid()
        while commits.count < count {
            let status = git_revwalk_next(&id, walk)
            guard status != GIT_ITEROVER.rawValue else { break }
            try LibGit2.check(status)
            if let commit = try facts(ofCommitWithID: id, touching: path) { commits.append(commit) }
        }
        return commits
    }

    /// The facts of one commit of the walk, when it passes the path filter.
    ///
    /// - Parameters:
    ///   - id: The id of the commit.
    ///   - path: The path that the commit must change, or `nil`.
    /// - Returns: The facts, or `nil` when the commit does not change `path`.
    /// - Throws: ``LibGit2Error`` when the commit or its trees cannot be read.
    private func facts(ofCommitWithID id: git_oid, touching path: String?) throws(LibGit2Error) -> LibGit2Commit? {
        try withCommit(id: id) { commit throws(LibGit2Error) in
            if let path, try !changes(commit, path: path) { return nil }
            return try Self.facts(of: commit)
        }
    }

    // MARK: - The path filter

    /// Whether `commit` changes the file at `path`, or a file below the folder
    /// at `path`, against its first parent.
    ///
    /// - Parameters:
    ///   - commit: The open commit.
    ///   - path: The path relative to the work folder.
    /// - Returns: `true` when the tree diff has a delta.
    /// - Throws: ``LibGit2Error`` when a tree or the diff cannot be read.
    private func changes(_ commit: OpaquePointer, path: String) throws(LibGit2Error) -> Bool {
        let diff = try firstParentDiff(of: commit, limitedTo: path)
        defer { git_diff_free(diff) }
        return git_diff_num_deltas(diff) > 0
    }
}
