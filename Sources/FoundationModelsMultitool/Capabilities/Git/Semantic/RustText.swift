// `RustText` — the text rules of the Rust `str` methods that the plugins of
// the semantic diff call.
//
// The Rust plugins in `../swissarmyhammer/crates/swissarmyhammer-sem/src/`
// cut and trim text with `str::lines`, `str::trim`, `str::trim_start`, and
// `str::trim_end`, and the YAML plugin writes the `Debug` text of a `str`.
// Each Swift plugin uses these functions, so that each line, each trimmed
// text, and each `Debug` text is the same as in Rust.

/// The text rules of the Rust `str` methods that the plugins call.
enum RustText {

    /// The lines of `text`: the Rust `str::lines`.
    ///
    /// A line ends at `\n`, and a `\r` just before the `\n` is not in the
    /// line. A newline at the end of the text gives no empty last line. A
    /// lone `\r` stays in its line.
    ///
    /// - Parameter text: The text to cut.
    /// - Returns: The lines, or no line for an empty text.
    static func lines(of text: String) -> [String] {
        EditMatch.lines(of: text)
    }

    /// Whether `scalar` is whitespace for the Rust `str::trim`: the Unicode
    /// `White_Space` property.
    ///
    /// - Parameter scalar: The scalar to test.
    /// - Returns: `true` for a whitespace scalar.
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    /// `text` with no whitespace at its two ends: the Rust `str::trim`.
    ///
    /// - Parameter text: The text to trim.
    /// - Returns: The trimmed text.
    static func trimmed(_ text: some StringProtocol) -> String {
        trimmedEnd(trimmedStart(text))
    }

    /// `text` with no whitespace at its start: the Rust `str::trim_start`.
    ///
    /// - Parameter text: The text to trim.
    /// - Returns: The trimmed text.
    static func trimmedStart(_ text: some StringProtocol) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.drop(while: isWhitespace)))
    }

    /// `text` with no whitespace at its end: the Rust `str::trim_end`.
    ///
    /// - Parameter text: The text to trim.
    /// - Returns: The trimmed text.
    static func trimmedEnd(_ text: some StringProtocol) -> String {
        let scalars = text.unicodeScalars
        let end = scalars.lastIndex { !isWhitespace($0) }.map(scalars.index(after:)) ?? scalars.startIndex
        return String(String.UnicodeScalarView(scalars[..<end]))
    }

    /// Whether `text` holds only whitespace: `text.trim().is_empty()` in Rust.
    ///
    /// - Parameter text: The text to test.
    /// - Returns: `true` for an empty text and for a text of whitespace.
    static func isBlank(_ text: some StringProtocol) -> Bool {
        text.unicodeScalars.allSatisfy(isWhitespace)
    }

    /// The short escapes of the Rust `Debug` of a `str`: `"`, `\`, newline,
    /// tab, carriage return, and NUL.
    private static let debugShortEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\t": "\\t", "\r": "\\r", "\0": "\\0",
    ]

    /// The scalars that the Rust `Debug` of a `str` writes as they are with
    /// no test: the printable ASCII range (`'\x20'..='\x7E'`).
    private static let debugPrintableASCII: ClosedRange<UInt32> = 0x20...0x7E

    /// `text` in quote marks with the escapes of the Rust `Debug` of a `str`
    /// (`format!("{:?}", text)`, `escape_debug_ext` in `core::char`).
    ///
    /// `"`, `\`, newline, tab, carriage return, and NUL get a short escape. A
    /// scalar that is a control, a private use, whitespace (other than a
    /// space), a grapheme extender, a default ignorable, a format control, or
    /// unassigned gets `\u{<hex>}`. Each other scalar stays as it is. The
    /// Unicode tables of Swift and of Rust can differ for a scalar that a
    /// newer Unicode version assigns.
    ///
    /// - Parameter text: The text.
    /// - Returns: The quoted text.
    static func debugQuoted(_ text: String) -> String {
        "\"" + text.unicodeScalars.map(debugText).joined() + "\""
    }

    /// The text of one scalar in the Rust `Debug` of a `str`: its short
    /// escape, its `\u{<hex>}` escape, or the scalar itself.
    private static func debugText(of scalar: Unicode.Scalar) -> String {
        if let escape = debugShortEscapes[scalar] {
            return escape
        }
        if !debugPrintableASCII.contains(scalar.value) && needsUnicodeEscape(scalar) {
            return "\\u{" + String(scalar.value, radix: NumberRadix.hexadecimal) + "}"
        }
        return String(scalar)
    }

    /// Whether the Rust `Debug` of a `str` writes `scalar` as `\u{…}`.
    private static func needsUnicodeEscape(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        switch properties.generalCategory {
        case .control, .privateUse, .format, .unassigned:
            return true
        default:
            return properties.isWhitespace || properties.isGraphemeExtend || properties.isDefaultIgnorableCodePoint
        }
    }
}
