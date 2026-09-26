import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// The checks that the detail of a finished background run stays within the
/// caps of `ResultRenderer`.
///
/// The detail of a terminal event comes back to the model as mail, and Router
/// carries it whole. Thus the caps of this package are the only bound on it,
/// and the tests of task `^v6en6ba` use these helpers to prove that bound for
/// `runCode` and for `tools.shell.execute`.
enum TerminalDetail {

    /// The text that starts the note `ResultRenderer` adds after a cut.
    ///
    /// Built from ``ResultRenderer/truncationMarker``, the one place the word
    /// is written, thus a reword of the note cannot make this check pass
    /// against text that was not cut.
    private static var truncationNoteStart: String {
        "\n[\(ResultRenderer.truncationMarker):"
    }

    /// Waits for the terminal event of one background run.
    ///
    /// - Parameters:
    ///   - completionToken: The token of the run.
    ///   - context: The session context that tracks the run.
    /// - Returns: The terminal event of the run.
    /// - Throws: When the run does not settle in
    ///   `scriptedRunSettlementSeconds`.
    static func settledEvent(
        of completionToken: String, in context: ToolContext
    ) async throws -> OperationEvent {
        let settlement = await context.wait(
            completionToken: completionToken, seconds: scriptedRunSettlementSeconds)
        guard case .settled(let terminal) = settlement else {
            throw TerminalDetailFailure.neverSettled(String(describing: settlement))
        }
        return terminal
    }

    /// The part of `section` in front of the truncation note.
    ///
    /// - Parameter section: One section of a rendered result: the return
    ///   value, or the console output.
    /// - Returns: The text that `ResultRenderer` kept, or `nil` when it did not
    ///   cut `section`.
    static func keptText(of section: String) -> Substring? {
        guard let note = section.range(of: truncationNoteStart) else { return nil }
        return section[..<note.lowerBound]
    }
}

/// Why ``TerminalDetail`` could not give a terminal event.
enum TerminalDetailFailure: Error, CustomStringConvertible {
    /// The run did not settle in time. The value is what the wait gave.
    case neverSettled(String)

    /// The message the test report shows.
    var description: String {
        switch self {
        case .neverSettled(let settlement):
            "the run never settled: \(settlement)"
        }
    }
}
