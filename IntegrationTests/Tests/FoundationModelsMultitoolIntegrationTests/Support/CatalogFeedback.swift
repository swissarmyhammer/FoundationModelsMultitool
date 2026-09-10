import Foundation

/// The banner line every spliced catalog block opens with, up to the path.
///
/// `SearchToolsTool.format(task:matches:sample:)` splices each matched
/// entry's `APISurface.Entry.block` verbatim, and that block opens with
/// `// tools.<path>` — so the paths the model was handed are readable off
/// the banner lines and off nothing else. The same prefix stands inside the
/// entry descriptions ("pass it to tools.shell.getLines"), which is why
/// ``catalogPaths(in:)`` reads a whole line and never a substring.
let catalogBannerPrefix = "// tools."

/// The catalog paths a `searchTools` result handed the model, in the order
/// the result lists them — one for each spliced block's banner line.
///
/// The order is the answer this package gives, so a reader of this list
/// reads what the model read, in the order it read it. The rule that order
/// obeys is written on `SearchToolsTool.format(task:matches:sample:)`.
///
/// - Parameter feedback: the text `SearchToolsTool.call(arguments:)`
///   answered.
/// - Returns: the `tools.*` paths of the matched entries, without the
///   `tools.` prefix; empty for the "found no matching functions" answer.
func catalogPaths(in feedback: String) -> [String] {
    feedback
        .split(separator: "\n", omittingEmptySubsequences: true)
        .filter { $0.hasPrefix(catalogBannerPrefix) }
        .map { String($0.dropFirst(catalogBannerPrefix.count)) }
}

/// Prints one `RESULT` line of a gated suite, in the shape every gated suite
/// prints its readings, so a log reader finds them under one label.
///
/// - Parameters:
///   - scenario: the label the printed line carries.
///   - line: the reading to print after the label.
func reportGatedResult(scenario: String, line: String) {
    // The gated suites report their readings on standard out, where a CI log
    // reader finds them beside the other `RESULT` lines.
    // swiftlint:disable:next no_direct_standard_out_logs
    print("RESULT [\(scenario)] \(line)")
}
