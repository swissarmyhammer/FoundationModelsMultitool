// `Branches` — the `tools.git.branches` verb.
//
// git.md § "Verbs": `tools.git.branches` takes no argument, and gives the
// local branches, the current branch, and the main branch. The sources are
// `list_local_branches`, `get_current_branch`, and `main_branch` of
// `swissarmyhammer-git`. The `LibGit2` layer (`LibGit2Branches.swift`) reads
// the branches, and this verb calls only that layer, never the C API (git.md §
// "Decisions", item 10).
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// git capability, in the pattern of `Capabilities/Files/Glob.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `branches`
// and the surface path renders as `tools.git.branches`.
//
// The main branch follows `main_branch` of the source: `main` when that local
// branch exists, else `master`, else none. The source gives an error for none;
// this verb gives `nil`, because a repository with no such branch is a fact,
// not a mistake of the model.
//
// A branch list the verb cannot read stays IN BAND, as a `correction` beside
// no branch. It is never thrown: a root in no repository and a list that
// libgit2 cannot read are each a fact the model reads inside the turn, and a
// thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.git.branches`: none. The verb reads each local
/// branch.
@Generable
struct BranchesArguments {}

/// The result of `tools.git.branches`: the local branches, the current
/// branch, and the main branch, or the correction that says why there is no
/// list.
///
/// `correction` and the branches are exclusive. A list that answers branches
/// carries no correction, and a correction carries no branch.
@Generable(description: "the local branches, the current branch, and the main branch, or the correction that says why there is no list.")
struct BranchesResult {

    /// The names of the local branches, in name order.
    @Guide(description: "The names of the local branches, in name order.")
    var branches: [String]

    /// The branch that HEAD names, or `nil` for a detached HEAD.
    @Guide(
        description:
            "The branch that HEAD names; null when HEAD is detached (it names a commit, not a branch) or the "
            + "repository has no commit.")
    var current: String?

    /// The main branch: `main`, else `master`, else `nil`.
    @Guide(description: "The main branch: main when that branch exists, else master when that branch exists, else null.")
    var main: String?

    /// Why the verb answered no branch, or `nil` when the branches stand.
    @Guide(description: "Why the verb answered no branch; null when the branches stand.")
    var correction: String?
}

extension Branches {

    // MARK: Main branch

    /// The names that can be the main branch, in the order of preference.
    private static let mainBranchCandidates = ["main", "master"]

    // MARK: Corrective text

    /// The description of a branch list that libgit2 could not read, before
    /// the `: <libgit2 error>` suffix.
    private static let failedBranchesDescription = "git branches failed"

    // MARK: Execution

    /// Reads the local branches, or answers the correction that says why
    /// there is no list.
    ///
    /// Checks the repository of the root, then reads the branches through
    /// the `LibGit2` layer. Each recoverable failure comes back as the
    /// `correction` field of the result; nothing here throws.
    ///
    /// - Parameter arguments: None.
    /// - Returns: The branches, or the correction.
    func call(arguments: BranchesArguments) async throws -> BranchesResult {
        context.repository.resolve(corrective: Self.corrective) { location in
            Self.branches(in: location).resolve(corrective: Self.corrective) { $0 }
        }
    }

    // MARK: Steps

    /// Reads the branches through the `LibGit2` layer.
    ///
    /// - Parameter location: The repository of the root.
    /// - Returns: The result with its branches, or the correction for a
    ///   failed read.
    private static func branches(in location: GitRepositoryLocation) -> Result<BranchesResult, CorrectiveRejection> {
        let names: [String]
        let current: String?
        do {
            let repository = try LibGit2Repository(discoveringFrom: location.workDirectory)
            names = try repository.localBranchNames().sorted()
            current = try repository.currentBranchName()
        } catch {
            return .failure(CorrectiveRejection(correctiveMessage: "\(failedBranchesDescription): \(error)"))
        }
        let main = mainBranchCandidates.first { candidate in names.contains(candidate) }
        return .success(BranchesResult(branches: names, current: current, main: main, correction: nil))
    }

    // MARK: Corrective results

    /// A result that carries only a correction: no branch.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``BranchesResult``.
    private static func corrective(_ message: String) -> BranchesResult {
        BranchesResult(branches: [], current: nil, main: nil, correction: message)
    }
}

/// Gives the local branches, the current branch, and the main branch.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { current, main } = await tools.git.branches({});
/// ```
///
/// The contract: the names of the local branches in name order, the branch
/// that HEAD names (`nil` for a detached HEAD and for a repository with no
/// commit), and the main branch (`main`, else `master`, else `nil`). A root in
/// no repository comes back as a `correction`, not as an error.
struct Branches: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.branches`.
    let name = "branches"

    /// The usage instructions, as the model reads them.
    let description = """
        branches gives the names of the local branches in name order, current (the branch that \
        HEAD names; null when HEAD is detached or the repository has no commit), and main (main \
        when that branch exists, else master, else null). A root in no git repository comes back \
        as a correction rather than as an error — read it and act on it.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Branches(context:)`.
    let context: GitContext
}
