import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Proves that the terminal event of an inner `tools.*` call never takes the
/// place of the terminal event of the `runCode` call that made it.
///
/// The engine mounts each inner call on the context of the `runCode` run, and
/// the sink of that mount sends each event of the inner run through the
/// `runCode` context. An inner call that fails ends with its own terminal
/// event. When that event goes up as a terminal event of the `runCode` run,
/// the funnel of the `runCode` run keeps it as the one terminal, and drops the
/// real terminal of the `runCode` run.
///
/// Each test mounts `runCode` the way a Router session mounts it, with a sink
/// that records each event, and compares the terminal events on that sink for
/// the `runCode` completion token with the terminal event of the run plane.
@Suite("an inner tools.* terminal never takes the place of the runCode terminal")
struct InnerTerminalEventTests {
    @Test("a mounted runCode whose snippet catches an inner failure gives one succeeded terminal")
    func caughtInnerFailureGivesOneSucceededTerminal() async throws {
        let run = try await Self.run(snippet: Self.catchingSnippet)

        #expect(run.sinkTerminals.count == 1, "terminals on the sink: \(run.sinkTerminals)")
        let terminal = try #require(run.sinkTerminals.first)
        #expect(terminal.outcome == .succeeded)
        #expect(terminal.detail == run.settled.detail)
        #expect(run.settled.outcome == .succeeded)
    }

    @Test("a mounted runCode whose snippet does not catch an inner failure gives one runCode terminal")
    func uncaughtInnerFailureGivesOneRunCodeTerminal() async throws {
        let run = try await Self.run(snippet: Self.uncaughtSnippet)

        #expect(run.sinkTerminals.count == 1, "terminals on the sink: \(run.sinkTerminals)")
        let terminal = try #require(run.sinkTerminals.first)
        #expect(terminal.outcome == run.settled.outcome)
        #expect(terminal.detail == run.settled.detail)
        #expect(terminal.tool == run.settled.tool)
    }

    // MARK: - Fixtures

    /// The snippet that calls ``FailingTool``, catches its error, and returns
    /// a value.
    private static let catchingSnippet = """
        try {
          await tools.failing();
        } catch (error) {
          return "caught";
        }
        return "not thrown";
        """

    /// The snippet that calls ``FailingTool`` and does not catch its error.
    private static let uncaughtSnippet = "return await tools.failing();"

    /// What one mounted `runCode` run gave.
    private struct RecordedRun {
        /// The terminal events on the session sink for the `runCode`
        /// completion token, in arrival order.
        let sinkTerminals: [OperationEvent]

        /// The terminal event that the run plane keeps for the `runCode`
        /// completion token.
        let settled: OperationEvent
    }

    /// Mounts `runCode` over a registry with ``FailingTool``, runs `snippet`,
    /// and waits until the run settles.
    ///
    /// The mount posts each event of the `runCode` run to a recording sink
    /// with the `runCode` completion token. The run plane gives its terminal
    /// event only after the funnel of the run sent its last event to the
    /// sink, thus the sink holds each event when this function reads it.
    ///
    /// - Parameter snippet: The snippet to run.
    /// - Returns: The terminal events on the sink and on the run plane.
    private static func run(snippet: String) async throws -> RecordedRun {
        let context = try await makeOuterRunContext()
        let sink = RecordingEventSink()
        let registry = try MultiTool.Builder().addTool(FailingTool()).buildRegistry()
        let mounted = try #require(
            context.mount(MultiTool(registry: registry), as: .synchronous, postingTo: sink)
                as? any Tool<RunCodeArguments, String>
        )

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: snippet))

        let token = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8)).completionToken
        let settled = try await TerminalDetail.settledEvent(of: token, in: context)
        let terminals = await sink.events.filter { $0.kind == .completed && $0.correlationID == token }
        return RecordedRun(sinkTerminals: terminals, settled: settled)
    }
}

/// The error that ``FailingTool`` throws.
private struct InnerToolFailure: Error, CustomStringConvertible {
    /// The text of the error.
    var description: String { "the inner tool failed" }
}

/// A `String` tool that always throws ``InnerToolFailure``.
///
/// The output is `String`, thus the engine runs each inner call of it as a
/// full run with its own funnel and its own terminal event.
private struct FailingTool: Tool {
    /// The `Tool` name. A snippet reaches it as `tools.failing()`.
    let name = "failing"

    /// The model-facing description. No test reads it.
    let description = "Always throws."

    /// Throws ``InnerToolFailure``.
    ///
    /// - Parameter arguments: No arguments.
    /// - Returns: Never returns.
    func call(arguments: NoArguments) async throws -> String {
        throw InnerToolFailure()
    }
}
