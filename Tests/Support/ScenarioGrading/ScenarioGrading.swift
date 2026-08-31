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

/// The label of the check that grades the answer as grounded in the returns it
/// depends on.
public let groundedCheckName = "grounded"

/// The label of the check that grades a background `runCode` call as having
/// handed a pending envelope back.
public let pendingEnvelopeCheckName = "pendingEnvelope"

/// The label of the check that grades the model as having collected its own
/// background run in band, with a `wait` call of its own.
public let inBandCollectionCheckName = "inBandCollection"

/// The label of the check that grades no background run as still running at the
/// instant the model's first turn ended.
public let noBackgroundRunsAtAnswerCheckName = "noBackgroundRunsAtAnswer"

/// The label of the check that grades no background run as still running at the
/// instant `respond(to:)` returned.
public let noBackgroundRunsAfterRespondCheckName = "noBackgroundRunsAfterRespond"

/// The label of the check that grades the nested-generation probe's tool as
/// having been entered at all.
public let nestedCallEnteredCheckName = "nestedCallEntered"

/// The label of the check that grades the nested, ungrammared generation as
/// having come back.
public let nestedGenerationReturnedCheckName = "nestedGenerationReturned"

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
///   - groundedIn: the `tools.*` paths whose returns this scenario's answer
///     depends on. Must not be empty: an empty declaration would grade every
///     run as grounded, including one that called nothing.
/// - Returns: every condition this run is graded on, in reporting order.
public func scenarioChecks(
    for evidence: ScenarioEvidence,
    answerContainsOneOf: [String],
    answerMustNotContain: [String],
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

/// Everything one in-band collection canary run produced that its verdict is
/// graded on.
///
/// Collected into one value so `inBandCollectionChecks(for:answerContainsOneOf:
/// groundedIn:)` grades a record rather than five loose arguments, and so the
/// printed line and the assertions read the same record.
///
/// Built from plain values a test can write down, which is what lets
/// `ScenarioGradingTests` grade the recorded gated run and its inverse without
/// live inference — the canary's whole worth is in which conditions fire, and a
/// rule only a 30GB model can exercise is a rule that rots.
public struct InBandCollectionEvidence {
    /// The model's final reply — the last drained turn's, when the drain ran one.
    public let answer: String

    /// The tools owning the runs still going at the instant the model's first
    /// turn ended.
    ///
    /// The owning tools' names rather than the `BackgroundRun` rows themselves, for
    /// the reason `ScenarioEvidence` carries paths: a `BackgroundRun` is Router's
    /// own type — its spelling, for the row this package calls a background run
    /// — and its memberwise initializer is internal to that module, so a record
    /// built from rows could be graded only by a live run. The name is all the
    /// verdict and the diagnostic line ever read.
    public let backgroundRunsAtAnswer: [String]

    /// The tools owning the runs still going when `respond(to:)` returned.
    public let backgroundRunsAfterRespond: [String]

    /// The `tools.*` paths a fixture tool handed a value back from.
    public let returnedPaths: Set<String>

    /// How many `wait` calls the model made — the whole of the in-band
    /// collection surface, so any call at all is the model collecting its own
    /// run and none is something else having collected it.
    public let waitCalls: Int

    /// Records what one in-band collection canary run produced.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - answer: the model's final reply.
    ///   - backgroundRunsAtAnswer: the tools owning the runs still going at the
    ///     instant the model's first turn ended.
    ///   - backgroundRunsAfterRespond: the tools owning the runs still going
    ///     when `respond(to:)` returned.
    ///   - returnedPaths: the `tools.*` paths a fixture tool handed a value back from.
    ///   - waitCalls: how many `wait` calls the model made.
    public init(
        answer: String,
        backgroundRunsAtAnswer: [String],
        backgroundRunsAfterRespond: [String],
        returnedPaths: Set<String>,
        waitCalls: Int
    ) {
        self.answer = answer
        self.backgroundRunsAtAnswer = backgroundRunsAtAnswer
        self.backgroundRunsAfterRespond = backgroundRunsAfterRespond
        self.returnedPaths = returnedPaths
        self.waitCalls = waitCalls
    }
}

/// Grades one in-band collection canary run into the conditions its verdict is
/// the conjunction of.
///
/// Two of them are the canary proper — `inBandCollection` and
/// `noBackgroundRunsAtAnswer` — and their failure messages say what a failure
/// means rather than only what was expected, because that reading is the whole
/// reason the scenario is run. The other three keep the canary from asserting
/// that nothing happened: the answer must be a valid one, grounded in the
/// rebuild's own return, with no background run left on the way out.
///
/// - Parameters:
///   - evidence: what the run produced.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     reply must contain case-insensitively.
///   - groundedIn: the `tools.*` paths whose returns the answer depends on.
/// - Returns: every condition this run is graded on, in reporting order.
public func inBandCollectionChecks(
    for evidence: InBandCollectionEvidence,
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
            name: inBandCollectionCheckName,
            held: evidence.waitCalls > 0,
            failureMessage:
                "expected the model to collect its own background run with a `wait` call — the "
                + "only in-band collector, and the path every host's own tooling advises (Router's "
                + "`^466d38p`) — but it made none. Read `\(noBackgroundRunsAtAnswerCheckName)` "
                + "beside this: if "
                + "that failed too, the turn ended with work in flight and Router's drain is what "
                + "collected it"
        )
    )
    checks.append(
        ScenarioCheck(
            name: noBackgroundRunsAtAnswerCheckName,
            held: evidence.backgroundRunsAtAnswer.isEmpty,
            failureMessage:
                "expected no background run at the instant the model's first turn ended, but "
                + "\(evidence.backgroundRunsAtAnswer) were still running — the turn ended with "
                + "work in flight, so Router's respond drain, not the model, is what collected "
                + "it. That is "
                + "the condition `^466d38p` says no host can reach, so task `^xeqs138`'s question "
                + "reopens: the drain is running for real and nothing in this target covers it. "
                + "Do not relax this check to make the run green"
        )
    )
    checks.append(
        ScenarioCheck(
            name: noBackgroundRunsAfterRespondCheckName,
            held: evidence.backgroundRunsAfterRespond.isEmpty,
            failureMessage:
                "expected no background run when respond returned, but "
                + "\(evidence.backgroundRunsAfterRespond) were still running"
        )
    )
    return checks
}

/// Everything one nested-generation probe run produced that its verdict is
/// graded on.
///
/// Both fields are read off the run's own `ScenarioCallLog`, and they are two
/// different questions. `enteredPaths` says the probe measured anything at all
/// — a model that never called the tool leaves a run with nothing in it, and
/// that must fail rather than pass vacuously. `returnedPaths` says the nested
/// call *came back*, which is the whole subject.
///
/// Plain values a test can write down, for `InBandCollectionEvidence`'s reason:
/// the grading rule is then exercised without live inference.
public struct NestedGenerationEvidence {
    /// The model's final reply.
    public let answer: String

    /// The `tools.*` paths a fixture tool entered, recorded on the way in —
    /// `ScenarioCallLog.enteredPaths`, never `invokedPaths`.
    public let enteredPaths: Set<String>

    /// The `tools.*` paths a fixture tool handed a value back from.
    public let returnedPaths: Set<String>

    /// Records what one nested-generation probe run produced.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameters:
    ///   - answer: the model's final reply.
    ///   - enteredPaths: the `tools.*` paths a fixture tool entered.
    ///   - returnedPaths: the `tools.*` paths a fixture tool handed a value back from.
    public init(answer: String, enteredPaths: Set<String>, returnedPaths: Set<String>) {
        self.answer = answer
        self.enteredPaths = enteredPaths
        self.returnedPaths = returnedPaths
    }
}

/// Grades one nested-generation probe run into the conditions its verdict is
/// the conjunction of.
///
/// - Parameter evidence: what the run produced.
/// - Returns: every condition this run is graded on, in reporting order.
public func nestedGenerationChecks(for evidence: NestedGenerationEvidence) -> [ScenarioCheck] {
    let path = integrationNestedGenerationPath
    return [
        ScenarioCheck(
            name: nestedCallEnteredCheckName,
            held: evidence.enteredPaths.contains(path),
            failureMessage:
                "expected the model to call `\(path)`, the one tool mounted, but it called nothing "
                + "— so this run measured neither a hang nor a return, and says nothing about "
                + "either explanation. Read the CALL lines: a run with none is a prompt problem, "
                + "not a verdict"
        ),
        ScenarioCheck(
            name: nestedGenerationReturnedCheckName,
            held: evidence.returnedPaths.contains(path),
            failureMessage:
                "`\(path)` was entered and handed no value back, so its nested ungrammared "
                + "`respond` did not come back. Read the `GATE` lines to say which way: "
                + "`permits=0 waiters=1` held to the end is the generation-gate deadlock — the "
                + "outer turn holding the permit `beginTurn()` took, the nested `respond` parked "
                + "on `generationGate.wait()` — and it is what the first gated run of this probe "
                + "measured. Any other gate reading means the call threw instead, which is a "
                + "third thing and belongs to neither explanation"
        ),
    ]
}
