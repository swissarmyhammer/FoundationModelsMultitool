import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// A shell command holds a `.shellCommand` lease in the `WorkRegistry` of
/// the session of its call, from its start until its process exited and its
/// report settled: also on a failure, a cancel and a time limit. A read of the
/// store, for example `tools.shell.getLines`, holds no lease. A call in a
/// child session, for example a subagent, leases in the registry of the child
/// only.
@Suite("ShellCommandLeaseTests", .ownsTemporaryDirectories)
struct ShellCommandLeaseTests {

    /// Owns the temporary directories of the shell stores of this test.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "worklease-tests"

    /// The exit code of the failing command.
    private static let failingExitCode = 3

    /// The time limit of the timed-out command, in seconds. The gated clock
    /// of the runner ends a sleep of this length at once.
    private static let timeLimitSeconds = 7

    // MARK: - Helpers

    /// Makes a shell store in a temporary directory that this test owns.
    ///
    /// - Returns: The store.
    /// - Throws: When the directory or the store does not prepare.
    private func makeState() throws -> ShellState {
        try ShellState(
            preferredDirectory: scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
                .appendingPathComponent(".shell"))
    }

    /// The `execute` verb over `state`, with a private process registry.
    ///
    /// - Parameters:
    ///   - state: The store of the runs.
    ///   - clock: The clock of the time limit and of the progress interval.
    /// - Returns: The verb.
    private static func makeVerb(over state: ShellState, pacedBy clock: GatedClock = GatedClock()) -> Execute {
        var runner = ShellRunner(state: state, registry: ProcessRegistry())
        runner.clock = clock
        return Execute(runner: runner)
    }

    /// Calls the mounted verb, which goes to the background at once, and
    /// gives the completion token of its run.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - verb: The verb.
    ///   - session: The session that the call is mounted on.
    /// - Returns: The completion token of the run.
    /// - Throws: When the answer is not the pending envelope.
    private static func startPending(
        _ arguments: ExecuteArguments, on verb: Execute, in session: LeasedSession
    ) async throws -> String {
        let engine = ShellRunPlane.mounted(verb, inheriting: session.context)
        let output = try await engine.call(arguments: arguments)
        try #require(PendingRunEnvelope.isRendered(text: output), "answer was: \(output)")
        return try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(output.utf8)).completionToken
    }

    /// Waits until the command whose line holds the path of `gate` started,
    /// or until its run settled first.
    ///
    /// - Parameters:
    ///   - gate: The gate that the command waits on.
    ///   - state: The store of the run.
    ///   - token: The completion token of the run.
    ///   - session: The session of the run.
    /// - Throws: When the run settled before the command started.
    private static func waitForStart(
        of gate: ShellCommandGate, in state: ShellState, token: String, session: LeasedSession
    ) async throws {
        let path = gate.path
        try await EventRace.firstOf(
            { _ = await state.waitForCommand(holding: path) },
            or: { await TerminalDetail.waitForEnd(of: token, in: session.context) })
        try #require(await state.record(commandID: token)?.status == .running, "the command ended before the test read it")
    }

    /// The lease of the shell command of `token` in `session`.
    ///
    /// - Parameters:
    ///   - token: The completion token of the run.
    ///   - session: The session of the run.
    /// - Returns: The item of the lease.
    private static func shellLease(of token: String, in session: LeasedSession) -> WorkItem {
        WorkItem(kind: .shellCommand, id: token, sessionID: session.sessionID)
    }

    // MARK: - Shell commands

    @Test("a pending shell command holds a shellCommand lease until it exits and its report settled")
    func aPendingShellCommandHoldsALeaseUntilItSettles() async throws {
        let session = LeasedSession()
        let state = try makeState()
        let gate = try ShellCommandGate()

        let token = try await Self.startPending(
            ExecuteArguments(command: gate.waitCommand), on: Self.makeVerb(over: state), in: session)
        try await Self.waitForStart(of: gate, in: state, token: token, session: session)

        #expect(session.registry.openWork.contains(Self.shellLease(of: token, in: session)))

        let group = try #require(await state.groupToCancel(commandID: token))
        _ = try await gate.release(whileAlive: group.pid)
        _ = try await TerminalDetail.settledEvent(of: token, in: session.context)

        let terminal = try #require(session.sink.terminalSnapshot(of: token))
        #expect(terminal.openWork.contains(Self.shellLease(of: token, in: session)))
        #expect(session.registry.openWork.isEmpty)
    }

    @Test("a failed shell command ends its lease when its report settled")
    func aFailedShellCommandEndsItsLease() async throws {
        let session = LeasedSession()
        let state = try makeState()

        let token = try await Self.startPending(
            ExecuteArguments(command: "exit \(Self.failingExitCode)"), on: Self.makeVerb(over: state), in: session)
        _ = try await TerminalDetail.settledEvent(of: token, in: session.context)

        #expect(await state.record(commandID: token)?.exitCode == Self.failingExitCode)
        let terminal = try #require(session.sink.terminalSnapshot(of: token))
        #expect(terminal.openWork.contains(Self.shellLease(of: token, in: session)))
        #expect(session.registry.openWork.isEmpty)
    }

    @Test("a shell command that cannot start ends its lease")
    func aShellCommandThatCannotStartEndsItsLease() async throws {
        let session = LeasedSession()
        let state = try makeState()
        let recorder = WorkTransitionsRecorder(session.registry)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("worklease-missing-\(UUID().uuidString)").path

        let token = try await Self.startPending(
            ExecuteArguments(command: "true", workingDirectory: missing), on: Self.makeVerb(over: state),
            in: session)
        _ = try await TerminalDetail.settledEvent(of: token, in: session.context)

        #expect(await state.record(commandID: token)?.exitCode == ShellRunner.absentExitCode)
        #expect(session.registry.openWork.isEmpty)
        #expect(await recorder.close() == [.workStarted, .noWork])
    }

    @Test("a cancel of a pending shell command ends its lease when the process ended")
    func aCancelOfAPendingShellCommandEndsItsLease() async throws {
        let session = LeasedSession()
        let state = try makeState()
        let gate = try ShellCommandGate()

        let token = try await Self.startPending(
            ExecuteArguments(command: gate.waitCommand), on: Self.makeVerb(over: state), in: session)
        try await Self.waitForStart(of: gate, in: state, token: token, session: session)
        #expect(session.registry.openWork.contains(Self.shellLease(of: token, in: session)))

        #expect(await session.context.cancel(completionToken: token) == .reported(.stopped))
        await session.registry.awaitNoWork()

        #expect(session.registry.openWork.isEmpty)
        #expect(await state.record(commandID: token)?.status == .killed)
    }

    @Test("a shell command that hits its time limit ends its lease when its report settled")
    func aTimedOutShellCommandEndsItsLease() async throws {
        let session = LeasedSession()
        let state = try makeState()
        let gate = try ShellCommandGate()
        let clock = GatedClock()
        clock.open(sleepsOf: .seconds(Self.timeLimitSeconds))

        let token = try await Self.startPending(
            ExecuteArguments(command: gate.waitCommand, timeout: Self.timeLimitSeconds),
            on: Self.makeVerb(over: state, pacedBy: clock), in: session)
        _ = try await TerminalDetail.settledEvent(of: token, in: session.context)

        #expect(await state.record(commandID: token)?.status == .timedOut)
        let terminal = try #require(session.sink.terminalSnapshot(of: token))
        #expect(terminal.openWork.contains(Self.shellLease(of: token, in: session)))
        #expect(session.registry.openWork.isEmpty)
    }

    @Test("getLines of a finished command holds no lease")
    func getLinesOfAFinishedCommandHoldsNoLease() async throws {
        let session = LeasedSession()
        let state = try makeState()
        let token = try await Self.startPending(
            ExecuteArguments(command: "echo leased"), on: Self.makeVerb(over: state), in: session)
        _ = try await TerminalDetail.settledEvent(of: token, in: session.context)
        let recorder = WorkTransitionsRecorder(session.registry)

        let result = try await ToolContext.$current.withValue(session.context) {
            try await GetLines(state: state).call(arguments: GetLinesArguments(commandID: token))
        }

        #expect(result.lines.contains { $0.contains("leased") })
        #expect(session.registry.openWork.isEmpty)
        #expect(await recorder.close().isEmpty)
    }

    // MARK: - Child sessions

    @Test("a call in a child session leases in the registry of the child only")
    func aCallInAChildSessionLeasesInTheChildOnly() async throws {
        let parent = LeasedSession()
        let child = try await parent.makeChild()
        let state = try makeState()
        let gate = try ShellCommandGate()
        #expect(child.context.parentSessionID == parent.sessionID)

        let token = try await Self.startPending(
            ExecuteArguments(command: gate.waitCommand), on: Self.makeVerb(over: state), in: child)
        try await Self.waitForStart(of: gate, in: state, token: token, session: child)

        #expect(child.registry.openWork.contains(Self.shellLease(of: token, in: child)))
        #expect(!parent.registry.hasWork)

        _ = await child.context.cancel(completionToken: token)
        await child.registry.awaitNoWork()
        #expect(!parent.registry.hasWork)
    }
}
