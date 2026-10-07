import Testing

@testable import FoundationModelsMultitool

/// Tests for the quote rules of ``RustText``: the one shared function that
/// puts a text in quote marks, and the two escape rules that use it (the Rust
/// `Debug` of a `str`, and the JSON string of serde_json).
@Suite("RustTextTests")
struct RustTextTests {

    /// The shared function puts each scalar through the escape callback, in
    /// order, and puts the result in quote marks.
    @Test("quoted applies the escape callback to each scalar")
    func quotedAppliesTheEscapeCallbackToEachScalar() {
        let quoted = RustText.quoted("ab") { "<\($0)>" }

        #expect(quoted == "\"<a><b>\"")
    }

    /// An empty text gives only the two quote marks.
    @Test("quoted writes an empty text as two quote marks")
    func quotedWritesAnEmptyTextAsTwoQuoteMarks() {
        #expect(RustText.quoted("") { _ in "x" } == "\"\"")
    }

    /// The Rust `Debug` text uses a short escape, a `\u{…}` escape, or the
    /// scalar itself.
    @Test("debugQuoted writes the Rust Debug escapes")
    func debugQuotedWritesTheRustDebugEscapes() {
        #expect(RustText.debugQuoted("a\"\n\u{7F}é") == "\"a\\\"\\n\\u{7f}é\"")
    }

    /// The JSON text uses a short escape, a `\u00XX` escape, or the scalar
    /// itself.
    @Test("JSONText.quoted writes the serde_json escapes")
    func jsonQuotedWritesTheSerdeJSONEscapes() {
        #expect(JSONText.quoted("a\"\n\u{01}é") == "\"a\\\"\\n\\u0001é\"")
    }
}
