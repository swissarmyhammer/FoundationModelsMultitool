import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the run-plane verb of the shell capability,
/// `tools.shell.execute`.
///
/// Ported from
/// `../FoundationModelsShelltool/Tests/ShellToolTests/ExecuteCommandTests.swift`.
/// The sibling drives its operation through `OperationTool.call` with a
/// `GeneratedContent` bag and races its own deadline; here the verb is a plain
/// `FoundationModels.Tool` and the shared elevation engine of Router owns the
/// race, the park and the cancel.
///
/// Each test makes a store in a temporary directory of its own, thus the tests
/// are independent and they run in parallel safely. Each test that starts a
/// long command ends it, through the canceler of the run or through the time
/// limit of the request, thus nothing leaks from one test to the next.
///
/// eventplan.md § "Consolidation of the siblings" makes the `commandID` of a
/// shell run its `correlationID` and its `completionToken` — one string on two
/// planes. The verb mints nothing: it reads that string out of the ambient
/// `ToolContext`, which is why every test here binds one.
@Suite("ShellExecuteTests")
struct ShellExecuteTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellexecute-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The noun the verb renders under, which is the noun the shell capability
    /// gives it.
    private static let shellNoun = "shell"

    /// The rendered call path of the `execute` verb.
    private static let executePath = "shell.execute"

    /// The text the short command of the inline tests writes.
    private static let inlineMarker = "hello-from-execute"

    /// The exit code a command that ended with success reports.
    private static let successExitCode = 0

    /// How long the long command of the detached tests sleeps. Long enough
    /// that it certainly still runs while the test reads the run plane, and
    /// each such test ends it before it returns.
    private static let detachedRunSleepSeconds = 30

    /// The longest a `wait: false` call may take. It stands far under
    /// ``detachedRunSleepSeconds``, thus a call that reaches it proves the
    /// call blocked on the command rather than handing back its identifier.
    private static let doesNotBlockUpperBound = Duration.seconds(10)

    /// How long a poll of the run plane waits between reads.
    private static let pollInterval = Duration.milliseconds(25)

    /// How long a poll waits for a detached run to reach the run plane.
    private static let parkArrivalDeadline = Duration.seconds(10)

    /// How many lines the command of the progress test writes. More than one,
    /// thus the run has output to report before it ends.
    private static let progressLineCount = 3

    /// How many terminal events one run posts. The engine and the verb agree
    /// on exactly one — see `RunEventFunnel`, which drops a second.
    private static let terminalEventCount = 1

    // MARK: - The ground of one test

    /// Makes a store in a temporary directory this test owns.
    ///
    /// - Returns: A store that no other test shares.
    /// - Throws: When the directory or the store does not prepare.
    private func makeState() throws -> ShellState {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        return try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
    }

    /// The verb over a store, with a process-group registry private to this
    /// test.
    ///
    /// Never `ProcessRegistry.global`: an ordinary test must not touch the
    /// process-wide instance — see the doc comment of that property.
    ///
    /// - Parameter state: The store the verb records into.
    /// - Returns: The verb.
    private func makeVerb(over state: ShellState) -> Execute {
        Execute(runner: ShellRunner(state: state, registry: ProcessRegistry()))
    }

    /// The report one rendered answer carries, read back as a JSON object.
    ///
    /// The verb answers `String`, because only a `String`-output tool reaches
    /// `DetachingTool` and thus the run plane. So a test reads the answer the
    /// way the model does: as the JSON object `ResultRenderer` serialized.
    ///
    /// - Parameter output: The rendered answer of one call.
    /// - Returns: The fields of the report.
    /// - Throws: When the answer is not a JSON object.
    private static func report(_ output: String) throws -> [String: Any] {
        let data = try #require(output.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Runs one call of the verb under a bound ambient context, the way the
    /// elevation engine binds one around every mounted call.
    ///
    /// - Parameters:
    ///   - verb: The verb to call.
    ///   - arguments: The call's arguments.
    ///   - context: The ambient context to bind.
    /// - Returns: The rendered answer.
    /// - Throws: What the verb throws.
    private static func call(
        _ verb: Execute, _ arguments: ExecuteArguments, under context: ToolContext
    ) async throws -> String {
        try await ToolContext.$current.withValue(context) {
            try await verb.call(arguments: arguments)
        }
    }

    /// Mounts the verb on the shared elevation engine over one mailbox, the
    /// way `RunBinding` mounts every inner `tools.*` call.
    ///
    /// The configuration is `RunBinding.innerCallMount` on purpose: the verb's
    /// own `detachmentMount` must win over it, because that declaration is the
    /// only way a `wait: false` call can ever park.
    ///
    /// - Parameters:
    ///   - verb: The verb to mount.
    ///   - context: The session context the engine inherits.
    /// - Returns: The mounted engine.
    /// - Throws: When the decorator did not preserve the verb's own types.
    private static func mounted(
        _ verb: Execute, inheriting context: ToolContext
    ) throws -> any Tool<ExecuteArguments, String> {
        try #require(
            ToolDetachment.wrapping(
                tool: verb,
                inheriting: context,
                sink: AmbientUpstreamSink(context: context),
                configuration: RunBinding.innerCallMount
            ) as? any Tool<ExecuteArguments, String>
        )
    }

    /// Waits until the run plane of `context` holds a run, and answers it.
    ///
    /// - Parameter context: The session context whose run plane to read.
    /// - Returns: The parked run.
    /// - Throws: When no run reaches the run plane before the deadline.
    private static func parkedRun(in context: ToolContext) async throws -> ParkedRun {
        let deadline = ContinuousClock.now + parkArrivalDeadline
        while ContinuousClock.now < deadline {
            if let going = await context.parkedRuns().first { return going }
            try await Task.sleep(for: pollInterval)
        }
        Issue.record("No run reached the run plane before the deadline.")
        throw ParkedRunAbsent()
    }

    /// The failure ``parkedRun(in:)`` throws when no run parks.
    private struct ParkedRunAbsent: Error {}

    // MARK: - The rendered surface

    /// eventplan.md § "Registration of capabilities: noun/verb": the path, the
    /// `findAPIs` result and the `help()` entry all come from the one pair
    /// `tools.<noun>.<verb>`, and the entry carries a runnable example.
    ///
    /// The example line is generated from the schema, so it runs as written
    /// only when `command` is the one required argument and every other one is
    /// optional.
    @Test("tools.shell.execute renders with an @example line that runs as written")
    func executeRendersWithARunnableExampleLine() throws {
        let state = try makeState()
        let surface = try MultiTool.Builder()
            .addGroup(named: Self.shellNoun, [makeVerb(over: state)])
            .build()

        #expect(surface.entries.map(\.path) == [Self.executePath])

        let entry = try #require(surface.entries.first { $0.path == Self.executePath })
        #expect(entry.qualifiedExample.hasPrefix("await tools.\(Self.executePath)("))
        #expect(
            entry.block.contains("@example const r = await tools.\(Self.executePath)("),
            "block was: \(entry.block)")
        #expect(
            entry.qualifiedExample.contains("command:"),
            "example was: \(entry.qualifiedExample)")
    }

    // MARK: - The inline answer

    @Test("a short command answers with its output inline")
    func aShortCommandAnswersWithItsOutputInline() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await Self.call(
            verb, ExecuteArguments(command: "echo \(Self.inlineMarker)"), under: context)
        let report = try Self.report(output)

        #expect(report["status"] as? String == CommandStatus.completed.rawValue)
        #expect(report["exitCode"] as? Int == Self.successExitCode)
        let lines = try #require(report["output"] as? [String])
        #expect(lines.contains { $0.contains(Self.inlineMarker) }, "output was: \(lines)")
    }

    // MARK: - One string on two planes

    /// eventplan.md § "Consolidation of the siblings": "the `commandID` of a
    /// shell run is its `correlationID` is its `completionToken` — one string,
    /// two planes."
    ///
    /// The verb mints nothing, so the store's key and the correlation of every
    /// event are the token the ambient context already carried.
    @Test("the commandID, the event correlationID and the completionToken are one string")
    func theThreeIdentifiersAreOneString() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)
        let token = context.completionToken

        let output = try await Self.call(
            verb, ExecuteArguments(command: "echo \(Self.inlineMarker)"), under: context)

        #expect(try Self.report(output)["commandID"] as? String == token)
        #expect(await state.record(commandID: token) != nil)

        let correlations = await Set(sink.events.map(\.correlationID))
        #expect(correlations == [token], "correlations were: \(correlations)")
    }

    // MARK: - The events of one run

    /// The card's contract: the verb posts a `progress` event as output
    /// arrives, and exactly one terminal event at the end.
    @Test("one terminal event stands after one or more progress events")
    func oneTerminalEventStandsAfterTheProgressEvents() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)
        let command = (1...Self.progressLineCount).map { "echo line\($0)" }.joined(separator: "; ")

        _ = try await Self.call(verb, ExecuteArguments(command: command), under: context)

        let events = await sink.events
        let kinds = events.map(\.kind)
        #expect(
            kinds.filter { $0 == .completed }.count == Self.terminalEventCount,
            "kinds were: \(kinds)")
        #expect(kinds.contains(.progress), "kinds were: \(kinds)")
        let terminalIndex = try #require(kinds.firstIndex(of: .completed))
        #expect(
            kinds[..<terminalIndex].contains(.progress),
            "no progress event stands before the terminal one: \(kinds)")
        #expect(events[terminalIndex].outcome == .succeeded)
        #expect(
            events[terminalIndex].detail.contains(context.completionToken),
            "the terminal detail carries no run identifier: \(events[terminalIndex].detail)")
    }

    // MARK: - The detached run

    /// eventplan.md § "The constraint boundary": "A capability that wants
    /// detach semantics declares it as a usual argument (shell's `wait`). The
    /// capability then returns the run's identifier for the builtins."
    @Test("a wait: false call answers with the run identifier and does not block")
    func aCallThatDoesNotWaitAnswersWithTheIdentifierAndDoesNotBlock() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try Self.mounted(makeVerb(over: state), inheriting: context)

        let started = ContinuousClock.now
        let output = try await engine.call(
            arguments: ExecuteArguments(
                command: "sleep \(Self.detachedRunSleepSeconds)", wait: false))
        let elapsed = ContinuousClock.now - started

        let going = try await Self.parkedRun(in: context)

        #expect(elapsed < Self.doesNotBlockUpperBound, "the call took \(elapsed)")
        #expect(
            output.contains(going.completionToken),
            "the answer carries no run identifier: \(output)")

        // Awaited rather than deferred into a task of its own: an unstructured
        // task started at the end of a test need never run, and the command
        // this one stops sleeps far longer than the whole suite.
        _ = await context.cancel(completionToken: going.completionToken)
    }

    /// eventplan.md § "Processes and tasks stay different kinds": an OS
    /// process group is a `RunKind.process`, and never a `.swiftTask`.
    @Test("a detached run stands in the run plane under RunKind.process")
    func aDetachedRunStandsInTheRunPlaneAsAProcess() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try Self.mounted(makeVerb(over: state), inheriting: context)

        _ = try await engine.call(
            arguments: ExecuteArguments(
                command: "sleep \(Self.detachedRunSleepSeconds)", wait: false))

        let going = try await Self.parkedRun(in: context)

        #expect(going.kind == .process)
        #expect(await state.record(commandID: going.completionToken) != nil)

        // Awaited rather than deferred into a task of its own — see the reason
        // in the test above.
        _ = await context.cancel(completionToken: going.completionToken)
    }

    /// eventplan.md § "Processes and tasks stay different kinds":
    /// `killpg(SIGKILL)` is authoritative, thus the honest outcome is
    /// `.stopped` and never `.cancelled`.
    @Test("cancel of a detached run reports .stopped")
    func cancelOfADetachedRunReportsStopped() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try Self.mounted(makeVerb(over: state), inheriting: context)

        _ = try await engine.call(
            arguments: ExecuteArguments(
                command: "sleep \(Self.detachedRunSleepSeconds)", wait: false))
        let going = try await Self.parkedRun(in: context)

        let outcome = await context.cancel(completionToken: going.completionToken)

        #expect(outcome == .reported(.stopped))
        #expect(await state.record(commandID: going.completionToken)?.status == .killed)
    }

    // MARK: - The corrective answers

    @Test("a blank command answers with a correction and runs nothing")
    func aBlankCommandAnswersWithACorrection() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await Self.call(verb, ExecuteArguments(command: "   "), under: context)

        #expect(try Self.report(output)["correction"] as? String != nil, "answer was: \(output)")
        #expect(await state.listCommands().isEmpty)
    }

    @Test("an environment that is not a JSON object of strings answers with a correction")
    func anUnparsableEnvironmentAnswersWithACorrection() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await Self.call(
            verb,
            ExecuteArguments(command: "echo \(Self.inlineMarker)", environment: "not-json"),
            under: context)

        #expect(try Self.report(output)["correction"] as? String != nil, "answer was: \(output)")
        #expect(await state.listCommands().isEmpty)
    }

    @Test("a call with no session answers with a correction, because it mints nothing")
    func aCallWithNoSessionAnswersWithACorrection() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)

        let output = try await verb.call(
            arguments: ExecuteArguments(command: "echo \(Self.inlineMarker)"))

        #expect(try Self.report(output)["correction"] as? String != nil, "answer was: \(output)")
        #expect(await state.listCommands().isEmpty)
    }
}
