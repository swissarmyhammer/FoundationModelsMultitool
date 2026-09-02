// `Execute` — the `tools.shell.execute` verb.
//
// A behavioral port of `../FoundationModelsShelltool/Sources/ShellTool/
// Operations/ExecuteCommand.swift`. The sibling is an `@Operation` that takes a
// `ShellContext`, races a deadline of its own and supervises its own backgrounding;
// this package has none of those, thus the verb is a plain
// `FoundationModels.Tool` and the shared background engine of Router owns the
// tracking, the work bound and the cancel.
//
// eventplan.md § "Consolidation of the siblings": "consolidation is promotion,
// not construction", and "Background supervision moves to the shared engine". So
// this file holds the shape of one request and the shape of one answer, and it
// holds no supervisor.
//
// **This verb is the RUN plane. Its two siblings are the content plane.**
// `tools.shell.getLines` and `tools.shell.grepHistory` read what a run wrote;
// this verb starts one. The join between the two planes is one string:
// eventplan.md states that "the `commandID` of a shell run is its
// `correlationID` is its `completionToken` — one string, two planes." Mounted
// under Router, this verb reads that string out of the ambient `ToolContext` at
// the start of the call, thus a run is reachable under the same identifier from
// the store, from the event stream and from the run plane. On a bare
// `LanguageModelSession` there is no context, so the verb mints the string
// itself: the store records the run under it, and no run-plane entry exists.
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
// **The background is a declaration of the verb, and never a choice of the
// call.** A command can run for hours, so the verb declares the background
// mount through `BackgroundTool`, and every mounted call answers
// the pending envelope at once. There is no argument that selects a block
// window, because there is no block window. The verb never tracks a run
// itself — `SessionMailbox.track` is internal to Router and no code here names
// it. It DECLARES what kind of run this is and how to stop one, and the engine
// tracks it on those terms. See the extension below.
//
// **The answer is `String`, and its two siblings answer a `@Generable` value.**
// That is the Router's rule rather than a preference:
// `ToolMounting.makeWrapped` gives `BackgroundToolRunner` to a `String`-output tool
// that declares the background, and `ContextBindingTool` — which never reaches
// the run plane — to every tool with another output. A verb that must reach the
// run plane therefore has one available output type. The answer is rendered
// through `ResultRenderer`, exactly as `runCode` and `wait` render theirs, thus
// the model reads one format for all of them.
//
// A request the verb cannot make stays IN BAND, as a `correction`. It is never
// thrown: a blank command, a command over the length cap, an environment that
// is not a JSON object of strings, an environment value the verb refuses, and a
// confinement the sandbox refuses are each a mistake the model corrects inside
// the turn, and a thrown error would end the turn instead.
//
// **The cap on the length of a command and the cap on the length of an
// environment value stand HERE.** `ShellRunner.run(_:)` states that they belong
// to this verb and that the runner takes input this verb already examined. Each
// is measured in UTF-8 BYTES rather than in characters, because what the caps
// stand in front of is `E2BIG` from `posix_spawn`, and the kernel counts the
// bytes of the argv and envp block. UTF-8 text runs up to four times longer in
// bytes than in grapheme clusters, so a count of characters would let a command
// through that the spawn then refuses.

import Foundation
import FoundationModels
import FoundationModelsRouter

/// The arguments of `tools.shell.execute`: what to run, where, under what
/// environment, and for how long.
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

    /// The directory the command runs in, or `nil` for the default working
    /// directory of the runner — the session root a host gave the capability —
    /// and, when the runner has no default, the current directory of this
    /// process.
    ///
    /// The `@Guide` text below names the session and not the process on
    /// purpose. The model cannot see the directory of the host process, and a
    /// sandbox rooted at the session refuses a run there — UPSTREAM_ASKS.md
    /// Ask 6.
    @Guide(
        description:
            "The directory the command runs in. Omit it to run in the session's working "
            + "directory.")
    var workingDirectory: String?

    /// The extra environment variables as JSON text, or `nil` for none.
    @Guide(
        description:
            "Extra environment variables, as a JSON object of string values — for example "
            + "'{\"KEY\":\"value\"}'. They stand on top of the environment this process holds. "
            + "Omit it to add none.")
    var environment: String?
}

// MARK: - What kind of run this is, and how to stop one

extension Execute: BackgroundTool {

    /// The mount every `execute` call carries, which stands over the mount of
    /// whatever composed this verb: the background.
    ///
    /// **A declared mount is the only way a call of this verb reaches the
    /// background.** `ToolMounting.makeWrapped` picks `BackgroundToolRunner` on the
    /// mount's mode alone, and `RunBinding.innerCallMount` — the mount every
    /// inner `tools.*` call travels under — is `.runToCompletion`. Router
    /// states that a declared mount wins over the composition site, and this
    /// is that declaration: every mounted call answers the pending envelope at
    /// once, and the command goes on behind it.
    ///
    /// The work clock is deliberately absent. A shell run already carries its
    /// own hard limit — the `timeout` argument, which `ShellRunner` arms as a
    /// timer that kills the process group — so a second work clock in the
    /// engine would be a second authority over the same question, firing on
    /// its own schedule.
    var mount: ToolMount? {
        ToolMount(mode: .background, timeout: nil)
    }

    /// What kind of work a background `execute` call is: an OS process group.
    ///
    /// eventplan.md § "Processes and tasks stay different kinds" keeps this
    /// distinction mandatory. A `.swiftTask` is cancelled cooperatively and
    /// reports `.cancelled`; a `.process` dies by `killpg(SIGKILL)`, which is
    /// authoritative, and reports `.stopped`. The canceler below carries that
    /// half of the contract, and this property carries the declaration of it.
    var runKind: RunKind { .process }

    /// The canceler the engine tracks beside the run body: the one that kills
    /// the process group of the child and reports `.stopped`.
    ///
    /// It is `ShellRunner.canceler(completionToken:)` and nothing else. That
    /// closure was written as this canceler — its own doc comment says it is
    /// "the closure that `SessionMailbox.track(kind:)` takes beside the run
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
    func canceler(
        forCompletionToken completionToken: String
    ) -> (@Sendable () async -> OperationOutcome)? {
        ShellRunner(state: runner.state).canceler(completionToken: completionToken)
    }

    /// The `next` sentence the pending envelope of a background command hands
    /// the model.
    ///
    /// It names the two planes a background run answers on, because they
    /// answer different questions: the `wait` tool says when the run ended, and
    /// `tools.shell.getLines` says what it wrote up to now. A sentence that
    /// named one alone would leave the model either blocked on a run it only
    /// wanted to peek at, or reading output with no way to learn it was final.
    ///
    /// - Parameter completionToken: The background run's token.
    /// - Returns: The collect directive, as plain prose.
    func collectInstruction(forCompletionToken completionToken: String) -> String {
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

    /// The exit code of a command that ended with success.
    private static let successExitCode = 0

    /// Runs one command and answers with the report of the run. Mounted, the
    /// engine hands the model the pending envelope at once and delivers this
    /// report as the terminal detail when the command ends.
    ///
    /// **The ambient context is read one time, at the start.** eventplan.md
    /// § "The ambient context" makes that rule mandatory: work that inherits
    /// no task local sees none, so a verb that read `ToolContext.current` again
    /// after an `await` would find `nil` exactly on the path this verb exists
    /// to serve. The value captured here is what every later post and every
    /// later identifier comes from.
    ///
    /// **There are two paths, and the ambient context decides between them.**
    /// Mounted under Router, the engine parks the run, the model gets the
    /// pending envelope at once, and the `commandID` is the completion token
    /// the context carries. On a bare `LanguageModelSession` there is no
    /// context: the verb mints the `commandID` itself, runs the command to
    /// completion and returns the report — the same text the terminal detail
    /// carries when mounted. Every post through the absent context is a no-op.
    ///
    /// - Parameter arguments: What to run, and how.
    /// - Returns: The rendered report: the run's identifier, its status and the
    ///   tail of its output; or the correction that says why nothing ran.
    /// - Throws: What `ShellRunner.run(_:)` throws for a child that never
    ///   started, and what the pipeline of the output throws in the middle of a
    ///   run. A request this verb refuses does not reach it.
    func call(arguments: ExecuteArguments) async throws -> String {
        let context = ToolContext.current
        let commandID = context?.completionToken ?? ToolContext.makeCompletionToken()

        if arguments.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.corrected(Self.blankCommandCorrection)
        }

        let commandByteCount = arguments.command.utf8.count
        if commandByteCount > Self.maximumCommandLengthBytes {
            return Self.corrected(Self.commandTooLongCorrection(measuring: commandByteCount))
        }

        let environment: [String: String]
        switch Self.parsedEnvironment(arguments.environment) {
        case .parsed(let parsed):
            environment = parsed
        case .invalid(let message):
            return Self.corrected(message)
        }

        if let refusal = Self.environmentRefusal(in: environment) {
            return Self.corrected(refusal)
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
        // the directories examined here are the ones it confines — the default
        // of the runner included, for a request that names no directory.
        let directories = ShellRunner.resolvedSandboxDirectories(
            request: request, defaultWorkingDirectory: runner.defaultWorkingDirectory)
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
    /// post at all: `ShellRunner` tees each raw chunk into the streams it is
    /// given, before the line buffer sees it, and one task here drains the
    /// stream this call made and posts what it reads. The stream is ended after
    /// the run rather than by the drain, so the drain cannot outlive the run and
    /// a run with no output still ends its own pump.
    ///
    /// The stream goes into `ShellRunner.callerOutputChunkStream`, which stands
    /// BESIDE the stream a host configured, and never in place of it. Two
    /// reasons make this verb's stream its own rather than the host's. A
    /// `ShellOutputChunkStream` hands each event to ONE consumer, so a drain of
    /// the host's stream would take the host's chunks away from it. And this
    /// drain ends with `finish()`, which ends a stream for good — the host
    /// keeps its stream across every run of the capability, so this call has no
    /// business ending it.
    ///
    /// - Parameters:
    ///   - request: The command to run.
    ///   - context: The session context captured at the start of the call, or
    ///     `nil` on a bare session, where every post is a no-op.
    /// - Returns: The rendered report of the run.
    /// - Throws: What `ShellRunner.run(_:)` throws.
    private func report(
        of request: ShellRunner.Request, in context: ToolContext?
    ) async throws -> String {
        let stream = ShellOutputChunkStream()
        var running = runner
        running.callerOutputChunkStream = stream
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
    ///   - context: The session context captured at the start of the call, or
    ///     `nil` on a bare session, where the stream is drained and no event
    ///     is posted.
    private static func reportOutput(
        of stream: ShellOutputChunkStream, to context: ToolContext?
    ) async {
        for await event in stream {
            switch event.kind {
            case .output(let source, let bytes):
                let text = String(decoding: bytes, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                await context?.progress("\(name(of: source)): \(text)")
            case .gap(let source, let droppedByteCount):
                await context?.progress(
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
    /// added. An unmounted call under a bound context has this event and no
    /// other. A call on a bare session has no context and posts nothing.
    ///
    /// - Parameters:
    ///   - detail: The rendered report of the run.
    ///   - completionToken: The completion token of the run.
    ///   - state: The store the run recorded into.
    ///   - context: The session context captured at the start of the call, or
    ///     `nil` on a bare session.
    private static func postTerminal(
        _ detail: String, of completionToken: String, in state: ShellState, to context: ToolContext?
    ) async {
        guard let context else { return }
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

    /// What a command of only whitespace says to the model.
    static let blankCommandCorrection =
        "The command is empty, thus there is nothing to run. Give the command line to run."

    /// The longest command line this verb passes on, in UTF-8 BYTES: 256 KiB.
    ///
    /// The number is the one the sibling shell tool's settings defaults state
    /// for the length of a command. The MEASURE is not: the sibling counted
    /// grapheme clusters, and this verb counts bytes, because the cap stands
    /// in front of `E2BIG` from `posix_spawn` and the kernel counts the bytes
    /// of the argv block. One emoji is one cluster and four bytes, so a count
    /// of characters passes a command four times over the real limit.
    static let maximumCommandLengthBytes = 262_144

    /// The longest environment value this verb passes on, in UTF-8 BYTES.
    ///
    /// The number the sibling states, measured the same way and for the same
    /// reason as ``maximumCommandLengthBytes``: `envp` shares the block the
    /// kernel caps.
    static let maximumEnvironmentValueLengthBytes = 1024

    /// The byte a null is. No environment value may hold one.
    private static let nullByte = UInt8(ascii: "\0")

    /// The byte a line feed is. No environment value may hold one.
    private static let lineFeedByte = UInt8(ascii: "\n")

    /// The byte a carriage return is. No environment value may hold one.
    private static let carriageReturnByte = UInt8(ascii: "\r")

    /// What a command over ``maximumCommandLengthBytes`` says to the model.
    ///
    /// The message names the check, the cap and the measured length, because
    /// a model that reads "too long" alone cannot tell how much to cut.
    ///
    /// - Parameter byteCount: How many UTF-8 bytes the command measures.
    /// - Returns: The correction.
    static func commandTooLongCorrection(measuring byteCount: Int) -> String {
        "The command is \(byteCount) UTF-8 bytes, over the limit of \(maximumCommandLengthBytes) "
            + "bytes on the length of one command. Nothing was run. Write the long part to a file "
            + "and run that file instead."
    }

    /// The correction that names the one environment value this verb refuses,
    /// or `nil` when every value can go to the child.
    ///
    /// The entries are read in the order of their names, thus a map holding
    /// more than one bad value names the same one on every call. A dictionary
    /// carries no order of its own, and a message that moved from call to call
    /// would make one mistake read as several.
    ///
    /// - Parameter environment: The extra environment the call asked for.
    /// - Returns: The correction, or `nil` to run the command.
    static func environmentRefusal(in environment: [String: String]) -> String? {
        for name in environment.keys.sorted() {
            guard let value = environment[name],
                let defect = EnvironmentValueDefect.allCases.first(where: { $0.stands(in: value) })
            else { continue }
            return defect.correction(forValueNamed: name, measuring: value.utf8.count)
        }
        return nil
    }

    /// One way an environment value cannot go to a child process.
    ///
    /// The three checks the sibling's policy made on a value, ported whole and
    /// kept as data rather than as a chain of `if` statements: they differ in
    /// what they look for and in what the message calls them, and in nothing
    /// else. ``allCases`` is read in declaration order, which is the order the
    /// sibling examined them in.
    ///
    /// The null case and the line-break case are the injection-relevant two,
    /// and neither is decoration. `execve` takes each entry as one
    /// NUL-terminated C string, so a null inside a value silently truncates it
    /// and everything after the null goes away. A carriage return or a line
    /// feed inside a value ends the line of every reader that takes the
    /// environment back as text, so one value can write what reads as a second
    /// variable.
    enum EnvironmentValueDefect: Sendable, Equatable, CaseIterable {

        /// The value runs past ``Execute/maximumEnvironmentValueLengthBytes``.
        case overLength

        /// The value holds a null byte.
        case embeddedNull

        /// The value holds a carriage return or a line feed.
        case embeddedLineBreak

        /// Whether `value` carries this defect.
        ///
        /// Each test reads the UTF-8 bytes and never the characters. The
        /// length is a byte count for the reason the cap states, and the line
        /// break is a byte test because Swift reads a CR LF PAIR as ONE
        /// grapheme cluster, which equals neither `"\r"` nor `"\n"` — a search
        /// for either Character therefore passes a value holding that pair,
        /// which is exactly the value this check exists to stop.
        ///
        /// - Parameter value: The environment value to examine.
        /// - Returns: `true` when the value carries this defect.
        func stands(in value: String) -> Bool {
            switch self {
            case .overLength:
                return value.utf8.count > Execute.maximumEnvironmentValueLengthBytes
            case .embeddedNull:
                return value.utf8.contains(Execute.nullByte)
            case .embeddedLineBreak:
                return value.utf8.contains(Execute.lineFeedByte)
                    || value.utf8.contains(Execute.carriageReturnByte)
            }
        }

        /// What this defect says to the model.
        ///
        /// One shape for all three cases, thus each message names the check
        /// that failed, the cap, and the measured length in bytes, and the
        /// model reads one sentence pattern however the value went wrong.
        ///
        /// - Parameters:
        ///   - name: The name of the environment variable.
        ///   - byteCount: How many UTF-8 bytes its value measures.
        /// - Returns: The correction.
        func correction(forValueNamed name: String, measuring byteCount: Int) -> String {
            "The environment value for \(name) \(summary). A value must hold no null byte, no "
                + "carriage return and no line feed, and must be within "
                + "\(Execute.maximumEnvironmentValueLengthBytes) UTF-8 bytes; this one measures "
                + "\(byteCount) bytes. Nothing was run."
        }

        /// What the correction calls this defect.
        private var summary: String {
            switch self {
            case .overLength: return "is over the cap on the length of an environment value"
            case .embeddedNull: return "holds a null byte"
            case .embeddedLineBreak: return "holds a carriage return or a line feed"
            }
        }
    }

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

/// Runs one shell command in the background, and reports the tail of its
/// output when it ends.
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
        execute starts one shell command in the background and answers at once with its \
        completion token. When the command ends, its report carries the tail of its output, its \
        status and its exit code; collect it with the wait tool. commandID in the report is the \
        run's completion token: pass it to tools.shell.getLines to read the whole output so far, \
        and to tools.shell.grepHistory to search it. Give timeout to bound the command, \
        workingDirectory to run it somewhere else, and environment as a JSON object of string \
        values to add variables. A command that is empty or longer than 262144 UTF-8 bytes, an \
        environment that is not a JSON object of strings, an environment value longer than 1024 \
        UTF-8 bytes or holding a null byte, a carriage return or a line feed, and a command the \
        sandbox cannot confine each come back as a correction rather than as an error — read it, \
        correct the call, and ask again.
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
