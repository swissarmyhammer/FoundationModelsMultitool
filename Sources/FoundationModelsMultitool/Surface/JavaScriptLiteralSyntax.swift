/// Recognizes one JavaScript literal expression: the grammar a
/// `ToolAPIRenderer.RenderedParameter.exampleValue` must satisfy before the
/// renderer splices it into the generated `@example` call.
///
/// The recognizer is deliberately narrower than JavaScript. It accepts a
/// string literal in double or single quotes with backslash escapes, a
/// decimal number with an optional leading minus, fraction and exponent,
/// the keywords `true`, `false` and `null`, an array literal of literals,
/// and an object literal whose keys are bare identifiers or string literals
/// and whose values are literals. Whitespace may surround any token. It
/// accepts nothing else: no identifier, no call, no operator, no comment, no
/// trailing comma, no second statement. A text that passes therefore cannot
/// close the object literal it lands in, cannot open a statement of its own,
/// and cannot name a binding — which is what makes the check a sufficient
/// guard for text a caller supplies.
///
/// A syntax check of `(<text>)` through the interpreter is not enough here:
/// `1); evil(); (2` keeps the parentheses balanced and parses, yet it is
/// three statements. This recognizer reads the text itself, so that text is
/// refused.
///
/// Recognizing rather than parsing: the renderer only needs a yes or a no,
/// so the recognizer builds no tree and reports no position. A refused text
/// is reported whole by `ToolAPIRendererError`.
enum JavaScriptLiteralSyntax {
    /// Whether `text` is exactly one JavaScript literal expression, with
    /// optional whitespace before and after it.
    ///
    /// - Parameter text: the candidate literal source text.
    /// - Returns: `true` when the whole of `text` is one literal.
    static func isLiteral(_ text: String) -> Bool {
        var reader = Reader(text)
        reader.skipWhitespace()
        guard reader.readLiteral() else { return false }
        reader.skipWhitespace()
        return reader.isAtEnd
    }

    /// The whitespace the recognizer skips between tokens: a space, a tab,
    /// a line feed and a carriage return.
    private static let whitespace: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r"]

    /// The line terminators JavaScript forbids inside a string literal
    /// unescaped: a line feed, a carriage return, and the two Unicode line
    /// terminators `ToolAPIRenderer.jsStringLiteral(_:)` escapes.
    private static let stringLineTerminators: Set<Unicode.Scalar> = ["\n", "\r", "\u{2028}", "\u{2029}"]

    /// The keywords the recognizer accepts as literals.
    private static let keywordLiterals: Set<String> = ["true", "false", "null"]

    /// What one entry of a delimited list is: a bare literal in an array,
    /// or a `key: literal` member in an object.
    private enum ListEntry {
        case literal
        case objectMember
    }

    /// A cursor over the scalars of one text, with one `read…` method per
    /// production of the grammar. Each `read…` method consumes its
    /// production and returns `true`, or returns `false` with the cursor
    /// somewhere inside the failed production — `isLiteral(_:)` never reads
    /// on after a failure, so the position after one is not load-bearing.
    private struct Reader {
        private let scalars: [Unicode.Scalar]
        private var index = 0

        /// Creates a reader positioned at the start of `text`.
        ///
        /// - Parameter text: the text to read.
        init(_ text: String) {
            scalars = Array(text.unicodeScalars)
        }

        /// Whether every scalar has been consumed.
        var isAtEnd: Bool { index >= scalars.count }

        /// The scalar under the cursor, or `nil` at the end.
        private var current: Unicode.Scalar? { isAtEnd ? nil : scalars[index] }

        /// Consumes the scalar under the cursor when it is `scalar`.
        ///
        /// - Parameter scalar: the scalar to match.
        /// - Returns: `true` when the scalar matched and was consumed.
        private mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
            guard current == scalar else { return false }
            index += 1
            return true
        }

        /// Consumes scalars while `predicate` holds.
        ///
        /// - Parameter predicate: the test each scalar must pass.
        /// - Returns: the number of scalars consumed.
        private mutating func consume(while predicate: (Unicode.Scalar) -> Bool) -> Int {
            let start = index
            while let scalar = current, predicate(scalar) {
                index += 1
            }
            return index - start
        }

        /// Skips the whitespace the grammar allows between tokens.
        mutating func skipWhitespace() {
            _ = consume(while: { whitespace.contains($0) })
        }

        /// Reads one literal of any form, chosen by its first scalar.
        ///
        /// - Returns: `true` when one complete literal was consumed.
        mutating func readLiteral() -> Bool {
            guard let scalar = current else { return false }
            switch scalar {
            case "\"", "'":
                return readString()
            case "[":
                return readList(open: "[", close: "]", entry: .literal)
            case "{":
                return readList(open: "{", close: "}", entry: .objectMember)
            case "-":
                return readNumber()
            default:
                return isDigit(scalar) ? readNumber() : readKeyword()
            }
        }

        /// Reads a string literal: the opening quote, any run of escapes
        /// and plain scalars, and the matching closing quote. A backslash
        /// consumes the scalar after it whatever it is, and an unescaped
        /// line terminator ends the string without closing it.
        ///
        /// - Returns: `true` when a complete string literal was consumed.
        private mutating func readString() -> Bool {
            guard let quote = current, quote == "\"" || quote == "'" else { return false }
            index += 1
            while let scalar = current {
                if scalar == quote {
                    index += 1
                    return true
                }
                guard !stringLineTerminators.contains(scalar) else { return false }
                index += 1
                if scalar == "\\" {
                    guard !isAtEnd else { return false }
                    index += 1
                }
            }
            return false
        }

        /// Reads a decimal number: an optional minus, one or more digits,
        /// an optional fraction of one or more digits, and an optional
        /// exponent with an optional sign and one or more digits.
        ///
        /// - Returns: `true` when a complete number was consumed.
        private mutating func readNumber() -> Bool {
            _ = consume("-")
            guard consume(while: isDigit) > 0 else { return false }
            if consume(".") {
                guard consume(while: isDigit) > 0 else { return false }
            }
            if consume("e") || consume("E") {
                _ = consume("+") || consume("-")
                guard consume(while: isDigit) > 0 else { return false }
            }
            return true
        }

        /// Reads one of the keyword literals `true`, `false` or `null`, as
        /// a whole word.
        ///
        /// - Returns: `true` when one keyword literal was consumed.
        private mutating func readKeyword() -> Bool {
            guard let word = readWord() else { return false }
            return keywordLiterals.contains(word)
        }

        /// Consumes one run of identifier scalars and returns it as a word.
        ///
        /// - Returns: the word, or `nil` when no identifier scalar is under
        ///   the cursor.
        private mutating func readWord() -> String? {
            let start = index
            guard consume(while: isIdentifierScalar) > 0 else { return nil }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }

        /// Reads a delimited, comma-separated list — an array literal or an
        /// object literal — with any whitespace around its entries. The
        /// list may be empty. A trailing comma is refused.
        ///
        /// - Parameters:
        ///   - open: the opening bracket.
        ///   - close: the closing bracket.
        ///   - entry: what each entry of the list is.
        /// - Returns: `true` when a complete list was consumed.
        private mutating func readList(open: Unicode.Scalar, close: Unicode.Scalar, entry: ListEntry) -> Bool {
            guard consume(open) else { return false }
            skipWhitespace()
            if consume(close) { return true }
            while true {
                guard readEntry(entry) else { return false }
                skipWhitespace()
                if consume(close) { return true }
                guard consume(",") else { return false }
                skipWhitespace()
            }
        }

        /// Reads one entry of a list, by kind.
        ///
        /// - Parameter entry: what the entry is.
        /// - Returns: `true` when one complete entry was consumed.
        private mutating func readEntry(_ entry: ListEntry) -> Bool {
            switch entry {
            case .literal:
                return readLiteral()
            case .objectMember:
                return readObjectMember()
            }
        }

        /// Reads one `key: literal` member of an object literal. The key is
        /// a bare identifier `ToolAPIRenderer.isLegalTSIdentifier(_:)`
        /// accepts, or a string literal.
        ///
        /// - Returns: `true` when one complete member was consumed.
        private mutating func readObjectMember() -> Bool {
            guard readObjectKey() else { return false }
            skipWhitespace()
            guard consume(":") else { return false }
            skipWhitespace()
            return readLiteral()
        }

        /// Reads an object key: a string literal, or a bare identifier.
        ///
        /// - Returns: `true` when one complete key was consumed.
        private mutating func readObjectKey() -> Bool {
            guard let scalar = current else { return false }
            if scalar == "\"" || scalar == "'" {
                return readString()
            }
            guard let key = readWord() else { return false }
            return ToolAPIRenderer.isLegalTSIdentifier(key)
        }

        /// Whether `scalar` is an ASCII decimal digit.
        ///
        /// - Parameter scalar: the scalar to test.
        /// - Returns: `true` for `0` through `9`.
        private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
            ("0"..."9").contains(scalar)
        }

        /// Whether `scalar` can stand in a bare identifier or keyword: an
        /// ASCII letter, a digit, `_` or `$` — the same alphabet
        /// `ToolAPIRenderer.isLegalTSIdentifier(_:)` reads.
        ///
        /// - Parameter scalar: the scalar to test.
        /// - Returns: `true` when the scalar is in that alphabet.
        private func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
            isDigit(scalar) || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                || scalar == "_" || scalar == "$"
        }
    }
}
