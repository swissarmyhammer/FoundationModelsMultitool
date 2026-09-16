import Testing

@testable import FoundationModelsMultitool

/// Coverage for `JavaScriptLiteralSyntax`: the recognizer that decides
/// whether a caller-supplied `RenderedParameter.exampleValue` is one
/// JavaScript literal expression before `ToolAPIRenderer` splices it into
/// the generated `@example` call.
@Suite("JavaScriptLiteralSyntax")
struct JavaScriptLiteralSyntaxTests {
    /// One text per literal form the recognizer accepts: each scalar form,
    /// each escape and quote style, nested arrays and objects, identifier
    /// and string keys, and surrounding whitespace.
    static let literals: [String] = [
        #""a""#,
        "'a'",
        #""esc \" \\ \n \t""#,
        "0",
        "-3",
        "1.5",
        "1e+20",
        "2E-3",
        "true",
        "false",
        "null",
        "[]",
        #"[1, "a", [true]]"#,
        "{}",
        "{ a: 1 }",
        #"{ "a b": 1, $c_1: [null] }"#,
        "  {\n  a: 1\n}  ",
        "{ a: { b: [ { } ] } }",
    ]

    @Test("one literal expression is recognized", arguments: literals)
    func recognizesOneLiteral(_ text: String) {
        #expect(JavaScriptLiteralSyntax.isLiteral(text), "text was: \(text)")
    }

    /// One text per shape the recognizer refuses: nothing, an identifier, a
    /// call, an operator, a second statement, a balanced break-out, two
    /// literals in a row, an unterminated or line-broken string, an
    /// incomplete number, a trailing comma, and a malformed object member.
    static let nonLiterals: [String] = [
        "",
        "   ",
        "a",
        "evil()",
        "undefined",
        "NaN",
        "1 + 2",
        "1; 2",
        "1) + (2",
        #""a" "b""#,
        #""unterminated"#,
        "\"line\nbreak\"",
        "\"line\u{2028}break\"",
        "-",
        "1.",
        "1e",
        "[1,]",
        "[1 2]",
        "{ a }",
        "{ a: }",
        "{ a: 1 b: 2 }",
        "{ 1: 2 }",
        "trueish",
        #""a"b"#,
    ]

    @Test("a text that is not one literal expression is refused", arguments: nonLiterals)
    func refusesWhatIsNotOneLiteral(_ text: String) {
        #expect(!JavaScriptLiteralSyntax.isLiteral(text), "text was: \(text)")
    }
}
