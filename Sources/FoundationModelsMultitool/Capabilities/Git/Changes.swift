// `Changes` — the `tools.git.changes` verb.
//
// git.md § "Verbs": `tools.git.changes` takes `branch?` and `range?`, and
// gives `{ branch, parentBranch, range, files }`. The source is the `get
// changes` operation of the MCP tool `git`
// (`swissarmyhammer-tools/src/mcp/tools/git/changes/mod.rs`, `execute`). The
// `LibGit2` layer (`LibGit2MergeTarget.swift`, `LibGit2Changes.swift`) reads
// the parent and the changed files, the shared status reader
// (`GitStatusReader.swift`) reads the uncommitted files, and this verb calls
// only those, never the C API (git.md § "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `changes`
// and the surface path renders as `tools.git.changes`.
//
// The rules are the ones of the source, in this order:
//
// 1. The branch is the `branch` argument, else the branch that HEAD names.
//    The parent is the merge target of the branch; a target that is the
//    branch itself, or no target, is no parent. A detached HEAD names no
//    branch: the verb then reads `HEAD` itself, with no parent.
// 2. `range` is set: the files of that range.
// 3. The branch has a parent: the files that the branch changed since the
//    merge-base with the parent.
// 4. No parent and a clean tree: the files of `HEAD~1..HEAD`. When that range
//    names no commit (a repository with one commit), no file and no range.
// 5. No parent and a dirty tree: no committed file.
// 6. In each case, the uncommitted files (staged, unstaged, renamed, and
//    untracked) are added. The files are sorted, one time each.
//
// Each path is relative to the root, and a file outside the root is in no
// list (git.md § "Decisions", item 8). The clean test of rule 4 reads the same
// status as `tools.git.status`, thus a file outside the root does not make the
// tree dirty.
//
// Three steps differ from the source on purpose. A `branch` that is not a
// local branch is a correction, where the source falls back to the
// uncommitted files (task `^zdb38q4`). A repository with no commit and no
// `branch` argument is a correction, where the source gives an error (task
// `^zdb38q4`). A detached HEAD with no `branch` argument reads `HEAD` itself
// with no parent (task `^8fd3kgk`), where the source takes the short name
// `HEAD` as the name of a branch: a checkout of one commit, as a benchmark
// clone makes, has no branch, and the changes from HEAD are still the answer.
//
// A changes call the verb cannot answer stays IN BAND, as a `correction`
// beside no file. It is never thrown: a bad range, an unknown branch, a root
// in no repository, and a failed read are each a mistake or a fact the model
// reads inside the turn, and a thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.changes`: the branch to read, and the range
/// that takes the place of the parent rule.
@Generable
struct ChangesArguments {

    /// The local branch to read, or `nil` for the branch that HEAD names
    /// (`HEAD` itself for a detached HEAD).
    @Guide(
        description:
            "The local branch to read. Omit it to read the branch that HEAD names, or HEAD itself when HEAD is "
            + "detached.")
    var branch: String?

    /// The range to read in place of the parent rule, or `nil` for the
    /// parent rule.
    @Guide(
        description:
            "A range to read in place of the parent branch: from..to, for example HEAD~1..HEAD, or one ref "
            + "such as HEAD~3, which reads up to HEAD. Omit it to read the changes since the parent branch.")
    var range: String?
}

/// The result of `tools.git.changes`: the files that changed on the branch,
/// or the correction that says why there is no list.
///
/// `correction` and the files are exclusive. A result that answers files
/// carries no correction, and a correction carries no file, no parent, and no
/// range.
@Generable(description: "the files that changed on a branch, or the correction that says why there is no list.")
struct ChangesResult {

    /// The branch that the verb read, `HEAD` for a detached HEAD.
    @Guide(
        description:
            "The branch that the verb read; HEAD when HEAD is detached; empty when the correction came before a "
            + "branch was known.")
    var branch: String

    /// The branch that `branch` merges back to, or `nil` when it has none.
    @Guide(description: "The branch that branch merges back to (its parent branch); null when it has none.")
    var parentBranch: String?

    /// The range whose files the result holds, or `nil` when no range gave
    /// files.
    @Guide(
        description:
            "The range whose files the result holds: the range argument, or HEAD~1..HEAD on a clean branch with "
            + "no parent; null when no range gave files.")
    var range: String?

    /// The changed files and the uncommitted files, in path order.
    @Guide(
        description:
            "The files that changed, relative to the session root, in path order: the committed changes and each "
            + "uncommitted file.")
    var files: [String]

    /// Why the verb answered no list, or `nil` when the files stand.
    @Guide(description: "Why the verb answered no list; null when the files stand.")
    var correction: String?
}

/// The committed part of a changes call: the files and the range that gave
/// them.
private struct CommittedChanges {

    /// The changed files, relative to the work folder.
    let paths: [String]

    /// The range that gave the files, or `nil` when no range gave them.
    let range: String?
}

extension CommittedChanges {

    /// No committed file, and no range.
    static let empty = CommittedChanges(paths: [], range: nil)
}

/// The branch that a changes call reads, and the parent of that branch.
private struct BranchTarget {

    /// The branch that the verb reads: a local branch, or `HEAD` for a
    /// detached HEAD.
    let branch: String

    /// The branch that ``branch`` merges back to, or `nil` when it has none.
    let parent: String?
}

extension Changes {

    // MARK: Ranges

    /// The range of the last commit, which the verb reads on a clean branch
    /// with no parent.
    static let lastCommitRange = "HEAD~1..HEAD"

    // MARK: Corrective text

    /// The description of a read that libgit2 could not make, before the
    /// `: <libgit2 error>` suffix.
    private static let failedChangesDescription = "git changes failed"

    /// The correction for a call with no `branch` argument when HEAD names no
    /// commit: the repository has no commit yet.
    private static let noCommitMessage =
        "HEAD names no commit: the git repository has no commit yet. Commit a file first, or give branch to "
        + "name a local branch to read."

    // MARK: Execution

    /// Reads the files that changed on the branch, or answers the correction
    /// that says why there is no list.
    ///
    /// Checks the repository of the root, reads the uncommitted files through
    /// the shared status reader, then reads the branch, its parent, and the
    /// committed files through the `LibGit2` layer. Each recoverable failure
    /// comes back as the `correction` field of the result; nothing here
    /// throws.
    ///
    /// - Parameter arguments: The branch and the range.
    /// - Returns: The files, or the correction.
    func call(arguments: ChangesArguments) async throws -> ChangesResult {
        let corrective = { (message: String) in Self.corrective(message, branch: arguments.branch) }
        return context.repository.resolve(corrective: corrective) { location in
            context.status().resolve(corrective: corrective) { status in
                Self.changes(for: arguments, status: status, in: location).resolve(corrective: corrective) { $0 }
            }
        }
    }

    // MARK: Steps

    /// Reads the branch, its parent, and the committed files, and adds the
    /// uncommitted files.
    ///
    /// - Parameters:
    ///   - arguments: The branch and the range.
    ///   - status: The uncommitted files below the root.
    ///   - location: The repository of the root.
    /// - Returns: The result with its files, or the correction for a
    ///   repository with no commit, an unknown branch, a bad range, or a
    ///   failed read.
    private static func changes(
        for arguments: ChangesArguments,
        status: GitStatus,
        in location: GitRepositoryLocation
    ) -> Result<ChangesResult, CorrectiveRejection> {
        let repository: LibGit2Repository
        let target: BranchTarget
        do {
            repository = try LibGit2Repository(discoveringFrom: location.workDirectory)
            switch try branchTarget(named: arguments.branch, in: repository) {
            case .success(let found):
                target = found
            case .failure(let rejection):
                return .failure(rejection)
            }
        } catch {
            return .failure(failedReadRejection(error))
        }
        return committedChanges(
            onBranch: target.branch, parent: target.parent, range: arguments.range, isClean: status.isClean,
            in: repository
        ).map { committed in
            let committedFiles = committed.paths.compactMap(location.rootRelativePath(fromRepositoryPath:))
            return ChangesResult(
                branch: target.branch, parentBranch: target.parent, range: committed.range,
                files: Set(committedFiles + status.allFiles).sorted(), correction: nil)
        }
    }

    /// The branch to read and its parent: rule 1.
    ///
    /// The `branch` argument, else the branch that HEAD names. A detached
    /// HEAD names no branch, thus the verb reads HEAD itself, with no parent
    /// (task `^8fd3kgk`).
    ///
    /// - Parameters:
    ///   - argument: The `branch` argument, or `nil`.
    ///   - repository: The open repository.
    /// - Returns: The branch and its parent, or the correction for an unknown
    ///   branch and for a HEAD that names no commit.
    /// - Throws: ``LibGit2Error`` when HEAD, the branch, or the merge target
    ///   cannot be read.
    private static func branchTarget(
        named argument: String?,
        in repository: LibGit2Repository
    ) throws(LibGit2Error) -> Result<BranchTarget, CorrectiveRejection> {
        // `??` takes an autoclosure that drops the typed error, thus the
        // current branch is read in a plain `if`.
        var name = argument
        if name == nil {
            name = try repository.currentBranchName()
        }
        guard let named = name else {
            guard try repository.isHeadDetached() else {
                return .failure(CorrectiveRejection(correctiveMessage: noCommitMessage))
            }
            return .success(BranchTarget(branch: GitContext.defaultRef, parent: nil))
        }
        guard try repository.hasLocalBranch(named: named) else {
            return .failure(CorrectiveRejection(correctiveMessage: unknownBranchMessage(named)))
        }
        return .success(BranchTarget(branch: named, parent: try repository.mergeTarget(forBranch: named)))
    }

    /// The committed files of rules 2 to 5.
    ///
    /// - Parameters:
    ///   - branch: The branch to read.
    ///   - parent: The parent of the branch, or `nil`.
    ///   - range: The range argument, or `nil`.
    ///   - isClean: Whether no file below the root differs from HEAD.
    ///   - repository: The open repository.
    /// - Returns: The committed files and their range, or the correction for
    ///   a bad range or a failed read.
    private static func committedChanges(
        onBranch branch: String,
        parent: String?,
        range: String?,
        isClean: Bool,
        in repository: LibGit2Repository
    ) -> Result<CommittedChanges, CorrectiveRejection> {
        if let range {
            return paths(inRange: range, of: repository).map { paths in CommittedChanges(paths: paths, range: range) }
        }
        if let parent {
            return Result { () throws(LibGit2Error) in
                CommittedChanges(
                    paths: try repository.changedPaths(onBranch: branch, sinceMergeBaseWith: parent), range: nil)
            }
            .mapError(failedReadRejection)
        }
        guard isClean else { return .success(.empty) }
        switch paths(inRange: lastCommitRange, of: repository) {
        case .success(let paths):
            return .success(CommittedChanges(paths: paths, range: lastCommitRange))
        case .failure:
            return .success(.empty)
        }
    }

    /// The files of a range.
    ///
    /// - Parameters:
    ///   - range: The range: `from..to`, or one ref.
    ///   - repository: The open repository.
    /// - Returns: The paths relative to the work folder, or the correction
    ///   for a range that names no commit or that libgit2 cannot read.
    private static func paths(
        inRange range: String,
        of repository: LibGit2Repository
    ) -> Result<[String], CorrectiveRejection> {
        do {
            guard let paths = try repository.changedPaths(inRange: range) else {
                return .failure(CorrectiveRejection(correctiveMessage: unknownRangeMessage(range)))
            }
            return .success(paths)
        } catch {
            return .failure(
                CorrectiveRejection(
                    correctiveMessage: "\(failedChangesDescription): the range `\(range)` cannot be read (\(error))"))
        }
    }

    // MARK: Corrective results

    /// The correction for a branch that is not a local branch.
    ///
    /// - Parameter branch: The branch argument.
    /// - Returns: The correction, which names the branch and the way to find
    ///   a local branch.
    private static func unknownBranchMessage(_ branch: String) -> String {
        "The branch `\(branch)` is not a local branch of the git repository. Give the name of a local branch "
            + "(tools.git.branches lists them), or omit branch to read the branch that HEAD names."
    }

    /// The correction for a range that names no commit.
    ///
    /// - Parameter range: The range argument.
    /// - Returns: The correction, which names the range and the forms that a
    ///   range can take.
    private static func unknownRangeMessage(_ range: String) -> String {
        "The range `\(range)` names no commit in the git repository. Give from..to, for example HEAD~1..HEAD, "
            + "or one ref such as HEAD~3, which reads up to HEAD. Each end is a branch, a tag, a sha, or a form "
            + "such as HEAD~1."
    }

    /// The rejection for a read that libgit2 could not make.
    ///
    /// - Parameter error: The libgit2 error.
    /// - Returns: The rejection, which carries the libgit2 text.
    private static func failedReadRejection(_ error: any Error) -> CorrectiveRejection {
        CorrectiveRejection(correctiveMessage: "\(failedChangesDescription): \(error)")
    }

    /// A result that carries only a correction: no file, no parent, and no
    /// range.
    ///
    /// - Parameters:
    ///   - message: The correction the model reads and acts on.
    ///   - branch: The branch argument, or `nil`. The result names it, thus
    ///     the model sees which branch the correction is about.
    /// - Returns: The corrective ``ChangesResult``.
    private static func corrective(_ message: String, branch: String?) -> ChangesResult {
        ChangesResult(branch: branch ?? "", parentBranch: nil, range: nil, files: [], correction: message)
    }
}

/// Gives the files that changed on a branch.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { parentBranch, files } = await tools.git.changes({});
/// ```
///
/// The contract: the branch (the `branch` argument, else the branch of HEAD,
/// else `HEAD` itself for a detached HEAD), its parent branch, and the files
/// that changed, relative to the root, in path order. A `range` gives the
/// files of that range. With no range, a branch with a parent gives the files
/// since the merge-base with the parent; a clean branch with no parent gives
/// the files of the last commit (``lastCommitRange``); a dirty branch with no
/// parent gives no committed file. Each uncommitted file is added in every
/// case. A bad range, an unknown branch, a repository with no commit, and a
/// root in no repository each come back as a `correction`, not as an error.
struct Changes: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.changes`.
    let name = "changes"

    /// The usage instructions, as the model reads them.
    let description = """
        changes gives the files that changed on a branch, relative to the session root, in path \
        order. branch is the local branch to read; omit it to read the branch that HEAD names, \
        or HEAD itself when HEAD is detached (a checkout of one commit), which has no parent. \
        parentBranch is the branch that it merges back to. With range (from..to, for example \
        HEAD~1..HEAD, or one ref such as HEAD~3, which reads up to HEAD), files are the files of \
        that range. With no range: a branch with a parent gives the files changed since the \
        merge-base with the parent; a clean branch with no parent gives the files of the last \
        commit (range is then \(Changes.lastCommitRange)); a branch with no parent and uncommitted \
        files gives no committed file. Each uncommitted file (staged, unstaged, renamed, or \
        untracked) is in files in every case. A bad range, an unknown branch, a git repository \
        with no commit, and a root in no git repository each come back as a correction rather \
        than as an error — read it, correct the call, and ask again.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Changes(context:)`.
    let context: GitContext
}
