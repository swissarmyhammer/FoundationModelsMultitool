import FoundationModelsRouter

// The fold of the session output of a gated run into its answers, cut out of
// the gated package's `Support/ScenarioRunner.swift` for the reason
// `ScenarioGrading.swift` states: the rule reads plain values, so it stands
// here, where the root test target runs it on each commit with no model.
//
// Router reports each answer as a chain of submissions (`generation-queue.md`,
// section 5.6). `submissionStarted` opens one SDK call of the chain, and
// `submissionEnded` closes it. The chain ends with one `answered`, or with one
// `answerFailed` when it gives no answer. A runner that reads "the end of the
// reply" reads `answered`. A runner that reads "the end of one SDK call" reads
// `submissionEnded`. This file gives both, per answer.
//
// Each output event of an answer has the origin of that answer: the mail ids
// of the batch that started it (`mailbox.md`, section 4). Thus the fold finds
// the chain of each event by its origin, not by the order of the events. Two
// answers whose events mix in the output fold to two records.

/// One submission of an answer chain: one SDK call, as its start and end
/// events report it.
public struct SubmissionRecord: Sendable, Equatable {
    /// The submission this record is about.
    public let submissionId: SubmissionID

    /// The start of the submission: the mail it delivers and why the session
    /// made it. `nil` when the submission never started — the token budget
    /// refused it, or a cancel came before its call — because Router then
    /// sends its `submissionEnded` alone.
    public let start: SubmissionStart?

    /// The end of the submission: its usage and its finish reason. `nil`
    /// while the submission is still open.
    public let end: SubmissionEnd?

    /// Records one submission.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - submissionId: the submission this record is about.
    ///   - start: the start of the submission, or `nil` when it never started.
    ///   - end: the end of the submission, or `nil` while it is open.
    public init(submissionId: SubmissionID, start: SubmissionStart?, end: SubmissionEnd?) {
        self.submissionId = submissionId
        self.start = start
        self.end = end
    }

    /// This record, with its end recorded.
    ///
    /// - Parameter end: the end event of the submission.
    /// - Returns: the record with ``end`` set.
    func ended(by end: SubmissionEnd) -> SubmissionRecord {
        SubmissionRecord(submissionId: submissionId, start: start, end: end)
    }
}

/// One answer of a session, folded from the events of its chain.
public struct AnswerRecord: Sendable, Equatable {
    /// How the chain ended.
    public enum Outcome: Sendable, Equatable {
        /// The chain gave its final answer.
        case answered(SessionAnswer)

        /// The chain ended with no answer: a cancel stopped it, or it failed.
        case failed(AnswerFailure)
    }

    /// The origin of each event of the chain: the ids of the mail whose batch
    /// started the answer.
    public let origin: Set<MailID>

    /// Every submission of the chain, in the order the events reported them.
    public let submissions: [SubmissionRecord]

    /// Every stop for repeated lines inside the chain, in event order.
    public let repetitionStops: [RepetitionStop]

    /// How the chain ended.
    public let outcome: Outcome

    /// Records one answer.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - origin: the ids of the mail whose batch started the answer.
    ///   - submissions: every submission of the chain, in event order.
    ///   - repetitionStops: every stop for repeated lines, in event order.
    ///   - outcome: how the chain ended.
    public init(
        origin: Set<MailID>, submissions: [SubmissionRecord], repetitionStops: [RepetitionStop], outcome: Outcome
    ) {
        self.origin = origin
        self.submissions = submissions
        self.repetitionStops = repetitionStops
        self.outcome = outcome
    }

    /// The identity of each submission of the chain, in event order.
    public var submissionIds: [SubmissionID] {
        submissions.map(\.submissionId)
    }

    /// Why the chain started: the cause of its first submission that
    /// started, or `nil` when no submission of the chain started.
    ///
    /// `.mail` here is an answer that no caller asked for — the settled
    /// result of a background run came back to the session as mail.
    public var cause: SubmissionStart.Cause? {
        submissions.lazy.compactMap(\.start).first?.cause
    }

    /// The final reply of the chain — `SessionAnswer.reply`, the text that
    /// `respond(to:)` returns for the same message — or `nil` when the chain
    /// gave no answer.
    public var reply: String? {
        guard case .answered(let answer) = outcome else { return nil }
        return answer.reply
    }

    /// The ids of all mail that the chain delivered: the mail of its origin,
    /// and each mail that joined it later (`SessionAnswer.mailIds`).
    public var deliveredMailIds: [MailID] {
        switch outcome {
        case .answered(let answer): answer.mailIds
        case .failed(let failure): failure.mailIds
        }
    }

    /// Whether this chain is the answer to the mail `id`: its origin holds
    /// `id`, or the chain delivered `id`.
    ///
    /// - Parameter id: the id of one mail.
    /// - Returns: `true` when the chain answers `id`.
    public func answers(_ id: MailID) -> Bool {
        origin.contains(id) || deliveredMailIds.contains(id)
    }
}

/// The fold of the session output of one run into its answers.
public enum SubmissionLog {
    /// Folds `outputs` into one record for each answer chain that ended.
    ///
    /// A pure function of its argument: no model, no session and no clock, so
    /// a test gives it a scripted output list. The fold puts each event in the
    /// chain of its origin. An event whose origin is not mail (a signal, or
    /// the session itself) is not part of an answer. A chain whose
    /// `answered` or `answerFailed` event is not in `outputs` is still open
    /// and gives no record. Every event that is not about a submission, an
    /// answer or a stop for repeated lines leaves the fold as it is.
    ///
    /// - Parameter outputs: the session output, in the order the session
    ///   sent it.
    /// - Returns: one record for each chain that ended, in the order the
    ///   chains ended.
    public static func fold(outputs: [SessionOutput]) -> [AnswerRecord] {
        outputs.reduce(into: Fold()) { fold, output in fold.apply(output) }.records
    }

    /// The record of the answer to the mail `id`, when its chain ended in
    /// `outputs`.
    ///
    /// - Parameters:
    ///   - id: the id of one mail.
    ///   - outputs: the session output, in the order the session sent it.
    /// - Returns: the record of the chain that answers `id`, or `nil` when
    ///   that chain did not end in `outputs`.
    public static func answer(to id: MailID, in outputs: [SessionOutput]) -> AnswerRecord? {
        fold(outputs: outputs).first { $0.answers(id) }
    }

    /// Whether `output` ends the answer chain of the mail `id`: its
    /// `answered`, or `answerFailed` in its place.
    ///
    /// A runner that reads a session's output up to "the end of the reply"
    /// to its message stops at the first output for which this is `true`.
    /// The end of one SDK call, `submissionEnded`, is not the end of the
    /// reply: a chain that continues sends more than one. The end of the
    /// answer to another mail is not the end of this reply.
    ///
    /// - Parameters:
    ///   - output: the session output to test.
    ///   - id: the id of the mail whose answer the runner reads.
    /// - Returns: `true` for the `answered` and `answerFailed` events of the
    ///   chain that answers `id`, and `false` for every other output.
    public static func endsAnswer(_ output: SessionOutput, of id: MailID) -> Bool {
        switch output.event {
        case .answered(let answer):
            output.origin.contains(id) || answer.mailIds.contains(id)
        case .answerFailed(let failure):
            output.origin.contains(id) || failure.mailIds.contains(id)
        default:
            false
        }
    }
}

/// The state of ``SubmissionLog/fold(outputs:)`` between two events.
private struct Fold {
    /// Each chain that ended, in the order it ended.
    var records: [AnswerRecord] = []

    /// The chains that have not ended yet, by their origin.
    var open: [Set<MailID>: OpenChain] = [:]

    /// One chain that has not ended yet.
    struct OpenChain {
        /// The submissions of the chain so far.
        var submissions: [SubmissionRecord] = []

        /// The stops for repeated lines of the chain so far.
        var stops: [RepetitionStop] = []
    }

    /// Applies one output event to the chain of its origin.
    ///
    /// `default` absorbs every other case on purpose: `SessionEvent` has no
    /// library evolution, and Router documents that a consumer writes a
    /// `default` arm to absorb new cases. A new case carries nothing this
    /// fold records until someone adds it here.
    ///
    /// - Parameter output: the next session output.
    mutating func apply(_ output: SessionOutput) {
        guard case .mail(let origin) = output.origin else { return }
        switch output.event {
        case .submissionStarted(let start):
            open[origin, default: OpenChain()].submissions.append(
                SubmissionRecord(submissionId: start.submissionId, start: start, end: nil))
        case .submissionEnded(let end):
            record(end: end, in: origin)
        case .repetitionStopped(let stop):
            open[origin, default: OpenChain()].stops.append(stop)
        case .answered(let answer):
            closeChain(origin, outcome: .answered(answer))
        case .answerFailed(let failure):
            closeChain(origin, outcome: .failed(failure))
        default:
            break
        }
    }

    /// Records the end of one submission on its open record, or as a record
    /// of its own when the submission never started.
    ///
    /// - Parameters:
    ///   - end: the end event of the submission.
    ///   - origin: the origin of the chain of the submission.
    private mutating func record(end: SubmissionEnd, in origin: Set<MailID>) {
        var chain = open[origin, default: OpenChain()]
        if let index = chain.submissions.firstIndex(where: { $0.submissionId == end.submissionId }) {
            chain.submissions[index] = chain.submissions[index].ended(by: end)
        } else {
            chain.submissions.append(SubmissionRecord(submissionId: end.submissionId, start: nil, end: end))
        }
        open[origin] = chain
    }

    /// Ends the open chain of `origin` with `outcome`.
    ///
    /// - Parameters:
    ///   - origin: the origin of the chain.
    ///   - outcome: how the chain ended.
    private mutating func closeChain(_ origin: Set<MailID>, outcome: AnswerRecord.Outcome) {
        let chain = open.removeValue(forKey: origin) ?? OpenChain()
        records.append(
            AnswerRecord(origin: origin, submissions: chain.submissions, repetitionStops: chain.stops, outcome: outcome))
    }
}
