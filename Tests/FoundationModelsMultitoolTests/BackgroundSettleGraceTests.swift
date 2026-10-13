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
@Suite("a background call that ends inside the settle period answers with its own result")
struct BackgroundSettleGraceTests {

    // MARK: - Fixtures

    /// A short settle period, in seconds, for a test that needs the period to
    /// elapse.
    private static let shortGrace: TimeInterval = 2

    /// The settle period of the "host that sets one second" test.
    private static let oneSecondGrace: TimeInterval = 1

    /// A command that ends inside the default settle period but not inside
    /// one second.
    private static let threeSecondCommand = "sleep 3; echo done"

    /// A command that runs longer than ``shortGrace``.
    private static let longCommand = "sleep 4; echo done"

    /// A command that ends well inside the default settle period, but not at
    /// once, so a snippet that does not await it ends first.
    private static let shortCommand = "sleep 1; echo done"

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
    /// - Parameter grace: The settle period of `runCode`, or `nil` for the
    ///   stock value.
    /// - Returns: The tool, and the store of its shell commands.
    /// - Throws: When the store does not prepare, or the surface does not
    ///   render.
    private static func shellRunCode(grace: TimeInterval? = nil) throws -> (runCode: MultiTool, state: ShellState) {
        let verbs = try shellVerbs()
        let registry = try MultiTool.Builder()
            .addGroup(named: "shell", [verbs.execute, verbs.getLines])
            .buildRegistry()
        let configuration = grace.map { MultiToolConfiguration(inlineSettleGrace: $0) } ?? .default
        return (MultiTool(registry: registry, configuration: configuration), verbs.state)
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

    /// Runs `snippet` in `runCode` with the stock settle period, and answers
    /// with the inline result.
    ///
    /// - Parameter snippet: The snippet to run.
    /// - Returns: The result, and the store of the shell commands.
    /// - Throws: When the session does not start or the call fails.
    private static func inlineResult(of snippet: String) async throws -> (result: String, state: ShellState) {
        let probe = try shellRunCode()
        let session = try await makeMailProbeSession(
            mounting: [probe.runCode], prompts: MailProbePrompts(), step: runningSnippet(snippet))
        let result = try await session.respond(to: "run the snippet")
        #expect(!PendingRunEnvelope.isRendered(text: result), "the snippet went to the background: \(result)")
        return (result, probe.state)
    }

    // MARK: - Acceptance 1: a short inner execute gives the snippet its own value

    @Test("a snippet that runs echo hi through tools.shell.execute reads r.exitCode as 0, and no mail comes")
    func snippetExecuteAnswersWithItsOwnResult() async throws {
        let prompts = MailProbePrompts()
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode().runCode], prompts: prompts,
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

    // MARK: - An awaited inner call gives the snippet its real result

    @Test("a snippet that awaits a long execute that writes a file, then reads and deletes it, reads the full output, and the result comes back as mail")
    func awaitedLongExecuteGivesTheRealResult() async throws {
        let prompts = MailProbePrompts()
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-await-\(ULID.generate()).log").path
        let snippet = """
            await tools.shell.execute({command: "sleep 4; echo \(Self.fullOutputLine) > \(logPath)"});
            const read = await tools.shell.execute({command: "cat \(logPath); rm \(logPath)"});
            return read.output;
            """
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode(grace: Self.shortGrace).runCode], inlineSettleGrace: Self.shortGrace,
            prompts: prompts, step: Self.runningSnippet(snippet))

        let answer = try await session.respond(to: "run the long command")

        let envelope = try mailProbeEnvelope(answer)
        try await TestPoll.waitUntil("the result of the snippet comes back as mail") {
            !Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).isEmpty
        }
        let mail = try #require(Self.laterPrompts(containing: envelope.completionToken, in: prompts.all).first)
        #expect(mail.contains(Self.fullOutputLine), "mail: \(mail)")
        #expect(!FileManager.default.fileExists(atPath: logPath))
    }

    @Test("a short snippet that awaits a short execute still answers inline with the real result, and no mail comes")
    func shortSnippetStillAnswersInline() async throws {
        let prompts = MailProbePrompts()
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode(grace: Self.shortGrace).runCode], inlineSettleGrace: Self.shortGrace,
            prompts: prompts,
            step: Self.runningSnippet("return (await tools.shell.execute({command: \"echo hi\"})).output;"))

        let result = try await session.respond(to: "run echo hi")
        _ = try await session.respond(to: Self.followUpMessage)
        let all = await prompts.awaiting(2)

        #expect(!PendingRunEnvelope.isRendered(text: result), "answer was: \(result)")
        #expect(try Self.returnedValue(of: result) == .array([.string("1: hi")]), "answer was: \(result)")
        #expect(!result.contains(PendingInnerCalls.noticeLead), "answer was: \(result)")
        #expect(all.count == 2, "a mail submission came: \(all)")
    }

    // MARK: - A call that the snippet did not await

    @Test("a snippet that starts a long execute without await and ends sends mail that names that call")
    func unawaitedLongExecuteIsNamedInTheMail() async throws {
        let prompts = MailProbePrompts()
        let probe = try Self.shellRunCode(grace: Self.shortGrace)
        let snippet = """
            tools.shell.execute({command: "\(Self.longCommand)"});
            return { started: 1 };
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
        Self.expectNamesUnawaitedExecute(commandID, in: mail)
    }

    @Test("a snippet that starts a short execute without await and ends inside the settle period gets a result that names that call")
    func unawaitedShortExecuteIsNamedInline() async throws {
        let run = try await Self.inlineResult(
            of: "tools.shell.execute({command: \"\(Self.shortCommand)\"}); return { started: 1 };")

        let commandID = try await Self.onlyCommandID(in: run.state)
        Self.expectNamesUnawaitedExecute(commandID, in: run.result)
    }

    @Test("a nested tools.runCode that starts an execute without await gets an outer result that names that call")
    func nestedUnawaitedExecuteIsNamedInTheOuterResult() async throws {
        let nestedSnippet = "tools.shell.execute({command: \"\(Self.shortCommand)\"}); return { remaining: 1 };"
        let run = try await Self.inlineResult(
            of: "const nested = await tools.runCode({code: `\(nestedSnippet)`}); return nested.remaining;")

        #expect(try Self.returnedValue(of: run.result) == .number(1), "result: \(run.result)")
        let commandID = try await Self.onlyCommandID(in: run.state)
        Self.expectNamesUnawaitedExecute(commandID, in: run.result)
    }

    @Test("a snippet that starts an execute without await and then throws gets an error that names that call")
    func failedSnippetNamesTheUnawaitedCall() async throws {
        let run = try await Self.inlineResult(
            of: "tools.shell.execute({command: \"\(Self.shortCommand)\"}); throw new Error(\"stopped\");")

        #expect(run.result.contains("stopped"), "result: \(run.result)")
        let commandID = try await Self.onlyCommandID(in: run.state)
        Self.expectNamesUnawaitedExecute(commandID, in: run.result)
    }

    // MARK: - Acceptance 4: a short snippet answers with its own value

    @Test("a runCode snippet that ends inside the settle period answers with its own value, with no envelope")
    func shortSnippetAnswersWithItsOwnValue() async throws {
        let prompts = MailProbePrompts()
        let session = try await makeMailProbeSession(
            mounting: [try Self.shellRunCode().runCode], prompts: prompts, step: Self.runningSnippet("return 1 + 1;"))

        let result = try await session.respond(to: "add")
        _ = try await session.respond(to: Self.followUpMessage)
        let all = await prompts.awaiting(2)

        #expect(result == "2")
        #expect(all.count == 2, "a mail submission came: \(all)")
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
