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
/// `FoundationModels.Tool` and the shared background engine of Router owns the
/// tracking, the work bound and the cancel.
///
/// Each test makes a store in a temporary directory of its own, thus the tests
/// are independent and they run in parallel safely. Each test that starts a
/// long command ends it, through the canceler of the run or through the time
/// limit of the request, thus nothing leaks from one test to the next.
///
/// eventplan.md § "Consolidation of the siblings" makes the `commandID` of a
/// shell run its `correlationID` and its `completionToken` — one string on two
/// planes. Under a bound `ToolContext` the verb reads that string out of the
/// context, which is why most tests here bind one. With no context — a bare
/// `LanguageModelSession` — the verb mints the string itself and runs the
/// command to completion; one test here binds nothing for that reason.
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

    /// How long the long command of the background tests sleeps. Long enough
    /// that it certainly still runs while the test reads the run plane, and
    /// each such test ends it before it returns.
    private static let backgroundRunSleepSeconds = 30

    /// The longest a mounted call may take. It stands far under
    /// ``backgroundRunSleepSeconds``, thus a call that reaches it proves the
    /// call blocked on the command rather than handing back its identifier.
    private static let doesNotBlockUpperBound = Duration.seconds(10)

    /// How many lines the command of the progress test writes. More than one,
    /// thus the run has output to report before it ends.
    private static let progressLineCount = 3

    /// How many terminal events one run posts. The engine and the verb agree
    /// on exactly one — see `RunEventFunnel`, which drops a second.
    private static let terminalEventCount = 1

    /// The cap on the length of one command, in UTF-8 bytes, as the sibling
    /// shell tool's settings defaults state it: 256 KiB.
    ///
    /// Written out here rather than read off ``Execute``, thus a port that
    /// carried the wrong number fails in this file rather than at a command
    /// the kernel refuses.
    private static let portedCommandLengthCap = 262_144

    /// The cap on the length of one environment value, in UTF-8 bytes, from
    /// the same defaults.
    private static let portedEnvironmentValueLengthCap = 1024

    /// The name of the environment variable the environment cases set.
    private static let environmentVariableName = "SAH_PROBE"

    /// One character that is four UTF-8 bytes, thus a command written out of
    /// it measures four times as many bytes as it holds characters.
    private static let fourByteCharacter = "😀"

    /// How many of ``fourByteCharacter`` the multi-byte command holds: half
    /// the byte cap, thus that command stands far under the cap in characters
    /// and at twice the cap in bytes.
    private static let multiByteCommandCharacterCount = Execute.maximumCommandLengthBytes / 2

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

    /// The `execute` verb of a whole capability that a host gave `stream` to,
    /// over a store this test owns.
    ///
    /// It goes through `ShellCapability` rather than through `Execute` alone,
    /// because what these tests examine is the path from the argument a host
    /// passes to the chunks that host reads, and the capability is the first
    /// step of it.
    ///
    /// The registry of the runner is replaced with a private one. The
    /// capability takes `ProcessRegistry.global`, and an ordinary test must not
    /// touch the process-wide instance — see the doc comment of that property.
    /// Nothing else of the configured runner is touched, thus the store, the
    /// live view and the confinement stay the ones the capability built.
    ///
    /// - Parameter stream: The live view the host subscribes to.
    /// - Returns: The verb of that capability.
    /// - Throws: When the directory, the store or the capability does not
    ///   prepare, or when the capability holds no `execute` verb.
    private func makeVerb(teeing stream: ShellOutputChunkStream) throws -> Execute {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let capability = try ShellCapability(
            storeDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName),
            outputChunkStream: stream)
        let configured = try #require(capability.tools.compactMap { $0 as? Execute }.first)
        var runner = configured.runner
        runner.registry = ProcessRegistry()
        return Execute(runner: runner)
    }

    /// Every event a host stream holds, read back after the run that fed it
    /// ended.
    ///
    /// The stream is finished first and drained afterward, which is the order
    /// that makes the read terminate: a stream nobody finished gives no end to
    /// a `for await` loop. `AsyncStream` hands out each event it already holds
    /// before it reports the end, thus finishing first takes nothing away.
    ///
    /// - Parameter stream: The live view the host subscribed to.
    /// - Returns: The events it holds, in delivery order.
    private static func events(of stream: ShellOutputChunkStream) async -> [ShellOutputEvent] {
        stream.finish()
        var events: [ShellOutputEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    /// The standard output of the run under `commandID`, joined out of the
    /// chunks a host stream delivered and decoded as UTF-8.
    ///
    /// - Parameters:
    ///   - events: The events the host stream held.
    ///   - commandID: The completion token of the run to read.
    /// - Returns: What that run wrote to its standard output.
    private static func stdoutText(in events: [ShellOutputEvent], of commandID: String) -> String {
        let bytes = events.flatMap { event -> [UInt8] in
            guard event.commandID == commandID,
                case .output(.stdout, let chunk) = event.kind
            else { return [] }
            return chunk
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The report one rendered answer carries, read back as a JSON object.
    ///
    /// The verb answers `String`, because only a `String`-output tool reaches
    /// `BackgroundToolRunner` and thus the run plane. So a test reads the answer the
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
    /// background engine binds one around every mounted call.
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

    /// A command of exactly `byteCount` UTF-8 bytes that writes
    /// ``inlineMarker``.
    ///
    /// The padding stands behind a `#`, thus the shell reads it as a comment
    /// and the command runs however long it is.
    ///
    /// - Parameter byteCount: How many UTF-8 bytes the command must measure.
    ///   It stands at or over the length of the part that does the writing.
    /// - Returns: The command line.
    private static func command(ofByteCount byteCount: Int) -> String {
        let head = "echo \(inlineMarker) #"
        return head + String(repeating: "a", count: byteCount - head.utf8.count)
    }

    /// One extra environment entry, as the JSON text the argument takes.
    ///
    /// - Parameter valueLiteral: The value of ``environmentVariableName``,
    ///   spelled the way JSON spells it.
    /// - Returns: The `environment` argument.
    private static func environmentJSON(valueLiteral: String) -> String {
        "{\"\(environmentVariableName)\":\"\(valueLiteral)\"}"
    }

    /// Calls the verb with one extra environment entry and answers the
    /// correction it gave back.
    ///
    /// Each environment case differs in the value alone, thus each of them
    /// calls this and reads the message.
    ///
    /// - Parameter valueLiteral: The value of ``environmentVariableName``,
    ///   spelled the way JSON spells it.
    /// - Returns: The corrective message.
    /// - Throws: When the store or the answer is not what the case needs.
    private func refusal(forEnvironmentValueLiteral valueLiteral: String) async throws -> String {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await Self.call(
            verb,
            ExecuteArguments(
                command: "echo \(Self.inlineMarker)",
                environment: Self.environmentJSON(valueLiteral: valueLiteral)),
            under: context)

        #expect(await state.listCommands().isEmpty)
        return try #require(try Self.report(output)["correction"] as? String)
    }

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
    /// Under a bound context the verb mints nothing, so the store's key and the
    /// correlation of every event are the token the ambient context already
    /// carried.
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

    // MARK: - The live view of a subscribed host

    /// A host that hands a `ShellOutputChunkStream` to `ShellCapability` reads
    /// what a run wrote, and reads the terminal marker of that run.
    ///
    /// The verb makes a live view of its own for each run, which it drains to
    /// post the `progress` events. That private view stands BESIDE the one the
    /// host configured, and never in place of it.
    @Test("a stream handed to the capability receives the chunks of a run and its marker")
    func aHostStreamReceivesTheChunksOfARunAndItsMarker() async throws {
        let stream = ShellOutputChunkStream()
        let verb = try makeVerb(teeing: stream)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())
        let token = context.completionToken

        _ = try await Self.call(
            verb, ExecuteArguments(command: "echo \(Self.inlineMarker)"), under: context)

        let events = await Self.events(of: stream)
        let written = Self.stdoutText(in: events, of: token)
        #expect(written.contains(Self.inlineMarker), "the host stream carried: \(written)")
        #expect(
            events.contains { $0.commandID == token && $0.kind == .completed },
            "the host stream carried no terminal marker: \(events)")
    }

    /// The `progress` events of a run stand as they are with no host stream:
    /// one for each chunk the child wrote, naming the stream it came from.
    ///
    /// The command writes one line with one `echo`, which is one write of one
    /// chunk, thus the run posts exactly one `progress` event and the whole
    /// list can be stated. `reportOutput` trims the line ending, which is why
    /// no `\n` stands in the expected text.
    @Test("the progress events of a run with a host stream are the ones it posts today")
    func theProgressEventsStandAsTheyDoWithNoHostStream() async throws {
        let stream = ShellOutputChunkStream()
        let verb = try makeVerb(teeing: stream)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

        _ = try await Self.call(
            verb, ExecuteArguments(command: "echo \(Self.inlineMarker)"), under: context)

        let progress = await sink.details(ofKind: .progress)
        #expect(progress == ["stdout: \(Self.inlineMarker)"], "progress was: \(progress)")
        let kinds = await sink.events.map(\.kind)
        #expect(
            kinds.filter { $0 == .completed }.count == Self.terminalEventCount,
            "kinds were: \(kinds)")

        stream.finish()
    }

    // MARK: - The background run

    /// The verb declares the background mount, thus every mounted call answers
    /// at once with the pending envelope, and the command goes on behind it.
    /// A short command is the sharpest case: the body could finish in
    /// microseconds, and the call still answers the envelope, never the report.
    @Test("a mounted execute call always answers with the pending envelope, and the report settles behind it")
    func aMountedCallAlwaysAnswersWithThePendingEnvelope() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try ShellRunPlane.mounted(makeVerb(over: state), inheriting: context)

        let output = try await engine.call(
            arguments: ExecuteArguments(command: "echo \(Self.inlineMarker)"))

        #expect(PendingRunEnvelope.isRendered(text: output), "answer was: \(output)")
        let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(output.utf8))
        let settlement = await context.wait(
            completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds)
        guard case .settled(let terminal) = settlement else {
            Issue.record("the run never settled: \(settlement)")
            return
        }
        let report = try Self.report(terminal.detail)
        #expect(report["status"] as? String == CommandStatus.completed.rawValue)
        let lines = try #require(report["output"] as? [String])
        #expect(lines.contains { $0.contains(Self.inlineMarker) }, "output was: \(lines)")
    }

    /// The `wait` argument selected a block window. There is no block window:
    /// a mounted call answers at once, so the schema offers no such choice.
    @Test("the rendered execute schema has no wait argument")
    func theRenderedSchemaHasNoWaitArgument() throws {
        let state = try makeState()

        let schema = try ToolAPIRenderer.jsonSchemaString(for: makeVerb(over: state).parameters)

        #expect(!schema.contains("\"wait\""), "schema was: \(schema)")
    }

    /// The verb never blocks on its command: the call hands back the run's
    /// identifier, and the builtins read the run from there.
    @Test("a mounted call answers with the run identifier and does not block")
    func aMountedCallAnswersWithTheIdentifierAndDoesNotBlock() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try ShellRunPlane.mounted(makeVerb(over: state), inheriting: context)

        let started = ContinuousClock.now
        let output = try await engine.call(
            arguments: ExecuteArguments(command: "sleep \(Self.backgroundRunSleepSeconds)"))
        let elapsed = ContinuousClock.now - started

        let going = try await ShellRunPlane.backgroundRun(in: context)

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
    @Test("a background run stands in the run plane under RunKind.process")
    func aBackgroundRunStandsInTheRunPlaneAsAProcess() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try ShellRunPlane.mounted(makeVerb(over: state), inheriting: context)

        _ = try await engine.call(
            arguments: ExecuteArguments(command: "sleep \(Self.backgroundRunSleepSeconds)"))

        let going = try await ShellRunPlane.backgroundRun(in: context)

        #expect(going.kind == .process)
        // The record is written by the run body, which starts after the call
        // already answered its envelope; one read here is a race, not a check.
        try await TestPoll.waitUntil("the store holds the record of the run") {
            await state.record(commandID: going.completionToken) != nil
        }

        // Awaited rather than deferred into a task of its own — see the reason
        // in the test above.
        _ = await context.cancel(completionToken: going.completionToken)
    }

    /// eventplan.md § "Processes and tasks stay different kinds":
    /// `killpg(SIGKILL)` is authoritative, thus the honest outcome is
    /// `.stopped` and never `.cancelled`.
    @Test("cancel of a background run reports .stopped")
    func cancelOfABackgroundRunReportsStopped() async throws {
        let state = try makeState()
        let mailbox = SessionMailbox()
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        let engine = try ShellRunPlane.mounted(makeVerb(over: state), inheriting: context)

        _ = try await engine.call(
            arguments: ExecuteArguments(command: "sleep \(Self.backgroundRunSleepSeconds)"))
        let going = try await ShellRunPlane.backgroundRun(in: context)

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

    // MARK: - The bare session

    /// A constituent verb is a plain `FoundationModels.Tool`, and it works on
    /// a bare `LanguageModelSession` with no Router. With no ambient context
    /// the verb mints the `commandID` itself, runs the command to completion
    /// and answers with the report; the store records the run under that id,
    /// so `tools.shell.getLines` reads it back as usual.
    @Test("a call with no session runs the command to completion and answers with the report")
    func aCallWithNoSessionRunsToCompletionAndAnswersWithTheReport() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)

        let output = try await verb.call(
            arguments: ExecuteArguments(command: "printf '%s' \(Self.inlineMarker)"))
        let report = try Self.report(output)

        #expect(report["status"] as? String == CommandStatus.completed.rawValue)
        #expect(report["exitCode"] as? Int == Self.successExitCode)
        let commandID = try #require(report["commandID"] as? String)
        #expect(!commandID.isEmpty, "the report carries no run identifier: \(output)")
        let lines = try #require(report["output"] as? [String])
        #expect(lines.contains { $0.contains(Self.inlineMarker) }, "output was: \(lines)")

        let stored = try await GetLines(state: state)
            .call(arguments: GetLinesArguments(commandID: commandID))
        #expect(stored.commandID == commandID)
        #expect(
            stored.lines.contains { $0.contains(Self.inlineMarker) },
            "getLines read: \(stored.lines)")
    }

    // MARK: - The caps that stand in front of E2BIG

    /// The caps are the sibling's own numbers, thus a port that carried the
    /// wrong one fails here rather than at a command the kernel refuses.
    @Test("the command cap and the environment-value cap are the ported numbers")
    func theCapsAreThePortedNumbers() {
        #expect(Execute.maximumCommandLengthBytes == Self.portedCommandLengthCap)
        #expect(Execute.maximumEnvironmentValueLengthBytes == Self.portedEnvironmentValueLengthCap)
    }

    @Test("a command of exactly the cap runs")
    func aCommandOfExactlyTheCapRuns() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await Self.call(
            verb,
            ExecuteArguments(command: Self.command(ofByteCount: Execute.maximumCommandLengthBytes)),
            under: context)
        let report = try Self.report(output)

        #expect(report["status"] as? String == CommandStatus.completed.rawValue)
        let lines = try #require(report["output"] as? [String])
        #expect(lines.contains { $0.contains(Self.inlineMarker) }, "output was: \(lines)")
    }

    @Test("a command one byte over the cap answers with a correction and runs nothing")
    func aCommandOneByteOverTheCapAnswersWithACorrection() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())
        let byteCount = Execute.maximumCommandLengthBytes + 1

        let output = try await Self.call(
            verb, ExecuteArguments(command: Self.command(ofByteCount: byteCount)), under: context)

        let message = try #require(try Self.report(output)["correction"] as? String)
        #expect(
            message.contains("\(Execute.maximumCommandLengthBytes)"), "message was: \(message)")
        #expect(message.contains("\(byteCount)"), "message was: \(message)")
        #expect(await state.listCommands().isEmpty)
    }

    /// The cap counts UTF-8 BYTES and never characters, because `E2BIG` from
    /// `posix_spawn` counts the bytes of the argv block. This is the command a
    /// count of grapheme clusters lets through.
    @Test("a command under the cap in characters and over it in bytes answers with a correction")
    func aMultiByteCommandOverTheByteCapAnswersWithACorrection() async throws {
        let state = try makeState()
        let verb = makeVerb(over: state)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())
        let command = String(
            repeating: Self.fourByteCharacter, count: Self.multiByteCommandCharacterCount)

        #expect(command.count < Execute.maximumCommandLengthBytes)
        #expect(command.utf8.count > Execute.maximumCommandLengthBytes)

        let output = try await Self.call(verb, ExecuteArguments(command: command), under: context)

        #expect(try Self.report(output)["correction"] as? String != nil, "answer was: \(output)")
        #expect(await state.listCommands().isEmpty)
    }

    @Test("an environment value over the cap answers with a correction")
    func anEnvironmentValueOverTheCapAnswersWithACorrection() async throws {
        let byteCount = Execute.maximumEnvironmentValueLengthBytes + 1

        let message = try await refusal(
            forEnvironmentValueLiteral: String(repeating: "a", count: byteCount))

        #expect(
            message.contains("\(Execute.maximumEnvironmentValueLengthBytes)"),
            "message was: \(message)")
        #expect(message.contains("\(byteCount)"), "message was: \(message)")
    }

    /// A null byte inside a value truncates it at the `execve` boundary, where
    /// each entry is a NUL-terminated C string.
    @Test("an environment value holding a null byte answers with a correction")
    func anEnvironmentValueHoldingANullByteAnswersWithACorrection() async throws {
        let message = try await refusal(forEnvironmentValueLiteral: "a\\u0000b")

        #expect(message.contains("holds a null byte"), "message was: \(message)")
    }

    @Test("an environment value holding a line feed answers with a correction")
    func anEnvironmentValueHoldingALineFeedAnswersWithACorrection() async throws {
        let message = try await refusal(forEnvironmentValueLiteral: "a\\nb")

        #expect(
            message.contains("holds a carriage return or a line feed"), "message was: \(message)")
    }

    @Test("an environment value holding a carriage return answers with a correction")
    func anEnvironmentValueHoldingACarriageReturnAnswersWithACorrection() async throws {
        let message = try await refusal(forEnvironmentValueLiteral: "a\\rb")

        #expect(
            message.contains("holds a carriage return or a line feed"), "message was: \(message)")
    }

    /// Swift reads a CR LF pair as ONE grapheme cluster, which equals neither
    /// `"\r"` nor `"\n"`, so a search for either Character passes this value
    /// through. The check reads the UTF-8 bytes for that reason.
    @Test("an environment value holding a CR LF pair answers with a correction")
    func anEnvironmentValueHoldingACarriageReturnLineFeedPairAnswersWithACorrection() async throws {
        let message = try await refusal(forEnvironmentValueLiteral: "a\\r\\nb")

        #expect(
            message.contains("holds a carriage return or a line feed"), "message was: \(message)")
    }
}
