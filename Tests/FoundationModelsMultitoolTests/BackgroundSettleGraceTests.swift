import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The rule of the user for each background tool call: "background should
/// mean 'if it takes longer than grace, background'".
///
/// Each call of a background tool waits for the settle period of the host. A
/// call that ends in that time answers with its own result, the same as a
/// synchronous call, and no mail comes for it. Only a call that runs longer
/// answers with a pending result, and its result comes back later as mail,
/// one time. The rule is the same at the top level and for an inner `tools.*`
/// call of a snippet, and `tools.shell.execute` is the tool where it matters
/// most (SWE-bench run `preds.code-context-1008`, instance
/// `django__django-14016`).
///
/// Each test goes through a real Router session that a host makes with
/// `SessionConfiguration`, so the session mount, the outbox and the mail pump
/// are the real ones. The backend records the prompt of each submission,
/// which is where mail arrives (see `MailProbeFixtures.swift`).
@Suite("a background call that ends inside the settle period answers with its own result")
struct BackgroundSettleGraceTests {

    // MARK: - Fixtures

    /// A short settle period, in seconds, for a test that needs the period to
    /// elapse. It is long enough for the reserve of an inner call
    /// (`BackgroundToolRunner.innerCallSettleReserve`, one second) to leave
    /// the inner call a wait of its own.
    private static let shortGrace: TimeInterval = 2

    /// The settle period of the "host that sets one second" test.
    private static let oneSecondGrace: TimeInterval = 1

    /// A command that ends inside the default settle period but not inside
    /// one second.
    private static let threeSecondCommand = "sleep 3; echo done"

    /// A command that runs longer than ``shortGrace``.
    private static let longCommand = "sleep 4; echo done"

    /// The caller message of the submission after the call. Mail that stays
    /// in the outbox goes into this prompt.
    private static let followUpMessage = "one more message"

    /// The `tools.*` path of the pause tool of ``pendingProbeRunCode()``.
    private static let pauseToolName = "pause"

    /// How long the pause tool waits: longer than ``shortGrace``, thus a
    /// snippet that calls it goes to the background.
    private static let pauseNanoseconds: UInt64 = 3_000_000_000

    /// A command that runs longer than a snippet that calls the pause tool.
    private static let longerCommand = "sleep 6; echo done"

    /// The `tools.*` path of the shell verb that the pending notice names.
    private static let executePath = "tools.shell.execute"

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

    /// A `runCode` with the settle period ``shortGrace``, whose snippets
    /// reach `tools.shell.execute` and a `tools.pause` that waits for
    /// ``pauseNanoseconds`` and does not go to the background.
    ///
    /// - Returns: The tool, and the store of its shell commands.
    /// - Throws: When the store does not prepare, or the surface does not
    ///   render.
    private static func pendingProbeRunCode() throws -> (runCode: MultiTool, state: ShellState) {
        let verbs = try shellVerbs()
        let registry = try MultiTool.Builder()
            .addGroup(named: "shell", [verbs.execute, verbs.getLines])
            .addTools([WindowRecordingTool(name: pauseToolName, delayNanoseconds: pauseNanoseconds)])
            .buildRegistry()
        let configuration = MultiToolConfiguration(inlineSettleGrace: shortGrace)
        return (MultiTool(registry: registry, configuration: configuration), verbs.state)
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

    /// Records an issue unless `text` names the pending `tools.shell.execute`
    /// call `commandID` and carries the shared pending-work text.
    ///
    /// - Parameters:
    ///   - commandID: The commandID of the pending call.
    ///   - text: The text the model reads.
    private static func expectNamesPendingExecute(_ commandID: String, in text: String) {
        #expect(text.contains(executePath), "text: \(text)")
        #expect(text.contains(commandID), "text: \(text)")
        #expect(text.contains(PendingRunEnvelope.pendingWorkInstruction), "text: \(text)")
    }

    /// A `runCode` whose snippets reach `tools.shell.execute` and
    /// `tools.shell.getLines`.
    ///
    /// - Parameter grace: The settle period of `runCode` and of its inner
    ///   calls, or `nil` for the stock value.
    /// - Returns: The tool.
    /// - Throws: When the store does not prepare, or the surface does not
    ///   render.
    private static func shellRunCode(grace: TimeInterval? = nil) throws -> MultiTool {
        let verbs = try shellVerbs()
        let registry = try MultiTool.Builder()
            .addGroup(named: "shell", [verbs.execute, verbs.getLines])
            .buildRegistry()
        let configuration = grace.map { MultiToolConfiguration(inlineSettleGrace: $0) } ?? .default
        return MultiTool(registry: registry, configuration: configuration)
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

    // MARK: - Acceptance 1: a short inner execute gives the snippet its own value

    @Test("a snippet that runs echo hi through tools.shell.execute reads r.exitCode as 0, and no mail comes")
    func snippetExecuteAnswersWithItsOwnResult() async throws {
        let prompts = MailProbePrompts()
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode()], prompts: prompts,
            step: Self.runningSnippet(
                "const r = await tools.shell.execute({command: \"echo hi\"}); return [r.exitCode, r.commandID];"))

        let result = try await session.respond(to: "run echo hi")
        _ = try await session.respond(to: Self.followUpMessage)
        let all = await prompts.awaiting(2)

        #expect(!PendingRunEnvelope.isRendered(text: result), "answer was: \(result)")
        guard case .array(let values) = try Self.returnedValue(of: result), values.count == 2,
            case .string(let commandID) = values[1]
        else {
            Issue.record("the snippet did not return [exitCode, commandID]: \(result)")
            return
        }
        #expect(values[0] == .number(0))
        #expect(all.count == 2, "a mail submission came: \(all)")
        #expect(Self.laterPrompts(containing: commandID, in: all).isEmpty)
    }

    // MARK: - Acceptance 2: a short top-level execute answers with its report

    @Test("a top-level execute of echo hi answers with its report, with no pending key, and no mail comes")
    func topLevelExecuteAnswersWithItsReport() async throws {
        let prompts = MailProbePrompts()
        let verbs = try Self.shellVerbs()
        let session = try await makeMailProbeSession(
            mounting: [verbs.execute], prompts: prompts, step: Self.executing("echo hi"))

        let report = try await session.respond(to: "run echo hi")
        _ = try await session.respond(to: Self.followUpMessage)
        let all = await prompts.awaiting(2)

        #expect(!PendingRunEnvelope.isRendered(text: report), "answer was: \(report)")
        guard case .object(let fields) = try Self.returnedValue(of: report),
            case .string(let commandID) = fields[Execute.commandIDField]
        else {
            Issue.record("the answer is not a report: \(report)")
            return
        }
        #expect(fields["pending"] == nil)
        #expect(fields["exitCode"] == .number(0))
        #expect(fields["output"] == .array([.string("1: hi")]))
        #expect(all.count == 2, "a mail submission came: \(all)")
        #expect(Self.laterPrompts(containing: commandID, in: all).isEmpty)
    }

    // MARK: - Acceptance 3: a long inner execute gives the snippet a pending object

    @Test("a snippet whose execute runs past the settle period gets {pending: true, commandID}, getLines takes that id, and the result comes back as one mail")
    func snippetLongExecuteGivesAPendingObject() async throws {
        let prompts = MailProbePrompts()
        let snippet = """
            const r = await tools.shell.execute({command: "\(Self.longCommand)"});
            const g = await tools.shell.getLines({commandID: r.commandID});
            return [r.pending, r.commandID, g.commandID];
            """
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode(grace: Self.shortGrace)], inlineSettleGrace: Self.shortGrace,
            prompts: prompts, step: Self.runningSnippet(snippet))

        let result = try await session.respond(to: "run the long command")

        #expect(!PendingRunEnvelope.isRendered(text: result), "the snippet itself went to the background: \(result)")
        guard case .array(let values) = try Self.returnedValue(of: result), values.count == 3,
            case .string(let commandID) = values[1]
        else {
            Issue.record("the snippet did not return [pending, commandID, getLines id]: \(result)")
            return
        }
        #expect(values[0] == .bool(true))
        #expect(values[2] == .string(commandID))

        try await TestPoll.waitUntil("the result of the command comes back as mail") {
            !Self.laterPrompts(containing: commandID, in: prompts.all).isEmpty
        }
        _ = try await session.respond(to: Self.followUpMessage)
        let all = prompts.all
        #expect(Self.laterPrompts(containing: commandID, in: all).count == 1, "prompts: \(all)")
        #expect(all.last.map { !$0.contains(commandID) } == true)
    }

    // MARK: - Acceptance 4: a short snippet answers with its own value

    @Test("a runCode snippet that ends inside the settle period answers with its own value, with no envelope")
    func shortSnippetAnswersWithItsOwnValue() async throws {
        let prompts = MailProbePrompts()
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode()], prompts: prompts, step: Self.runningSnippet("return 1 + 1;"))

        let result = try await session.respond(to: "add")
        _ = try await session.respond(to: Self.followUpMessage)
        let all = await prompts.awaiting(2)

        #expect(result == "2")
        #expect(all.count == 2, "a mail submission came: \(all)")
    }

    // MARK: - A snippet that ends while an inner call is pending

    @Test("a snippet that starts a long execute, does not return it, and ends inline gets a result that names the pending call")
    func inlineSettleNamesThePendingInnerCall() async throws {
        let prompts = MailProbePrompts()
        let probe = try Self.pendingProbeRunCode()
        let snippet = """
            const r = await tools.shell.execute({command: "\(Self.longCommand)"});
            return { remaining: 1 };
            """
        let session = try await makeMailProbeSession(
            mounting: [probe.runCode], inlineSettleGrace: Self.shortGrace, prompts: prompts,
            step: Self.runningSnippet(snippet))

        let result = try await session.respond(to: "run the long command")

        #expect(!PendingRunEnvelope.isRendered(text: result), "the snippet itself went to the background: \(result)")
        let commandID = try await Self.onlyCommandID(in: probe.state)
        Self.expectNamesPendingExecute(commandID, in: result)
        #expect(!result.contains(ToolReturnLedger.uncarriedReturnNotice), "result: \(result)")
        try await TestPoll.waitUntil("the result of the command comes back as mail") {
            !Self.laterPrompts(containing: commandID, in: prompts.all).isEmpty
        }
    }

    @Test("a snippet that fails on the pending object of a long execute gets an error that names the pending call")
    func failedSnippetNamesThePendingInnerCall() async throws {
        let prompts = MailProbePrompts()
        let probe = try Self.pendingProbeRunCode()
        let snippet = """
            const s = await tools.shell.execute({command: "\(Self.longCommand)"});
            return s.output.slice(0, 10);
            """
        let session = try await makeMailProbeSession(
            mounting: [probe.runCode], inlineSettleGrace: Self.shortGrace, prompts: prompts,
            step: Self.runningSnippet(snippet))

        let result = try await session.respond(to: "run the long command")

        #expect(!PendingRunEnvelope.isRendered(text: result), "the snippet itself went to the background: \(result)")
        let commandID = try await Self.onlyCommandID(in: probe.state)
        Self.expectNamesPendingExecute(commandID, in: result)
        try await TestPoll.waitUntil("the result of the command comes back as mail") {
            !Self.laterPrompts(containing: commandID, in: prompts.all).isEmpty
        }
    }

    @Test("a snippet that starts a long execute, does not return it, and ends in the background sends mail that names the pending call")
    func backgroundSettleNamesThePendingInnerCall() async throws {
        let prompts = MailProbePrompts()
        let probe = try Self.pendingProbeRunCode()
        let snippet = """
            await tools.shell.execute({command: "\(Self.longerCommand)"});
            return await tools.\(Self.pauseToolName)({});
            """
        let session = try await makeMailProbeSession(
            mounting: [probe.runCode], inlineSettleGrace: Self.shortGrace, prompts: prompts,
            step: Self.runningSnippet(snippet))

        let answer = try await session.respond(to: "run the long command")

        let envelope = try mailProbeEnvelope(answer)
        try await TestPoll.waitUntil("the result of the snippet comes back as mail") {
            !Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).isEmpty
        }
        let mail = try #require(Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).first)
        let commandID = try await Self.onlyCommandID(in: probe.state)
        Self.expectNamesPendingExecute(commandID, in: mail)
        try await TestPoll.waitUntil("the result of the command comes back as mail") {
            Self.laterPrompts(containing: commandID, in: prompts.all).contains { $0 != mail }
        }
    }

    // MARK: - The host setting

    @Test("a host that sets the settle period to one second gets a pending envelope for sleep 3, and the report comes back as one mail")
    func oneSecondHostGetsAPendingEnvelope() async throws {
        let prompts = MailProbePrompts()
        let verbs = try Self.shellVerbs()
        let session = try await makeMailProbeSession(
            mounting: [verbs.execute], inlineSettleGrace: Self.oneSecondGrace, prompts: prompts,
            step: Self.executing(Self.threeSecondCommand))

        let answer = try await session.respond(to: "run the command")

        let envelope = try mailProbeEnvelope(answer)
        #expect(envelope.pending)
        try await TestPoll.waitUntil("the report of the command comes back as mail") {
            !Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).isEmpty
        }
        _ = try await session.respond(to: Self.followUpMessage)
        #expect(Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).count == 1)
    }

    @Test("a host that keeps the default settle period gets the report of sleep 3 in the answer")
    func defaultHostGetsTheInlineReport() async throws {
        let prompts = MailProbePrompts()
        let verbs = try Self.shellVerbs()
        let session = try await makeMailProbeSession(
            mounting: [verbs.execute], prompts: prompts, step: Self.executing(Self.threeSecondCommand))

        let report = try await session.respond(to: "run the command")

        #expect(!PendingRunEnvelope.isRendered(text: report), "answer was: \(report)")
        guard case .object(let fields) = try Self.returnedValue(of: report) else {
            Issue.record("the answer is not a report: \(report)")
            return
        }
        #expect(fields["exitCode"] == .number(0))
        #expect(fields["output"] == .array([.string("1: done")]))
    }

    @Test("SessionConfiguration and MultiToolConfiguration take the one hosting default")
    func theStockSettlePeriodIsTheHostingDefault() {
        #expect(SessionConfiguration().inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
        #expect(MultiToolConfiguration.default.inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
    }
}
