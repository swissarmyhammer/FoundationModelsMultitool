import FoundationModels
import FoundationModelsRouter
import TestConcurrency

// MARK: - The output of a session, read by mail id
//
// Each mail that goes into a Router session has a `MailID`. Each output event
// of the session carries the origin of the work that sent it, and each mail id
// gets exactly one terminal event. Thus a test finds the answer to its message,
// and the run mail of a settled background run, by its id. It does not find
// them by the text of a prompt or by the order of the answers.
//
// The log reads `streamSessionEvents()` from before the first mail. A test
// waits on the events in the log, and not on a clock. The root unit tests and
// the gated scenarios of the nested package both read a session this way, so
// the log stands in this test-support product, which both link.

/// One user message that a test sent, and the answer that it got.
public struct AnsweredMail: Sendable {
    /// The id of the user message.
    public let id: MailID

    /// The answer of the session to the message.
    public let answer: SessionAnswer

    /// The final text of the answer: the text that `respond(to:)` returns for
    /// the same message.
    public var reply: String { answer.reply }
}

/// The run mail of a settled background run, and the answer that delivered
/// it to the model.
public struct DeliveredRunMail: Sendable {
    /// The id of the run mail.
    public let id: MailID

    /// The terminal event of the run that the mail holds.
    public let event: OperationEvent

    /// The answer whose submissions delivered the mail.
    public let answer: SessionAnswer
}

/// What a wait of ``SessionOutputLog`` throws when its event did not come.
public enum SessionOutputLogError: Error, Equatable {
    /// The event stream of the session finished, or the task of the caller
    /// was cancelled, before the run mail of the run came.
    case noRunMail(completionToken: String)

    /// The event stream of the session finished, or the task of the caller
    /// was cancelled, before the terminal event of the mail came.
    case noTerminal(mailID: MailID)
}

/// The output events of one Router session, in the order the session sent
/// them, with waits on those events.
public actor SessionOutputLog {
    /// The session that the log reads.
    public let session: any RoutedSession

    /// Each output event so far, in the order the session sent it.
    public private(set) var outputs: [SessionOutput] = []

    /// Each user message that ``ask(_:)`` sent and that got its answer, in
    /// the order the test sent them.
    public private(set) var askedMails: [AnsweredMail] = []

    /// Whether the event stream of the session finished. No event comes to
    /// the log after that.
    public private(set) var isStreamFinished = false

    /// The waits that are not satisfied yet, each with its condition on all
    /// events so far.
    private let waiters = WaitList<@Sendable ([SessionOutput]) -> Bool>()

    /// Makes a log for `session`. Use ``reading(_:)``.
    ///
    /// - Parameter session: The session that the log reads.
    private init(session: any RoutedSession) {
        self.session = session
    }

    /// Starts a log that reads each output event of `session`.
    ///
    /// Call it before the first mail goes into the session: the stream of
    /// the session gives only the events that come after the subscription.
    ///
    /// - Parameter session: The session to read.
    /// - Returns: The log.
    public static func reading(_ session: any RoutedSession) async -> SessionOutputLog {
        let log = SessionOutputLog(session: session)
        let stream = await session.streamSessionEvents()
        Task { [weak log] in
            for await output in stream {
                guard let log else { return }
                await log.append(output)
            }
            await log?.streamDidFinish()
        }
        return log
    }

    /// Adds one output event, and ends each wait that it satisfies.
    ///
    /// - Parameter output: The next output event of the session.
    private func append(_ output: SessionOutput) {
        outputs.append(output)
        let current = outputs
        waiters.resume { condition in condition(current) }
    }

    /// Records that the event stream of the session finished, and ends each
    /// wait: no event that could satisfy it comes any more.
    private func streamDidFinish() {
        isStreamFinished = true
        waiters.endAll()
    }

    /// Waits until `condition` is true for the events in the log.
    ///
    /// The wait ends on the first of three events: `condition` is true, the
    /// event stream of the session finished, or the task of the caller is
    /// cancelled. Thus a session that never sends the event does not make
    /// the wait stay.
    ///
    /// - Parameter condition: The condition on all events so far.
    /// - Returns: `true` when `condition` is true. `false` when the stream
    ///   finished or the task was cancelled first.
    public func wait(until condition: @escaping @Sendable ([SessionOutput]) -> Bool) async -> Bool {
        guard !isStreamFinished else { return condition(outputs) }
        return await waiters.wait(for: condition, unless: { condition(outputs) })
    }

    /// Sends `text` as a user message, and waits for its answer.
    ///
    /// This is `respond(to:)` with the id of the message kept. The method
    /// returns when the log holds the terminal event of the message, thus
    /// each event of its answer is in the log.
    ///
    /// - Parameter text: The text of the message.
    /// - Returns: The id of the message and its answer.
    /// - Throws: What `send(_:)` throws, the error of a failed answer, and
    ///   ``SessionOutputLogError/noTerminal(mailID:)`` when the event stream
    ///   of the session finished, or the task of the caller was cancelled,
    ///   before the terminal event of the message came.
    public func ask(_ text: String) async throws -> AnsweredMail {
        let id = try session.send(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: text))]))
        let answer = try await session.awaitAnswer(of: id)
        try await requireTerminal(of: id)
        let asked = AnsweredMail(id: id, answer: answer)
        askedMails.append(asked)
        return asked
    }

    /// Waits until the log holds the terminal event of the mail `id`.
    ///
    /// The wait ends on the first of three events, as ``wait(until:)`` does:
    /// the terminal event is in the log, the event stream of the session
    /// finished, or the task of the caller is cancelled.
    ///
    /// - Parameter id: The id of one mail.
    /// - Returns: `true` when the log holds the terminal event of `id`.
    ///   `false` when the stream finished or the task was cancelled first.
    public func waitForTerminal(of id: MailID) async -> Bool {
        await wait { outputs in outputs.contains { Self.isTerminal($0.event, of: id) } }
    }

    /// Waits until the log holds the terminal event of the mail `id`, and
    /// throws when it did not come.
    ///
    /// - Parameter id: The id of one mail.
    /// - Throws: ``SessionOutputLogError/noTerminal(mailID:)`` when the event
    ///   stream of the session finished, or the task of the caller was
    ///   cancelled, before the terminal event came.
    private func requireTerminal(of id: MailID) async throws {
        guard await waitForTerminal(of: id) else {
            throw SessionOutputLogError.noTerminal(mailID: id)
        }
    }

    /// The terminal event of the mail `id`, when the log holds it.
    ///
    /// - Parameter id: The id of one mail.
    /// - Returns: The first terminal event of `id`, or `nil`.
    public func terminal(of id: MailID) -> SessionEvent? {
        outputs.lazy.map(\.event).first { Self.isTerminal($0, of: id) }
    }

    /// Waits for the run mail that holds the terminal of the background run
    /// `completionToken`, and gives its id.
    ///
    /// The run mail of a settled run is the `runSettled` output event of the
    /// run, and its origin is the id of that mail.
    ///
    /// - Parameter completionToken: The completion token of the run.
    /// - Returns: The id of the run mail.
    /// - Throws: ``SessionOutputLogError/noRunMail(completionToken:)`` when
    ///   the event stream of the session finished, or the task of the caller
    ///   was cancelled, before the run mail came.
    public func runMail(settling completionToken: String) async throws -> MailID {
        let came = await wait { outputs in Self.runMailIds(settling: completionToken, in: outputs).first != nil }
        guard came, let id = Self.runMailIds(settling: completionToken, in: outputs).first else {
            throw SessionOutputLogError.noRunMail(completionToken: completionToken)
        }
        return id
    }

    /// The id of each run mail that holds the terminal of the run
    /// `completionToken`, in event order.
    ///
    /// - Parameter completionToken: The completion token of the run.
    /// - Returns: The ids. A run that settled one time gives one id.
    public func runMailIds(settling completionToken: String) -> [MailID] {
        Self.runMailIds(settling: completionToken, in: outputs)
    }

    /// The terminal event of a background run that the run mail `id` holds.
    ///
    /// - Parameter id: The id of one run mail.
    /// - Returns: The event of the `runSettled` output whose origin is `id`,
    ///   or `nil` when the log has no such event.
    public func settledRun(in id: MailID) -> OperationEvent? {
        outputs.lazy.compactMap { output -> OperationEvent? in
            guard case .runSettled(let event) = output.event, output.origin.contains(id) else { return nil }
            return event
        }.first
    }

    /// Waits for the run mail of the background run `completionToken`, then
    /// for the answer that delivers it.
    ///
    /// - Parameter completionToken: The completion token of the run.
    /// - Returns: The id of the run mail, the terminal event of the run that
    ///   it holds, and the answer that delivered it.
    /// - Throws: What ``runMail(settling:)`` throws, the error of a failed
    ///   answer, and ``SessionOutputLogError/noTerminal(mailID:)`` when the
    ///   event stream of the session finished, or the task of the caller was
    ///   cancelled, before the terminal event of the run mail came.
    public func deliveredRunMail(settling completionToken: String) async throws -> DeliveredRunMail {
        let id = try await runMail(settling: completionToken)
        let answer = try await session.awaitAnswer(of: id)
        try await requireTerminal(of: id)
        guard let event = settledRun(in: id) else {
            preconditionFailure("runMail(settling:) returned an id with no runSettled event")
        }
        return DeliveredRunMail(id: id, event: event, answer: answer)
    }

    /// The id of each run mail in the log: each `runSettled`, `runMessage` and
    /// `runProgress` event that has a mail origin.
    public var allRunMailIds: [MailID] {
        outputs.flatMap { output -> [MailID] in Self.runMailIds(of: output, completionToken: nil) }
    }

    /// The id of each run mail of the background run `completionToken`: its
    /// `runSettled`, `runMessage` and `runProgress` events that have a mail
    /// origin.
    ///
    /// - Parameter completionToken: The completion token of the run.
    /// - Returns: The ids, in event order.
    public func allRunMailIds(of completionToken: String) -> [MailID] {
        outputs.flatMap { output -> [MailID] in Self.runMailIds(of: output, completionToken: completionToken) }
    }

    /// The id of each `mailDelivered` event in the log, in event order.
    public var deliveredMailIds: [MailID] {
        outputs.compactMap { output in
            guard case .mailDelivered(let id) = output.event else { return nil }
            return id
        }
    }

    /// The run mail ids that one output event carries.
    ///
    /// - Parameters:
    ///   - output: One output event.
    ///   - completionToken: The run to keep, or `nil` for every run.
    /// - Returns: The ids of the origin, when the event is a run event with a
    ///   mail origin of that run, and no id otherwise.
    private static func runMailIds(of output: SessionOutput, completionToken: String?) -> [MailID] {
        let event: OperationEvent
        switch output.event {
        case .runSettled(let runEvent), .runMessage(let runEvent), .runProgress(let runEvent):
            event = runEvent
        default:
            return []
        }
        guard case .mail(let ids) = output.origin else { return [] }
        if let completionToken, event.correlationID != completionToken { return [] }
        return Array(ids)
    }

    /// The `runSettled` events of the run `completionToken` that have a mail
    /// origin, as the ids of their run mail.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the run.
    ///   - outputs: The events to read.
    /// - Returns: The ids, in event order.
    private static func runMailIds(settling completionToken: String, in outputs: [SessionOutput]) -> [MailID] {
        outputs.flatMap { output -> [MailID] in
            guard case .runSettled(let event) = output.event, event.correlationID == completionToken,
                case .mail(let ids) = output.origin
            else { return [] }
            return Array(ids)
        }
    }

    /// Whether `event` is the terminal event of the mail `id`.
    ///
    /// - Parameters:
    ///   - event: One output event.
    ///   - id: The id of one mail.
    /// - Returns: `true` for the `answered` or `answerFailed` event of an
    ///   answer that delivered `id`, and for `cancelled` or `lost` of `id`.
    private static func isTerminal(_ event: SessionEvent, of id: MailID) -> Bool {
        switch event {
        case .answered(let answer):
            answer.mailIds.contains(id)
        case .answerFailed(let failure):
            failure.mailIds.contains(id)
        case .cancelled(let cancelled), .lost(let cancelled):
            cancelled == id
        default:
            false
        }
    }
}
