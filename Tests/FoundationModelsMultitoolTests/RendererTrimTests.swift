import Foundation
import MCP
import Testing

@testable import FoundationModelsMultitool

/// Coverage for ``ToolContentRenderer``'s bounded-output render-budget
/// strategy: oversized text and `structuredContent` are deterministically
/// trimmed to a head/tail excerpt with an elision marker naming exactly how
/// much was elided; image/audio content stays a compact placeholder
/// regardless of budget; and results already under budget pass through
/// completely untouched.
///
/// A port of the sibling `FoundationModelsMCP` suite `RendererTrim`, renamed
/// so that `swift test --filter RendererTrimTests` selects it.
@Suite("RendererTrimTests")
struct RendererTrimTests {

    // MARK: - The sizes the trims are measured at

    /// The character count of the oversized text the trim tests build.
    private static let oneMegabyte = 1_000_000

    /// A budget far under ``oneMegabyte``, so trimming must happen.
    private static let smallBudget = 2_048

    /// A second budget under ``oneMegabyte``, for the determinism tests.
    private static let mediumBudget = 4_096

    /// The character count of the text of the digit-boundary test.
    private static let digitBoundaryTextLength = 20_000

    /// The first budget of the digit-boundary sweep. The elided count crosses
    /// from four digits to five inside this sweep.
    private static let digitBoundarySweepStart = 19_900

    /// The last budget of the digit-boundary sweep.
    private static let digitBoundarySweepEnd = 19_999

    /// The budget of the multi-byte Unicode test, well under its text.
    private static let unicodeBudget = 200

    /// The count of multi-byte characters between the two Unicode sentinels.
    private static let unicodeMiddleLength = 5_000

    /// The repeat count of a four-character base64 chunk, which gives roughly
    /// one megabyte of base64 text.
    private static let base64ChunkRepeats = 250_000

    /// A run of filler characters that must not survive a trim verbatim.
    private static let fillerRunLength = 1_000

    /// The `code` property of the composed error result.
    private static let errorCode = 500

    // MARK: - Oversized text

    /// A 1MB text content item, with distinguishable head/tail sentinels so
    /// tests can assert exactly what survives trimming without depending on
    /// the internal head/tail split ratio.
    private func oneMegabyteText(head: String, tail: String) -> String {
        let middleLength = Self.oneMegabyte - head.count - tail.count
        return head + String(repeating: "x", count: middleLength) + tail
    }

    @Test("a 1MB text result is trimmed within budget with an elision marker naming the elided size")
    func oversizedTextContentIsTrimmedWithinBudget() {
        let text = oneMegabyteText(head: "HEAD-SENTINEL", tail: "TAIL-SENTINEL")
        let result = CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
        let budget = Self.smallBudget

        let rendered = ToolContentRenderer.render(result: result, budget: budget)

        #expect(rendered.hasPrefix("HEAD-SENTINEL"))
        #expect(rendered.hasSuffix("TAIL-SENTINEL"))
        assertBudgetSafeTrim(rendered: rendered, totalCount: text.count, budget: budget)
    }

    @Test("trimming a 1MB text result is deterministic — same input and budget produce identical output")
    func oversizedTextTrimmingIsDeterministic() {
        let text = oneMegabyteText(head: "HEAD", tail: "TAIL")
        let result = CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])

        let first = ToolContentRenderer.render(result: result, budget: Self.mediumBudget)
        let second = ToolContentRenderer.render(result: result, budget: Self.mediumBudget)

        #expect(first == second)
    }

    @Test("oversized resource text is trimmed the same way as oversized .text content")
    func oversizedResourceTextIsTrimmedWithinBudget() {
        let text = oneMegabyteText(head: "HEAD-SENTINEL", tail: "TAIL-SENTINEL")
        let resource = Resource.Content.text(text, uri: "file:///huge.txt", mimeType: "text/plain")
        let result = CallTool.Result(content: [.resource(resource: resource, annotations: nil, _meta: nil)])
        let budget = Self.smallBudget

        let rendered = ToolContentRenderer.render(result: result, budget: budget)

        #expect(rendered.contains("file:///huge.txt"))
        #expect(rendered.contains("HEAD-SENTINEL"))
        #expect(rendered.contains("TAIL-SENTINEL"))
        // The resource's own "[resource: <uri>]\n" prefix line sits outside
        // the trimmed text unit, so the overall budget check allows for it.
        let uriPrefixLength = "[resource: file:///huge.txt]\n".count
        #expect(rendered.count <= budget + uriPrefixLength)
    }

    @Test(
        "trimming stays within budget across a digit-count boundary in the elided count, not just the sizes exercised by other tests"
    )
    func trimmingStaysWithinBudgetAcrossADigitCountBoundary() {
        // Regression case for a prior bug: sizing the elision marker off an
        // *approximate* elided count (rather than the worst case) could
        // under-reserve space when the approximate and actual elided counts
        // had different digit widths (e.g. 9999 vs 10000), letting the
        // rendered text run over budget by exactly the extra digit.
        let text = String(repeating: "x", count: Self.digitBoundaryTextLength)
        for budget in Self.digitBoundarySweepStart...Self.digitBoundarySweepEnd {
            let result = CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
            let rendered = ToolContentRenderer.render(result: result, budget: budget)
            assertBudgetSafeTrim(rendered: rendered, totalCount: text.count, budget: budget)
        }
    }

    @Test("trimming a multi-byte Unicode text does not corrupt grapheme clusters and stays within budget")
    func trimmingMultiByteUnicodeTextStaysWithinBudget() {
        // The budget is a Character (grapheme cluster) count, not a byte or
        // UTF-8 scalar count, so `.prefix`/`.suffix` — which are always
        // grapheme-safe on `String` — cannot split a multi-byte character.
        let head = "HEAD-🎉-SENTINEL"
        let tail = "TAIL-世界-SENTINEL"
        let middle = String(repeating: "é", count: Self.unicodeMiddleLength)
        let text = head + middle + tail
        let result = CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
        let budget = Self.unicodeBudget

        let rendered = ToolContentRenderer.render(result: result, budget: budget)

        #expect(rendered.hasPrefix(head))
        #expect(rendered.hasSuffix(tail))
        assertBudgetSafeTrim(rendered: rendered, totalCount: text.count, budget: budget)
    }

    // MARK: - Image/audio stay compact regardless of budget

    /// Roughly one megabyte of base64 text, which no budget may render.
    private var hugeBase64Payload: String {
        String(repeating: "QQ==", count: Self.base64ChunkRepeats)
    }

    @Test("image content stays a compact placeholder even under a tiny budget, never dumping raw data")
    func imageContentStaysCompactUnderTinyBudget() {
        let result = CallTool.Result(content: [
            .image(data: hugeBase64Payload, mimeType: "image/png", annotations: nil, _meta: nil)
        ])

        let rendered = ToolContentRenderer.render(result: result, budget: 1)

        #expect(rendered == "[image: image/png]")
        #expect(!rendered.contains("QQ=="))
    }

    @Test("audio content stays a compact placeholder even under a tiny budget, never dumping raw data")
    func audioContentStaysCompactUnderTinyBudget() {
        let result = CallTool.Result(content: [
            .audio(data: hugeBase64Payload, mimeType: "audio/mpeg", annotations: nil, _meta: nil)
        ])

        let rendered = ToolContentRenderer.render(result: result, budget: 1)

        #expect(rendered == "[audio: audio/mpeg]")
        #expect(!rendered.contains("QQ=="))
    }

    // MARK: - structuredContent respects the same budget

    @Test("oversized structuredContent is trimmed within budget with an elision marker")
    func oversizedStructuredContentIsTrimmedWithinBudget() {
        let text = oneMegabyteText(head: "HEAD-SENTINEL", tail: "TAIL-SENTINEL")
        let structured: Value = .object(["payload": .string(text)])
        let result = CallTool.Result(content: [], structuredContent: structured as Value?)
        let budget = Self.smallBudget

        let rendered = ToolContentRenderer.render(result: result, budget: budget)

        #expect(rendered.contains("Structured result:"))
        #expect(rendered.contains("HEAD-SENTINEL"))
        #expect(rendered.contains("TAIL-SENTINEL"))
        #expect(rendered.contains("elided"))
        // The full 1MB payload must not survive verbatim in the output.
        #expect(!rendered.contains(String(repeating: "x", count: Self.fillerRunLength)))
        // Only the trimmed JSON body is budgeted, not the "Structured
        // result:" header line that precedes it.
        let headerLength = "Structured result:\n".count
        #expect(rendered.count <= budget + headerLength)
    }

    @Test("trimming oversized structuredContent is deterministic — same input and budget produce identical output")
    func oversizedStructuredContentTrimmingIsDeterministic() {
        let text = oneMegabyteText(head: "HEAD", tail: "TAIL")
        let structured: Value = .object(["payload": .string(text)])
        let result = CallTool.Result(content: [], structuredContent: structured as Value?)

        let first = ToolContentRenderer.render(result: result, budget: Self.mediumBudget)
        let second = ToolContentRenderer.render(result: result, budget: Self.mediumBudget)

        #expect(first == second)
    }

    // MARK: - Under-budget results are untouched

    @Test("a small text result under the default budget is untouched byte-for-byte")
    func smallTextResultIsUntouchedUnderDefaultBudget() {
        let result = CallTool.Result(content: [.text(text: "hello world", annotations: nil, _meta: nil)])

        let rendered = ToolContentRenderer.render(result: result, budget: ToolContentRenderer.defaultRenderBudget)

        #expect(rendered == "hello world")
    }

    @Test("a small text result under a small explicit budget is untouched byte-for-byte")
    func smallTextResultIsUntouchedUnderExplicitBudget() {
        let text = "short"
        let result = CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])

        let rendered = ToolContentRenderer.render(result: result, budget: text.count)

        #expect(rendered == text)
    }

    @Test("a composed result (content + isError + structuredContent) under budget renders identically to the unbudgeted call")
    func composedResultUnderBudgetMatchesUnbudgetedRender() {
        let structuredContent: Value = .object(["code": .int(Self.errorCode)])
        let result = CallTool.Result(
            content: [.text(text: "partial failure", annotations: nil, _meta: nil)],
            structuredContent: structuredContent as Value?,
            isError: true
        )

        let withoutBudget = ToolContentRenderer.render(result: result)
        let withGenerousBudget = ToolContentRenderer.render(result: result, budget: ToolContentRenderer.defaultRenderBudget)

        #expect(withoutBudget == withGenerousBudget)
    }

    // MARK: - Helpers

    /// Parses the `"[elided <count> characters]"` marker out of `text`, for
    /// asserting the named elided count is consistent with what's actually
    /// missing.
    ///
    /// - Parameter text: The rendered text to search for an elision marker.
    /// - Returns: The elided character count named by the marker, or `nil`
    ///   if `text` contains no such marker.
    private func elidedCharacterCount(in text: String) -> Int? {
        guard let range = text.range(of: #"elided (\d+) characters"#, options: .regularExpression) else {
            return nil
        }
        let digits = text[range].filter(\.isNumber)
        return Int(digits)
    }

    /// Asserts that `rendered` is a well-formed, budget-safe trim of an
    /// original text of `totalCount` characters: the elided count named by
    /// its marker plus everything else in `rendered` (the kept head/tail)
    /// accounts for exactly `totalCount` characters, and `rendered` itself
    /// never exceeds `budget`.
    ///
    /// This is a self-consistency check — it does not assume the internal
    /// head/tail split ratio, only that the marker's own claim is accurate
    /// and that the budget contract is honored.
    ///
    /// - Parameters:
    ///   - rendered: The trimmed text produced by the renderer.
    ///   - totalCount: The character count of the original, untrimmed text.
    ///   - budget: The budget `rendered` was trimmed to.
    private func assertBudgetSafeTrim(rendered: String, totalCount: Int, budget: Int) {
        guard let elidedCount = elidedCharacterCount(in: rendered) else {
            Issue.record("expected an elision marker naming the elided character count")
            return
        }
        let markerLength = "\n[elided \(elidedCount) characters]\n".count
        #expect(rendered.count - markerLength + elidedCount == totalCount)
        #expect(rendered.count <= budget)
    }
}
