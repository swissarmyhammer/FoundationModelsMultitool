// `LibGit2Commit` — the commit calls of the `LibGit2` layer that more than one
// verb uses: find the commit that a ref names, and read the facts of a commit.
//
// `tools.git.blame` reads the author and the date of the commit of each line.
// `tools.git.log` reads the same facts and the subject of each commit that it
// walks. `tools.git.show` and `tools.git.log` find the commit that a ref names,
// and `tools.git.changes` finds the id of the commit at each end of a range.
// `tools.git.log` and `tools.git.commit` diff a commit against its first
// parent. Thus each of these reads is one function here, and no verb file
// holds its own copy.
//
// A ref is any text that `git_revparse_single` reads: a branch, a tag, a full
// or short sha, or a form such as `HEAD~1`. The object that the ref names is
// peeled to its commit, thus a tag that names a commit gives that commit.

import Foundation
import libgit2

/// The facts of one commit that the git verbs show.
struct LibGit2Commit: Equatable, Sendable {

    /// The 40-hex sha of the commit.
    let sha: String

    /// The name of the author of the commit.
    let author: String

    /// The author date of the commit.
    let date: Date

    /// The subject of the commit: the first paragraph of its message, on one
    /// line (`git_commit_summary`).
    let subject: String
}

extension LibGit2Commit {

    /// The form of each date that a verb result writes: ISO 8601 in UTC.
    private static let dateStyle = Date.ISO8601FormatStyle(timeZone: .gmt)

    /// The author date in ISO 8601 (UTC), as each verb result writes it.
    var formattedDate: String {
        Self.dateStyle.format(date)
    }
}

extension LibGit2Repository {

    /// The text of the ``LibGit2Error`` for a commit with no author.
    ///
    /// libgit2 reads the author when it parses a commit, thus a commit that
    /// `git_commit_lookup` gives always has one. The guard stays, thus a later
    /// libgit2 that breaks that promise gives this text and not a crash.
    private static let missingAuthorText = "the commit has no author"

    /// The index of the first parent of a commit, for `git_commit_parent`.
    private static let firstParentIndex: UInt32 = 0

    /// The version of `git_diff_options` that this layer fills.
    private static let diffOptionsVersion = UInt32(GIT_DIFF_OPTIONS_VERSION)

    /// Finds the commit that `revision` names.
    ///
    /// - Parameter revision: A ref, as `git_revparse_single` reads it.
    /// - Returns: The commit, or `nil` when no object has that name
    ///   (`GIT_ENOTFOUND`). The caller frees the commit with
    ///   `git_commit_free`.
    /// - Throws: ``LibGit2Error`` when the ref is not valid, or when the
    ///   object that it names is not a commit and does not peel to one.
    func commit(forRevision revision: String) throws(LibGit2Error) -> OpaquePointer? {
        let object: OpaquePointer
        do {
            object = try LibGit2.makeHandle { object in git_revparse_single(&object, handle, revision) }
        } catch where error.isNotFound {
            return nil
        }
        defer { git_object_free(object) }
        return try LibGit2.makeHandle { commit in git_object_peel(&commit, object, GIT_OBJECT_COMMIT) }
    }

    /// Finds the id of the commit that `revision` names.
    ///
    /// - Parameter revision: A ref, as `git_revparse_single` reads it.
    /// - Returns: The id, or `nil` when no object has that name
    ///   (`GIT_ENOTFOUND`).
    /// - Throws: ``LibGit2Error`` when the ref is not valid, or when the
    ///   object that it names is not a commit and does not peel to one.
    func commitID(forRevision revision: String) throws(LibGit2Error) -> git_oid? {
        guard let commit = try commit(forRevision: revision) else { return nil }
        defer { git_commit_free(commit) }
        return git_commit_id(commit).pointee
    }

    /// Reads the facts of the commit with the id `id`.
    ///
    /// - Parameter id: The id of the commit.
    /// - Returns: The facts of the commit.
    /// - Throws: ``LibGit2Error`` when the commit cannot be read.
    func commitFacts(withID id: git_oid) throws(LibGit2Error) -> LibGit2Commit {
        try withCommit(id: id) { commit throws(LibGit2Error) in try Self.facts(of: commit) }
    }

    /// Opens the commit with the id `id`, runs `body` with it, and frees it.
    ///
    /// - Parameters:
    ///   - id: The id of the commit.
    ///   - body: The work to do with the open commit. The commit is valid
    ///     only inside `body`.
    /// - Returns: The value of `body`.
    /// - Throws: ``LibGit2Error`` when the commit cannot be read, or the
    ///   error of `body`.
    func withCommit<Value>(
        id: git_oid,
        _ body: (_ commit: OpaquePointer) throws(LibGit2Error) -> Value
    ) throws(LibGit2Error) -> Value {
        var id = id
        let commit = try LibGit2.makeHandle { commit in git_commit_lookup(&commit, handle, &id) }
        defer { git_commit_free(commit) }
        return try body(commit)
    }

    /// Reads the facts of an open commit.
    ///
    /// - Parameter commit: The commit. The caller keeps it and frees it.
    /// - Returns: The facts of the commit.
    /// - Throws: ``LibGit2Error`` when the commit has no author.
    static func facts(of commit: OpaquePointer) throws(LibGit2Error) -> LibGit2Commit {
        guard let author = git_commit_author(commit)?.pointee else {
            throw LibGit2Error(code: GIT_ERROR.rawValue, message: missingAuthorText)
        }
        return LibGit2Commit(
            sha: String(cString: git_oid_tostr_s(git_commit_id(commit))),
            author: String(cString: author.name),
            date: Date(timeIntervalSince1970: TimeInterval(author.when.time)),
            subject: git_commit_summary(commit).map { String(cString: $0) } ?? "")
    }

    // MARK: - The first-parent diff

    /// The tree diff from the first parent of `commit` to `commit`.
    ///
    /// A root commit diffs from no tree, thus each of its files is added. A
    /// merge commit diffs from its first parent only.
    ///
    /// - Parameters:
    ///   - commit: The open commit. The caller keeps it and frees it.
    ///   - path: A path relative to the work folder, as a literal path and
    ///     not a glob. The diff keeps only the file at the path, or the files
    ///     below the folder at the path. `nil` keeps each file.
    /// - Returns: The diff. The caller frees it with `git_diff_free`.
    /// - Throws: ``LibGit2Error`` when a tree or the diff cannot be read.
    func firstParentDiff(of commit: OpaquePointer, limitedTo path: String?) throws(LibGit2Error) -> OpaquePointer {
        let tree = try LibGit2.makeHandle { tree in git_commit_tree(&tree, commit) }
        defer { git_tree_free(tree) }
        let parentTree = try firstParentTree(of: commit)
        defer { if let parentTree { git_tree_free(parentTree) } }
        guard let path else {
            return try LibGit2.makeHandle { diff in git_diff_tree_to_tree(&diff, handle, parentTree, tree, nil) }
        }
        return try diff(from: parentTree, to: tree, limitedTo: path)
    }

    /// The tree of the first parent of `commit`.
    ///
    /// - Parameter commit: The open commit.
    /// - Returns: The tree, or `nil` for a root commit. The caller frees it.
    /// - Throws: ``LibGit2Error`` when the parent or its tree cannot be read.
    private func firstParentTree(of commit: OpaquePointer) throws(LibGit2Error) -> OpaquePointer? {
        guard git_commit_parentcount(commit) > 0 else { return nil }
        let parent = try LibGit2.makeHandle { parent in git_commit_parent(&parent, commit, Self.firstParentIndex) }
        defer { git_commit_free(parent) }
        return try LibGit2.makeHandle { tree in git_commit_tree(&tree, parent) }
    }

    /// The tree diff from `oldTree` to `newTree`, limited to one literal path.
    ///
    /// libgit2 copies the pathspec into the diff, thus the C text of `path`
    /// needs to live only for the call.
    ///
    /// - Parameters:
    ///   - oldTree: The old tree, or `nil` for no tree (a root commit).
    ///   - newTree: The new tree.
    ///   - path: The path relative to the work folder.
    /// - Returns: The diff. The caller frees it.
    /// - Throws: ``LibGit2Error`` when the diff cannot be made.
    private func diff(
        from oldTree: OpaquePointer?,
        to newTree: OpaquePointer,
        limitedTo path: String
    ) throws(LibGit2Error) -> OpaquePointer {
        var options = git_diff_options()
        try LibGit2.check(git_diff_options_init(&options, Self.diffOptionsVersion))
        options.flags |= GIT_DIFF_DISABLE_PATHSPEC_MATCH.rawValue
        let diff = path.withCString { text in
            var pathspec: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: text)
            return withUnsafeMutablePointer(to: &pathspec) { strings in
                options.pathspec = git_strarray(strings: strings, count: 1)
                return Result { () throws(LibGit2Error) in
                    try LibGit2.makeHandle { diff in git_diff_tree_to_tree(&diff, handle, oldTree, newTree, &options) }
                }
            }
        }
        return try diff.get()
    }
}
