// `LibGit2MergeTarget` — the merge-target call of the `LibGit2` layer: the
// local branch that a branch merges back to (its parent branch).
//
// A port of `find_merge_target_for_issue` in
// `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`, with its
// steps `collect_candidate_branches`, `find_best_scoring_branch`,
// `score_candidate`, `find_merge_base_with_time`, `compute_merge_score`, and
// `count_commits_between`. The rules are the ones of the source, in this
// order:
//
// 1. The candidates are the local branches, in the order of libgit2, except
//    the branch itself. When the branch name holds a `/`, a branch with the
//    same first name part (for example `issue/` for `issue/42`) is a sibling,
//    not a candidate.
// 2. A candidate gets no score when its commit or the merge-base commit cannot
//    be read, or when it has no merge-base with the branch (no history in
//    common).
// 3. The score of a candidate is the sum of three parts:
//    - distance: max(1000 − d, 0) × 1000, where d is the number of commits
//      from the merge-base to the tip of the branch;
//    - perfect match: 100 when the merge-base is the tip of the candidate;
//    - recency: the committer time of the merge-base in seconds, ÷ 1000.
// 4. The first candidate with the highest score wins. Its score must be above
//    0.
// 5. No candidate with a score while there are candidates: no target (an
//    orphan branch).
// 6. No candidate at all: the main branch (`main`, else `master`). When there
//    is no main branch, or the main branch is the branch itself: no target.
//
// The source gives an error where this layer gives `nil` (rules 5 and 6, and
// a branch that is not a local branch), and its caller reads each error as
// "no parent". The caller of this layer reads `nil` the same way.
//
// One step differs from the source on purpose. When the source cannot count
// the commits of rule 3, it takes the largest count as the distance, and a
// type conversion makes that count −1, which then gets the best distance
// score. The comment of the source says that such a candidate counts as
// unrelated, thus this layer gives it a distance score of 0.
//
// A real behavior of the source that the port keeps: on `main`, a branch whose
// tip is in the history of `main` is a candidate with a perfect match, thus it
// is the target of `main`.

import Foundation
import libgit2

extension LibGit2Repository {

    /// The separator between the parts of a branch name.
    private static let branchNameSeparator: Character = "/"

    /// The commit count from which a candidate is unrelated: its distance
    /// score is 0.
    private static let maximumDistance: Int64 = 1000

    /// The weight of the distance score, thus the distance outweighs the
    /// other parts of the score.
    private static let distanceWeight: Int64 = 1000

    /// The score bonus when the merge-base is the tip of the candidate.
    private static let perfectMatchBonus: Int64 = 100

    /// The divisor that makes the committer time of the merge-base (in
    /// seconds) a small part of the score.
    private static let recencyDivisor: Int64 = 1000

    /// The local branch that `branch` merges back to.
    ///
    /// The rules are in the header of this file.
    ///
    /// - Parameter branch: The name of the local branch.
    /// - Returns: The name of the target branch, or `nil` when the branch has
    ///   no target: it is not a local branch, it is an orphan, or it is the
    ///   main branch with no other branch.
    /// - Throws: ``LibGit2Error`` when the branch or the list of branches
    ///   cannot be read.
    func mergeTarget(forBranch branch: String) throws(LibGit2Error) -> String? {
        guard let branchID = try branchCommitID(named: branch) else { return nil }
        let names = try localBranchNames()
        let candidates = Self.candidates(among: names, forBranch: branch)
        if let best = bestCandidate(among: candidates, forCommit: branchID) { return best }
        guard candidates.isEmpty, let main = Self.mainBranchName(among: names), main != branch else { return nil }
        return main
    }

    // MARK: - Steps

    /// The candidates of rule 1: each name except the branch and its
    /// siblings.
    ///
    /// - Parameters:
    ///   - names: The names of the local branches, in the order of libgit2.
    ///   - branch: The name of the branch.
    /// - Returns: The candidates, in the order of `names`.
    private static func candidates(among names: [String], forBranch branch: String) -> [String] {
        let siblingPrefix = branch.firstIndex(of: branchNameSeparator).map { separator in
            String(branch[...separator])
        }
        return names.filter { name in
            name != branch && !(siblingPrefix.map { prefix in name.hasPrefix(prefix) } ?? false)
        }
    }

    /// The candidate with the highest score (rules 2 to 4).
    ///
    /// - Parameters:
    ///   - candidates: The candidates, in the order of libgit2.
    ///   - branchID: The id of the commit at the tip of the branch.
    /// - Returns: The first candidate with the highest score above 0, or
    ///   `nil` when no candidate has such a score.
    private func bestCandidate(among candidates: [String], forCommit branchID: git_oid) -> String? {
        var best: (name: String, score: Int64)?
        for name in candidates {
            guard let score = score(ofCandidate: name, forCommit: branchID), score > best?.score ?? 0 else {
                continue
            }
            best = (name, score)
        }
        return best?.name
    }

    /// The score of one candidate (rules 2 and 3).
    ///
    /// The source reads the commit of the candidate and the merge-base
    /// leniently: a candidate that it cannot read gets no score. This step
    /// does the same, thus a failed read of the candidate gives `nil`.
    ///
    /// - Parameters:
    ///   - candidate: The name of the candidate branch.
    ///   - branchID: The id of the commit at the tip of the branch.
    /// - Returns: The score, or `nil` when the candidate or the merge-base
    ///   cannot be read, or when the candidate has no merge-base with the
    ///   branch.
    private func score(ofCandidate candidate: String, forCommit branchID: git_oid) -> Int64? {
        guard var targetID = try? branchCommitID(named: candidate) else { return nil }
        var branchID = branchID
        var mergeBase = git_oid()
        guard git_merge_base(&mergeBase, handle, &branchID, &targetID) == GIT_OK.rawValue,
            let mergeBaseTime = try? withCommit(id: mergeBase, { commit in Int64(git_commit_time(commit)) })
        else {
            return nil
        }
        return Self.mergeScore(
            distance: try? commitCount(from: mergeBase, to: branchID),
            isPerfectMatch: git_oid_equal(&mergeBase, &targetID) == LibGit2.trueValue,
            mergeBaseTime: mergeBaseTime)
    }

    /// The score of rule 3.
    ///
    /// - Parameters:
    ///   - distance: The number of commits from the merge-base to the tip of
    ///     the branch, or `nil` when it cannot be counted. An unknown count
    ///     gives a distance score of 0.
    ///   - isPerfectMatch: Whether the merge-base is the tip of the candidate.
    ///   - mergeBaseTime: The committer time of the merge-base, in seconds.
    /// - Returns: The score.
    private static func mergeScore(distance: Int?, isPerfectMatch: Bool, mergeBaseTime: Int64) -> Int64 {
        let distanceScore = distance.map { count in max(maximumDistance - Int64(count), 0) * distanceWeight } ?? 0
        let perfectMatchScore = isPerfectMatch ? perfectMatchBonus : 0
        return distanceScore + perfectMatchScore + mergeBaseTime / recencyDivisor
    }

    /// The number of commits that `tip` reaches and `base` does not.
    ///
    /// - Parameters:
    ///   - base: The id of the older commit, which the walk hides.
    ///   - tip: The id of the newer commit, which the walk starts at.
    /// - Returns: The number of commits.
    /// - Throws: ``LibGit2Error`` when the walk fails.
    private func commitCount(from base: git_oid, to tip: git_oid) throws(LibGit2Error) -> Int {
        var base = base
        var tip = tip
        let walk = try LibGit2.makeHandle { walk in git_revwalk_new(&walk, handle) }
        defer { git_revwalk_free(walk) }
        try LibGit2.check(git_revwalk_push(walk, &tip))
        try LibGit2.check(git_revwalk_hide(walk, &base))
        var count = 0
        var id = git_oid()
        var status = git_revwalk_next(&id, walk)
        while status != GIT_ITEROVER.rawValue {
            try LibGit2.check(status)
            count += 1
            status = git_revwalk_next(&id, walk)
        }
        return count
    }
}
