// MARK: - The no-op check of a runCode snippet
//
// SWE-bench run no-otel-1011 recorded a model that sent 73 `runCode` calls
// while one `tools.*` call was pending. Each of these snippets called no
// `tools.*` verb (`return null`, `return "end 11"`, ...), and one form
// (`await new Promise(() => {});`) never settles. A host must know that a call
// is a no-op before it runs the call, so the check reads the snippet text and
// never runs it (task `^9pnyvyp`). The check only gives information: the
// Multitool does not block or change a call because of it.

extension MultiTool {
    /// The identifier through which a snippet reaches every `tools.*` verb,
    /// as UTF-8 bytes. The preamble of each run binds it as
    /// `globalThis.tools`.
    private static let toolsIdentifier = Array("tools".utf8)

    /// The bytes that start a JavaScript `\u` escape. An identifier can hold
    /// one, so a snippet can spell `tools` with no plain `tools` in its text.
    private static let unicodeEscapeOpener = Array("\\u".utf8)

    /// The bytes that continue an ASCII JavaScript identifier. Each other
    /// byte counts as a word boundary. A non-ASCII identifier character
    /// therefore counts as a boundary too, and that only makes the check
    /// return `false` more often.
    private static let identifierPartBytes = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$".utf8)

    /// Tells if a `runCode` snippet calls no `tools.*` verb.
    ///
    /// The check is static and pure: it reads the snippet text and never runs
    /// the snippet. A host uses it to see a no-op call before the call runs,
    /// for example a call that only returns a placeholder while an earlier
    /// call is pending.
    ///
    /// The result is `true` only when the text holds no whole-word identifier
    /// `tools` and no `\u` escape. A snippet that names `tools` through an
    /// alias (`const t = tools;`) or a computed member (`tools["shell"]`)
    /// thus gives `false`. The check is strict in one direction only: a
    /// no-op snippet that holds the word `tools`, for example in a string or
    /// a comment, gives `false`, and that is safe.
    ///
    /// A static check of the text cannot see a name that the snippet builds
    /// at run time, for example `globalThis["to" + "ols"]`.
    ///
    /// - Parameter snippet: The raw JavaScript text of the call, as
    ///   `RunCodeArguments.snippet` holds it.
    /// - Returns: `true` when the snippet calls no `tools.*` verb.
    public static func callsNoTool(snippet: String) -> Bool {
        let bytes = Array(snippet.utf8)
        guard bytes.firstRange(of: unicodeEscapeOpener) == nil else { return false }
        let matches = bytes.ranges(of: toolsIdentifier)
        return !matches.contains { isWholeIdentifier($0, in: bytes) }
    }

    /// Tells if the bytes in `range` are a whole identifier: no identifier
    /// byte comes directly before or directly after them.
    ///
    /// - Parameters:
    ///   - range: The range of one match of ``toolsIdentifier``.
    ///   - bytes: The UTF-8 bytes of the snippet.
    /// - Returns: `true` when both neighbors are word boundaries.
    private static func isWholeIdentifier(_ range: Range<Int>, in bytes: [UInt8]) -> Bool {
        let neighbors = [bytes[..<range.lowerBound].last, bytes[range.upperBound...].first]
        return neighbors.allSatisfy { neighbor in
            neighbor.map { !identifierPartBytes.contains($0) } ?? true
        }
    }
}
