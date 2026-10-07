// `LibGit2Blame` — the blame calls of the `LibGit2` layer: one attribution
// for each line of a file.
//
// A port of `blame_lines` in `../swissarmyhammer/crates/swissarmyhammer-git/
// src/operations.rs`, and of its `LineBlame` kinds. The algorithm has two
// libgit2 steps, the same as the source:
//
// 1. `git_blame_file` blames the path as of HEAD: the committed history.
// 2. `git_blame_buffer` blames that result again against the content of the
//    file in the work folder. libgit2 gives a line that differs from the
//    committed blob a zero commit id and no signature (`buffer_line_cb` in
//    `blame.c`). That is the "not committed yet" line of `git blame`.
//
// Before step 1, a path that is in neither the index nor the tree of HEAD is
// untracked for each line, and no blame runs. A tracked path that no commit
// holds is uncommitted for each line: step 1 gives `GIT_ENOTFOUND` for a
// staged file that is in no commit. A repository with no commit (HEAD names a
// branch with no commit) gives the generic `GIT_ERROR` in step 1, thus the
// layer looks for that case before step 1. The source documents both cases
// as "not yet blamable", and this layer keeps that contract. Any other
// failure is a `LibGit2Error`; the verb changes it into one correction.
//
// A blame at a revision (the `rev` argument of `tools.git.blame`) has one
// step only: `git_blame_file` with `newest_commit` set to the commit of the
// revision. libgit2 then reads the blob of that commit, not the work folder,
// thus no buffer layer runs. Both kinds of blame read their hunks through one
// shared function.
//
// The author and the date come from the commit (`git_commit_author`, through
// `LibGit2Commit.swift`), not from the hunk. `git_blame_buffer` splits a hunk
// around a changed line, and the second part of the split has the commit id
// but no signature.
//
// git.md § "Spike result", fact 3: the hunks are read with
// `git_blame_hunkcount` and `git_blame_hunk_byindex`, not with the deprecated
// `git_blame_get_*` names.

import Foundation
import libgit2

/// Where one line of a file comes from: the `LineBlame` kinds of the source,
/// less `Failed`, which the layer throws as a ``LibGit2Error``.
enum LibGit2LineBlame: Equatable, Sendable {

    /// A commit holds the line. The payload is the commit that last changed
    /// it.
    case committed(LibGit2Commit)

    /// No commit holds the line: the work folder changed it, or git tracks
    /// the file but no commit holds the file yet.
    case uncommitted

    /// git does not track the file: it is in neither the index nor the tree
    /// of HEAD, thus it has no history.
    case untracked
}

extension LibGit2Repository {

    /// The revision text of the tree of HEAD, which tells whether a commit
    /// holds a path.
    private static let headTreeRevision = "HEAD^{tree}"

    /// The index stage of a file with no merge conflict.
    private static let normalIndexStage = Int32(GIT_INDEX_STAGE_NORMAL.rawValue)

    /// The version of `git_blame_options` that this layer fills.
    private static let blameOptionsVersion = UInt32(GIT_BLAME_OPTIONS_VERSION)

    /// The text of the ``LibGit2Error`` for a revision that names no object.
    private static let unknownRevisionText = "the revision names no commit"

    /// Blames each line of `content`, the text of the file at `path` in the
    /// work folder, against the history of HEAD.
    ///
    /// - Parameters:
    ///   - path: The path of the file relative to the work folder, as libgit2
    ///     reads it (for example `src/a.txt`).
    ///   - content: The bytes of the file in the work folder. They can differ
    ///     from the committed blob.
    ///   - lineCount: The number of lines in `content`, in git's line model
    ///     (split on `\n`; a last line with no `\n` counts).
    /// - Returns: One attribution for each line, never more and never fewer
    ///   than `lineCount`.
    /// - Throws: ``LibGit2Error`` when the blame fails for a reason other than
    ///   an untracked file or a file that no commit holds.
    func blameLines(atPath path: String, content: Data, lineCount: Int) throws(LibGit2Error) -> [LibGit2LineBlame] {
        guard lineCount > 0 else { return [] }
        guard isTracked(path) else { return Array(repeating: .untracked, count: lineCount) }
        guard git_repository_head_unborn(handle) != LibGit2.trueValue else {
            return Array(repeating: .uncommitted, count: lineCount)
        }
        let base: OpaquePointer
        do {
            base = try LibGit2.makeHandle { blame in git_blame_file(&blame, handle, path, nil) }
        } catch where error.isNotFound {
            return Array(repeating: .uncommitted, count: lineCount)
        }
        defer { git_blame_free(base) }
        let layered = try Self.blame(base, against: content)
        defer { git_blame_free(layered) }
        return try attributions(of: layered, lineCount: lineCount)
    }

    /// Blames each line of the file at `path` as the commit that `revision`
    /// names holds it, against the history up to that commit.
    ///
    /// The blame reads the blob of that commit, not the work folder, thus no
    /// line is uncommitted and no line is untracked. A commit after the
    /// commit of `revision` is in no attribution.
    ///
    /// - Parameters:
    ///   - path: The path of the file relative to the work folder, as libgit2
    ///     reads it (for example `src/a.txt`).
    ///   - revision: A ref, as `git_revparse_single` reads it.
    ///   - lineCount: The number of lines in the blob of that commit, in
    ///     git's line model (split on `\n`; a last line with no `\n` counts).
    /// - Returns: One attribution for each line, never more and never fewer
    ///   than `lineCount`.
    /// - Throws: ``LibGit2Error`` with `GIT_ENOTFOUND` when `revision` names
    ///   no object, and ``LibGit2Error`` when the ref is not valid, when the
    ///   commit holds no file at `path`, or when the blame fails.
    func blameLines(atPath path: String, revision: String, lineCount: Int) throws(LibGit2Error) -> [LibGit2LineBlame] {
        guard lineCount > 0 else { return [] }
        guard let commitID = try commitID(forRevision: revision) else {
            throw LibGit2Error(code: GIT_ENOTFOUND.rawValue, message: Self.unknownRevisionText)
        }
        var options = git_blame_options()
        try LibGit2.check(git_blame_options_init(&options, Self.blameOptionsVersion))
        options.newest_commit = commitID
        let blame = try LibGit2.makeHandle { blame in git_blame_file(&blame, handle, path, &options) }
        defer { git_blame_free(blame) }
        return try attributions(of: blame, lineCount: lineCount)
    }

    // MARK: - Tracked paths

    /// Whether git tracks `path`: the index holds it, or the tree of HEAD
    /// holds it.
    ///
    /// The same as `path_is_tracked` of the source, which answers `false`
    /// when it cannot read the index or HEAD. A repository with no commit has
    /// no tree of HEAD, thus only the index can hold its files.
    ///
    /// - Parameter path: The path relative to the work folder.
    /// - Returns: `true` when git tracks the path.
    private func isTracked(_ path: String) -> Bool {
        isInIndex(path) || isInHeadTree(path)
    }

    /// Whether the index holds `path` with no merge conflict.
    ///
    /// - Parameter path: The path relative to the work folder.
    /// - Returns: `true` when the index holds the path; `false` too when the
    ///   index cannot be read.
    private func isInIndex(_ path: String) -> Bool {
        guard let index = try? LibGit2.makeHandle({ index in git_repository_index(&index, handle) }) else {
            return false
        }
        defer { git_index_free(index) }
        return git_index_get_bypath(index, path, Self.normalIndexStage) != nil
    }

    /// Whether the tree of HEAD holds `path`.
    ///
    /// - Parameter path: The path relative to the work folder.
    /// - Returns: `true` when the tree holds the path; `false` too when HEAD
    ///   has no commit.
    private func isInHeadTree(_ path: String) -> Bool {
        guard let tree = try? LibGit2.makeHandle({ tree in git_revparse_single(&tree, handle, Self.headTreeRevision) })
        else { return false }
        defer { git_object_free(tree) }
        guard let entry = try? LibGit2.makeHandle({ entry in git_object_lookup_bypath(&entry, tree, path, GIT_OBJECT_ANY) })
        else { return false }
        git_object_free(entry)
        return true
    }

    // MARK: - Hunks

    /// Blames `base` again against `content`.
    ///
    /// - Parameters:
    ///   - base: The blame of the committed history (`git_blame_file`).
    ///   - content: The bytes of the file in the work folder.
    /// - Returns: The layered blame. The caller frees it.
    /// - Throws: ``LibGit2Error`` when `git_blame_buffer` fails.
    private static func blame(_ base: OpaquePointer, against content: Data) throws(LibGit2Error) -> OpaquePointer {
        let layered = content.withUnsafeBytes { bytes in
            Result { () throws(LibGit2Error) in
                try LibGit2.makeHandle { blame in
                    git_blame_buffer(&blame, base, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count)
                }
            }
        }
        return try layered.get()
    }

    /// One attribution for each line, from the hunks of `blame`.
    ///
    /// A line that no hunk covers is uncommitted, the same as the source: the
    /// source does not stop on a line that has no hunk.
    ///
    /// - Parameters:
    ///   - blame: The layered blame, or the blame at a revision.
    ///   - lineCount: The number of lines.
    /// - Returns: One attribution for each line.
    /// - Throws: ``LibGit2Error`` when the commit of a hunk cannot be read.
    private func attributions(of blame: OpaquePointer, lineCount: Int) throws(LibGit2Error) -> [LibGit2LineBlame] {
        var lines = Array(repeating: LibGit2LineBlame.uncommitted, count: lineCount)
        var commits: [String: LibGit2Commit] = [:]
        for index in 0..<git_blame_hunkcount(blame) {
            guard let hunk = git_blame_hunk_byindex(blame, index)?.pointee else { continue }
            let first = Int(hunk.final_start_line_number) - 1
            let end = min(first + Int(hunk.lines_in_hunk), lineCount)
            guard first >= 0, first < end else { continue }
            let attribution = try attribution(of: hunk, commits: &commits)
            lines.replaceSubrange(first..<end, with: repeatElement(attribution, count: end - first))
        }
        return lines
    }

    /// The attribution of the lines of one hunk.
    ///
    /// - Parameters:
    ///   - hunk: The hunk.
    ///   - commits: The commits that this blame read before, by sha. Many
    ///     hunks name one commit, thus each commit is read one time.
    /// - Returns: The commit of the hunk, or `uncommitted` for the zero commit
    ///   id that `git_blame_buffer` gives to a line that is not committed.
    /// - Throws: ``LibGit2Error`` when the commit cannot be read.
    private func attribution(
        of hunk: git_blame_hunk,
        commits: inout [String: LibGit2Commit]
    ) throws(LibGit2Error) -> LibGit2LineBlame {
        var commitID = hunk.final_commit_id
        guard git_oid_is_zero(&commitID) != LibGit2.trueValue else { return .uncommitted }
        let sha = String(cString: git_oid_tostr_s(&commitID))
        if let commit = commits[sha] { return .committed(commit) }
        let commit = try commitFacts(withID: commitID)
        commits[sha] = commit
        return .committed(commit)
    }
}
