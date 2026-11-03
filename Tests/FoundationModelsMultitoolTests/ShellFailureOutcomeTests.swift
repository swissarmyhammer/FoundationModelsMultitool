import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Tests that a command with a nonzero exit code ends its run as failed, and
/// that the exit code goes on the terminal event as a value.
///
/// Each test runs one command through the mounted `execute` verb, in the way a
/// session mounts it, and reads the terminal event of the run. The verb
/// returns its normal report text in each case.
@Suite("ShellFailureOutcomeTests", .ownsTemporaryDirectories)
struct ShellFailureOutcomeTests {

    /// Owns the temporary directories this test makes.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "shellfailureoutcome-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The exit code of a command that fails with a general error.
    private static let failureExitCode = 2

    /// The exit code that grep gives when it finds no match.
    private static let grepNoMatchExitCode = 1

    /// The exit code of a command that succeeds.
    private static let successExitCode = 0

    /// The command that kills its own shell with a signal.
    private static let selfKillCommand = "kill -9 $$"

    /// Runs `command` through the mounted verb and waits for the terminal event.
    ///
    /// A settle period of 0 sends the call to the background at once, so the
    /// run plane keeps the terminal event for the completion token.
    ///
    /// - Parameter command: The command to run.
    /// - Returns: The terminal event of the run.
    /// - Throws: When the store, the call or the wait fails.
    private func finish(running command: String) async throws -> OperationEvent {
        let state = try ShellState(
            preferredDirectory: scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
                .appendingPathComponent(Self.shellStoreDirectoryName))
        return try await withOuterRunContext { context in
            let verb = Execute(runner: ShellRunner(state: state, registry: ProcessRegistry()))
            let engine = ShellRunPlane.mounted(verb, inheriting: context.settling(within: 0))
            let pending = try await engine.call(arguments: ExecuteArguments(command: command))
            let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(pending.utf8))
            let terminal = try await TerminalDetail.settledEvent(of: envelope.completionToken, in: context)
            return terminal
        }
    }

    // MARK: - A command that succeeds

    @Test("exit 0 ends the run as succeeded")
    func exitZeroSucceeds() async throws {
        let terminal = try await finish(running: "exit \(Self.successExitCode)")

        #expect(terminal.outcome == .succeeded)
    }

    @Test("exit 0 gives no value")
    func exitZeroGivesNoValue() async throws {
        let terminal = try await finish(running: "exit \(Self.successExitCode)")

        #expect(terminal.value == nil)
    }

    // MARK: - A command that fails

    @Test("exit 1 ends the run as failed")
    func exitOneFails() async throws {
        let terminal = try await finish(running: "exit 1")

        #expect(terminal.outcome == .failed)
    }

    @Test("exit 1 gives the exit code as the value")
    func exitOneGivesTheCode() async throws {
        let terminal = try await finish(running: "exit 1")

        #expect(terminal.value == .int(1))
    }

    @Test("exit 2 gives the exit code as the value")
    func exitTwoGivesTheCode() async throws {
        let terminal = try await finish(running: "exit \(Self.failureExitCode)")

        #expect(terminal.value == .int(Self.failureExitCode))
    }

    @Test("exit 2 ends the run as failed")
    func exitTwoFails() async throws {
        let terminal = try await finish(running: "exit \(Self.failureExitCode)")

        #expect(terminal.outcome == .failed)
    }

    @Test("grep with no match ends the run as failed")
    func grepNoMatchFails() async throws {
        let terminal = try await finish(running: "echo abc | grep zzz")

        #expect(terminal.outcome == .failed)
    }

    @Test("grep with no match gives exit code 1 as the value")
    func grepNoMatchGivesTheCode() async throws {
        let terminal = try await finish(running: "echo abc | grep zzz")

        #expect(terminal.value == .int(Self.grepNoMatchExitCode))
    }

    @Test("a failed command keeps its output in the detail of the terminal event")
    func failedCommandKeepsTheOutput() async throws {
        let terminal = try await finish(running: "echo kept-output; exit \(Self.failureExitCode)")

        #expect(terminal.detail.contains("kept-output"))
    }

    // MARK: - A command that dies by a signal

    @Test("a death by signal has no exit code, thus it gives no value")
    func signalDeathGivesNoValue() async throws {
        let terminal = try await finish(running: Self.selfKillCommand)

        #expect(terminal.value == nil)
    }
}
