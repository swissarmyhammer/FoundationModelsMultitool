import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import ScenarioGrading
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The rule of the user for each background tool call: "background should
/// mean 'if it takes longer than grace, background'".
///
/// Each call of a background tool that a session mounts waits for the settle
/// period of the host. A call that ends in that time answers with its own
/// result, the same as a synchronous call, and no mail comes for it. Only a
/// call that runs longer answers with a pending result, and its result comes
/// back later as mail, one time. `tools.shell.execute` is the tool where it
/// matters most (SWE-bench run `preds.code-context-1008`, instance
/// `django__django-14016`).
///
/// The settle period applies to the outer `runCode` call only. An inner
/// `tools.*` call of a snippet always runs to completion, so a snippet that
/// awaits it gets the real result, and a snippet that runs past the settle
/// period goes to the background as one run (task `^6nnykct`). A call that
/// the snippet did not await is named in the result.
///
/// Each test goes through a real Router session that a host makes with
/// `SessionConfiguration`, so the session mount, the outbox and the mail pump
/// are the real ones. The backend records the prompt of each submission,
/// which is where mail arrives (see `MailProbeFixtures.swift`).
///
/// No test waits on real time. Each session runs on a `ManualRunClock`, thus
/// a settle period ends only when the test moves the clock past it. A command
/// that must run "long" blocks on a ``ShellCommandGate`` until the test
/// releases it. A test that needs "ends inside the settle period" releases the
/// command while the clock stands still. A test that needs "runs longer than
/// the settle period" moves the clock past the period first, and releases the
/// command after the call answered with its pending envelope.
@Suite("a background call that ends inside the settle period answers with its own result")
struct BackgroundSettleGraceTests {

    // MARK: - Fixtures

    /// A short settle period, in seconds, for a test that needs the period to
    /// elapse. The test moves the run clock past it.
    private static let shortGrace: TimeInterval = 2

    /// The settle period of the "host that sets one second" test.
    private static let oneSecondGrace: TimeInterval = 1

    /// How far the clock moves while the command of the "default host" test
    /// runs: three seconds, inside the default settle period and not inside
    /// one second.
    private static let threeSecondRun: Duration = .seconds(3)

    /// The line that the long command of
    /// ``awaitedLongExecuteGivesTheRealResult()`` writes into its file.
    private static let fullOutputLine = "the-full-test-output"

    /// The caller message of the submission after the call. Mail that stays
    /// in the outbox goes into this prompt.
    private static let followUpMessage = "one more message"

    /// The `tools.*` path of the shell verb that the notice names.
    private static let executePath = "tools.shell.execute"

    /// The `Tool` name of the shell verb that the notice names.
    private static let executeTool = "execute"

    /// The journal `op` of the shell verb that the notice names.
    private static let executeOp = "execute shell"

    /// How many waits the run clock holds while a mounted `runCode` call
    /// waits for its settle period: the timeout of the run
    /// (`executionTimeLimit`) and the settle period.
    private static let runCodeSleepers = 2

    /// How many waits the run clock holds while a top-level `execute` call
    /// waits for its settle period: only the settle period, because
    /// `execute` declares no timeout.
    private static let executeSleepers = 1

    /// A command that blocks on `gate`, then prints `done`.
    ///
    /// - Parameter gate: The gate the command waits on.
    /// - Returns: The command.
    private static func heldCommand(_ gate: ShellCommandGate) -> String {
        "\(gate.waitCommand); echo done"
    }

    /// Releases the command that waits on `gate`, and records an issue when
    /// that command exited before it got the line, or when the call that must
    /// start the command ended before the command started.
    ///
    /// The release ends on an event in each case, see
    /// ``ShellCommandGate/release(commandIn:orEndOf:)``. When the command is
    /// gone, the test waits for the end of its record, which is an event of
    /// `state`, and records an issue with that record. When the call ended
    /// first, the test records an issue with what the call returned. Thus no
    /// release waits for all time.
    ///
    /// - Parameters:
    ///   - gate: The gate the command waits on.
    ///   - state: The store of the shell commands of the test.
    ///   - call: The end of the call that must start the command.
    /// - Throws: What ``ShellCommandGate/release(commandIn:orEndOf:)`` throws.
    private static func release(
        _ gate: ShellCommandGate, commandIn state: ShellState, orEndOf call: CallEnd
    ) async throws {
        switch try await gate.release(commandIn: state, orEndOf: call) {
        case .released(.reached, _):
            return
        case .released(.commandExited, let commandID):
            await state.waitForStoredLines(commandID: commandID, atLeast: .max)
            let record = await state.record(commandID: commandID)
            Issue.record(
                "the command ended before the gate released it; its record: \(String(describing: record))")
        case .callEndedFirst(let returned):
            Issue.record("the call ended before it started the command; the call \(returned)")
        }
    }

    /// The end of the background run `completionToken`: the event of its
    /// run mail in `log`.
    ///
    /// Each test that uses it waits for the run mail of that run next, thus
    /// the task that waits for the event ends in the test.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the run.
    ///   - log: The output of the session.
    /// - Returns: The end of the run, with the terminal event of the run.
    private static func endOfRun(_ completionToken: String, in log: SessionOutputLog) -> CallEnd {
        CallEnd.after {
            do {
                let runMail = try await log.runMail(settling: completionToken)
                return "settled with \(String(describing: await log.settledRun(in: runMail)))"
            } catch {
                return "ended with no run mail: \(error)"
            }
        }
    }

    /// The `execute` verb and the `getLines` verb over one store, with a
    /// process-group registry private to this test.
    ///
    /// - Returns: The two verbs, and the store that records each command.
    /// - Throws: When the store does not prepare.
    private static func shellVerbs() throws -> (execute: Execute, getLines: GetLines, state: ShellState) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-settle-\(ULID.generate())")
        let state = try ShellState(preferredDirectory: directory)
        return (
            Execute(runner: ShellRunner(state: state, registry: ProcessRegistry())), GetLines(state: state), state
        )
    }

    /// The commandID of the one command that `state` recorded.
    ///
    /// - Parameter state: The store of the shell commands.
    /// - Returns: The commandID.
    /// - Throws: When the store holds no command.
    private static func onlyCommandID(in state: ShellState) async throws -> String {
        let records = await state.listCommands()
        #expect(records.count == 1, "commands: \(records.map(\.command))")
        return try #require(records.first).id
    }

    /// Records an issue unless `text` names the `tools.shell.execute` call
    /// `commandID` as a call that the snippet did not await, and does not
    /// ask the model to run the call again.
    ///
    /// - Parameters:
    ///   - commandID: The commandID of the call.
    ///   - text: The text the model reads.
    private static func expectNamesUnawaitedExecute(_ commandID: String, in text: String) {
        #expect(text.contains(PendingInnerCalls.noticeLead), "text: \(text)")
        #expect(text.contains(executePath), "text: \(text)")
        #expect(text.contains(executeTool), "text: \(text)")
        #expect(text.contains(executeOp), "text: \(text)")
        #expect(text.contains(commandID), "text: \(text)")
        #expect(!text.contains(ToolReturnLedger.uncarriedReturnNotice), "text: \(text)")
    }

    /// A `runCode` whose snippets reach `tools.shell.execute` and
    /// `tools.shell.getLines`.
    ///
    /// - Parameters:
    ///   - grace: The settle period of `runCode`, or `nil` for the stock
    ///     value.
    ///   - snippetEnded: The gate to open when the code of a snippet ends, or
    ///     `nil` for the stock interpreter (see
    ///     ``SnippetEndSignalingInterpreter``).
    /// - Returns: The tool, and the store of its shell commands.
    /// - Throws: When the store does not prepare, or the surface does not
    ///   render.
    private static func shellRunCode(
        grace: TimeInterval? = nil, snippetEnded: TestGate? = nil
    ) throws -> (runCode: MultiTool, state: ShellState) {
        let verbs = try shellVerbs()
        let registry = try MultiTool.Builder()
            .addGroup(named: "shell", [verbs.execute, verbs.getLines])
            .buildRegistry()
        let configuration = grace.map { MultiToolConfiguration(inlineSettleGrace: $0) } ?? .default
        let interpreter = snippetEnded.map { SnippetEndSignalingInterpreter(opening: $0) }
        return (
            MultiTool(registry: registry, configuration: configuration, interpreter: interpreter), verbs.state
        )
    }

    /// Makes a Router session over a mail probe backend, as
    /// `makeMailProbeSession(mounting:inlineSettleGrace:prompts:step:)` does,
    /// on the run clock `clock`, and gives it to `body`.
    ///
    /// The helper closes the session when `body` returns or throws. A session
    /// that is not closed has no contract: its tasks can still run after the
    /// test.
    ///
    /// - Parameters:
    ///   - tools: The tools the session mounts.
    ///   - inlineSettleGrace: The settle period of the session, in seconds.
    ///   - prompts: Where the backend records each prompt.
    ///   - step: What each submission does.
    ///   - clock: The run clock of the session.
    ///   - body: The work that uses the session.
    /// - Returns: What `body` returned.
    /// - Throws: What resolving the stub profile throws, or what `body` threw.
    private static func withSession<Result>(
        mounting tools: [any Tool],
        inlineSettleGrace: TimeInterval = ToolMount.defaultInlineSettleGrace,
        prompts: MailProbePrompts,
        step: @escaping MailProbeToolsStep,
        clock: ManualRunClock,
        _ body: (any RoutedSession) async throws -> Result
    ) async throws -> Result {
        let loader = StubModelLoader(container: MailProbeContainer(prompts: prompts, step: step))
        let profile = try await makeStubProfile(
            loader: loader, standardModel: ModelRef(stringLiteral: "stub/mailprobe-\(ULID.generate())"),
            runClock: clock)
        let session = profile.standard.makeSession(
            configuration: SessionConfiguration(tools: tools, inlineSettleGrace: inlineSettleGrace))
        return try await closing(session) { try await body(session) }
    }

    /// The step of a session whose first submission runs `snippet` in
    /// `runCode`, and answers with what the call gave. Each later submission
    /// only answers.
    ///
    /// - Parameter snippet: The snippet to run.
    /// - Returns: The step.
    private static func runningSnippet(_ snippet: String) -> MailProbeToolsStep {
        runCodeStep { index, runCode in
            guard index == 0 else { return "answered" }
            return try await runCode.call(arguments: RunCodeArguments(code: snippet))
        }
    }

    /// The step of a session whose first submission calls the mounted
    /// `execute` with `command`, and answers with what the call gave.
    ///
    /// - Parameter command: The command to run.
    /// - Returns: The step.
    private static func executing(_ command: String) -> MailProbeToolsStep {
        { index, tools in
            guard index == 0 else { return "answered" }
            let execute = try #require(tools.lazy.compactMap { $0 as? any Tool<ExecuteArguments, String> }.first)
            return try await execute.call(arguments: ExecuteArguments(command: command))
        }
    }

    /// The text a snippet value renders as, read back as a value.
    ///
    /// A `runCode` result can end with the notice of `ToolReturnLedger`, thus
    /// only the first line is read.
    ///
    /// - Parameter result: The `runCode` result.
    /// - Returns: The value of its first line.
    /// - Throws: When the first line is not JSON.
    private static func returnedValue(of result: String) throws -> InterpreterValue {
        let firstLine = String(result.prefix { $0 != "\n" })
        return try JSONDecoder().decode(InterpreterValue.self, from: Data(firstLine.utf8))
    }

    /// The prompts after the first one that contain `text`.
    ///
    /// - Parameters:
    ///   - text: The text to find.
    ///   - prompts: Every prompt the backend got, in order.
    /// - Returns: The later prompts that contain it.
    private static func laterPrompts(containing text: String, in prompts: [String]) -> [String] {
        prompts.dropFirst().filter { $0.contains(text) }
    }

    /// Records an issue when the model got run mail: when the session
    /// delivered mail other than the user messages of the test, or when the
    /// answer to a user message delivered other mail.
    ///
    /// A call that ends inside the settle period still posts its terminal
    /// event, and the session queues it as run mail. The mount then withdraws
    /// that mail, and the session ends it with `cancelled`. Thus each run
    /// mail of the session must end `cancelled`, with no `mailDelivered`.
    ///
    /// - Parameters:
    ///   - log: The output of the session.
    ///   - followUp: The last user message of the test, and its answer.
    private static func expectNoRunMail(in log: SessionOutputLog, followUp: AnsweredMail) async {
        let userMessages = await log.askedMails
        #expect(userMessages.last?.id == followUp.id)
        let userIds = userMessages.map(\.id)
        let delivered = await log.deliveredMailIds
        #expect(delivered == userIds, "the session delivered: \(delivered)")
        for message in userMessages {
            #expect(message.answer.mailIds == [message.id], "the answer delivered: \(message.answer.mailIds)")
        }
        for runMail in await log.allRunMailIds {
            guard await log.waitForTerminal(of: runMail) else {
                Issue.record("run mail \(runMail) got no terminal event: the event stream finished or the task was cancelled first")
                continue
            }
            guard case .cancelled = await log.terminal(of: runMail) else {
                Issue.record("run mail \(runMail) ended with \(String(describing: await log.terminal(of: runMail)))")
                continue
            }
        }
    }

    /// Runs a snippet that starts a held command with no `await`, with the
    /// stock settle period, and answers with the inline result.
    ///
    /// The command ends after the code of the snippet ended, in a fixed
    /// order: the interpreter opens a gate when the snippet code ends (see
    /// ``SnippetEndSignalingInterpreter``), and the test releases the command
    /// only after that gate opened. The clock of the session never moves,
    /// thus the call answers inline when the run settles.
    ///
    /// - Parameter snippet: Makes the snippet from the held command.
    /// - Returns: The result, and the store of the shell commands.
    /// - Throws: When the session does not start or the call fails.
    private static func inlineResultOfFloatingCall(
        _ snippet: (_ command: String) -> String
    ) async throws -> (result: String, state: ShellState) {
        let gate = try ShellCommandGate()
        let snippetEnded = TestGate()
        let probe = try shellRunCode(snippetEnded: snippetEnded)
        let result = try await Self.withSession(
            mounting: [probe.runCode], prompts: MailProbePrompts(),
            step: runningSnippet(snippet(heldCommand(gate))), clock: ManualRunClock()
        ) { session in
            let callEnd = CallEnd()
            // The wait for the end of the snippet code also ends when the call
            // ends first.
            let responded = try await EventRace.watch(
                { try await callEnd.recording { try await session.respond(to: "run the snippet") } },
                untilOpen: snippetEnded, orFail: "the call ended before the code of the snippet ended")
            try await Self.release(gate, commandIn: probe.state, orEndOf: callEnd)
            return try await responded.task.value
        }
        #expect(!PendingRunEnvelope.isRendered(text: result), "the snippet went to the background: \(result)")
        return (result, probe.state)
    }

    // MARK: - Acceptance 1: a short inner execute gives the snippet its own value

    @Test("a snippet that runs echo hi through tools.shell.execute reads r.exitCode as 0, and no mail comes")
    func snippetExecuteAnswersWithItsOwnResult() async throws {
        let prompts = MailProbePrompts()
        try await Self.withSession(
            mounting: [try Self.shellRunCode().runCode], prompts: prompts,
            step: Self.runningSnippet(
                "const r = await tools.shell.execute({command: \"echo hi\"}); return [r.exitCode, r.commandID];"),
            clock: ManualRunClock()
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let result = try await log.ask("run echo hi").reply
            let followUp = try await log.ask(Self.followUpMessage)
            let all = prompts.all

            #expect(!PendingRunEnvelope.isRendered(text: result), "answer was: \(result)")
            let values = try #require(
                Self.returnedValue(of: result).arrayItems, "the snippet did not return an array: \(result)")
            try #require(values.count == 2, "the snippet did not return [exitCode, commandID]: \(result)")
            let commandID = try #require(values[1].stringText, "the snippet returned no commandID: \(result)")
            #expect(values[0] == .number(0))
            #expect(all.count == 2, "a mail submission came: \(all)")
            #expect(Self.laterPrompts(containing: commandID, in: all).isEmpty)
            await Self.expectNoRunMail(in: log, followUp: followUp)
        }
    }

    // MARK: - Acceptance 2: a short top-level execute answers with its report

    @Test("a top-level execute of echo hi answers with its report, with no pending key, and no mail comes")
    func topLevelExecuteAnswersWithItsReport() async throws {
        let prompts = MailProbePrompts()
        let verbs = try Self.shellVerbs()
        try await Self.withSession(
            mounting: [verbs.execute], prompts: prompts, step: Self.executing("echo hi"), clock: ManualRunClock()
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let report = try await log.ask("run echo hi").reply
            let followUp = try await log.ask(Self.followUpMessage)
            let all = prompts.all

            #expect(!PendingRunEnvelope.isRendered(text: report), "answer was: \(report)")
            let fields = try #require(
                Self.returnedValue(of: report).objectFields, "the answer is not a report: \(report)")
            let commandID = try #require(
                fields[Execute.commandIDField]?.stringText, "the report has no commandID: \(report)")
            #expect(fields["pending"] == nil)
            #expect(fields["exitCode"] == .number(0))
            #expect(fields["output"] == .array([.string("1: hi")]))
            #expect(all.count == 2, "a mail submission came: \(all)")
            #expect(Self.laterPrompts(containing: commandID, in: all).isEmpty)
            await Self.expectNoRunMail(in: log, followUp: followUp)
        }
    }

    // MARK: - An awaited inner call gives the snippet its real result

    /// The first command holds until the test releases it. The test moves the
    /// clock past the settle period while the command holds, thus the call
    /// answers with the pending envelope, and the test releases the command
    /// only after that answer.
    @Test("a snippet that awaits a long execute that writes a file, then reads and deletes it, reads the full output, and the result comes back as mail")
    func awaitedLongExecuteGivesTheRealResult() async throws {
        let prompts = MailProbePrompts()
        let gate = try ShellCommandGate()
        let clock = ManualRunClock()
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-await-\(ULID.generate()).log").path
        let snippet = """
            await tools.shell.execute({command: "\(gate.waitCommand); echo \(Self.fullOutputLine) > \(logPath)"});
            const read = await tools.shell.execute({command: "cat \(logPath); rm \(logPath)"});
            return read.output;
            """
        let probe = try Self.shellRunCode(grace: Self.shortGrace)
        try await Self.withSession(
            mounting: [probe.runCode], inlineSettleGrace: Self.shortGrace,
            prompts: prompts, step: Self.runningSnippet(snippet), clock: clock
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let answer = try await callPastSettlePeriod(
                on: clock, grace: Self.shortGrace, timers: Self.runCodeSleepers
            ) {
                try await log.ask("run the long command")
            }.reply

            let envelope = try mailProbeEnvelope(answer)
            try await Self.release(
                gate, commandIn: probe.state, orEndOf: Self.endOfRun(envelope.completionToken, in: log))
            let runMail = try await log.deliveredRunMail(settling: envelope.completionToken)
            #expect(runMail.event.detail.contains(Self.fullOutputLine), "run mail: \(runMail.event.detail)")
            #expect(runMail.answer.mailIds.contains(runMail.id))
            let mail = try #require(Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).first)
            #expect(mail.contains(Self.fullOutputLine), "mail: \(mail)")
            #expect(!FileManager.default.fileExists(atPath: logPath))
        }
    }

    @Test("a short snippet that awaits a short execute still answers inline with the real result, and no mail comes")
    func shortSnippetStillAnswersInline() async throws {
        let prompts = MailProbePrompts()
        try await Self.withSession(
            mounting: [try Self.shellRunCode(grace: Self.shortGrace).runCode], inlineSettleGrace: Self.shortGrace,
            prompts: prompts,
            step: Self.runningSnippet("return (await tools.shell.execute({command: \"echo hi\"})).output;"),
            clock: ManualRunClock()
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let result = try await log.ask("run echo hi").reply
            let followUp = try await log.ask(Self.followUpMessage)
            let all = prompts.all

            #expect(!PendingRunEnvelope.isRendered(text: result), "answer was: \(result)")
            #expect(try Self.returnedValue(of: result) == .array([.string("1: hi")]), "answer was: \(result)")
            #expect(!result.contains(PendingInnerCalls.noticeLead), "answer was: \(result)")
            #expect(all.count == 2, "a mail submission came: \(all)")
            await Self.expectNoRunMail(in: log, followUp: followUp)
        }
    }

    // MARK: - A call that the snippet did not await

    /// The command holds until the test releases it. The test moves the clock
    /// past the settle period while the command holds, and releases the
    /// command only after the call answered with the pending envelope.
    @Test("a snippet that starts a long execute without await and ends sends mail that names that call")
    func unawaitedLongExecuteIsNamedInTheMail() async throws {
        let prompts = MailProbePrompts()
        let gate = try ShellCommandGate()
        let clock = ManualRunClock()
        let probe = try Self.shellRunCode(grace: Self.shortGrace)
        let snippet = """
            tools.shell.execute({command: "\(Self.heldCommand(gate))"});
            return { started: 1 };
            """
        try await Self.withSession(
            mounting: [probe.runCode], inlineSettleGrace: Self.shortGrace, prompts: prompts,
            step: Self.runningSnippet(snippet), clock: clock
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let answer = try await callPastSettlePeriod(
                on: clock, grace: Self.shortGrace, timers: Self.runCodeSleepers
            ) {
                try await log.ask("run the long command")
            }.reply

            let envelope = try mailProbeEnvelope(answer)
            try await Self.release(
                gate, commandIn: probe.state, orEndOf: Self.endOfRun(envelope.completionToken, in: log))
            let runMail = try await log.deliveredRunMail(settling: envelope.completionToken)
            #expect(runMail.answer.mailIds.contains(runMail.id))
            let mail = try #require(Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).first)
            let commandID = try await Self.onlyCommandID(in: probe.state)
            Self.expectNamesUnawaitedExecute(commandID, in: runMail.event.detail)
            Self.expectNamesUnawaitedExecute(commandID, in: mail)
        }
    }

    @Test("a snippet that starts a short execute without await and ends inside the settle period gets a result that names that call")
    func unawaitedShortExecuteIsNamedInline() async throws {
        let run = try await Self.inlineResultOfFloatingCall { command in
            "tools.shell.execute({command: \"\(command)\"}); return { started: 1 };"
        }

        let commandID = try await Self.onlyCommandID(in: run.state)
        Self.expectNamesUnawaitedExecute(commandID, in: run.result)
    }

    /// The command of the nested snippet must end after the code of the
    /// nested snippet ended. A nested `tools.runCode` runs on the interpreter
    /// of the outer `MultiTool`, thus ``SnippetEndSignalingInterpreter`` also
    /// sees the end of the nested snippet code. The nested snippet ends before
    /// the outer one, thus it opens the gate first, and the test releases the
    /// held command only then. The settle period waits on a stopped
    /// `ManualRunClock`, thus no settle period can end by time.
    @Test("a nested tools.runCode that starts an execute without await gets an outer result that names that call")
    func nestedUnawaitedExecuteIsNamedInTheOuterResult() async throws {
        let run = try await Self.inlineResultOfFloatingCall { command in
            let nestedSnippet = "tools.shell.execute({command: \"\(command)\"}); return { remaining: 1 };"
            return "const nested = await tools.runCode({code: `\(nestedSnippet)`}); return nested.remaining;"
        }

        #expect(try Self.returnedValue(of: run.result) == .number(1), "result: \(run.result)")
        let commandID = try await Self.onlyCommandID(in: run.state)
        Self.expectNamesUnawaitedExecute(commandID, in: run.result)
    }

    @Test("a snippet that starts an execute without await and then throws gets an error that names that call")
    func failedSnippetNamesTheUnawaitedCall() async throws {
        let run = try await Self.inlineResultOfFloatingCall { command in
            "tools.shell.execute({command: \"\(command)\"}); throw new Error(\"stopped\");"
        }

        #expect(run.result.contains("stopped"), "result: \(run.result)")
        let commandID = try await Self.onlyCommandID(in: run.state)
        Self.expectNamesUnawaitedExecute(commandID, in: run.result)
    }

    // MARK: - Acceptance 4: a short snippet answers with its own value

    @Test("a runCode snippet that ends inside the settle period answers with its own value, with no envelope")
    func shortSnippetAnswersWithItsOwnValue() async throws {
        let prompts = MailProbePrompts()
        try await Self.withSession(
            mounting: [try Self.shellRunCode().runCode], prompts: prompts, step: Self.runningSnippet("return 1 + 1;"),
            clock: ManualRunClock()
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let result = try await log.ask("add").reply
            let followUp = try await log.ask(Self.followUpMessage)
            let all = prompts.all

            #expect(result == "2")
            #expect(all.count == 2, "a mail submission came: \(all)")
            await Self.expectNoRunMail(in: log, followUp: followUp)
        }
    }

    // MARK: - The host setting

    /// The command holds while the test moves the clock past the settle
    /// period of one second, thus the call answers with the pending envelope.
    /// The test then releases the command, and its report comes back as mail.
    @Test("a host that sets the settle period to one second gets a pending envelope for sleep 3, and the report comes back as one mail")
    func oneSecondHostGetsAPendingEnvelope() async throws {
        let prompts = MailProbePrompts()
        let verbs = try Self.shellVerbs()
        let gate = try ShellCommandGate()
        let clock = ManualRunClock()
        try await Self.withSession(
            mounting: [verbs.execute], inlineSettleGrace: Self.oneSecondGrace, prompts: prompts,
            step: Self.executing(Self.heldCommand(gate)), clock: clock
        ) { session in
            let log = await SessionOutputLog.reading(session)

            let answer = try await callPastSettlePeriod(
                on: clock, grace: Self.oneSecondGrace, timers: Self.executeSleepers
            ) {
                try await log.ask("run the command")
            }.reply

            let envelope = try mailProbeEnvelope(answer)
            #expect(envelope.pending)
            try await Self.release(
                gate, commandIn: verbs.state, orEndOf: Self.endOfRun(envelope.completionToken, in: log))
            let runMail = try await log.deliveredRunMail(settling: envelope.completionToken)
            let followUp = try await log.ask(Self.followUpMessage)
            #expect(await log.runMailIds(settling: envelope.completionToken) == [runMail.id])
            #expect(await log.deliveredMailIds.filter { $0 == runMail.id }.count == 1)
            #expect(followUp.answer.mailIds == [followUp.id])
            #expect(Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).count == 1)
        }
    }

    /// The command holds while the test moves the clock three seconds, inside
    /// the default settle period. The test then releases the command, and the
    /// call answers with the report.
    @Test("a host that keeps the default settle period gets the report of sleep 3 in the answer")
    func defaultHostGetsTheInlineReport() async throws {
        let prompts = MailProbePrompts()
        let verbs = try Self.shellVerbs()
        let gate = try ShellCommandGate()
        let clock = ManualRunClock()
        try await Self.withSession(
            mounting: [verbs.execute], prompts: prompts, step: Self.executing(Self.heldCommand(gate)), clock: clock
        ) { session in
            let callEnd = CallEnd()
            let responded = EventRace.watch {
                try await callEnd.recording { try await session.respond(to: "run the command") }
            }
            // The wait for the timer of the settle period also ends when the
            // call ends first.
            await clock.waitForSleepers(atLeast: Self.executeSleepers, orUntil: { await responded.waitForEnd() })
            clock.advance(by: Self.threeSecondRun)
            try await Self.release(gate, commandIn: verbs.state, orEndOf: callEnd)
            let report = try await responded.task.value

            #expect(!PendingRunEnvelope.isRendered(text: report), "answer was: \(report)")
            let fields = try #require(
                Self.returnedValue(of: report).objectFields, "the answer is not a report: \(report)")
            #expect(fields["exitCode"] == .number(0))
            #expect(fields["output"] == .array([.string("1: done")]))
        }
    }

    @Test("SessionConfiguration and MultiToolConfiguration take the one hosting default")
    func theStockSettlePeriodIsTheHostingDefault() {
        #expect(SessionConfiguration().inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
        #expect(MultiToolConfiguration.default.inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
    }
}
