import Foundation
import FoundationModelsRouter
import Testing

/// The offline checks of how the shell background scenario counts the
/// background report of the `tools.shell.execute` run (card `^pw3p6gb`).
///
/// Under the settle-period rule (card `^38j4bbn`) the outer `runCode` call of
/// the scenario answers with its own result, and the inner
/// `tools.shell.execute` run is the run that goes to the background. That
/// inner run posts its background report through the ambient context of the
/// outer call, so the journal holds the report under the correlation of the
/// OUTER run. Each check here gives journaled events to
/// `backgroundReportCount(in:of:)`. No check loads a model or starts a
/// process. Thus each check always runs, and it is fast.
@Suite("The shell background scenario counts the background report of the execute run")
struct ShellBackgroundReportTests {
    /// The completion token of the outer `runCode` run.
    private static let outerRunToken = "01M4GA0Y38HZK62EFTZBCCQ39D"

    /// The completion token of the inner `tools.shell.execute` run.
    private static let executeRunToken = "01M4GA0YA5WBXH5TQ3T6GPK18Q"

    /// The completion token of a different background run of the same
    /// session, as the run the scenario leaves for the session-end sweep.
    private static let otherRunToken = "01M4GA9ZRG20YT5M75APW3P6GB"

    /// The `next` text of each envelope. The count does not read it.
    private static let collectInstruction = "End your answer now."

    /// The tool the reports stand under. The count does not read it.
    private static let reportingTool = "runCode"

    /// Makes the rendered pending envelope of one run.
    ///
    /// The envelope is decoded through its own `Codable` conformance and
    /// rendered through its own `rendered` property, so this test spells no
    /// wire form of its own.
    ///
    /// - Parameter token: the completion token of the run.
    /// - Returns: the rendered envelope.
    /// - Throws: an error when the envelope does not decode.
    private static func renderedEnvelope(of token: String) throws -> String {
        let fields: [String: Any] = [
            "pending": true, "completionToken": token, "next": collectInstruction,
        ]
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(PendingRunEnvelope.self, from: data).rendered
    }

    /// Makes one journaled progress event under the outer run's correlation.
    ///
    /// - Parameter detail: the detail of the event.
    /// - Returns: the event.
    private static func outerProgress(detail: String) -> OperationEvent {
        OperationEvent(
            tool: reportingTool, op: reportingTool, correlationID: outerRunToken,
            kind: .progress, detail: detail)
    }

    @Test("a report under the outer run's correlation counts for the execute run it names")
    func reportUnderTheOuterCorrelationCounts() throws {
        let events = [Self.outerProgress(detail: try Self.renderedEnvelope(of: Self.executeRunToken))]

        #expect(backgroundReportCount(in: events, of: Self.executeRunToken) == 1)
    }

    @Test("a report that names another run does not count for the execute run")
    func reportOfAnotherRunDoesNotCount() throws {
        let events = [Self.outerProgress(detail: try Self.renderedEnvelope(of: Self.otherRunToken))]

        #expect(backgroundReportCount(in: events, of: Self.executeRunToken) == 0)
    }
}
