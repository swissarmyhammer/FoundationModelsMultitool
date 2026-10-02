import Foundation

// The grading half of the gated scenario harness, cut out of the gated
// package's `Support/ScenarioRunner.swift`. That file held two unrelated
// things: these rules, which read plain values, and the live-model driving,
// which needs a resolved profile, the Metal bootstrap and the turnstile. Only
// the driving half needs a model, so the rules stand here, where the root test
// target links them and runs their coverage on every commit.
//
// `grade(scenario:checks:)` stays with the driving half. It records a Swift
// Testing issue for each condition that did not hold, so it belongs to a test
// target rather than to a library.

/// One graded condition in a gated scenario's verdict.
///
/// A scenario's conditions are collected before any of them is asserted, so
/// the same list drives both the recorded expectations and the per-scenario
/// `SCENARIO` line — the verdict a run reports can never drift from the
/// verdict it enforces.
public struct ScenarioCheck {
    /// The short label naming this condition on the `SCENARIO` line.
    public let name: String

    /// Whether the condition held on this run.
    public let held: Bool

    /// What to say when it did not — the scenario label is prefixed by
    /// `grade(scenario:checks:)`, in the gated package's `ScenarioRunner.swift`.
    public let failureMessage: String

    /// Records one graded condition.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - name: the short label naming this condition.
    ///   - held: whether the condition held on this run.
    ///   - failureMessage: what to say when it did not.
    public init(name: String, held: Bool, failureMessage: String) {
        self.name = name
        self.held = held
        self.failureMessage = failureMessage
    }
}

/// The label of the check that grades the reply's *form* — the one
/// `ScenarioFailureModes` reads to tell a wrong-form answer from a right
/// one.
public let validAnswerCheckName = "validAnswer"

/// The label of the check that grades the reply as carrying none of the
/// phrasings that invalidate it, even when a required substring matched.
public let answerNotInvalidatedCheckName = "answerNotInvalidated"

/// The label of the check that grades the reply as stating the reading a tool
/// returned, beside the answer `validAnswer` grades.
public let readingReportedCheckName = "readingReported"

/// The label of the check that grades the answer as grounded in the returns it
/// depends on.
public let groundedCheckName = "grounded"

/// The label of the check that grades a background `runCode` call as having
/// handed a pending envelope back.
public let pendingEnvelopeCheckName = "pendingEnvelope"

/// The label of the check that grades the settled background run as having
/// come back to the session as mail, and as having started an answer.
public let mailCollectionCheckName = "mailCollection"

/// The label of the check that grades no background run as still running at the
/// instant the last answer ended.
public let noBackgroundRunsAtLastAnswerCheckName = "noBackgroundRunsAtLastAnswer"

/// The label of the check that grades the nested-generation probe's tool as
/// having been entered at all.
public let nestedCallEnteredCheckName = "nestedCallEntered"

/// The label of the check that grades the nested call as refused with
/// `GenerationQueueError.waitInsideOpenSubmission`.
public let nestedGenerationRefusedCheckName = "nestedGenerationRefused"

/// The label of the check that grades the refusal of the nested call as at
/// once: it came while the outer submission still held the model, and with
/// no job queued behind that submission.
public let nestedRefusalAtOnceCheckName = "nestedRefusalAtOnce"

/// Both spellings of one integer a model may write in prose: the bare digits
/// and the locale's grouped form (`41,739`).
///
/// A grounded answer is graded on the value it carries, never on how the model
/// chose to punctuate it, so every scenario whose distinctive fixture value is
/// a number offers both candidates to `answerContainsOneOf`. Observed on real
/// hardware: a background run collected the backgrounded scan correctly and answered
/// "exactly **41,739**" — the right value, spelled the way prose spells it —
/// and was failed by an assertion that only accepted `41739`.
///
/// - Parameter value: the fixture value the answer must carry.
/// - Returns: the candidate substrings for `answerContainsOneOf`.
public func integerAnswers(for value: Int) -> [String] {
    ["\(value)", value.formatted(.number.grouping(.automatic))]
}

/// Everything one native scenario run produced that its verdict is graded on.
///
/// Three signals, three different questions, deliberately kept apart: the typed
/// paths are what the model *wrote* into its snippets, read off the transcript;
/// the invoked paths are what a fixture tool actually *entered*; the returned
/// paths are what handed a value back. Only the first was ever measured, and it
/// answered the other two wrongly (task `0981ar3`).
///
/// Distinct from `ScenarioObservation`, which the failure-mode instrument
/// reads: that record carries `isValidAnswer`, which is read *off* this
/// verdict, so the verdict cannot take it as input.
public struct ScenarioEvidence {
    /// The model's final reply.
    public let answer: String

    /// The `tools.*` paths the run's `runCode` snippets wrote — `NativeTranscript.typedToolPaths(in:)`.
    ///
    /// Reported in the grounding condition's failure message, and never graded
    /// on: a path the model merely typed never ran.
    public let typedPaths: Set<String>

    /// The `tools.*` paths a fixture tool entered — `ScenarioCallLog.invokedPaths`.
    ///
    /// Reported in the grounding condition's failure message, and never graded
    /// on: a call that entered and then threw handed the snippet an error
    /// rather than data.
    public let invokedPaths: Set<String>

    /// The `tools.*` paths whose call handed a value back — `ScenarioCallLog.returnedPaths`.
    public let returnedPaths: Set<String>

    /// Records what one native scenario run produced.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - answer: the model's final reply.
    ///   - typedPaths: the `tools.*` paths the run's snippets wrote.
    ///   - invokedPaths: the `tools.*` paths a fixture tool entered.
    ///   - returnedPaths: the `tools.*` paths whose call handed a value back.
    public init(
        answer: String,
        typedPaths: Set<String>,
        invokedPaths: Set<String>,
        returnedPaths: Set<String>
    ) {
        self.answer = answer
        self.typedPaths = typedPaths
        self.invokedPaths = invokedPaths
        self.returnedPaths = returnedPaths
    }
}

/// Grades one native scenario run into the conditions its verdict is the
/// conjunction of.
///
/// Separate from the run that produced the evidence so the grading rule is
/// checkable without live inference: `ScenarioGradingTests` grades evidence
/// built from real fixture calls and asserts which conditions hold, so the
/// gated `SCENARIO` line rests on a rule that has itself been tested. The rule
/// this replaced was checkable only by reading a gated run's output, and it
/// passed a recorded run whose answer nothing it fetched could support (task
/// `0981ar3`).
///
/// - Parameters:
///   - evidence: what the run produced.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     reply must contain case-insensitively.
///   - answerMustNotContain: substrings whose case-insensitive presence
///     invalidates the reply even when a required substring matched.
///   - readingContainsOneOf: candidate substrings for the reading the reply
///     must also state, at least one of which it must contain
///     case-insensitively. An empty list adds no check rather than a
///     vacuously true one.
///   - groundedIn: the `tools.*` paths whose returns this scenario's answer
///     depends on. Must not be empty: an empty declaration would grade every
///     run as grounded, including one that called nothing.
/// - Returns: every condition this run is graded on, in reporting order.
public func scenarioChecks(
    for evidence: ScenarioEvidence,
    answerContainsOneOf: [String],
    answerMustNotContain: [String],
    readingContainsOneOf: [String],
    groundedIn: Set<String>
) -> [ScenarioCheck] {
    precondition(
        !groundedIn.isEmpty,
        """
        a scenario must declare the tools.* returns its answer depends on; an empty declaration grades \
        every run as grounded, including one that called nothing
        """
    )
    var checks = answerChecks(
        evidence.answer,
        containsOneOf: answerContainsOneOf,
        mustNotContain: answerMustNotContain
    )
    if !readingContainsOneOf.isEmpty {
        checks.append(
            ScenarioCheck(
                name: readingReportedCheckName,
                held: readingContainsOneOf.contains { evidence.answer.localizedCaseInsensitiveContains($0) },
                failureMessage:
                    "expected the answer to state the reading, one of \(readingContainsOneOf), "
                    + "got \"\(evidence.answer)\""
            )
        )
    }
    checks.append(
        ScenarioCheck(
            name: groundedCheckName,
            // Containment, not emptiness: the question is whether the values
            // this answer depends on were fetched, not whether anything came
            // back at all. The rule this replaced asked the second question
            // and passed a run that held the itinerary and named the warmest
            // city off it.
            held: groundedIn.isSubset(of: evidence.returnedPaths),
            failureMessage:
                "expected the answer to be grounded in what \(groundedIn.sorted()) returned, but only "
                + "\(evidence.returnedPaths.sorted()) returned (\(evidence.invokedPaths.sorted()) were "
                + "invoked at all, and the snippets wrote \(evidence.typedPaths.sorted()))"
        )
    )
    return checks
}

/// Grades one scenario's reply as a valid answer: it carries at least one
/// required substring, and none of the phrasings that would invalidate it.
///
/// - Parameters:
///   - answer: the model's final reply.
///   - containsOneOf: candidate substrings, at least one of which `answer`
///     must contain case-insensitively.
///   - mustNotContain: substrings whose case-insensitive presence invalidates
///     `answer` even when a required substring matched. An empty list adds no
///     check rather than a vacuously true one.
/// - Returns: the answer-content checks, ready to extend with the scenario's
///   own.
public func answerChecks(
    _ answer: String,
    containsOneOf: [String],
    mustNotContain: [String]
) -> [ScenarioCheck] {
    var checks = [
        ScenarioCheck(
            name: validAnswerCheckName,
            held: containsOneOf.contains { answer.localizedCaseInsensitiveContains($0) },
            failureMessage: "expected the answer to contain one of \(containsOneOf), got \"\(answer)\""
        )
    ]
    let invalidating = mustNotContain.filter { answer.localizedCaseInsensitiveContains($0) }
    if !mustNotContain.isEmpty {
        checks.append(
            ScenarioCheck(
                name: answerNotInvalidatedCheckName,
                held: invalidating.isEmpty,
                failureMessage: "the answer contains \(invalidating), which invalidates it: \"\(answer)\""
            )
        )
    }
    return checks
}

/// Everything one mail collection canary run produced that its verdict is
/// graded on.
///
/// The canary asks one question: when the model ends its answer while its
/// background run is still going, does the settled run come back to the
/// session as mail, and does the model answer from it? No `wait` tool is
/// mounted, so mail is the only path a result has to the model after its
/// answer ends (Router `generation-queue.md` §5.5 rule 1).
///
/// Collected into one value so `mailCollectionChecks(for:answerContainsOneOf:
/// groundedIn:)` grades a record rather than five loose arguments, and so the
/// printed line and the assertions read the same record.
///
/// Built from plain values a test can write down, which is what lets
/// `ScenarioGradingTests` grade a run and its inverse without live
/// inference — the canary's whole worth is in which conditions fire, and a
/// rule only a 30GB model can exercise is a rule that rots.
public struct MailCollectionEvidence {
    /// The reply of the last answer — the answer that mail started, when one
    /// ran.
    public let answer: String

    /// The `tools.*` paths a fixture tool handed a value back from.
    public let returnedPaths: Set<String>

    /// How many tool outputs of the turn were exactly the rendered pending
    /// envelope — the outputs Router's own `PendingRunEnvelope.isRendered`
    /// recognizes.
    ///
    /// A count and not the outputs themselves, for the reason
    /// ``backgroundRunsAtLastAnswer`` gives: the recognizer is Router's, and
    /// the verdict reads only how many outputs it accepted.
    public let pendingEnvelopes: Int

    /// How many answers mail alone started: the answers whose first
    /// submission reports `SubmissionStart.cause == .mail`.
    public let mailAnswers: Int

    /// The tools owning the runs still going at the instant the last answer
    /// ended.
    ///
    /// The owning tools' names rather than the `BackgroundRun` rows themselves, for
    /// the reason `ScenarioEvidence` carries paths: a `BackgroundRun` is Router's
    /// own type — its spelling, for the row this package calls a background run
    /// — and its memberwise initializer is internal to that module, so a record
    /// built from rows could be graded only by a live run. The name is all the
    /// verdict and the diagnostic line ever read.
    public let backgroundRunsAtLastAnswer: [String]

    /// Records what one mail collection canary run produced.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - answer: the reply of the last answer.
    ///   - returnedPaths: the `tools.*` paths a fixture tool handed a value back from.
    ///   - pendingEnvelopes: how many tool outputs of the turn were the
    ///     rendered pending envelope.
    ///   - mailAnswers: how many answers mail alone started.
    ///   - backgroundRunsAtLastAnswer: the tools owning the runs still going
    ///     at the instant the last answer ended.
    public init(
        answer: String,
        returnedPaths: Set<String>,
        pendingEnvelopes: Int,
        mailAnswers: Int,
        backgroundRunsAtLastAnswer: [String]
    ) {
        self.answer = answer
        self.returnedPaths = returnedPaths
        self.pendingEnvelopes = pendingEnvelopes
        self.mailAnswers = mailAnswers
        self.backgroundRunsAtLastAnswer = backgroundRunsAtLastAnswer
    }
}

/// Grades one mail collection canary run into the conditions its verdict is
/// the conjunction of.
///
/// `mailCollection` is the canary proper, and its failure message says what a
/// failure means rather than only what was expected, because that reading is
/// the whole reason the scenario is run. `pendingEnvelope` grades the handle
/// the model got first: some `runCode` output of the turn was exactly the
/// rendered pending envelope. The background-in-code-mode scenario graded that
/// condition until card `^3vtvrzg` merged it into the canary. The other three
/// keep the canary from asserting that nothing happened: the answer must be a
/// valid one, grounded in the fixture's own return, with no background run
/// left when the last answer ended.
///
/// - Parameters:
///   - evidence: what the run produced.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     reply must contain case-insensitively.
///   - groundedIn: the `tools.*` paths whose returns the answer depends on.
/// - Returns: every condition this run is graded on, in reporting order.
public func mailCollectionChecks(
    for evidence: MailCollectionEvidence,
    answerContainsOneOf: [String],
    groundedIn: Set<String>
) -> [ScenarioCheck] {
    var checks = answerChecks(evidence.answer, containsOneOf: answerContainsOneOf, mustNotContain: [])
    checks.append(
        ScenarioCheck(
            name: groundedCheckName,
            held: groundedIn.isSubset(of: evidence.returnedPaths),
            failureMessage:
                "expected the answer to be grounded in what \(groundedIn.sorted()) returned, but "
                + "only \(evidence.returnedPaths.sorted()) returned"
        )
    )
    checks.append(
        ScenarioCheck(
            name: pendingEnvelopeCheckName,
            held: evidence.pendingEnvelopes > 0,
            failureMessage:
                "expected at least one runCode call to go to the background and return a pending "
                + "envelope, but no tool output of the turn was the rendered envelope"
        )
    )
    checks.append(
        ScenarioCheck(
            name: mailCollectionCheckName,
            held: evidence.mailAnswers > 0,
            failureMessage:
                "expected the settled background run to come back to the session as mail and to "
                + "start an answer, but no answer started from mail. The model possibly held its "
                + "answer open until the run settled, which holds the model for every session on "
                + "it (Router `generation-queue.md` §5.5), or the run settled inside the inline "
                + "settle grace and needed no mail"
        )
    )
    checks.append(
        ScenarioCheck(
            name: noBackgroundRunsAtLastAnswerCheckName,
            held: evidence.backgroundRunsAtLastAnswer.isEmpty,
            failureMessage:
                "expected no background run when the last answer ended, but "
                + "\(evidence.backgroundRunsAtLastAnswer) were still running"
        )
    )
    return checks
}

/// What the generation queue of the model read at the instant the nested call
/// of the nested-generation probe got the refusal.
///
/// The probe grades the order of events, and never a time (card `^kdtrmhv`:
/// no test checks the speed of the machine). A refusal at once comes while the
/// outer submission still runs on the queue, and before any job waits behind
/// it: the queue throws before it queues anything. A nested call that the
/// queue takes waits behind the outer submission, which cannot end while its
/// own tool body waits. That is the old defect, and the hang guard of the
/// probe suite reports it.
///
/// Plain values, for `MailCollectionEvidence`'s reason: the grading rule is
/// then exercised without live inference.
public struct GenerationQueueReading: Equatable, Sendable {
    /// Whether a job ran on the queue: the outer submission still held the
    /// model.
    public let isRunning: Bool

    /// How many jobs waited behind the running job.
    public let waitingCount: Int

    /// Records one reading of the queue.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - isRunning: whether a job ran on the queue.
    ///   - waitingCount: how many jobs waited behind the running job.
    public init(isRunning: Bool, waitingCount: Int) {
        self.isRunning = isRunning
        self.waitingCount = waitingCount
    }
}

/// How the nested call of the nested-generation probe ended.
///
/// Router refuses a `respond` on a model from inside an open submission of the
/// same model, with `GenerationQueueError.waitInsideOpenSubmission(model:)`.
/// The probe tool records which of these three ends its nested call got. A
/// nested call that hangs records nothing, and the hang guard of the probe
/// suite reports it.
public enum NestedGenerationOutcome: Equatable, Sendable {
    /// Router refused the nested call with `waitInsideOpenSubmission`. The
    /// value is what the generation queue of the model read at that instant,
    /// or `nil` when the backend of the model names no generation queue.
    case refused(queueAtRefusal: GenerationQueueReading?)

    /// The nested call came back with a reply. Router did not refuse it.
    case returned

    /// The nested call threw an error that is not the refusal.
    case threw(description: String)
}

/// Everything one nested-generation probe run produced that its verdict is
/// graded on.
///
/// Two different questions. `enteredPaths` says the probe measured anything at
/// all — a model that never called the tool leaves a run with nothing in it,
/// and that must fail rather than pass vacuously. `outcome` says how the nested
/// call ended, which is the whole subject.
///
/// Plain values a test can write down, for `MailCollectionEvidence`'s reason:
/// the grading rule is then exercised without live inference.
public struct NestedGenerationEvidence {
    /// The model's final reply.
    public let answer: String

    /// The `tools.*` paths a fixture tool entered, recorded on the way in —
    /// `ScenarioCallLog.enteredPaths`, never `invokedPaths`.
    public let enteredPaths: Set<String>

    /// How the nested call ended, or `nil` when no nested call ended.
    public let outcome: NestedGenerationOutcome?

    /// Records what one nested-generation probe run produced.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - answer: the model's final reply.
    ///   - enteredPaths: the `tools.*` paths a fixture tool entered.
    ///   - outcome: how the nested call ended, or `nil` when none ended.
    public init(answer: String, enteredPaths: Set<String>, outcome: NestedGenerationOutcome?) {
        self.answer = answer
        self.enteredPaths = enteredPaths
        self.outcome = outcome
    }
}

/// Grades one nested-generation probe run into the conditions its verdict is
/// the conjunction of.
///
/// The probe passes when the nested call was entered, got
/// `waitInsideOpenSubmission`, and got it at once: the order of events, and
/// never a real-time bound (card `^kdtrmhv`: no test checks the speed of the
/// machine).
///
/// - Parameter evidence: what the run produced.
/// - Returns: every condition this run is graded on, in reporting order.
public func nestedGenerationChecks(for evidence: NestedGenerationEvidence) -> [ScenarioCheck] {
    let path = integrationNestedGenerationPath
    let outcomeDescription = evidence.outcome?.failureDescription ?? noNestedOutcomeDescription
    return [
        ScenarioCheck(
            name: nestedCallEnteredCheckName,
            held: evidence.enteredPaths.contains(path),
            failureMessage:
                "expected the model to call `\(path)`, the one tool mounted, but it called nothing "
                + "— so this run made no nested call, and says nothing about the refusal. Read the "
                + "CALL lines: a run with none is a prompt problem, not a verdict"
        ),
        ScenarioCheck(
            name: nestedGenerationRefusedCheckName,
            held: evidence.outcome?.isRefusal ?? false,
            failureMessage:
                "expected the nested `respond` inside `\(path)` to get "
                + "`GenerationQueueError.waitInsideOpenSubmission`, but it ended as \(outcomeDescription)"
        ),
        ScenarioCheck(
            name: nestedRefusalAtOnceCheckName,
            held: evidence.outcome?.isRefusalAtOnce ?? false,
            failureMessage:
                "expected the refusal at once — while the outer submission still held the model "
                + "(running=true) and with no job queued behind it (waiting=0) — but the nested call "
                + "ended as \(outcomeDescription)"
        ),
    ]
}

extension NestedGenerationOutcome {
    /// Whether Router refused the nested call with `waitInsideOpenSubmission`.
    var isRefusal: Bool {
        guard case .refused = self else { return false }
        return true
    }

    /// Whether Router refused the nested call at once: the queue read at the
    /// refusal shows the outer submission still running, and no job waiting
    /// behind it.
    var isRefusalAtOnce: Bool {
        guard case .refused(let queue?) = self else { return false }
        return queue.isRunning && queue.waitingCount == 0
    }

    /// Says how the nested call ended, for a failure message.
    var failureDescription: String {
        switch self {
        case .refused(let queue?):
            "a refusal while the queue read running=\(queue.isRunning) waiting=\(queue.waitingCount)"
        case .refused(nil):
            "a refusal, but the backend of the model names no generation queue, so the order of "
                + "events is not known"
        case .returned:
            "a reply: Router did not refuse the nested call on the same model"
        case .threw(let description):
            "a different error: \(description)"
        }
    }
}

/// What a failure message says when no nested call ended.
private let noNestedOutcomeDescription = "nothing: no nested call ended"
