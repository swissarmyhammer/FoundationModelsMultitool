// `Execute` — the `tools.shell.execute` verb.
//
// A behavioral port of `../FoundationModelsShelltool/Sources/ShellTool/
// Operations/ExecuteCommand.swift`. The sibling is an `@Operation` that takes a
// `ShellContext`, races a deadline of its own and supervises its own detach;
// this package has none of those, thus the verb is a plain
// `FoundationModels.Tool` and the shared elevation engine of Router owns the
// race, the park and the cancel.
//
// eventplan.md § "Consolidation of the siblings": "consolidation is promotion,
// not construction", and "Detach supervision moves to the shared engine". So
// this file holds the shape of one request and the shape of one answer, and it
// holds no supervisor.
//
// **This verb is the RUN plane. Its two siblings are the content plane.**
// `tools.shell.getLines` and `tools.shell.grepHistory` read what a run wrote;
// this verb starts one. The join between the two planes is one string:
// eventplan.md states that "the `commandID` of a shell run is its
// `correlationID` is its `completionToken` — one string, two planes." This verb
// mints nothing. It reads that string out of the ambient `ToolContext` at the
// start of the call, thus a run is reachable under the same identifier from the
// store, from the event stream and from the run plane.
//
// **The seatbelt sandbox is the only gate on a command** (decision of
// 2026-08-24, eventplan.md § "Consolidation of the siblings"). This verb asks
// no permission question, it prompts nobody, and it keeps no remembered answer.
// What it does ask the sandbox is whether it can confine this command at all,
// and it asks BEFORE the run — see `CommandSandbox.preflight`, whose own doc
// comment names this verb as its caller: a confinement failure raised inside
// the runner is erased to a string on the way out, and a failure the model
// cannot read stops the turn instead of being repaired inside it.
//
// **Detach is an ordinary argument, and never an elevation the verb performs.**
// eventplan.md § "The constraint boundary": "A capability that wants detach
// semantics declares it as a usual argument (shell's `wait`). The capability
// then returns the run's identifier for the builtins." `wait` is that argument.
// The verb never parks a run itself — `SessionMailbox.park` is internal to
// Router and no code here names it. It DECLARES, through
// `DetachmentParameterProviding`, what kind of run this is and how to stop one,
// and the engine parks it on those terms. See the extension below.
//
// **The answer is `String`, and its two siblings answer a `@Generable` value.**
// That is the Router's rule rather than a preference:
// `ToolDetachment.wrapping` gives `DetachingTool` to a tool whose `Output` is
// `String`, and `ContextBindingTool` — which never parks — to every other tool.
// A verb that must reach the run plane therefore has one available output type.
// The answer is rendered through `ResultRenderer`, exactly as `runCode` and
// `wait` render theirs, thus the model reads one format for all of them.
//
// A request the verb cannot make stays IN BAND, as a `correction`. It is never
// thrown: a blank command, an environment that is not a JSON object of strings,
// and a confinement the sandbox refuses are each a mistake the model corrects
// inside the turn, and a thrown error would end the turn instead.
//
// Out of scope here: the limit on the length of a command and the limit on the
// length of an environment value. `ShellRunner.run(_:)` states that those
// belong to this verb, and they arrive with the card that depends on this one.

import Foundation
import FoundationModels
import FoundationModelsRouter

/// The arguments of `tools.shell.execute`: what to run, where, under what
/// environment, for how long, and whether to wait for it.
@Generable
struct ExecuteArguments {

    /// The command line that goes to `sh -c`.
    @Guide(description: "The shell command to run.")
    var command: String

    /// The time limit on the wall clock in seconds, or `nil` for no limit.
    @Guide(
        description:
            "Seconds before the command and every process it started are killed. Omit it for no "
            + "limit.")
    var timeout: Int?

    /// The directory the command runs in, or `nil` for the current directory of
    /// this process.
    @Guide(
        description:
            "The directory the command runs in. Omit it to run in the current directory.")
    var workingDirectory: String?

    /// The extra environment variables as JSON text, or `nil` for none.
    @Guide(
        description:
            "Extra environment variables, as a JSON object of string values — for example "
            + "'{\"KEY\":\"value\"}'. They stand on top of the environment this process holds. "
            + "Omit it to add none.")
    var environment: String?

    /// `false` to start the command in the background, or `nil` to wait for it.
    @Guide(
        description:
            "Whether to wait for the command to finish. Pass false to start it in the background "
            + "and get its completion token back at once, then collect it with the wait tool. "
            + "Omit it to wait.")
    var wait: Bool?
}

// MARK: - What kind of run this is, and how to stop one

extension Execute: DetachmentParameterProviding {

    /// The mount every `execute` call carries, which stands over the mount of
    /// whatever composed this verb.
    ///
    /// **A declared mount is the only way `wait: false` can ever park.**
    /// `DetachingTool` decides to detach on `configuration.mode` alone, and
    /// `RunBinding.innerCallMount` — the mount every inner `tools.*` call
    /// travels under — is `.runToCompletion`. A clock cannot move a mode, so a
    /// verb that answers a wait clock of zero under that mount would still
    /// block. Router states that a declared mount wins over the composition
    /// site, and this is the declaration eventplan.md § "The constraint
    /// boundary" asks a capability with detach semantics to make.
    ///
    /// The work clock is deliberately absent. A shell run already carries its
    /// own hard limit — the `timeout` argument, which `ShellRunner` arms as a
    /// timer that kills the process group — so a second work clock in the
    /// engine would be a second authority over the same question, firing on its
    /// own schedule. Leaving it `nil` also puts the `waitSeconds >= timeout`
    /// refusal of `DetachConfiguration` out of reach, which a per-call `timeout`
    /// under the block window would otherwise trip before any work started.
    var detachmentMount: DetachConfiguration? {
        DetachConfiguration(mode: .detaching, waitSeconds: Self.blockSeconds, timeout: nil)
    }

    /// The per-call clocks one `execute` call carries: the block window, and no
    /// work clock.
    ///
    /// This is the whole of what the `wait` argument does. `wait: false`
    /// answers a block window of zero, which `DetachConfiguration.waitSeconds`
    /// defines as detach immediately, so the call hands back the run's
    /// identifier and the command goes on. Every other value falls back to the
    /// mount's own window, and a command that outruns it detaches there.
    ///
    /// The arguments arrive as opaque `GeneratedContent`, and they are decoded
    /// through `ExecuteArguments` itself rather than read field by field, so
    /// this reading and the reading `call(arguments:)` makes cannot drift.
    ///
    /// - Parameter arguments: The call's arguments, as the engine holds them.
    /// - Returns: The block window, and no work clock.
    func detachmentClocks(
        from arguments: GeneratedContent
    ) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) {
        guard let decoded = try? ExecuteArguments(arguments), decoded.wait == false else {
            return (nil, nil)
        }
        return (Self.detachImmediatelySeconds, nil)
    }

    /// What kind of work a parked `execute` call is: an OS process group.
    ///
    /// eventplan.md § "Processes and tasks stay different kinds" keeps this
    /// distinction mandatory. A `.swiftTask` is cancelled cooperatively and
    /// reports `.cancelled`; a `.process` dies by `killpg(SIGKILL)`, which is
    /// authoritative, and reports `.stopped`. The canceler below carries that
    /// half of the contract, and this property carries the declaration of it.
    var detachmentRunKind: RunKind { .process }

    /// The canceler the engine parks beside the run body: the one that kills
    /// the process group of the child and reports `.stopped`.
    ///
    /// It is `ShellRunner.canceler(completionToken:)` and nothing else. That
    /// closure was written as this canceler — its own doc comment says it is
    /// "the closure that `SessionMailbox.park(kind:)` takes beside the run
    /// body" — and it holds no pid of its own, reading the process group out of
    /// the store at the moment it runs. A second copy of that reading here
    /// could signal a group the store already gave up.
    ///
    /// The runner is built over this verb's own store rather than reusing the
    /// configured one, because the canceler reads the store and touches nothing
    /// else of the runner: no sandbox, no registry and no output stream reach
    /// it.
    ///
    /// - Parameter completionToken: The completion token of the run to stop.
    /// - Returns: The canceler of that run.
    func detachmentCanceler(
        forCompletionToken completionToken: String
    ) -> (@Sendable () async -> OperationOutcome)? {
        ShellRunner(state: runner.state).canceler(completionToken: completionToken)
    }

    /// The `next` sentence the pending envelope of a backgrounded command hands
    /// the model.
    ///
    /// It names the two planes a backgrounded run answers on, because they
    /// answer different questions: the `wait` tool says when the run ended, and
    /// `tools.shell.getLines` says what it wrote up to now. A sentence that
    /// named one alone would leave the model either blocked on a run it only
    /// wanted to peek at, or reading output with no way to learn it was final.
    ///
    /// - Parameter completionToken: The backgrounded run's token.
    /// - Returns: The collect directive, as plain prose.
    func detachmentCollectInstruction(forCompletionToken completionToken: String) -> String {
        "The command is running in the background. Do not answer yet, and do not guess what it "
            + "wrote. Call the wait tool with completionToken \"\(completionToken)\" to collect "
            + "its result. To read what it has written so far without waiting for it, call "
            + "tools.shell.getLines with commandID \"\(completionToken)\"."
    }
}

// MARK: - Running one command

extension Execute {

    /// How many trailing stored lines the answer echoes back, so that the
    /// ordinary "run a command, read its tail" case takes one round trip. The
    /// whole output stays in the store, where `tools.shell.getLines` reads it.
    private static let tailLineCount = 32

    /// How many seconds a call blocks before the command goes to the
    /// background, when the call did not ask to skip the wait.
    ///
    /// Long enough that an ordinary command still answers inline in the same
    /// call, short enough that a runaway command still hands the model a
    /// completion token inside one turn instead of holding it.
    private static let blockSeconds: TimeInterval = 30

    /// The block window a `wait: false` call reports: detach immediately.
    ///
    /// Named rather than written as a bare `0` at the one site that answers it,
    /// because the value is the whole rule — see ``detachmentClocks(from:)``.
    private static let detachImmediatelySeconds: TimeInterval = 0

    /// The exit code of a command that ended with success.
    private static let successExitCode = 0

    /// Runs one command and answers with its tail, or starts one and answers
    /// with its identifier.
    ///
    /// **The ambient context is read one time, at the start.** eventplan.md
    /// § "The ambient context" makes that rule mandatory: a detached task
    /// inherits no task local, so a verb that read `ToolContext.current` again
    /// after an `await` would find `nil` exactly on the path this verb exists
    /// to serve. The value captured here is what every later post and every
    /// later identifier comes from.
    ///
    /// **A call with no session runs nothing.** The verb mints no identifier,
    /// so with no ambient context there is no `commandID` for the store, no
    /// `correlationID` for the events and no token for the run plane. That is
    /// answered in band, like every other request this verb cannot make.
    ///
    /// - Parameter arguments: What to run, and how.
    /// - Returns: The rendered report: the run's identifier, its status and the
    ///   tail of its output; or the correction that says why nothing ran.
    /// - Throws: What `ShellRunner.run(_:)` throws for a child that never
    ///   started, and what the pipeline of the output throws in the middle of a
    ///   run. A request this verb refuses does not reach it.
    func call(arguments: ExecuteArguments) async throws -> String {
        guard let context = ToolContext.current else {
            return Self.corrected(Self.noSessionCorrection)
        }
        let commandID = context.completionToken

        if arguments.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.corrected(Self.blankCommandCorrection)
        }

        let environment: [String: String]
        switch Self.parsedEnvironment(arguments.environment) {
        case .parsed(let parsed):
            environment = parsed
        case .invalid(let message):
            return Self.corrected(message)
        }

        let request = ShellRunner.Request(
            command: arguments.command,
            completionToken: commandID,
            workingDirectory: arguments.workingDirectory,
            environment: environment,
            timeout: arguments.timeout.map { .seconds($0) }
        )

        if let refusal = await confinementRefusal(for: request) {
            return Self.corrected(refusal)
        }

        return try await report(of: request, in: context)
    }

    /// Why the sandbox cannot confine this request, or `nil` when it can — and
    /// `nil` as well when this verb carries no sandbox at all.
    ///
    /// This stands before the run for the reason `CommandSandbox.preflight`
    /// states: a confinement failure raised inside `ShellRunner.run` travels
    /// out through the body of the run, and each layer above it erases the
    /// error to a string, so by the time a `catch` here could read it the
    /// diagnosis is gone. Asking first is what keeps it typed long enough to
    /// become text the model acts on.
    ///
    /// Only `SeatbeltSandboxError` is rendered. A `preflight` that throws
    /// anything else is choosing its own error type, and that value travels on
    /// and stops the turn, exactly as a throw at spawn time does. To fold every
    /// error into corrective text here would turn a cancel and a programmer
    /// mistake into advice to try something else, which hides a defect behind a
    /// suggestion.
    ///
    /// - Parameter request: The command whose confinement to examine.
    /// - Returns: The correction, or `nil` to run the command.
    private func confinementRefusal(for request: ShellRunner.Request) async -> String? {
        guard let sandbox = runner.sandbox else { return nil }
        // The runner's own resolution, reused rather than spelled again, thus
        // the directories examined here are the ones it confines.
        let directories = ShellRunner.resolvedSandboxDirectories(request: request)
        do {
            try await sandbox.preflight(
                workingDirectory: directories.work, temporaryDirectory: directories.tmp)
            return nil
        } catch let error as SeatbeltSandboxError {
            return Self.correction(for: error)
        } catch {
            return nil
        }
    }

    /// Runs `request` to its end, reporting output as it arrives, and answers
    /// with the report of the run.
    ///
    /// The live view of the output is the reason this verb has progress to
    /// post at all: `ShellRunner` tees each raw chunk into the stream it is
    /// given, before the line buffer sees it, and one task here drains that
    /// stream and posts what it reads. The stream is ended after the run rather
    /// than by the drain, so the drain cannot outlive the run and a run with no
    /// output still ends its own pump.
    ///
    /// - Parameters:
    ///   - request: The command to run.
    ///   - context: The session context captured at the start of the call.
    /// - Returns: The rendered report of the run.
    /// - Throws: What `ShellRunner.run(_:)` throws.
    private func report(
        of request: ShellRunner.Request, in context: ToolContext
    ) async throws -> String {
        let stream = ShellOutputChunkStream()
        var running = runner
        running.outputChunkStream = stream
        let pump = Task { await Self.reportOutput(of: stream, to: context) }

        do {
            _ = try await running.run(request)
        } catch {
            stream.finish()
            await pump.value
            throw error
        }
        stream.finish()
        await pump.value

        let fields = await Self.reportFields(of: request.completionToken, in: runner.state)
        let rendered = Self.rendered(.object(fields))
        await Self.postTerminal(
            rendered, of: request.completionToken, in: runner.state, to: context)
        return rendered
    }

    /// Drains the live view of one run and posts each chunk of output as a
    /// `progress` event.
    ///
    /// The bytes are decoded here and nowhere else. The stream carries them
    /// exactly as the child wrote them, and an event carries text, so the
    /// decode belongs at this boundary. A chunk that decodes to nothing but
    /// whitespace is passed over: it says the child wrote a line ending, which
    /// is not news.
    ///
    /// A gap says the consumer fell behind the budget of the stream, and it is
    /// reported rather than passed over, because output that went away is
    /// exactly what a reader must not mistake for output that never came.
    ///
    /// - Parameters:
    ///   - stream: The live view of the output of the run.
    ///   - context: The session context captured at the start of the call.
    private static func reportOutput(
        of stream: ShellOutputChunkStream, to context: ToolContext
    ) async {
        for await event in stream {
            switch event.kind {
            case .output(let source, let bytes):
                let text = String(decoding: bytes, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                await context.progress("\(name(of: source)): \(text)")
            case .gap(let source, let droppedByteCount):
                await context.progress(
                    "\(name(of: source)): \(droppedByteCount) bytes of output went away")
            case .completed:
                continue
            }
        }
    }

    /// What one output stream of a child is called in a `progress` event.
    ///
    /// - Parameter source: The stream a chunk came from.
    /// - Returns: The name the event carries.
    private static func name(of source: ShellOutputStream) -> String {
        switch source {
        case .stdout: return "stdout"
        case .stderr: return "stderr"
        }
    }

    /// Posts the one terminal event of a run.
    ///
    /// eventplan.md § "Consolidation of the siblings": "The `detail` of each
    /// terminal event carries the output tail plus the run's identifier. As a
    /// result, the model always knows how to get more." The detail is therefore
    /// the same report the call answers with, and not a second rendering of it.
    ///
    /// Exactly one terminal event reaches a session however this run ended. A
    /// mounted call posts through `RunEventFunnel`, which settles the run on
    /// the first `.completed` it carries and drops every later one, so the
    /// event the engine would otherwise synthesize is dropped rather than
    /// added. An unmounted call has this event and no other.
    ///
    /// - Parameters:
    ///   - detail: The rendered report of the run.
    ///   - completionToken: The completion token of the run.
    ///   - state: The store the run recorded into.
    ///   - context: The session context captured at the start of the call.
    private static func postTerminal(
        _ detail: String, of completionToken: String, in state: ShellState, to context: ToolContext
    ) async {
        await context.post(
            OperationEvent(
                tool: context.tool,
                op: context.op,
                correlationID: completionToken,
                kind: .completed,
                detail: detail,
                outcome: await outcome(of: completionToken, in: state)
            )
        )
    }

    /// The honest outcome of the run under `completionToken`, read from the
    /// finalized record of the store.
    ///
    /// The store is the authority and the runner is not: a cancel that ran
    /// while the body was still going wrote `.killed` into the record, and
    /// `completeIfRunning` kept it there, so the record is what reports that
    /// cancel faithfully.
    ///
    /// A `.killed` record is `.stopped` and never `.cancelled`, because a
    /// process group that took `killpg(SIGKILL)` is certainly dead — the
    /// authority distinction `OperationOutcome` makes mandatory. A record that
    /// still reads `.running` after the body finalized it, and a record that is
    /// not there at all, are each `.lost`: the outcome is not knowable, and no
    /// other word says so.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the run.
    ///   - state: The store the run recorded into.
    /// - Returns: The outcome the terminal event carries.
    private static func outcome(
        of completionToken: String, in state: ShellState
    ) async -> OperationOutcome {
        guard let record = await state.record(commandID: completionToken) else { return .lost }
        switch record.status {
        case .completed:
            return record.exitCode == successExitCode ? .succeeded : .failed
        case .timedOut:
            return .timedOut
        case .killed:
            return .stopped
        case .running:
            return .lost
        }
    }
}

// MARK: - The shape of one answer

extension Execute {

    /// The fields of the report of one run: its identifier, how it ended, and
    /// the tail of what it wrote.
    ///
    /// The tail is read back out of the store rather than kept from the run,
    /// because the store is the one place the output of a run lives and
    /// `tools.shell.getLines` reads it from there too. Thus the tail this verb
    /// answers and the lines that verb answers can never disagree.
    ///
    /// `exitCode` is absent while a run has none to report, and `outputNote` is
    /// absent unless the stored output ran past the tail. An absent field is
    /// left out of the object rather than written as null, which is what makes
    /// the rendered JSON read the way the sibling verbs' results read.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the run.
    ///   - state: The store the run recorded into.
    /// - Returns: The fields of the report.
    static func reportFields(
        of completionToken: String, in state: ShellState
    ) async -> [String: InterpreterValue] {
        let record = await state.record(commandID: completionToken)
        let stored = (try? await state.getLines(commandID: completionToken)) ?? []
        let tail = stored.suffix(tailLineCount).map { "\($0.lineNumber): \($0.text)" }

        var fields: [String: InterpreterValue] = [
            "commandID": .string(completionToken),
            "status": .string((record?.status ?? .running).rawValue),
            "lines": .number(Double(stored.count)),
            "durationMs": .number(Double(record?.durationMs ?? 0)),
            "output": .array(tail.map { .string($0) }),
        ]
        if let exitCode = record?.exitCode {
            fields["exitCode"] = .number(Double(exitCode))
        }
        if stored.count > tailLineCount {
            fields["outputNote"] = .string(tailNote(shown: tailLineCount, of: stored.count))
        }
        return fields
    }

    /// What the answer says when it carries the tail of a longer output.
    ///
    /// - Parameters:
    ///   - shown: How many lines the answer carries.
    ///   - total: How many lines the store holds.
    /// - Returns: The note.
    private static func tailNote(shown: Int, of total: Int) -> String {
        "Showing the last \(shown) of \(total) lines. Call tools.shell.getLines with this "
            + "commandID to read the rest."
    }

    /// The empty answer one correction stands in place of.
    ///
    /// - Parameter message: Why nothing ran.
    /// - Returns: The rendered corrective answer.
    private static func corrected(_ message: String) -> String {
        rendered(.object(["correction": .string(message)]))
    }

    /// Renders one answer the way every other output of this package is
    /// rendered.
    ///
    /// Through `ResultRenderer` rather than an encode of its own, so an
    /// `execute` answer is capped and shaped exactly as a `runCode` return
    /// value and a `wait` report are, and the model reads one format for all
    /// three.
    ///
    /// - Parameter value: The answer to render.
    /// - Returns: The verb's output text.
    private static func rendered(_ value: InterpreterValue) -> String {
        ResultRenderer.render(InterpreterResult(returnValue: value, consoleLines: []))
    }
}

// MARK: - The requests this verb refuses

extension Execute {

    /// What a call outside any session says to the model.
    static let noSessionCorrection =
        "This call has no session, so the run has no identifier to record under and nothing was "
        + "run. Call it from a snippet, where the session gives each run its completion token."

    /// What a command of only whitespace says to the model.
    static let blankCommandCorrection =
        "The command is empty, thus there is nothing to run. Give the command line to run."

    /// The parsed extra environment, or the correction that says why the text
    /// is not one.
    ///
    /// Absent text and empty text each mean no extra environment, and neither
    /// is a mistake. Text that is not a JSON object of string values is one,
    /// and the message names the value that is not a string, because a map of
    /// many entries with one bad value is otherwise a search.
    ///
    /// - Parameter text: The `environment` argument of the call.
    /// - Returns: The parsed map, or the correction.
    static func parsedEnvironment(_ text: String?) -> EnvironmentParse {
        guard let text, !text.isEmpty else { return .parsed([:]) }
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let entries = object as? [String: Any]
        else {
            return .invalid(
                "environment is not a JSON object: it must map string keys to string values, for "
                    + "example '{\"KEY\":\"value\"}'. Nothing was run.")
        }

        var environment: [String: String] = [:]
        for (key, value) in entries {
            guard let value = value as? String else {
                return .invalid(
                    "The environment value for \(key) is not a string. Every value of the JSON "
                        + "object must be a string. Nothing was run.")
            }
            environment[key] = value
        }
        return .parsed(environment)
    }

    /// The outcome of reading the `environment` argument: the parsed map, or
    /// the correction that says why the text is not a JSON object of strings.
    enum EnvironmentParse: Sendable, Equatable {

        /// The extra environment the call asked for.
        case parsed([String: String])

        /// Why the text is not a JSON object of string values.
        case invalid(String)
    }

    /// What a sandbox that cannot confine this command says to the model.
    ///
    /// Total over `SeatbeltSandboxError` and answering a non-optional `String`,
    /// because every case of that error means the command must not run: there
    /// is no "proceed" answer to state.
    ///
    /// Each message names the diagnosis and then says the command was not run.
    /// The second half is not decoration. The model is deciding what to do
    /// next, and the difference between "your command failed" and "your command
    /// never happened" is the difference between it running the command again
    /// and it working around a side effect that does not exist.
    ///
    /// A bare exit code is never the whole message. `sandbox-exec` exits 65 for
    /// a profile it refuses, and a command may exit 65 for its own reasons, so
    /// the number alone would be a riddle. The stderr of the wrapper travels
    /// with it, because that one line separates a profile that is malformed
    /// from a grant that is missing, and whoever fixes the configuration of the
    /// host needs it.
    ///
    /// - Parameter error: The confinement failure the sandbox diagnosed.
    /// - Returns: The correction.
    static func correction(for error: SeatbeltSandboxError) -> String {
        switch error {
        case .sandboxExecMissing:
            return "The sandbox is not available: /usr/bin/sandbox-exec is not there. The command "
                + "was NOT run."
        case .profileRejected(let exitCode, let stderr):
            return "The sandbox refused its profile (exit \(exitCode)): \(stderr). The command was "
                + "NOT run."
        case .workingDirectoryOutsideRoots(let path, let roots):
            return "The sandbox refused the working directory '\(path)': it stands outside the "
                + "configured roots \(roots). The command was NOT run."
        }
    }
}

/// Runs one shell command, and answers with the tail of its output.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const run = await tools.shell.execute({ command: "swift build" });
/// ```
///
/// The store it records into is the store the capability owns, thus each verb
/// of one capability answers for the same session.
struct Execute: Tool {

    /// The verb this tool renders as, which the shell noun stands in front of:
    /// `tools.shell.execute`.
    let name = "execute"

    /// The usage instructions, as the model reads them.
    let description = """
        execute runs one shell command and answers with the tail of its output, its status and its \
        exit code. commandID in the answer is the run's completion token: pass it to \
        tools.shell.getLines to read the whole output, and to tools.shell.grepHistory to search \
        it. Give timeout to bound the command, workingDirectory to run it somewhere else, and \
        environment as a JSON object of string values to add variables. Pass wait false to start a \
        long command in the background and get its completion token back at once, then collect it \
        with the wait tool. A command that is empty, an environment that is not a JSON object of \
        strings, and a command the sandbox cannot confine each come back as a correction rather \
        than as an error — read it, correct the call, and ask again.
        """

    /// The runner this verb spawns each command through, which holds the store,
    /// the process-group registry and the confinement of the capability.
    let runner: ShellRunner

    /// Makes the verb over one runner.
    ///
    /// The runner is the whole of what this verb is configured with, and that
    /// is why it takes one rather than a bare store: the confinement, the
    /// process-group registry and the live view of the output all stand on it.
    /// A host gives the capability its sandbox this way, and a test gives it a
    /// runner whose process registry is private the same way.
    ///
    /// - Parameter runner: The runner each command of this verb spawns through.
    init(runner: ShellRunner) {
        self.runner = runner
    }
}
