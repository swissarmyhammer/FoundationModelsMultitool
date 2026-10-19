import Foundation
import FoundationModelsExtras
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
        try terminalEvent(
            of: await context.wait(completionToken: completionToken, seconds: scriptedRunSettlementSeconds))
    }

    /// Waits for the terminal event of one background run, on the run plane
    /// itself — for a test that mounts on a `MountSite` and holds no
    /// `ToolContext`.
    ///
    /// - Parameters:
    ///   - completionToken: The token of the run.
    ///   - runPlane: The run plane that tracks the run.
    /// - Returns: The terminal event of the run.
    /// - Throws: When the run does not settle in
    ///   `scriptedRunSettlementSeconds`.
    static func settledEvent(
        of completionToken: String, on runPlane: RunPlane
    ) async throws -> OperationEvent {
        try terminalEvent(
            of: await runPlane.wait(completionToken: completionToken, seconds: scriptedRunSettlementSeconds))
    }

    /// The terminal event of one wait for a run.
    ///
    /// - Parameter settlement: The outcome of the wait.
    /// - Returns: The terminal event of the run.
    /// - Throws: When the wait ended before the run settled.
    private static func terminalEvent(of settlement: WaitOutcome) throws -> OperationEvent {
        guard case .settled(let terminal) = settlement else {
            throw TerminalDetailFailure.neverSettled(String(describing: settlement))
        }
        return terminal
    }

    /// Waits until one background run settled, with no deadline — the
    /// second event of a test that waits for a step of that run.
    ///
    /// A run that settled cannot do a step any more. Thus a test that waits
    /// for the step also waits for this event, and fails at once when it
    /// comes first. The wait returns at once for a run that already settled,
    /// and for a token that the run plane does not know. A cancel of the task
    /// of the caller also ends it, thus ``EventRace/firstOf(_:or:)`` can end
    /// it.
    ///
    /// - Parameters:
    ///   - completionToken: The token of the run.
    ///   - context: The session context that tracks the run.
    static func waitForEnd(of completionToken: String, in context: ToolContext) async {
        _ = await context.wait(completionToken: completionToken, seconds: nil)
    }

    /// The wait for the end of the run of a pending envelope — see
    /// ``waitForEnd(of:in:)``.
    ///
    /// - Parameters:
    ///   - rendered: The pending envelope that a mounted call answered with.
    ///   - context: The session context that tracks the run.
    /// - Returns: The wait, for ``EventRace/firstOf(_:or:)`` or for
    ///   `ManualRunClock.waitForSleepers(atLeast:orUntil:)`.
    /// - Throws: When `rendered` is not a pending envelope.
    static func runEnd(
        of rendered: String, in context: ToolContext
    ) throws -> @Sendable () async -> Void {
        let completionToken = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
            .completionToken
        return { await waitForEnd(of: completionToken, in: context) }
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
