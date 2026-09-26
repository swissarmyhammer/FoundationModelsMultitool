import FoundationModelsRouter

// The fold of the session events of a gated run into its answers, cut out of
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

/// One submission of an answer chain: one SDK call, as its start and end
/// events report it.
public struct SubmissionRecord: Sendable, Equatable {
    /// The submission this record is about.
    public let submissionId: SubmissionID

    /// The start of the submission: the caller messages it delivers and why
    /// the session made it. `nil` when the submission never started — the
    /// token budget refused it, or a cancel came before its call — because
    /// Router then sends its `submissionEnded` alone.
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
    ///   - submissions: every submission of the chain, in event order.
    ///   - repetitionStops: every stop for repeated lines, in event order.
    ///   - outcome: how the chain ended.
    public init(submissions: [SubmissionRecord], repetitionStops: [RepetitionStop], outcome: Outcome) {
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
}

/// The fold of the session events of one run into its answers.
public enum SubmissionLog {
    /// Folds `events` into one record for each answer chain that ended.
    ///
    /// A pure function of its argument: no model, no session and no clock, so
    /// a test gives it a scripted event list. A chain whose `answered` or
    /// `answerFailed` event is not in `events` is still open and gives no
    /// record. Every event that is not about a submission, an answer or a
    /// stop for repeated lines leaves the fold as it is.
    ///
    /// - Parameter events: the session events, in the order the session sent
    ///   them.
    /// - Returns: one record for each chain that ended, in the order the
    ///   chains ended.
    public static func fold(_ events: [SessionEvent]) -> [AnswerRecord] {
        events.reduce(into: Fold()) { fold, event in fold.apply(event) }.records
    }

    /// Whether `event` ends an answer chain: `answered`, or `answerFailed`
    /// in its place.
    ///
    /// A runner that reads a session's events up to "the end of the reply"
    /// stops at the first event for which this is `true`. The end of one SDK
    /// call, `submissionEnded`, is not the end of the reply: a chain that
    /// continues sends more than one.
    ///
    /// - Parameter event: the session event to test.
    /// - Returns: `true` for `answered` and `answerFailed`, and `false` for
    ///   every other event.
    public static func endsAnswer(_ event: SessionEvent) -> Bool {
        switch event {
        case .answered, .answerFailed:
            true
        default:
            false
        }
    }
}

/// The state of ``SubmissionLog/fold(_:)`` between two events.
private struct Fold {
    /// Each chain that ended, in the order it ended.
    var records: [AnswerRecord] = []

    /// The submissions of the chain that has not ended yet.
    var openSubmissions: [SubmissionRecord] = []

    /// The stops for repeated lines of the chain that has not ended yet.
    var openStops: [RepetitionStop] = []

    /// Applies one event.
    ///
    /// `default` absorbs every other case on purpose: `SessionEvent` has no
    /// library evolution, and Router documents that a consumer writes a
    /// `default` arm to absorb new cases. A new case carries nothing this
    /// fold records until someone adds it here.
    ///
    /// - Parameter event: the next session event.
    mutating func apply(_ event: SessionEvent) {
        switch event {
        case .submissionStarted(let start):
            openSubmissions.append(SubmissionRecord(submissionId: start.submissionId, start: start, end: nil))
        case .submissionEnded(let end):
            record(end)
        case .repetitionStopped(let stop):
            openStops.append(stop)
        case .answered(let answer):
            closeChain(.answered(answer))
        case .answerFailed(let failure):
            closeChain(.failed(failure))
        default:
            break
        }
    }

    /// Records the end of one submission on its open record, or as a record
    /// of its own when the submission never started.
    ///
    /// - Parameter end: the end event of the submission.
    private mutating func record(_ end: SubmissionEnd) {
        guard let index = openSubmissions.firstIndex(where: { $0.submissionId == end.submissionId }) else {
            openSubmissions.append(SubmissionRecord(submissionId: end.submissionId, start: nil, end: end))
            return
        }
        openSubmissions[index] = openSubmissions[index].ended(by: end)
    }

    /// Ends the open chain with `outcome`, and starts the next chain empty.
    ///
    /// - Parameter outcome: how the chain ended.
    private mutating func closeChain(_ outcome: AnswerRecord.Outcome) {
        records.append(AnswerRecord(submissions: openSubmissions, repetitionStops: openStops, outcome: outcome))
        openSubmissions = []
        openStops = []
    }
}
