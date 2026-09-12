import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``EditEngine`` pure normalization + resolution core.
///
/// This suite is a port of the sibling FileTool suite
/// (`../FoundationModelsFileTool/Tests/FileToolTests/EditEngineTests.swift`).
/// The engine is IO-free: it turns `edit file` argument shapes into `find` /
/// `replace` pairs, resolves each pair against an in-memory working copy through
/// the anchor → literal → recovery-ladder cascade, and drives a batch of pairs
/// against an evolving working copy with idempotency reclassification and
/// before-mutation short-circuit. These tests exercise each cascade rung, the
/// competing-anchor/literal candidate path, occurrence selection, `replaceAll`,
/// the near-miss line diff, and the batch semantics.
@Suite struct EditEngineTests {
    // MARK: Constants

    /// The 1-based line of `beta` in the three-line `alpha`/`beta`/`gamma` fixtures.
    private static let betaLine = 2

    /// The 1-based line of the second `beta` in the competing-anchor fixture.
    private static let repeatedBetaLine = 4

    /// The 1-based occurrence selector for the second occurrence of a find.
    private static let secondOccurrence = 2

    /// The occurrence count of a find that appears exactly twice in a fixture.
    private static let duplicateOccurrenceCount = 2

    /// The occurrence count of the triple-`x` fixture (`"x\nx\nx\n"`).
    private static let tripleOccurrenceCount = 3

    /// A 1-based occurrence selector beyond every occurrence of the triple-`x` fixture.
    private static let outOfRangeOccurrence = 5

    // MARK: Helpers

    /// The hashline anchor string (`N:HH|text`) for the 1-based `line` of `content`.
    ///
    /// Built by tagging `content` with ``Hashline/tag(lines:startingAtLine:)`` so
    /// the anchor's hash is guaranteed valid and resolvable.
    ///
    /// - Parameters:
    ///   - line: the 1-based line whose anchor to extract.
    ///   - content: the content to tag.
    /// - Returns: the tagged anchor string for that line.
    private func anchor(forLine line: Int, in content: String) -> String {
        let tagged = Hashline.splitLines(Hashline.tag(lines: content, startingAtLine: 1)).map(\.text)
        return tagged[line - 1]
    }

    /// The expected context lines for the given texts, numbered by lookup in `lines`.
    ///
    /// Each text must occur exactly once in `lines`; its 1-based line number is
    /// derived by lookup rather than hard-coded, so the expectation tracks the
    /// fixture content.
    ///
    /// - Parameters:
    ///   - texts: the context line texts, in expected order.
    ///   - lines: the fixture's per-line texts.
    /// - Returns: the expected context lines.
    private func expectedContext(of texts: [String], in lines: [String]) -> [EditEngine.ContextLine] {
        texts.map { text in
            EditEngine.ContextLine(line: (lines.firstIndex(of: text) ?? -1) + 1, text: text)
        }
    }

    // MARK: normalize — shapes

    @Test func scalarPairNormalizes() {
        let result = EditEngine.normalize(.init(finds: ["a"], replaces: ["b"]))
        #expect(result == .pairs([EditEngine.Pair(find: "a", replace: "b")]))
    }

    @Test func parallelArraysZipPairwise() {
        let result = EditEngine.normalize(.init(finds: ["a", "b"], replaces: ["X", "Y"]))
        #expect(
            result
                == .pairs([
                    EditEngine.Pair(find: "a", replace: "X"),
                    EditEngine.Pair(find: "b", replace: "Y"),
                ])
        )
    }

    @Test func singleReplaceBroadcastsAcrossFinds() {
        let result = EditEngine.normalize(.init(finds: ["a", "b", "c"], replaces: ["X"]))
        #expect(
            result
                == .pairs([
                    EditEngine.Pair(find: "a", replace: "X"),
                    EditEngine.Pair(find: "b", replace: "X"),
                    EditEngine.Pair(find: "c", replace: "X"),
                ])
        )
    }

    @Test func countMismatchIsCorrectiveListingRemainder() {
        let result = EditEngine.normalize(.init(finds: ["a", "b", "c"], replaces: ["X", "Y"]))
        guard case .corrective(let message) = result else {
            Issue.record("expected corrective, got \(result)")
            return
        }
        #expect(message.contains("\"c\""))
    }

    @Test func editsArrayNormalizesWithPerEditReplaceAll() {
        let result = EditEngine.normalize(
            .init(edits: [
                EditEngine.EditSpec(find: "a", replace: "b"),
                EditEngine.EditSpec(find: "c", replace: "d", replaceAll: true),
            ])
        )
        #expect(
            result
                == .pairs([
                    EditEngine.Pair(find: "a", replace: "b", replaceAll: false),
                    EditEngine.Pair(find: "c", replace: "d", replaceAll: true),
                ])
        )
    }

    @Test func identicalFindAndReplaceIsRejectedAsNoOp() {
        let result = EditEngine.normalize(.init(finds: ["same"], replaces: ["same"]))
        guard case .corrective = result else {
            Issue.record("expected corrective no-op, got \(result)")
            return
        }
    }

    @Test func emptyFindsAreCorrective() {
        let result = EditEngine.normalize(.init())
        guard case .corrective = result else {
            Issue.record("expected corrective, got \(result)")
            return
        }
    }

    // MARK: resolve — cascade order

    @Test func resolvingAnchorWinsOverLiteral() {
        let content = "alpha\nbeta\ngamma\n"
        let pair = EditEngine.Pair(find: anchor(forLine: Self.betaLine, in: content), replace: "BETA")
        #expect(EditEngine.resolve(pair, in: content) == .anchor(line: Self.betaLine))
    }

    @Test func literalWinsOverLadder() {
        let content = "foo bar\nfoo baz\n"
        let find = "foo bar"
        let pair = EditEngine.Pair(find: find, replace: "X")
        guard case .literal(let range) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected literal")
            return
        }
        #expect(range == 0..<find.utf8.count)
    }

    @Test func ladderRecoversLineEndingDrift() {
        let content = "line one\r\nline two\r\nline three\r\n"
        let pair = EditEngine.Pair(find: "line one\nline two", replace: "X")
        guard case .recovered(let range) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected recovered")
            return
        }
        // The recovered span covers the same two lines in the CRLF original.
        let recoveredSpan = "line one\r\nline two"
        #expect(range == 0..<recoveredSpan.utf8.count)
    }

    // MARK: resolve — competing anchor + literal

    @Test func competingAnchorAndLiteralYieldCandidates() {
        let content = "alpha\nbeta\ngamma\nbeta\n"
        let pair = EditEngine.Pair(find: anchor(forLine: Self.betaLine, in: content), replace: "X")
        guard case .ambiguous(let candidates) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected ambiguous")
            return
        }
        #expect(candidates.count == Self.duplicateOccurrenceCount)
        #expect(candidates[0].occurrence == 1)
        #expect(candidates[0].line == Self.betaLine)
        #expect(candidates[1].occurrence == Self.secondOccurrence)
        #expect(candidates[1].line == Self.repeatedBetaLine)
    }

    // MARK: resolve — occurrence selection

    @Test func occurrenceSelectsAmongLiteralCandidates() {
        let content = "x\nx\nx\n"
        let pair = EditEngine.Pair(find: "x", replace: "y", occurrence: Self.secondOccurrence)
        // The second `x` starts right after the first `x\n` line.
        let start = "x\n".utf8.count
        #expect(EditEngine.resolve(pair, in: content) == .literal(range: start..<start + 1))
    }

    @Test func outOfRangeOccurrenceListsAllCandidates() {
        let content = "x\nx\nx\n"
        let pair = EditEngine.Pair(find: "x", replace: "y", occurrence: Self.outOfRangeOccurrence)
        guard case .ambiguous(let candidates) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected ambiguous")
            return
        }
        #expect(candidates.map(\.occurrence) == Array(1...Self.tripleOccurrenceCount))
        #expect(candidates.map(\.line) == Array(1...Self.tripleOccurrenceCount))
    }

    @Test func multipleLiteralOccurrencesWithoutSelectorAreAmbiguous() {
        let content = "x\nx\n"
        let pair = EditEngine.Pair(find: "x", replace: "y")
        guard case .ambiguous(let candidates) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected ambiguous")
            return
        }
        #expect(candidates.count == Self.duplicateOccurrenceCount)
    }

    @Test func ambiguousCandidatesCarryContextWindow() throws {
        let lines = ["a", "b", "TARGET", "d", "e", "f", "g", "TARGET", "i"]
        let content = lines.map { $0 + "\n" }.joined()
        let pair = EditEngine.Pair(find: "TARGET", replace: "Z")
        guard case .ambiguous(let candidates) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected ambiguous")
            return
        }
        let firstTargetLine = try #require(lines.firstIndex(of: "TARGET")) + 1
        let secondTargetLine = try #require(lines.lastIndex(of: "TARGET")) + 1
        #expect(candidates.count == Self.duplicateOccurrenceCount)
        #expect(candidates[0].line == firstTargetLine)
        #expect(candidates[0].text == "TARGET")
        #expect(candidates[0].context == expectedContext(of: ["a", "b", "d", "e"], in: lines))
        #expect(candidates[1].line == secondTargetLine)
        #expect(candidates[1].context == expectedContext(of: ["f", "g", "i"], in: lines))
    }

    // MARK: resolve — replaceAll global literal

    @Test func replaceAllResolvesToFirstOccurrence() {
        let content = "x\nx\nx\n"
        let pair = EditEngine.Pair(find: "x", replace: "y", replaceAll: true)
        #expect(EditEngine.resolve(pair, in: content) == .literal(range: 0..<1))
    }

    @Test func replaceAllRewritesEveryOccurrence() {
        let pair = EditEngine.Pair(find: "x", replace: "y", replaceAll: true)
        guard case .applied(let content, _) = EditEngine.apply([pair], to: "x\nx\nx\n") else {
            Issue.record("expected applied")
            return
        }
        #expect(content == "y\ny\ny\n")
    }

    // MARK: resolve — near-miss diff

    @Test func noMatchCarriesLineDiff() {
        let content = "the quick brown fox\n"
        let pair = EditEngine.Pair(find: "the quick red fox", replace: "X")
        guard case .noMatch(let nearMisses) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected noMatch")
            return
        }
        #expect(nearMisses.count == 1)
        #expect(nearMisses[0].startLine == 1)
        #expect(
            nearMisses[0].lines == [
                EditEngine.DiffLine(change: .expected, text: "the quick red fox"),
                EditEngine.DiffLine(change: .actual, text: "the quick brown fox"),
            ]
        )
    }

    @Test func emptyFindResolvesToNoMatch() {
        let pair = EditEngine.Pair(find: "", replace: "x")
        #expect(EditEngine.resolve(pair, in: "abc\n") == .noMatch([]))
    }

    @Test func confusableEqualNearMissCarriesAConfusablePunctuationNote() throws {
        // The find and the file agree except for a smart apostrophe, plus a find
        // line with no counterpart — so the ladder fails, yet the near-miss diff's
        // expected/actual pair is confusable-equal and must be named.
        let content = "don\u{2019}t stop\n"
        let pair = EditEngine.Pair(find: "don't stop\nEXTRA_LINE_NOT_PRESENT", replace: "X")
        guard case .noMatch(let nearMisses) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected noMatch")
            return
        }
        let note = try #require(nearMisses.first?.note)
        #expect(
            note
                == "differs only by Unicode punctuation: the file has '\u{2019}' (U+2019) where the find has \"'\" (U+0027)"
        )
    }

    @Test func genuinelyDifferentNearMissHasNoConfusableNote() {
        let content = "the quick brown fox\n"
        let pair = EditEngine.Pair(find: "the quick red fox", replace: "X")
        guard case .noMatch(let nearMisses) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected noMatch")
            return
        }
        #expect(nearMisses.first?.note == nil)
    }

    @Test func indentationOnlyNearMissHasNoConfusableNote() {
        // The near-miss line pair is equal after a plain whitespace trim — only the
        // find's indentation differs, with no confusable punctuation — so folding is
        // not load-bearing and no confusable note may be emitted.
        let content = "alpha\nbeta\n"
        let pair = EditEngine.Pair(find: "  alpha\nZZZ_UNIQUE", replace: "X")
        guard case .noMatch(let nearMisses) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected noMatch")
            return
        }
        #expect(nearMisses.allSatisfy { $0.note == nil })
    }

    @Test func indentedConfusableNearMissNamesTheConfusableNotTheIndentation() {
        // A find line that is both indented and confusable-different from the file
        // line must name the real confusable scalar, not the leading-whitespace shift.
        let content = "don\u{2019}t stop\n"
        let pair = EditEngine.Pair(find: "    don't stop\nZZZ_UNIQUE", replace: "X")
        guard case .noMatch(let nearMisses) = EditEngine.resolve(pair, in: content) else {
            Issue.record("expected noMatch")
            return
        }
        let note = nearMisses.compactMap(\.note).first
        #expect(
            note
                == "differs only by Unicode punctuation: the file has '\u{2019}' (U+2019) where the find has \"'\" (U+0027)"
        )
    }

    // MARK: apply — batch semantics

    @Test func batchAppliesPairsSequentially() {
        let pairs = [
            EditEngine.Pair(find: "foo", replace: "FOO"),
            EditEngine.Pair(find: "bar", replace: "BAR"),
        ]
        guard case .applied(let content, let edits) = EditEngine.apply(pairs, to: "foo\nbar\n") else {
            Issue.record("expected applied")
            return
        }
        #expect(content == "FOO\nBAR\n")
        #expect(edits.map(\.pair) == pairs)
        // Each applied record carries the definite resolution that placed it,
        // located against the working copy as mutated by the earlier pairs.
        let secondStart = "FOO\n".utf8.count
        #expect(
            edits.map(\.resolution) == [
                .literal(range: 0..<"foo".utf8.count),
                .literal(range: secondStart..<secondStart + "bar".utf8.count),
            ]
        )
    }

    @Test func alreadyAppliedReclassifiesBareNoMatch() {
        let pair = EditEngine.Pair(find: "hello", replace: "world")
        guard case .failed(let index, _, let resolution) = EditEngine.apply([pair], to: "world\n") else {
            Issue.record("expected failed")
            return
        }
        #expect(index == 0)
        #expect(resolution == .alreadyApplied)
    }

    @Test func consumedTargetReclassifiesBareNoMatchInBatch() {
        let pairs = [
            EditEngine.Pair(find: "foo", replace: "XXX"),
            EditEngine.Pair(find: "foo", replace: "YYY"),
        ]
        guard case .failed(let index, _, let resolution) = EditEngine.apply(pairs, to: "foo\nbar\n") else {
            Issue.record("expected failed")
            return
        }
        #expect(index == 1)
        #expect(resolution == .consumedTarget)
    }

    @Test func genuineNearMissIsNotReclassifiedWhenReplaceIsAbsent() {
        // A typo'd `find` that is absent and whose `replace` is also absent must
        // stay a near-miss, not be mislabelled already-applied/consumed-target.
        let pair = EditEngine.Pair(find: "helo", replace: "WORLD")
        guard case .failed(_, _, let resolution) = EditEngine.apply([pair], to: "hello\n") else {
            Issue.record("expected failed")
            return
        }
        guard case .noMatch = resolution else {
            Issue.record("expected noMatch, got \(resolution)")
            return
        }
    }

    @Test func ambiguousPairShortCircuitsBatchLeavingContentUnchanged() {
        let pairs = [
            EditEngine.Pair(find: "foo", replace: "ZZZ"),
            EditEngine.Pair(find: "x", replace: "Y"),
        ]
        let outcome = EditEngine.apply(pairs, to: "foo\nx\nx\n")
        guard case .failed(let index, _, let resolution) = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(index == 1)
        guard case .ambiguous = resolution else {
            Issue.record("expected ambiguous resolution")
            return
        }
    }

    // MARK: resolve — a block of tagged lines pasted back as one find

    @Test func taggedBlockSpansEveryLineItNames() throws {
        // The regression this rung exists for: read the first two lines back as
        // `N:HH|text` and edit them as one span. Reading only the first prefix
        // would rewrite line 1 alone and leave line 2 standing.
        let content = "alpha\nbeta\ngamma\n"
        let pair = EditEngine.Pair(
            find: TestSupport.taggedBlock(forLines: 1...2, in: content), replace: "X")
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "X\ngamma\n")
    }

    @Test func taggedBlockRelocatesUnderDrift() throws {
        // The block was read before an insertion moved the span down one line.
        let original = "alpha\nbeta\ngamma\n"
        let pair = EditEngine.Pair(
            find: TestSupport.taggedBlock(forLines: 1...2, in: original), replace: "X")
        let edited = try #require(
            EditEngine.apply([pair], to: "INSERTED\n" + original).appliedContent,
            "expected applied")
        #expect(edited == "INSERTED\nX\ngamma\n")
    }

    @Test func staleTaggedBlockStillResolvesByItsUntaggedText() throws {
        // The line numbers are far out of the proximity window, so the block
        // rung declines; the untagged text still locates the span literally.
        let content = "alpha\nbeta\ngamma\n"
        let staleNumbers = Hashline.taggedLines(of: content)[0...1]
            .map { "9\($0)" }
            .joined(separator: "\n")
        let pair = EditEngine.Pair(find: staleNumbers, replace: "X")
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "X\ngamma\n")
    }

    @Test func multiLineFindWithOnePrefixedLineIsNeverAnAnchor() {
        // Only the first line carries a prefix, so the paste is not a block —
        // and it must not resolve as the lone anchor its first line parses as,
        // which would rewrite that one line and drop the second.
        let content = "alpha\nbeta\ngamma\n"
        let find = anchor(forLine: 1, in: content) + "\nbeta"
        let resolution = EditEngine.resolve(EditEngine.Pair(find: find, replace: "X"), in: content)
        if case .anchor = resolution {
            Issue.record("a multi-line find must not resolve as a lone anchor")
        }
    }

    @Test func taggedBlockOverCRLFKeepsTheTerminatorAfterTheSpan() throws {
        // A block carries no record of the file's line endings, thus its
        // untagged text joins with a line feed. The span must still be located
        // in a CRLF file, and the terminator after the span must survive.
        let content = "alpha\r\nbeta\r\ngamma\r\n"
        let pair = EditEngine.Pair(
            find: TestSupport.taggedBlock(forLines: 1...2, in: content), replace: "X")
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "X\r\ngamma\r\n")
    }

    @Test func taggedBlockSpansAnEmptyInteriorLine() throws {
        // The shape a caller sends when it lifts a run across a blank line: the
        // middle entry tags an empty line, whose hash is the commonest of all.
        // The whole-block agreement, not that one line, pins the span.
        let content = "alpha\n\nbeta\ngamma\n"
        let firstLine = 1
        let lastLine = 3
        let pair = EditEngine.Pair(
            find: TestSupport.taggedBlock(forLines: firstLine...lastLine, in: content),
            replace: "X")
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "X\ngamma\n")
    }

    @Test func taggedBlockAtTheEndOfAFileWithNoFinalTerminator() throws {
        let content = "alpha\nbeta"
        let pair = EditEngine.Pair(
            find: TestSupport.taggedBlock(forLines: 1...2, in: content), replace: "X")
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "X")
    }

    @Test func taggedBlockRelocatesAfterAnEarlierPairShiftedTheLines() throws {
        // The block was read against the original; the pair before it removed a
        // line, thus the span sits one line higher by the time it resolves.
        let content = "drop\nalpha\nbeta\ngamma\n"
        let pairs = [
            EditEngine.Pair(find: "drop\n", replace: ""),
            EditEngine.Pair(
                find: TestSupport.taggedBlock(forLines: 2...3, in: content), replace: "X"),
        ]
        let edited = try #require(
            EditEngine.apply(pairs, to: content).appliedContent, "expected applied")
        #expect(edited == "X\ngamma\n")
    }

    @Test func replaceAllOverATaggedBlockRewritesEveryOccurrenceOfItsText() throws {
        // `replaceAll` speaks about repeated occurrences of a text, which a
        // block pinned to one span cannot answer, thus the block rung stands
        // down and the untagged text drives the global rewrite.
        let content = "alpha\nbeta\nalpha\nbeta\n"
        let find = TestSupport.taggedBlock(forLines: 1...2, in: content)
        let pair = EditEngine.Pair(find: find, replace: "X", replaceAll: true)
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "X\nX\n")
    }

    @Test func occurrenceSelectsAmongTheSitesOfATaggedBlocksText() throws {
        // The same stand-down: `occurrence` counts sites of the untagged text.
        let content = "alpha\nbeta\nalpha\nbeta\n"
        let find = TestSupport.taggedBlock(forLines: 1...2, in: content)
        let pair = EditEngine.Pair(find: find, replace: "X", occurrence: Self.secondOccurrence)
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "alpha\nbeta\nX\n")
    }

    @Test func aTaggedBlockThatMatchesNothingDiffsItsUntaggedLines() throws {
        // The diff is what the caller reads before it tries again. It must show
        // the lines as the file would show them, not the `N:HH|` prefixes the
        // caller pasted, or the caller cannot see what actually differs.
        let original = "alpha\nbeta\n"
        let find = TestSupport.taggedBlock(forLines: 1...2, in: original)
        let resolution = EditEngine.resolve(
            EditEngine.Pair(find: find, replace: "X"), in: "totally\nother\n")
        let nearMisses = try #require(resolution.nearMisses, "expected noMatch")
        let expected = nearMisses.flatMap(\.lines).filter { $0.change == .expected }.map(\.text)
        #expect(expected.allSatisfy { Hashline.parseAnchor($0) == nil }, "the diff must carry untagged lines")
        #expect(expected.contains("alpha") || expected.contains("beta"))
    }

    @Test func aTaggedBlockResentAfterItsEditIsReportedAsAlreadyApplied() throws {
        // The idempotent re-run: the caller sends the same block again after the
        // edit landed. The batch context must name that, not a bare no-match.
        let original = "alpha\nbeta\ngamma\n"
        let pair = EditEngine.Pair(
            find: TestSupport.taggedBlock(forLines: 1...2, in: original), replace: "X")
        let resolution = try #require(
            EditEngine.apply([pair], to: "X\ngamma\n").failureResolution, "expected failed")
        #expect(resolution == .alreadyApplied)
    }

    @Test func taggedTextTheFileHoldsVerbatimIsEditedWhereItStands() throws {
        // A file of tagged sample lines is edited by naming its lines as they
        // stand; reinterpreting them as a block would edit somewhere else.
        let content = "1:a3|one\n2:b4|two\nplain\n"
        let find = "1:a3|one\n2:b4|two"
        let pair = EditEngine.Pair(find: find, replace: "REPLACED")
        let edited = try #require(
            EditEngine.apply([pair], to: content).appliedContent, "expected applied")
        #expect(edited == "REPLACED\nplain\n")
    }
}

// MARK: - Readers that let a case unwrap an engine result with `try #require`

/// Optional readers of a batch outcome.
///
/// A `guard` that returns takes a case out before its assertions run, thus a
/// broken engine would read as a pass. Each reader answers `nil` for the case
/// the test does not expect, thus `try #require` fails the case where the
/// expectation stands.
extension EditEngine.BatchOutcome {
    /// The rewritten content when every pair applied, and `nil` when the batch failed.
    fileprivate var appliedContent: String? {
        if case .applied(let content, _) = self { content } else { nil }
    }

    /// The resolution of the pair that failed, and `nil` when the batch applied.
    fileprivate var failureResolution: EditEngine.Resolution? {
        if case .failed(_, _, let resolution) = self { resolution } else { nil }
    }
}

/// An optional reader of a resolution, for the reason the readers above state.
extension EditEngine.Resolution {
    /// The near misses a no-match resolution carries, and `nil` in each other case.
    fileprivate var nearMisses: [EditEngine.NearMiss]? {
        if case .noMatch(let nearMisses) = self { nearMisses } else { nil }
    }
}
