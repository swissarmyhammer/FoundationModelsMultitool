import Foundation
import FoundationModelsMultitool
import FoundationModelsRouter

// MARK: - Errors

/// Why the demo has no answer to print.
///
/// `CLIRunner.run(arguments:resolve:output:errorOutput:)` writes the
/// description to standard error and returns `CLIRunner.ExitCode.answerFailed`.
enum CLIAnswerError: Error, Equatable, CustomStringConvertible {
    /// The chain of submissions that answers the message ended with no
    /// answer: the session sent `SessionEvent.answerFailed`.
    case failed(AnswerFailure)

    /// The event stream of the message ended before the end of its answer.
    case missing

    /// The one error line the CLI writes for this error.
    var description: String {
        switch self {
        case .failed(let failure):
            "\(cliErrorPrefix) the model gave no answer: \(Self.text(of: failure.reason))"
        case .missing:
            "\(cliErrorPrefix) the event stream ended before the end of the answer"
        }
    }

    /// The text of the reason why a chain gave no answer.
    ///
    /// - Parameter reason: the reason that `AnswerFailure` carries.
    /// - Returns: the text for the error line.
    private static func text(of reason: AnswerFailure.Reason) -> String {
        switch reason {
        case .cancelled:
            "a cancel stopped the answer"
        case .error(let description):
            description
        }
    }
}

// MARK: - The bounds of the wait for mail

/// The bounds of the wait for the answers that mail starts.
///
/// A settled background run comes back to the session as mail, and the mail
/// starts a new answer with no caller message. The CLI waits for these
/// answers before it exits, and these two bounds stop the wait.
struct CLIMailWait: Sendable {
    /// How long the demo session must stay idle before the CLI stops.
    ///
    /// The session starts the answer of a mail immediately after the running
    /// answer ends, so one second of no events is sufficient.
    static let defaultQuietPeriod: Duration = .seconds(1)

    /// The bounds of the demo: the default quiet period, and the time limit of
    /// one snippet, `MultiToolConfiguration.defaultExecutionTimeLimit`.
    static let demo = CLIMailWait(
        quietPeriod: defaultQuietPeriod,
        timeLimit: .seconds(MultiToolConfiguration.defaultExecutionTimeLimit))

    /// How long the session must stay idle, with no event, before the CLI
    /// stops.
    ///
    /// The quiet period is necessary because a background run can settle
    /// while an answer runs. Its mail then starts one more answer after the
    /// running answer ends, and no event before that start tells that it
    /// comes.
    let quietPeriod: Duration

    /// The longest time the CLI waits for mail answers. When the time limit
    /// ends first, the CLI cancels the work of the session.
    let timeLimit: Duration
}

// MARK: - The lines a person reads while an answer runs

/// Writes one line for each event that a person must see while an answer
/// runs: the tool calls, their progress, the reports of Router, and the
/// settled background runs.
///
/// The final text of an answer is not one of these lines. It comes whole in
/// `SessionEvent.answered`, and the drain writes it.
struct CLIEventReporter {
    /// What a reported line says in place of a detail the event did not carry.
    ///
    /// Router leaves `SessionEvent.toolStatus`' `summary` `nil` for a status it
    /// has no text for, and a line that ended at its own colon would read as
    /// truncated output rather than as a tool that said nothing.
    private static let missingDetail = "no detail"

    /// Where each reported line is written.
    private let output: @Sendable (String) -> Void

    /// The tool name of each call, by call id.
    ///
    /// A call's tool name arrives once, on its own `.toolCall`. Every later
    /// event about that call carries the call's id alone, so the name is kept
    /// here to report the call's progress under it.
    private var toolNamesByCallID: [String: String] = [:]

    /// Creates a reporter that writes to `output`.
    ///
    /// - Parameter output: where each reported line is written.
    init(output: @escaping @Sendable (String) -> Void) {
        self.output = output
    }

    /// Writes the line for `event`, when the event has one.
    ///
    /// - Parameter event: one event of the session.
    mutating func report(_ event: SessionEvent) {
        switch event {
        case .toolCall(let id, let name, _):
            toolNamesByCallID[id] = name
            output("Calling \(name)")
        case .toolStatus(let id, .running, let summary, _):
            output("\(toolName(of: id)) in process: \(summary ?? Self.missingDetail)")
        case .toolStatus(let id, .completed, _, _):
            output("\(toolName(of: id)) done")
        case .toolStatus(let id, .failed, let summary, _):
            output("\(toolName(of: id)) failed: \(summary ?? Self.missingDetail)")
        case .generationStalled(let stall):
            // Router reports a stall instead of imposing a timeout: no token
            // has moved for a while, which a long answer on a real model does.
            // Printed and never acted on — a demo that stayed silent here
            // reads as stuck while it is working.
            output("\(stall)")
        case .repetitionStopped(let stop):
            // Router stopped a generation call that wrote the same lines
            // again, and a recovery submission follows, or the answer ends.
            // Without the line, an answer that restarts reads as an answer
            // that lost its work.
            output("\(stop)")
        case .reasoningStopped(let stop):
            // Router stopped a pass that only reasoned past its reasoning
            // limit, and a recovery submission follows, or the answer ends.
            // The line tells why the answer restarts, for the reason the
            // repetition stop above gives.
            output("\(stop)")
        case .runSettled(let terminal):
            // The one terminal event that says how a background run ended.
            // Its mail can start one more answer.
            output(
                "\(terminal.tool) run \(terminal.correlationID) settled: "
                    + "\(terminal.outcome?.rawValue ?? Self.missingDetail)")
        case .mailDeliveryPaused(let pause):
            // The session holds mail and starts no answer for it, so no mail
            // answer comes. The line tells why.
            output("\(pause)")
        case .textDelta, .textReset:
            // The reply comes whole in `.answered`, and this CLI shows no live text.
            break
        case .answered, .answerFailed:
            // The drain reads the end of the answer, and it writes the reply or the error.
            break
        case .submissionQueued:
            // A wait for the model worker changes nothing that this demo prints.
            break
        case .submissionStarted:
            // The start of one SDK call; the answer, not the submission, is what this demo prints.
            break
        case .submissionEnded:
            // The usage of one SDK call; this demo prints no usage.
            break
        case .generationCall:
            // The usage of one generation call; this demo prints no usage.
            break
        case .toolStatus, .reasoningDelta, .toolInvocation, .toolCallReport, .entryRecorded, .compaction,
            .discoveryPrimingFailed, .elicitationRequested:
            // `.toolStatus` here is the residue of the three statuses handled
            // above. The rest are reasoning fragments, the live invocation
            // records, the structured records a call attached, transcript-entry
            // ids, compaction reports, seeding reports, and an elicitation this
            // demo's tools never raise: real signal for a host that keeps a view
            // of the session, and none of it part of what this demo prints. A
            // `.toolCallReport` carries the file-change set of a mutating
            // `tools.files` call, which a host renders as a reviewable diff;
            // this demo prints lines and renders no diff.
            break
        }
    }

    /// The name of the tool a call id belongs to, for a line reporting on that
    /// call.
    ///
    /// - Parameter callID: the call's id, as `SessionEvent.toolStatus` carries it.
    /// - Returns: the tool's name, or the call id itself when no `.toolCall`
    ///   announced that call — an id a reader can still correlate against the
    ///   recorded transcript, where a placeholder word could not be.
    private func toolName(of callID: String) -> String {
        toolNamesByCallID[callID] ?? callID
    }
}

// MARK: - The activity of the session

/// What the session still does that can give one more answer: the
/// submissions that wait or run, the caller messages with no answer yet, and
/// the background runs that did not settle.
///
/// `SessionProjection` of Router tracks the first two, but it is a
/// `@MainActor` view model and it does not track background runs. This value
/// applies the same submission and answer events, and it also applies the
/// open and close records of each run.
struct CLISessionActivity {
    /// The submissions that wait for the model worker or run now.
    private var openSubmissions: Set<SubmissionID> = []

    /// The caller messages that a submission delivered and that no answer
    /// named yet.
    private var messagesAwaitingAnswer: Set<MessageID> = []

    /// The completion tokens of the runs with an open invocation record and no
    /// terminal event.
    ///
    /// A background run keeps its open record after the envelope goes back to
    /// the model, until its body ends. Its settlement then comes as mail.
    private var openRuns: Set<String> = []

    /// Whether the session does nothing now that can give one more answer.
    var isIdle: Bool {
        openSubmissions.isEmpty && messagesAwaitingAnswer.isEmpty && openRuns.isEmpty
    }

    /// Applies one event of the session.
    ///
    /// - Parameter event: the event to apply.
    mutating func apply(_ event: SessionEvent) {
        switch event {
        case .submissionQueued(let submission):
            openSubmissions.insert(submission)
        case .submissionStarted(let start):
            openSubmissions.insert(start.submissionId)
            messagesAwaitingAnswer.formUnion(start.messageIds)
        case .submissionEnded(let end):
            openSubmissions.remove(end.submissionId)
        case .answered(let answer):
            messagesAwaitingAnswer.subtract(answer.messageIds)
        case .answerFailed(let failure):
            messagesAwaitingAnswer.subtract(failure.messageIds)
        case .toolInvocation(let record):
            apply(record)
        case .runSettled(let terminal):
            openRuns.remove(terminal.correlationID)
        case .textDelta, .textReset, .reasoningDelta, .toolCall, .toolStatus, .toolCallReport, .entryRecorded,
            .compaction, .discoveryPrimingFailed, .generationStalled, .repetitionStopped, .reasoningStopped,
            .elicitationRequested, .generationCall, .mailDeliveryPaused:
            // These events come inside a submission, or they report work that
            // an event above already tracks, so they change no activity.
            break
        }
    }

    /// Applies one open or close record of a run.
    ///
    /// - Parameter record: the record to apply.
    private mutating func apply(_ record: ToolInvocationRecord) {
        guard record.closedAt == nil else {
            openRuns.remove(record.correlationID)
            return
        }
        openRuns.insert(record.correlationID)
    }
}

// MARK: - The mail drain

/// The state of the drain of the session events after the first answer.
///
/// The session stream carries every event of the session, also the events of
/// the first answer, which the CLI already printed from `streamEvents(to:)`.
/// So this drain applies every event to the activity, and it prints only the
/// events after the end of the first answer.
struct CLIMailDrain {
    /// The caller messages of the first answer, which identify its end on the
    /// session stream.
    private let firstAnswerMessageIds: [MessageID]

    /// Where each line is written.
    private let output: @Sendable (String) -> Void

    /// The activity of the session.
    private var activity = CLISessionActivity()

    /// The reporter of the events after the first answer.
    private var reporter: CLIEventReporter

    /// Whether the drain read the end of the first answer.
    private var isPastFirstAnswer = false

    /// Creates the drain that follows `firstAnswer`.
    ///
    /// - Parameters:
    ///   - firstAnswer: the first answer, which the CLI already printed.
    ///   - output: where each line is written.
    init(following firstAnswer: SessionAnswer, output: @escaping @Sendable (String) -> Void) {
        self.firstAnswerMessageIds = firstAnswer.messageIds
        self.output = output
        self.reporter = CLIEventReporter(output: output)
    }

    /// Whether the first answer ended and the session does nothing now that
    /// can give one more answer.
    var isSettled: Bool {
        isPastFirstAnswer && activity.isIdle
    }

    /// Applies one event of the session, and prints it when it comes after
    /// the first answer.
    ///
    /// - Parameter event: the event to apply.
    /// - Throws: `CLIAnswerError.failed` when an answer after the first one
    ///   failed.
    mutating func apply(_ event: SessionEvent) throws {
        activity.apply(event)
        guard isPastFirstAnswer else {
            isPastFirstAnswer = endsFirstAnswer(event)
            return
        }
        reporter.report(event)
        switch CLIRunner.end(of: event) {
        case .success(let answer):
            output("")
            output("\(CLIRunner.mailAnswerPrefix)\(answer.reply)")
        case .failure(let failure):
            throw CLIAnswerError.failed(failure)
        case nil:
            break
        }
    }

    /// Whether `event` is the end of the first answer.
    ///
    /// - Parameter event: one event of the session.
    /// - Returns: `true` for the `.answered` or `.answerFailed` that names the
    ///   caller messages of the first answer.
    private func endsFirstAnswer(_ event: SessionEvent) -> Bool {
        switch CLIRunner.end(of: event) {
        case .success(let answer):
            answer.messageIds == firstAnswerMessageIds
        case .failure(let failure):
            failure.messageIds == firstAnswerMessageIds
        case nil:
            false
        }
    }
}

/// One input of the loop of `CLIRunner.drainMailAnswers(_:after:wait:cancel:output:)`.
enum CLIMailSignal: Sendable {
    /// One event of the session.
    case event(SessionEvent)

    /// The session stream ended: the session closed.
    case streamEnded

    /// The quiet period that started after the event with this number ended.
    case quiet(afterEvent: Int)

    /// The time limit of the wait ended.
    case timeLimit
}

extension CLIRunner {
    /// The prefix of the line that prints the first answer.
    static let answerPrefix = "Answer: "

    /// The prefix of the line that prints an answer that mail started.
    static let mailAnswerPrefix = "Answer from mail: "

    /// Drains the event stream of one message, reporting each tool call while
    /// the answer runs, and returns the answer.
    ///
    /// This is the host half of the contract
    /// `MultiTool.Registry.makeSessionTools(selection:)` states: a session that
    /// carries the mounted tools is driven by draining `streamEvents(to:)`.
    /// Every line written here is one a `respond(to:)` caller never sees. Each
    /// `runCode` call goes to the background, and it reports itself while it is
    /// still working, where `respond(to:)` is a single await that returns only
    /// once the answer is whole.
    ///
    /// The answer is the `SessionEvent.answered` event, not the joined text
    /// fragments. One answer can have more than one submission, and
    /// `.textReset` clears only the text of the current submission, so the
    /// joined fragments of two submissions are not the reply.
    ///
    /// Not `private`: `Tests/FoundationModelsMultitoolTests/CLIAnswerDrainTests.swift`
    /// drives it over a scripted stream, so the drain is covered with no model,
    /// no Router and no network.
    ///
    /// - Parameters:
    ///   - events: the event stream of the message —
    ///     `RoutedSession.streamEvents(to:)` in production.
    ///   - output: where each reported line is written.
    /// - Returns: the answer, whose `reply` is the string `respond(to:)`
    ///   returns for the same message.
    /// - Throws: `CLIAnswerError.failed` when the session sent
    ///   `.answerFailed`, also when the stream then ends with the error of the
    ///   failed chain. `CLIAnswerError.missing` when the stream ends with no
    ///   end of the answer. Any other error the stream throws.
    static func drainAnswer(
        _ events: AsyncThrowingStream<SessionEvent, Error>,
        output: @escaping @Sendable (String) -> Void
    ) async throws -> SessionAnswer {
        var reporter = CLIEventReporter(output: output)
        var end: Result<SessionAnswer, AnswerFailure>?
        do {
            for try await event in events {
                reporter.report(event)
                end = Self.end(of: event) ?? end
            }
        } catch {
            // The session finishes the stream with the error of a failed chain
            // after its `.answerFailed`. The failure is the report the CLI
            // gives for it.
            guard case .failure(let failure) = end else { throw error }
            throw CLIAnswerError.failed(failure)
        }
        switch end {
        case .success(let answer):
            return answer
        case .failure(let failure):
            throw CLIAnswerError.failed(failure)
        case nil:
            // A stream whose reader is cancelled ends with no error and no end.
            try Task.checkCancellation()
            throw CLIAnswerError.missing
        }
    }

    /// Drains the event stream of one message and prints its answer one time.
    ///
    /// - Parameters:
    ///   - events: the event stream of the message.
    ///   - output: where each line is written.
    /// - Returns: the answer.
    /// - Throws: what `drainAnswer(_:output:)` throws. The answer line is not
    ///   printed then.
    static func presentAnswer(
        _ events: AsyncThrowingStream<SessionEvent, Error>,
        output: @escaping @Sendable (String) -> Void
    ) async throws -> SessionAnswer {
        let answer = try await drainAnswer(events, output: output)
        output("")
        output("\(answerPrefix)\(answer.reply)")
        return answer
    }

    /// Drains the session events after the first answer, and prints each
    /// answer that mail starts, until the session is idle.
    ///
    /// A settled background run comes back to the session as mail, and the
    /// mail starts a new answer by itself (`SubmissionStart.cause == .mail`).
    /// That answer streams on `RoutedSession.streamSessionEvents()` only. The
    /// drain stops when the session has no submission, no caller message with
    /// no answer and no open background run, and no event comes for
    /// `wait.quietPeriod`. When `wait.timeLimit` ends first, the drain
    /// prints one line and calls `cancel`.
    ///
    /// - Parameters:
    ///   - sessionEvents: the session stream, subscribed before the first
    ///     message was sent, so it also carries the first answer.
    ///   - firstAnswer: the first answer, which the CLI already printed.
    ///   - wait: the bounds of the wait.
    ///   - cancel: stops the work of the session — `RoutedSession.cancel()` in
    ///     production.
    ///   - output: where each line is written.
    /// - Throws: `CLIAnswerError.failed` when an answer that mail started
    ///   failed.
    static func drainMailAnswers(
        _ sessionEvents: AsyncStream<SessionEvent>,
        after firstAnswer: SessionAnswer,
        wait: CLIMailWait,
        cancel: @escaping @Sendable () async -> Void,
        output: @escaping @Sendable (String) -> Void
    ) async throws {
        let (signals, sink) = AsyncStream<CLIMailSignal>.makeStream()
        let forwarder = Task { await forward(sessionEvents, to: sink) }
        let limit = Task { await send(.timeLimit, after: wait.timeLimit, to: sink) }
        var quietTimer: Task<Void, Never>?
        defer {
            forwarder.cancel()
            limit.cancel()
            quietTimer?.cancel()
            sink.finish()
        }
        var drain = CLIMailDrain(following: firstAnswer, output: output)
        var eventCount = 0
        for await signal in signals {
            switch signal {
            case .event(let event):
                try drain.apply(event)
                eventCount += 1
                quietTimer?.cancel()
                quietTimer = drain.isSettled ? startQuietTimer(afterEvent: eventCount, wait: wait, sink: sink) : nil
            case .quiet(let afterEvent) where afterEvent == eventCount:
                return
            case .quiet:
                // A quiet period that an event after it made stale.
                continue
            case .timeLimit:
                output("The session did not become idle in \(wait.timeLimit). The CLI cancels the session.")
                await cancel()
                return
            case .streamEnded:
                return
            }
        }
    }

    /// The end of an answer that `event` carries.
    ///
    /// - Parameter event: one event of the session.
    /// - Returns: the answer of `.answered`, the failure of `.answerFailed`,
    ///   or `nil` for every other event.
    static func end(of event: SessionEvent) -> Result<SessionAnswer, AnswerFailure>? {
        if case .answered(let answer) = event {
            return .success(answer)
        }
        if case .answerFailed(let failure) = event {
            return .failure(failure)
        }
        return nil
    }

    /// Starts the quiet period after one event.
    ///
    /// - Parameters:
    ///   - afterEvent: the number of the event.
    ///   - wait: the bounds of the wait.
    ///   - sink: where the signal goes when the quiet period ends.
    /// - Returns: the timer task; cancel it when one more event comes.
    private static func startQuietTimer(
        afterEvent: Int, wait: CLIMailWait, sink: AsyncStream<CLIMailSignal>.Continuation
    ) -> Task<Void, Never> {
        Task { await send(.quiet(afterEvent: afterEvent), after: wait.quietPeriod, to: sink) }
    }

    /// Sends each event of the session to `sink`, and then `.streamEnded`.
    ///
    /// - Parameters:
    ///   - sessionEvents: the session stream.
    ///   - sink: where each signal goes.
    private static func forward(
        _ sessionEvents: AsyncStream<SessionEvent>, to sink: AsyncStream<CLIMailSignal>.Continuation
    ) async {
        for await event in sessionEvents {
            sink.yield(.event(event))
        }
        sink.yield(.streamEnded)
    }

    /// Sends `signal` to `sink` after `delay`, unless the task is cancelled
    /// first.
    ///
    /// - Parameters:
    ///   - signal: the signal to send.
    ///   - delay: how long to wait.
    ///   - sink: where the signal goes.
    private static func send(
        _ signal: CLIMailSignal, after delay: Duration, to sink: AsyncStream<CLIMailSignal>.Continuation
    ) async {
        guard (try? await Task.sleep(for: delay)) != nil else { return }
        sink.yield(signal)
    }
}
