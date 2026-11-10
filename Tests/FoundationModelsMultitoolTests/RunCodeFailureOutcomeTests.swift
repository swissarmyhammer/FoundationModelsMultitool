import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Tests that a code mode snippet that fails ends its run as failed, and that
/// the error text goes on the terminal event as the value. The text that the
/// model gets does not change.
///
/// Each test mounts `runCode` in the way a session mounts it, runs one snippet,
/// and reads the terminal event of the run.
@Suite("RunCodeFailureOutcomeTests", .ownsTemporaryDirectories)
struct RunCodeFailureOutcomeTests {

    /// A snippet that returns a value.
    private static let succeedingSnippet = "return 1 + 1;"

    /// A snippet that throws an error when it runs.
    private static let throwingSnippet = #"throw new Error("boom");"#

    /// A snippet that does not parse, and that no repair makes parse.
    private static let brokenSnippet = "return )(;"

    /// A snippet that does not parse, and that the repair makes parse: a
    /// closer is missing at the end.
    private static let repairableSnippet = "return (1 + 2"

    /// A snippet that runs a nested snippet which does not parse, and
    /// catches the failure of the nested run.
    private static let nestedCatchingSnippet = """
        try {
          await tools.runCode("return )(;");
        } catch (error) {
          return "caught";
        }
        return "not thrown";
        """

    /// Mounts `runCode`, runs `snippet`, and waits for the terminal event.
    ///
    /// A settle period of 0 sends the run to the background at once, so the
    /// run plane keeps the terminal event for the completion token.
    ///
    /// - Parameter snippet: The snippet to run.
    /// - Returns: The terminal event of the run.
    /// - Throws: When the mount, the call or the wait fails.
    private static func terminal(running snippet: String) async throws -> OperationEvent {
        try await withOuterRunContext { context in
            let registry = try MultiTool.Builder(mode: .open).buildRegistry()
            let runCode = MultiTool(registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 0))
            let mounted = try #require(
                context.mount(runCode, as: .synchronous, postingTo: RecordingEventSink())
                    as? any Tool<RunCodeArguments, String>
            )
            let rendered = try await mounted.call(arguments: RunCodeArguments(code: snippet))
            let token = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8)).completionToken
            return try await TerminalDetail.settledEvent(of: token, in: context)
        }
    }

    // MARK: - A snippet that succeeds

    @Test("a snippet that returns a value ends the run as succeeded")
    func successSucceeds() async throws {
        let terminal = try await Self.terminal(running: Self.succeedingSnippet)

        #expect(terminal.outcome == .succeeded)
    }

    @Test("a snippet that returns a value gives no value on the terminal event")
    func successGivesNoValue() async throws {
        let terminal = try await Self.terminal(running: Self.succeedingSnippet)

        #expect(terminal.value == nil)
    }

    // MARK: - A script error

    @Test("a snippet that throws ends the run as failed")
    func scriptThrowFails() async throws {
        let terminal = try await Self.terminal(running: Self.throwingSnippet)

        #expect(terminal.outcome == .failed)
    }

    @Test("a snippet that throws gives the error text as the value")
    func scriptThrowGivesTheErrorText() async throws {
        let terminal = try await Self.terminal(running: Self.throwingSnippet)

        #expect(terminal.value == .string(terminal.detail))
    }

    @Test("a snippet that throws still gives the error text to the model")
    func scriptThrowKeepsTheText() async throws {
        let terminal = try await Self.terminal(running: Self.throwingSnippet)

        #expect(terminal.detail.contains("boom"))
    }

    // MARK: - A syntax error

    @Test("a snippet that does not parse ends the run as failed")
    func syntaxErrorFails() async throws {
        let terminal = try await Self.terminal(running: Self.brokenSnippet)

        #expect(terminal.outcome == .failed)
    }

    @Test("a snippet that does not parse gives the error text as the value")
    func syntaxErrorGivesTheErrorText() async throws {
        let terminal = try await Self.terminal(running: Self.brokenSnippet)

        #expect(terminal.value == .string(terminal.detail))
    }

    // MARK: - A repaired snippet

    @Test("a snippet that the repair makes parse ends the run as succeeded")
    func repairedSnippetSucceeds() async throws {
        let terminal = try await Self.terminal(running: Self.repairableSnippet)

        #expect(terminal.outcome == .succeeded)
    }

    @Test("a snippet that the repair makes parse gives no value")
    func repairedSnippetGivesNoValue() async throws {
        let terminal = try await Self.terminal(running: Self.repairableSnippet)

        #expect(terminal.value == nil)
    }

    // MARK: - A nested run

    @Test("a nested snippet that fails and is caught leaves the outer run succeeded")
    func caughtNestedFailureLeavesTheOuterRunSucceeded() async throws {
        let terminal = try await Self.terminal(running: Self.nestedCatchingSnippet)

        #expect(terminal.outcome == .succeeded)
    }

    @Test("a nested snippet that fails and is caught gives the outer run no value")
    func caughtNestedFailureGivesTheOuterRunNoValue() async throws {
        let terminal = try await Self.terminal(running: Self.nestedCatchingSnippet)

        #expect(terminal.value == nil)
    }
}
