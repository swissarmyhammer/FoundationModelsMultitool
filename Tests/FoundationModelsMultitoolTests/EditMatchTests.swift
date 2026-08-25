import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Parity and behavioral tests for the ``EditMatch`` recovery ladder.
///
/// This suite is a port of the sibling FileTool suite. The golden fixtures in
/// `FilesGoldens/edit-match-golden.json` are generated directly from the Rust
/// `swissarmyhammer-edit-match` crate (its `find_match` ladder and
/// `similarity` scale). Asserting the Swift port against them pins the
/// recovery ladder rung-for-rung: a `find` that has drifted, been
/// re-indented, or had its line endings normalized must resolve to the exact
/// same byte span here as in the Rust `edit files` tool.
///
/// Cases are grouped by rung (`exact`, `normalized`, `crlf`, `anchor`,
/// `fuzzy`, `ambiguous`, `noMatch`, `empty`, `combined`) so each rung is
/// exercised by its own fixture table, driven by one shared assertion path.
@Suite struct EditMatchTests {
    // MARK: Golden fixture model

    private struct Golden: Decodable {
        struct SimilarityCase: Decodable {
            let a: String
            let b: String
            let expected: Float
        }
        struct RangeFixture: Decodable {
            let start: Int
            let end: Int
            var asRange: Range<Int> { start..<end }
        }
        struct SpanFixture: Decodable {
            let range: RangeFixture
            let startLine: Int
            let endLine: Int
            let text: String
        }
        struct OutcomeFixture: Decodable {
            let kind: String
            let range: RangeFixture?
            let rung: String?
            let confidence: Float?
            let candidates: [SpanFixture]?
            let near: [SpanFixture]?
        }
        struct Case: Decodable {
            let group: String
            let name: String
            let content: String
            let find: String
            let outcome: OutcomeFixture
        }
        let similarity: [SimilarityCase]
        let cases: [Case]
    }

    /// Tolerance for comparing `Float` confidences/similarities decoded from the
    /// fixture's decimal JSON against values recomputed in Swift.
    private static let floatTolerance: Float = 1e-6

    private static func loadGolden() throws -> Golden {
        let url = try #require(
            Bundle.module.url(
                forResource: "edit-match-golden",
                withExtension: "json",
                subdirectory: "FilesGoldens"
            ),
            "edit-match-golden.json fixture must be bundled with the test target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Golden.self, from: data)
    }

    private static func cases(inGroup group: String) throws -> [Golden.Case] {
        try loadGolden().cases.filter { $0.group == group }
    }

    // MARK: Comparison helpers

    /// Decode the UTF-8 byte range `range` of `content` back into a string.
    private func originalBytes(of content: String, in range: Range<Int>) -> String {
        String(decoding: Array(content.utf8)[range], as: UTF8.self)
    }

    private func rung(from name: String) -> EditMatch.Rung {
        switch name {
        case "exact": return .exact
        case "normalized": return .normalized
        case "unicode": return .unicode
        case "anchor": return .anchor
        case "fuzzy": return .fuzzy
        default:
            Issue.record("unknown rung \(name)")
            return .fuzzy
        }
    }

    private func assertSpan(_ actual: EditMatch.Span, matches fixture: Golden.SpanFixture, in name: String) {
        #expect(actual.range == fixture.range.asRange, "\(name): span range")
        #expect(actual.startLine == fixture.startLine, "\(name): span startLine")
        #expect(actual.endLine == fixture.endLine, "\(name): span endLine")
        #expect(actual.text == fixture.text, "\(name): span text")
    }

    /// Assert one fixture case reproduces the Rust outcome exactly, and that a
    /// located span indexes the **original** bytes.
    private func assertParity(_ testCase: Golden.Case) {
        let result = EditMatch.findMatch(find: testCase.find, in: testCase.content)
        let name = testCase.name
        switch (result, testCase.outcome.kind) {
        case (.unique(let range, let matchRung, let confidence), "unique"):
            #expect(range == testCase.outcome.range?.asRange, "\(name): unique range")
            #expect(matchRung == rung(from: testCase.outcome.rung ?? ""), "\(name): unique rung")
            let expectedConfidence = testCase.outcome.confidence ?? -1
            #expect(
                abs(confidence - expectedConfidence) < Self.floatTolerance,
                "\(name): confidence \(confidence) vs \(expectedConfidence)"
            )
            // Byte-preservation: the located range indexes valid original bytes.
            #expect(
                range.lowerBound >= 0 && range.upperBound <= testCase.content.utf8.count,
                "\(name): range must lie within the original content bytes"
            )
        case (.ambiguous(let candidates), "ambiguous"):
            let expected = testCase.outcome.candidates ?? []
            #expect(candidates.count == expected.count, "\(name): candidate count")
            for (actual, fixture) in zip(candidates, expected) {
                assertSpan(actual, matches: fixture, in: name)
            }
        case (.noMatch(let near), "noMatch"):
            let expected = testCase.outcome.near ?? []
            #expect(near.count == expected.count, "\(name): near count")
            for (actual, fixture) in zip(near, expected) {
                assertSpan(actual, matches: fixture, in: name)
            }
        default:
            Issue.record("\(name): outcome kind mismatch, got \(result), expected \(testCase.outcome.kind)")
        }
    }

    private func assertGroupParity(_ group: String) throws {
        let group = try Self.cases(inGroup: group)
        #expect(!group.isEmpty, "each rung group must contribute at least one fixture")
        for testCase in group { assertParity(testCase) }
    }

    // MARK: Per-rung parity tables

    @Test func exactRungMatchesRustFixtures() throws {
        try assertGroupParity("exact")
    }

    @Test func normalizedRungReindentAndDriftMatchesRustFixtures() throws {
        try assertGroupParity("normalized")
    }

    @Test func crlfNormalizedFindMatchesRustFixtures() throws {
        try assertGroupParity("crlf")
    }

    @Test func anchorRungMatchesRustFixtures() throws {
        try assertGroupParity("anchor")
    }

    @Test func fuzzyRungMatchesRustFixtures() throws {
        try assertGroupParity("fuzzy")
    }

    @Test func ambiguousOutcomesMatchRustFixtures() throws {
        try assertGroupParity("ambiguous")
    }

    @Test func noMatchNearMissesMatchRustFixtures() throws {
        try assertGroupParity("noMatch")
    }

    @Test func emptyFindGuardsMatchRustFixtures() throws {
        try assertGroupParity("empty")
    }

    @Test func combinedDriftMatchesRustFixtures() throws {
        try assertGroupParity("combined")
    }

    // MARK: similarity scale parity

    @Test func similarityMatchesRustGoldenValues() throws {
        for c in try Self.loadGolden().similarity {
            let actual = EditMatch.similarity(c.a, c.b)
            #expect(
                abs(actual - c.expected) < Self.floatTolerance,
                "similarity(\(c.a.debugDescription), \(c.b.debugDescription)) = \(actual), expected \(c.expected)"
            )
        }
    }

    // MARK: Byte-preservation (indentation / line endings untouched)

    @Test func normalizedReindentSpanPreservesOriginalIndentation() {
        // The find dropped its 4-space indent; the located span must cover the
        // ORIGINAL indented bytes so the caller rewrites the real text on disk.
        let content = "fn outer() {\n    let x = compute();\n}\n"
        let find = "let x = compute();"
        guard case .unique(let range, let rung, _) = EditMatch.findMatch(find: find, in: content) else {
            Issue.record("expected a unique normalized match")
            return
        }
        #expect(rung == .normalized)
        #expect(originalBytes(of: content, in: range) == "    let x = compute();")
        #expect(!find.hasPrefix("    "), "the find deliberately lost its indentation")
    }

    @Test func crlfNormalizedSpanPreservesOriginalCarriageReturns() {
        // An LF find against CRLF content: the span must cover the original CRLF
        // bytes (interior "\r\n" retained), not the normalized LF form.
        let content = "one\r\ntwo\r\nthree\r\n"
        let find = "one\ntwo"
        guard case .unique(let range, let rung, _) = EditMatch.findMatch(find: find, in: content) else {
            Issue.record("expected a unique normalized match")
            return
        }
        #expect(rung == .normalized)
        #expect(originalBytes(of: content, in: range) == "one\r\ntwo")
    }

    @Test func anchorSpanPreservesDriftedInteriorBytes() {
        let content = "fn f() {\n    let a = 1;\n    let b = 2;\n    let c = 3;\n}\n"
        let find = "fn f() {\n    DIFFERENT INTERIOR\n}"
        guard case .unique(let range, let rung, _) = EditMatch.findMatch(find: find, in: content) else {
            Issue.record("expected a unique anchor match")
            return
        }
        #expect(rung == .anchor)
        #expect(
            originalBytes(of: content, in: range)
                == "fn f() {\n    let a = 1;\n    let b = 2;\n    let c = 3;\n}"
        )
    }

    // MARK: Near-miss candidate quality

    /// The length, in scalars, of the all-`"a"` probe line the near-miss test
    /// scores content lines against. Long enough that the per-line
    /// similarities land at clean, well-separated values below the accept
    /// threshold.
    private static let nearMissProbeLength = 20

    /// The cap on retained near-miss candidates in a no-match verdict.
    /// Mirrors the ladder's own `maxNearMisses`.
    private static let nearMissCap = 3

    /// The count of content lines with positive similarity to the probe in
    /// the near-miss test; the zero-similarity third line is dropped.
    private static let survivingNearMissCount = 2

    @Test func nearMissesAreTheClosestCandidatesInDescendingOrder() {
        // A find with no exact/normalized/anchor match whose closest lines all
        // sit BELOW the fuzzy accept threshold must surface those lines as
        // near-misses: ordered by non-increasing similarity, capped, all with
        // positive similarity, and the zero-similarity line dropped entirely.
        let find = String(repeating: "a", count: Self.nearMissProbeLength)
        // Similarities to `find`: line 1 = 0.80, line 2 = 0.70, line 3 = 0.0.
        let content = "bbbbaaaaaaaaaaaaaaaa\nbbbbbbaaaaaaaaaaaaaa\nzzzzzzzzzzzzzzzzzzzz\n"
        guard case .noMatch(let near) = EditMatch.findMatch(find: find, in: content) else {
            Issue.record("expected NoMatch with near-miss candidates")
            return
        }
        #expect(!near.isEmpty, "close-but-below-threshold lines must be retained as near-misses")
        #expect(near.count <= Self.nearMissCap, "the retained near-miss count is capped")

        let scores = near.map { EditMatch.similarity(find, originalBytes(of: content, in: $0.range)) }
        #expect(scores == scores.sorted(by: >), "near-misses are ordered by non-increasing similarity")
        #expect(scores.allSatisfy { $0 > 0 }, "the zero-similarity line is not retained")

        // The strongest near-miss is the most-similar line (0.80), and the
        // zero-similarity line is excluded, so only two candidates survive.
        #expect(near.count == Self.survivingNearMissCount)
        #expect(near.first.map { originalBytes(of: content, in: $0.range) } == "bbbbaaaaaaaaaaaaaaaa")
    }

    /// The count of identical occurrences the ambiguity tests plant, and thus
    /// the count of candidate spans an ambiguous verdict must surface.
    private static let ambiguousOccurrenceCount = 2

    @Test func ambiguousNeverSilentlyPicksOneCandidate() {
        // Two identical lines: the outcome must be Ambiguous with both spans, so
        // a caller can never be handed a single silently-chosen location.
        let content = "dup line\nmiddle\ndup line\n"
        guard case .ambiguous(let candidates) = EditMatch.findMatch(find: "dup line", in: content) else {
            Issue.record("expected Ambiguous")
            return
        }
        #expect(candidates.count == Self.ambiguousOccurrenceCount)
        #expect(candidates[0].range != candidates[1].range)
    }

    // MARK: Unicode confusable rung

    /// Assert an ASCII-authored `find` resolves to a unique ``EditMatch/Rung/unicode``
    /// match at confidence `1.0`, with the returned range indexing the original
    /// (typographic) bytes.
    private func assertUnicodeMatch(content: String, find: String, original: String, _ label: String) {
        guard case .unique(let range, let rung, let confidence) = EditMatch.findMatch(find: find, in: content) else {
            Issue.record("\(label): expected a unique match")
            return
        }
        #expect(rung == .unicode, "\(label): rung must be unicode")
        #expect(confidence == 1.0, "\(label): confidence must be 1.0")
        #expect(
            originalBytes(of: content, in: range) == original,
            "\(label): range must index the original typographic bytes"
        )
    }

    @Test func unicodeRungFoldsEnDash() {
        assertUnicodeMatch(
            content: "value = a\u{2013}b\n", find: "value = a-b", original: "value = a\u{2013}b", "en dash U+2013")
    }

    @Test func unicodeRungFoldsEmDash() {
        assertUnicodeMatch(
            content: "sum = x\u{2014}y\n", find: "sum = x-y", original: "sum = x\u{2014}y", "em dash U+2014")
    }

    @Test func unicodeRungFoldsMinusSign() {
        assertUnicodeMatch(
            content: "delta = m\u{2212}n\n", find: "delta = m-n", original: "delta = m\u{2212}n", "minus sign U+2212")
    }

    @Test func unicodeRungFoldsSmartSingleQuote() {
        assertUnicodeMatch(
            content: "it\u{2019}s ready\n", find: "it's ready", original: "it\u{2019}s ready",
            "smart single quote U+2019")
    }

    @Test func unicodeRungFoldsSmartDoubleQuotes() {
        assertUnicodeMatch(
            content: "say \u{201C}hi\u{201D} now\n",
            find: "say \"hi\" now",
            original: "say \u{201C}hi\u{201D} now",
            "smart double quotes U+201C/U+201D"
        )
    }

    @Test func unicodeRungFoldsNoBreakSpace() {
        assertUnicodeMatch(content: "a\u{00A0}b\n", find: "a b", original: "a\u{00A0}b", "no-break space U+00A0")
    }

    @Test func unicodeRungFoldsThinSpace() {
        assertUnicodeMatch(content: "c\u{2009}d\n", find: "c d", original: "c\u{2009}d", "thin space U+2009")
    }

    @Test func unicodeRungAmbiguousNeverSilentlyPicksOneFoldedOccurrence() {
        // Two em-dash occurrences both fold to the ASCII `find`; the outcome must
        // be Ambiguous with both spans rather than a silent first pick.
        let content = "p\u{2014}q\nmiddle\np\u{2014}q\n"
        guard case .ambiguous(let candidates) = EditMatch.findMatch(find: "p-q", in: content) else {
            Issue.record("expected Ambiguous for two folded occurrences")
            return
        }
        #expect(candidates.count == Self.ambiguousOccurrenceCount)
        #expect(candidates[0].range != candidates[1].range)
    }

    @Test func exactVerbatimOccurrenceWinsOverConfusableVariant() {
        // A verbatim ASCII occurrence and a confusable em-dash variant both exist;
        // the exact rung must win before the unicode rung is ever consulted.
        let content = "a-b\nother\na\u{2014}b\n"
        guard case .unique(let range, let rung, _) = EditMatch.findMatch(find: "a-b", in: content) else {
            Issue.record("expected a unique exact match")
            return
        }
        #expect(rung == .exact, "the verbatim occurrence must win at .exact")
        #expect(originalBytes(of: content, in: range) == "a-b")
    }

    // MARK: foldConfusables unit cases

    @Test func foldConfusablesIsIdentityOnPureASCII() {
        let ascii = "plain ASCII text - 'quote' \"dq\" 123\n\t"
        #expect(EditMatch.foldConfusables(ascii) == ascii)
    }

    @Test func foldConfusablesMapsDashesToHyphen() {
        #expect(EditMatch.foldConfusables("\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}") == "-------")
    }

    @Test func foldConfusablesMapsSingleQuotesToApostrophe() {
        #expect(EditMatch.foldConfusables("\u{2018}\u{2019}\u{201A}\u{201B}") == "''''")
    }

    @Test func foldConfusablesMapsDoubleQuotesToQuotationMark() {
        #expect(EditMatch.foldConfusables("\u{201C}\u{201D}\u{201E}\u{201F}") == "\"\"\"\"")
    }

    @Test func foldConfusablesMapsExoticSpacesToSpace() {
        #expect(EditMatch.foldConfusables("\u{00A0}\u{2000}\u{2005}\u{200A}\u{202F}\u{205F}\u{3000}") == "       ")
    }

    @Test func foldConfusablesLeavesOtherScalarsUnchanged() {
        let text = "caf\u{00E9} \u{2603} \u{1F600}"
        #expect(EditMatch.foldConfusables(text) == text)
    }
}
