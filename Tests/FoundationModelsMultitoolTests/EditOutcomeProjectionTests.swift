import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``EditOutcomeProjection`` — the single ``EditEngine/Resolution`` →
/// wire-vocabulary mapping the edit and patch verbs share.
///
/// The sibling FileTool package exercises this mapping only through its
/// operation-level suites; this suite pins the mapping directly, since the verb
/// surfaces land with later cards (^v5xap97). It covers the status-name table,
/// the whole-batch `applied` status, and the ``EditOutcome`` projection of every
/// ``EditEngine/Resolution`` case, including the candidate, near-miss, and
/// reclassification-note details.
@Suite struct EditOutcomeProjectionTests {
    // MARK: Fixtures

    /// The resolved 1-based line used by the anchor fixtures.
    private static let anchorFixtureLine = 3

    /// The 1-based line of the context line beside the candidate fixture.
    private static let contextFixtureLine = 2

    /// The 1-based last line of the near-miss fixture span.
    private static let nearMissEndLine = 2

    /// A candidate carrying one context line, for the ambiguous projection test.
    private static let candidateFixture = EditEngine.Candidate(
        occurrence: 1,
        line: 1,
        text: "focal",
        context: [EditEngine.ContextLine(line: contextFixtureLine, text: "beside")]
    )

    /// A near-miss carrying one diff line of each change kind and a note.
    private static let nearMissFixture = EditEngine.NearMiss(
        startLine: 1,
        endLine: nearMissEndLine,
        lines: [
            EditEngine.DiffLine(change: .unchanged, text: "kept"),
            EditEngine.DiffLine(change: .expected, text: "wanted"),
            EditEngine.DiffLine(change: .actual, text: "present"),
        ],
        note: "differs only by Unicode punctuation"
    )

    // MARK: Status names

    @Test func statusNamesMirrorEveryResolutionCase() {
        #expect(EditOutcomeProjection.statusName(for: .anchor(line: 1)) == "anchor")
        #expect(EditOutcomeProjection.statusName(for: .literal(range: 0..<1)) == "literal")
        #expect(EditOutcomeProjection.statusName(for: .recovered(range: 0..<1)) == "recovered")
        #expect(EditOutcomeProjection.statusName(for: .ambiguous([])) == "ambiguous")
        #expect(EditOutcomeProjection.statusName(for: .noMatch([])) == "nearMiss")
        #expect(EditOutcomeProjection.statusName(for: .alreadyApplied) == "alreadyApplied")
        #expect(EditOutcomeProjection.statusName(for: .consumedTarget) == "consumedTarget")
    }

    @Test func appliedStatusNamesTheCommittedBatch() {
        #expect(EditOutcomeProjection.appliedStatus == "applied")
    }

    // MARK: Outcome mapping

    @Test func anchorOutcomeCarriesTheResolvedLine() {
        let outcome = EditOutcomeProjection.outcome(
            for: .anchor(line: Self.anchorFixtureLine), find: "a-find")
        #expect(outcome.matchedBy == "anchor")
        #expect(outcome.find == "a-find")
        #expect(outcome.line == Self.anchorFixtureLine)
        #expect(outcome.candidates == nil)
        #expect(outcome.nearMisses == nil)
        #expect(outcome.note == nil)
    }

    @Test func literalOutcomeCarriesOnlyTheMatchName() {
        let outcome = EditOutcomeProjection.outcome(for: .literal(range: 0..<1), find: "a-find")
        #expect(outcome.matchedBy == "literal")
        #expect(outcome.find == "a-find")
        #expect(outcome.line == nil)
        #expect(outcome.candidates == nil)
        #expect(outcome.nearMisses == nil)
        #expect(outcome.note == nil)
    }

    @Test func recoveredOutcomeCarriesOnlyTheMatchName() {
        let outcome = EditOutcomeProjection.outcome(for: .recovered(range: 0..<1), find: "a-find")
        #expect(outcome.matchedBy == "recovered")
        #expect(outcome.line == nil)
        #expect(outcome.note == nil)
    }

    @Test func ambiguousOutcomeProjectsEachCandidateWithItsContext() throws {
        let outcome = EditOutcomeProjection.outcome(
            for: .ambiguous([Self.candidateFixture]), find: "a-find")
        #expect(outcome.matchedBy == "ambiguous")
        let candidates = try #require(outcome.candidates)
        #expect(candidates.count == 1)
        #expect(candidates.first?.occurrence == Self.candidateFixture.occurrence)
        #expect(candidates.first?.line == Self.candidateFixture.line)
        #expect(candidates.first?.text == Self.candidateFixture.text)
        #expect(candidates.first?.context.map(\.line) == [Self.contextFixtureLine])
        #expect(candidates.first?.context.map(\.text) == ["beside"])
        #expect(outcome.nearMisses == nil)
        #expect(outcome.note == nil)
    }

    @Test func nearMissOutcomeProjectsTheDiffWithWireChangeNames() throws {
        let outcome = EditOutcomeProjection.outcome(
            for: .noMatch([Self.nearMissFixture]), find: "a-find")
        #expect(outcome.matchedBy == "nearMiss")
        let nearMisses = try #require(outcome.nearMisses)
        #expect(nearMisses.count == 1)
        let nearMiss = try #require(nearMisses.first)
        #expect(nearMiss.startLine == Self.nearMissFixture.startLine)
        #expect(nearMiss.endLine == Self.nearMissEndLine)
        #expect(nearMiss.lines.map(\.change) == ["unchanged", "expected", "actual"])
        #expect(nearMiss.lines.map(\.text) == ["kept", "wanted", "present"])
        #expect(nearMiss.note == Self.nearMissFixture.note)
        #expect(outcome.candidates == nil)
        #expect(outcome.note == nil)
    }

    @Test func alreadyAppliedOutcomeCarriesItsExplanatoryNote() {
        let outcome = EditOutcomeProjection.outcome(for: .alreadyApplied, find: "a-find")
        #expect(outcome.matchedBy == "alreadyApplied")
        #expect(
            outcome.note
                == "The edit appears to have been applied already: the `find` is absent and the `replace` is already present."
        )
    }

    @Test func consumedTargetOutcomeCarriesItsExplanatoryNote() {
        let outcome = EditOutcomeProjection.outcome(for: .consumedTarget, find: "a-find")
        #expect(outcome.matchedBy == "consumedTarget")
        #expect(
            outcome.note
                == "An earlier edit in this batch consumed this `find`: it was present before the batch but is now gone."
        )
    }

    // MARK: Wire encoding

    @Test func absentOutcomeDetailsAreOmittedFromTheEncoding() throws {
        let outcome = EditOutcomeProjection.outcome(for: .literal(range: 0..<1), find: "a-find")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(outcome), as: UTF8.self)
        #expect(json == #"{"find":"a-find","matchedBy":"literal"}"#)
    }
}
