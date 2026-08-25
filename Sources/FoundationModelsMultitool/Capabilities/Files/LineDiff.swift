// `LineDiff` — the one line-level diff in the package: a
// longest-common-subsequence alignment of two line arrays.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// LineDiff.swift`. The type is internal, the same way `PathGuard` and
// `Hashline` beside it are.
//
// eventplan.md § "Consolidation of the siblings": two very different
// consumers need the same alignment, thus it lives here once. `GitPatch`
// renders a change set as unified-diff hunks. The edit engine, which ports
// on a later file-verb card, renders a near-miss as a find-versus-current
// line diff. Both ask the same question — which lines are common, which
// were removed, which were added — thus both get the same answer from the
// same code.
//
// The alignment is the classic dynamic-programming LCS walk, preceded by
// common-prefix trimming (and, when the caller opts in, common-suffix
// trimming). Trimming is what makes a whole-file diff affordable: a typical
// edit shares almost every line with the original, thus the table covers
// only the region that differs. A differing region too large to align (see
// `maximumTableCells`) degrades to "everything removed, everything added",
// which is a correct — if coarse — diff rather than a pathological
// allocation.

import Foundation

/// A longest-common-subsequence alignment of two line arrays.
///
/// See the file header for the port provenance and the two consumers that
/// share this alignment.
enum LineDiff {
    /// One aligned line: which side of the comparison it came from.
    ///
    /// Generic over the element, thus a caller can diff bare line texts or
    /// lines paired with their terminators, whichever equality it needs.
    enum Change<Element: Equatable>: Equatable {
        /// The line is present, identical, in both inputs.
        case unchanged(Element)

        /// The line is present in the first input but absent from the second.
        case removed(Element)

        /// The line is present in the second input but absent from the first.
        case added(Element)
    }

    /// The largest dynamic-programming table the alignment will build, in cells.
    ///
    /// A cell per differing-line pair, thus the bound is on the *product* of
    /// the two differing regions. A region pair past this bound is a wholesale
    /// rewrite whose line-by-line alignment would be unreadable anyway, thus
    /// it degrades to a whole-region replacement instead of an allocation
    /// quadratic in the file size.
    private static let maximumTableCells = 1_000_000

    /// Align `old` against `new`, and report each line as unchanged, removed, or added.
    ///
    /// Common-prefix trimming is invisible: the walk consumes equal leading
    /// elements as unchanged anyway, thus trimming them only shrinks the
    /// table. Common-suffix trimming is **not** invisible — it anchors
    /// trailing matches where the untrimmed walk anchors the earliest match,
    /// thus two inputs that share repeated lines get a different (equally
    /// long, equally valid) alignment. It is therefore opt-in: ``GitPatch``
    /// takes it, because the anchored trailing match keeps a late edit in a
    /// long file from a re-alignment of the whole tail; the edit engine's
    /// near-miss diff does not take it, thus for any differing region within
    /// ``maximumTableCells`` its reported alignment stays exactly what it has
    /// always been. Past that bound the alignment degrades to a whole-region
    /// replacement rather than an allocation quadratic in the file.
    ///
    /// - Parameters:
    ///   - old: the first (left) line array.
    ///   - new: the second (right) line array.
    ///   - trimmingCommonSuffix: whether to anchor the shared trailing lines
    ///     before the alignment; defaults to `false`.
    /// - Returns: the aligned changes, in order; unchanged lines carry the
    ///   element from `old` (equal to the one in `new`).
    static func changes<Element: Equatable>(
        from old: [Element],
        to new: [Element],
        trimmingCommonSuffix: Bool = false
    ) -> [Change<Element>] {
        let prefix = commonPrefixLength(old, new)
        let suffix = trimmingCommonSuffix ? commonSuffixLength(old, new, beyond: prefix) : 0
        let oldMiddle = Array(old[prefix..<(old.count - suffix)])
        let newMiddle = Array(new[prefix..<(new.count - suffix)])
        return old[..<prefix].map { Change.unchanged($0) }
            + alignedMiddle(oldMiddle, newMiddle)
            + old[(old.count - suffix)...].map { Change.unchanged($0) }
    }

    /// The number of leading elements `old` and `new` share.
    ///
    /// - Parameters:
    ///   - old: the first line array.
    ///   - new: the second line array.
    /// - Returns: the shared leading length.
    private static func commonPrefixLength<Element: Equatable>(_ old: [Element], _ new: [Element])
        -> Int
    {
        var length = 0
        while length < old.count, length < new.count, old[length] == new[length] {
            length += 1
        }
        return length
    }

    /// The number of trailing elements `old` and `new` share, without reach back into the common prefix.
    ///
    /// - Parameters:
    ///   - old: the first line array.
    ///   - new: the second line array.
    ///   - prefix: the already-matched common prefix length the suffix must not overlap.
    /// - Returns: the shared trailing length.
    private static func commonSuffixLength<Element: Equatable>(
        _ old: [Element],
        _ new: [Element],
        beyond prefix: Int
    ) -> Int {
        let limit = min(old.count, new.count) - prefix
        var length = 0
        while length < limit, old[old.count - 1 - length] == new[new.count - 1 - length] {
            length += 1
        }
        return length
    }

    /// Align the differing middle regions; degrade to a whole-region replacement past the table bound.
    ///
    /// - Parameters:
    ///   - old: the first region's lines.
    ///   - new: the second region's lines.
    /// - Returns: the aligned changes for the region.
    private static func alignedMiddle<Element: Equatable>(_ old: [Element], _ new: [Element])
        -> [Change<Element>]
    {
        guard old.count * new.count <= maximumTableCells else {
            return old.map { Change.removed($0) } + new.map { Change.added($0) }
        }
        let table = longestCommonSubsequenceTable(old, new)
        var result: [Change<Element>] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count, newIndex < new.count {
            if old[oldIndex] == new[newIndex] {
                result.append(.unchanged(old[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if table[oldIndex + 1][newIndex] >= table[oldIndex][newIndex + 1] {
                result.append(.removed(old[oldIndex]))
                oldIndex += 1
            } else {
                result.append(.added(new[newIndex]))
                newIndex += 1
            }
        }
        result += old[oldIndex...].map { Change.removed($0) }
        result += new[newIndex...].map { Change.added($0) }
        return result
    }

    /// The longest-common-subsequence length table for two line arrays.
    ///
    /// `table[i][j]` is the LCS length of `left[i...]` and `right[j...]`, thus
    /// the alignment can be reconstructed forward from the origin.
    ///
    /// - Parameters:
    ///   - left: the first line array.
    ///   - right: the second line array.
    /// - Returns: a `(left.count + 1)` by `(right.count + 1)` length table.
    private static func longestCommonSubsequenceTable<Element: Equatable>(
        _ left: [Element],
        _ right: [Element]
    ) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
        for i in stride(from: left.count - 1, through: 0, by: -1) {
            for j in stride(from: right.count - 1, through: 0, by: -1) {
                table[i][j] =
                    left[i] == right[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }
}
