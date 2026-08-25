import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the shared ``LineDiff`` line alignment.
///
/// This suite is a port of the sibling FileTool suite. Two callers use the
/// same alignment: ``GitPatch`` renders a change set as unified-diff hunks,
/// and the edit engine (which ports on a later file-verb card) renders a
/// near-miss as a find-versus-current diff. Only the patch renderer opts
/// into common-suffix trimming. When the two sides share repeated lines,
/// trimming selects a different — equally long, equally valid — alignment.
/// These cases pin both alignments, thus neither can drift into the other.
@Suite struct LineDiffTests {
    // MARK: Alignment

    @Test func identicalInputsAreAllUnchanged() {
        #expect(
            LineDiff.changes(from: ["a", "b"], to: ["a", "b"]) == [.unchanged("a"), .unchanged("b")]
        )
    }

    @Test func anEmptyOldSideIsAllAdditions() {
        #expect(LineDiff.changes(from: [], to: ["a", "b"]) == [.added("a"), .added("b")])
    }

    @Test func anEmptyNewSideIsAllRemovals() {
        #expect(LineDiff.changes(from: ["a", "b"], to: []) == [.removed("a"), .removed("b")])
    }

    @Test func aChangedMiddleKeepsTheSurroundingLinesUnchanged() {
        #expect(
            LineDiff.changes(from: ["a", "b", "c"], to: ["a", "B", "c"]) == [
                .unchanged("a"), .removed("b"), .added("B"), .unchanged("c"),
            ]
        )
    }

    // MARK: Repeated lines: the two alignments

    @Test func theDefaultAlignmentAnchorsTheEarliestMatchingLine() {
        #expect(
            LineDiff.changes(from: ["A"], to: ["B", "A", "A"]) == [.added("B"), .unchanged("A"), .added("A")]
        )
    }

    @Test func trimmingTheCommonSuffixAnchorsTheTrailingMatchingLine() {
        #expect(
            LineDiff.changes(from: ["A"], to: ["B", "A", "A"], trimmingCommonSuffix: true) == [
                .added("B"), .added("A"), .unchanged("A"),
            ]
        )
    }

    @Test func trimmingTheCommonSuffixStillReportsAPlainMiddleChange() {
        #expect(
            LineDiff.changes(from: ["a", "b", "c"], to: ["a", "B", "c"], trimmingCommonSuffix: true) == [
                .unchanged("a"), .removed("b"), .added("B"), .unchanged("c"),
            ]
        )
    }
}
