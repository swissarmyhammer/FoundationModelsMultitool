import Foundation
import Testing

import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool
@testable import multitool_cli

/// Runs one gated scenario end to end against a freshly-resolved live
/// profile, using the *native* `LanguageModelSession`-driven design — no
/// `MultiToolAgent`, no `TurnFormat`, no hand-rolled turn parsing. Builds a
/// real `MLXLanguageModel` over the resolved `.standard` slot via
/// `CLIRunner.makeMLXLanguageModel(for:)` (the exact production wiring
/// `multitool-cli` itself uses — never a reimplementation of it), registers
/// `multiTool` and `searchToolsTool` (the latter backed by the resolved
/// `.flash` slot, mirroring the "librarian on flash" split) directly with a
/// `LanguageModelSession`, and lets Apple's own native tool-calling loop
/// decide when to call each.
///
/// **Outcome over path.** A scenario passes when the model produces a
/// *valid, grounded answer* — not when it takes the exact route we
/// predicted. Empirically (recorded on task `k4mj1gm`), asserting on the
/// route failed in both directions: a run once *passed* the compose
/// scenario while answering "there are no cities on your trip" (approved
/// path, wrong answer), and another *failed* it while answering "NYC, 31°C"
/// (correct grounded answer, unapproved path). So what is asserted is exactly
/// this:
///
/// 1. **The answer is valid** — the reply contains at least one of
///    `answerContainsOneOf`, chosen per scenario to match the fixtures'
///    distinctive values (e.g. the weather fixture's own reading for the city
///    scenario 1 asks about, and the single warmest trip city), so a
///    hallucinated answer cannot match; and none of `answerMustNotContain`,
///    the phrasings that invalidate a reply that otherwise matched.
/// 2. **The answer is grounded in what it depends on** — every `tools.*` path
///    the scenario declares in `groundedIn` handed a value back, as the tool
///    itself recorded in the run's `ScenarioCallLog`.
///
///    Per scenario, because "grounded" is a question about the answer that
///    scenario asks for. "Which trip city is warmest" depends on a temperature
///    reading, so a run that fetched only the itinerary and then named a city
///    answered by luck — and a recorded discovery run that did exactly that
///    scored `grounded=pass` back when the check asked only whether *some*
///    fixture call had returned (task `0981ar3`). The declarations live in
///    `IntegrationScenarioGrounding`, beside the readings they are about.
///
///    Declared paths must have *returned*, not merely been invoked: a call
///    that entered and then threw handed the snippet an error rather than
///    data. That is also how a claimed side effect is graded — "your booking
///    is confirmed" is true only if `confirmBooking` handed a confirmation
///    back, and that fixture throws instead of confirming when `confirm` is
///    not `true`, so the repair scenario declares that path and needs nothing
///    further. Read off the recorder rather than off the snippet source,
///    because the source says only what the model typed: a run whose two
///    `tools.*` call sites named functions no fixture defined once scored
///    `grounded=pass` while both calls threw and nothing ran (the same task).
///
///    A containment check, never an equality: which *other* functions ran, in
///    what order, across how many calls stays deliberately unasserted.
///
/// The old route assertions (searchTools-before-runCode ordering, exact
/// invoked-path sets, exact selection-tier picks, call-count budgets) are
/// printed as diagnostics on the `RESULT` line instead, so runs remain
/// comparable without gating on them.
///
/// **Per-scenario measurement.** Every condition above is collected as a
/// `ScenarioCheck` — by `scenarioChecks(for:answerContainsOneOf:
/// answerMustNotContain:groundedIn:)`, which is where the grading rule itself
/// is exercised ungated — before any of them is asserted, so a run reports its
/// own verdict on a `SCENARIO` line. See `grade(scenario:checks:)` for why
/// suite totals alone are not enough.
///
/// **Skip, not failure.** Mirrors the retired `runIntegrationScenario` this
/// supersedes: if resolving the profile or running the session throws
/// `GenerationError.notWiredForLiveInference`, this prints a note and returns
/// *without recording any issue* — Swift Testing reports a test with no
/// recorded issues as passed, so the suite stays green rather than failing
/// when live inference isn't wired up in this environment. Any other error
/// propagates as an ordinary test failure — real signal once a caller has
/// opted in via `MULTITOOL_INTEGRATION` on capable hardware.
///
/// - Parameters:
///   - name: a short label identifying the scenario, used only in the
///     printed result/skip line.
///   - makeTools: builds the scenario's fixed tool set around the run's own
///     call log. A builder rather than a ready-made array so exactly one
///     fresh log exists per run and no call site can hand the tools a
///     different log than this runner reads back.
///   - prompt: the user request driving `session.respond(to:)`.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     final reply must contain (case-insensitively) to count as a valid
///     answer. Pick values a hallucinating model cannot guess — the
///     fixtures' own distinctive data.
///   - answerMustNotContain: substrings whose (case-insensitive) presence
///     invalidates the answer even when a required substring matched —
///     guards required words that also appear inside failure phrasings
///     ("unable to confirm" contains "confirm"). Empty by default.
///   - groundedIn: the `tools.*` paths whose *returns* this scenario's answer
///     depends on — see `IntegrationScenarioGrounding`, which declares one set
///     per scenario question. Required rather than defaulted, and required to
///     be non-empty, because a scenario that declares nothing would grade
///     every run as grounded, including one that called nothing at all.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`
///   — including a failed `#expect` (Swift Testing turns a failed
///   expectation into a recorded issue, not a thrown error, so this
///   signature only actually throws for genuine setup/dispatch failures).
func runNativeIntegrationScenario(
    name: String,
    tools makeTools: (ScenarioCallLog) -> [any Tool],
    prompt: String,
    answerContainsOneOf: [String],
    answerMustNotContain: [String] = [],
    groundedIn: Set<String>
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        // One fresh log per run, minted here and never shared: the tools this
        // scenario mounts record into it, so nothing another scenario did can
        // be read back below.
        let log = ScenarioCallLog()
        let mlxModel = CLIRunner.makeMLXLanguageModel(for: fixture.profile.standard)
        let surface = try makeScenarioSurface(over: makeTools(log), on: fixture)
        // No instructions. Mounting the two tools is the whole product surface, so
        // the suite exercises exactly that: their descriptions carry the contract,
        // and a session instruction would be a harness-side assist a real host
        // never has to supply.
        let session = LanguageModelSession(
            model: mlxModel,
            tools: surface.tools
        )

        let start = Date()
        // Explicitly typed to pin the native FoundationModels API over
        // `FoundationModelsRanker`'s shadowing `respond(to:) -> String`
        // `AgentSession` extension.
        let response: LanguageModelSession.Response<String> = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let transcript = session.transcript
        let evidence = ScenarioEvidence(
            answer: response.content,
            typedPaths: NativeTranscript.typedToolPaths(in: transcript),
            invokedPaths: await log.invokedPaths,
            returnedPaths: await log.returnedPaths
        )
        let checks = scenarioChecks(
            for: evidence,
            answerContainsOneOf: answerContainsOneOf,
            answerMustNotContain: answerMustNotContain,
            groundedIn: groundedIn
        )
        grade(scenario: name, checks: checks)

        let toolCallCount = NativeTranscript.toolCallCount(in: transcript)
        let searchToolsFirst = NativeTranscript.searchToolsPrecedesRunCode(in: transcript)
        // plan.md acceptance: "the per-format results are recorded (test
        // attachment or log)" — the route details stay visible here as
        // diagnostics (see also `PrefixReuseTests` for the prefix-reuse
        // measurement's own recorded evidence), they just no longer gate.
        //
        // All three path signals are printed, not just the graded one: a run
        // where `typed` names paths `invoked` does not is precisely the shape
        // that used to pass silently, and the line is where a reader sees it.
        // The scenario's declaration is printed beside them, so which of those
        // returns the grade required is readable off the run rather than only
        // off this file.
        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(toolCallCount) "
                + "typed=\(evidence.typedPaths.sorted()) "
                + "invoked=\(evidence.invokedPaths.sorted()) "
                + "returned=\(evidence.returnedPaths.sorted()) "
                + "groundedIn=\(groundedIn.sorted()) "
                + "searchToolsFirst=\(searchToolsFirst) "
                + "reply=\"\(response.content.prefix(80))\""
        )
        // The same run's failure modes, counted. Emitted alongside the
        // `SCENARIO` verdict, never instead of it: nothing below is
        // asserted, and the grade above is unchanged.
        print(
            ScenarioFailureModes(
                ScenarioObservation(
                    reply: response.content,
                    toolCallCount: toolCallCount,
                    typedPaths: evidence.typedPaths,
                    invokedPaths: evidence.invokedPaths,
                    catalogPaths: surface.catalogPaths,
                    searchToolsFirst: searchToolsFirst,
                    returnedValues: NativeTranscript.returnedValues(in: transcript),
                    isValidAnswer: checks.contains { $0.name == validAnswerCheckName && $0.held }
                )
            )
            .line(scenario: name)
        )
    }
}

/// Runs one gated scenario end to end against a *Router-mounted* session, so
/// the scenario's `runCode` calls really can elevate — eventplan.md §
/// "Elevation: waitSeconds and the completion token".
///
/// **Why a second runner exists.** `runNativeIntegrationScenario` builds a
/// bare `LanguageModelSession` over an `MLXLanguageModel`. That session has no
/// elevation mount: `ElevatingTool` is applied only by Router's own
/// per-session tool wiring (`ToolElevation.sessionMounted(tool:sessionID:
/// mailbox:sink:cappedToTokenLimit:)`), so on that path a slow snippet simply
/// blocks and a pending envelope can never appear. This runner vends a real
/// `RoutedSession` through `RoutedLLM.makeSession(instructions:tools:)`
/// instead, which mounts every tool under
/// `ElevationConfiguration.nativeSessionMount` — elevation on, stock clocks —
/// and gives the snippet a live run plane (`status()`, `wait()`, `cancel()`)
/// to collect a parked run through.
///
/// **One turn, not two.** Splitting the scenario into a "start it" turn and a
/// "collect it" turn was tried on real hardware and is worse in both halves: a
/// turn that only asks to start the job gets an announcement and no `runCode`
/// call at all, and a second turn asked to report the result re-scans or
/// invents a code rather than reading the parked run (one run answered the
/// right code in the opening turn and a made-up `8472` in the closing one).
/// The single turn is also the honest unit of the claim — the model receives
/// the pending envelope and still finishes the job it was given.
///
/// **What it asserts.** The same outcome-over-path posture as the native
/// runner, plus the one mechanism this scenario exists to prove:
///
/// 1. **The answer is valid** — the reply carries the fixture's own
///    distinctive value, which reaches the model only through the collected
///    run's terminal `detail` (the capped output tail plus the run
///    identifier, per `MultiTool.terminalEventFields(of:state:)`).
/// 2. **A pending envelope really appeared** — some tool output on the way to
///    that answer was exactly `PendingRunEnvelope.rendered`, checked with
///    Router's own byte-shape recognizer. Which run-plane global the model
///    then reached for, and how many rounds it took, is deliberately
///    unasserted.
///
/// The answer is read off `RoutedSession.streamEvents(to:)` rather than
/// `respond(to:)` because the same stream is what carries the tool outputs the
/// envelope check reads. Every `textDelta` of a turn is accumulated, not just
/// the run of them after the last tool call: the stream derives its events
/// from committed transcript entries, so a turn's `toolCalls` entry can
/// surface after the reply text it preceded, and dropping text on a tool call
/// would throw the answer away.
///
/// **Skip, not failure.** Identical to `runNativeIntegrationScenario`: a
/// `GenerationError.notWiredForLiveInference` prints a note and records no
/// issue.
///
/// - Parameters:
///   - name: a short label identifying the scenario, used only in the
///     printed result/skip line.
///   - makeTools: builds the scenario's fixed tool set around the run's own
///     call log — the same builder shape `runNativeIntegrationScenario`
///     takes, because every fixture tool needs a log to record into.
///   - prompt: the user request driving the session's turn.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     reply must contain (case-insensitively) to count as a valid answer.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runElevationIntegrationScenario(
    name: String,
    tools makeTools: (ScenarioCallLog) -> [any Tool],
    prompt: String,
    answerContainsOneOf: [String]
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        // This runner grades on the collected run's answer and on the pending
        // envelope, and emits no `MODES` line, so nothing reads the log back.
        // It still exists per run because the fixture tools require one, and
        // it is minted here so it cannot outlive this scenario.
        let log = ScenarioCallLog()
        // No instructions, for the same reason as the native runner above: mounting
        // the tools is the whole product surface.
        let session = fixture.profile.standard.makeSession(
            tools: try makeScenarioSurface(over: makeTools(log), on: fixture).tools
        )

        let start = Date()
        let turn = try await streamTurn(of: session, prompt: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let pendingEnvelopes = turn.toolOutputs.filter(PendingRunEnvelope.isRendered)
        var checks = answerChecks(turn.answer, containsOneOf: answerContainsOneOf, mustNotContain: [])
        checks.append(
            ScenarioCheck(
                name: "pendingEnvelope",
                held: !pendingEnvelopes.isEmpty,
                failureMessage:
                    "expected at least one runCode call to elevate and return a pending envelope, but the tool outputs were \(turn.toolOutputs)"
            )
        )
        grade(scenario: name, checks: checks)

        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) "
                + "toolOutputs=\(turn.toolOutputs.count) "
                + "pendingEnvelopes=\(pendingEnvelopes.count) "
                + "reply=\"\(turn.answer.prefix(120))\""
        )
    }
}

/// Everything one streamed turn produced that an elevation scenario grades or
/// reports.
private struct StreamedTurn {
    /// The turn's reply text, every `textDelta` in production order.
    var answer = ""

    /// How many tool calls the model made during the turn.
    var toolCallCount = 0

    /// Each completed tool call's own output text, in completion order.
    var toolOutputs: [String] = []
}

/// Drives one turn of a mounted session and harvests it.
///
/// - Parameters:
///   - session: the mounted session to drive.
///   - prompt: the user request driving this turn.
/// - Returns: the turn's reply, tool-call count, and tool outputs.
/// - Throws: whatever the session's event stream throws.
private func streamTurn(of session: RoutedSession, prompt: String) async throws -> StreamedTurn {
    var turn = StreamedTurn()
    for try await event in await session.streamEvents(to: prompt) {
        switch event {
        case .textDelta(let fragment):
            turn.answer += fragment
        case .toolCall:
            turn.toolCallCount += 1
        case .toolStatus(_, .completed, let summary):
            turn.toolOutputs.append(summary ?? "")
        case .toolStatus, .reasoningDelta, .compaction, .turnEnded:
            break
        }
    }
    return turn
}

/// Both spellings of one integer a model may write in prose: the bare digits
/// and the locale's grouped form (`41,739`).
///
/// A grounded answer is graded on the value it carries, never on how the model
/// chose to punctuate it, so every scenario whose distinctive fixture value is
/// a number offers both candidates to `answerContainsOneOf`. Observed on real
/// hardware: an elevation run collected the parked scan correctly and answered
/// "exactly **41,739**" — the right value, spelled the way prose spells it —
/// and was failed by an assertion that only accepted `41739`.
///
/// - Parameter value: the fixture value the answer must carry.
/// - Returns: the candidate substrings for `answerContainsOneOf`.
func integerAnswers(for value: Int) -> [String] {
    ["\(value)", value.formatted(.number.grouping(.automatic))]
}

// MARK: - Shared scenario plumbing

/// Resolves one live fixture, runs `body` against it, and releases it on every
/// exit path — success, assertion failure, or thrown error.
///
/// A `GenerationError.notWiredForLiveInference` from either the resolution or
/// the body is the typed "no live inference here" signal (plan.md M6.5): it
/// prints a skip note and returns without recording an issue, so the suite
/// stays green on a network/GPU-less box. Every other error propagates.
///
/// - Parameters:
///   - name: the scenario label named in the skip note.
///   - body: the scenario's own work, given the resolved fixture.
/// - Throws: whatever `body` throws, other than
///   `GenerationError.notWiredForLiveInference`.
private func withLiveRouterFixture(
    name: String,
    _ body: (LiveRouterFixture) async throws -> Void
) async throws {
    let fixture: LiveRouterFixture
    do {
        fixture = try await LiveRouterFixture.resolve()
    } catch GenerationError.notWiredForLiveInference {
        printSkipNote(name)
        return
    }

    do {
        try await body(fixture)
        await fixture.tearDown()
    } catch GenerationError.notWiredForLiveInference {
        printSkipNote(name)
        await fixture.tearDown()
    } catch {
        await fixture.tearDown()
        throw error
    }
}

/// The model-facing tool surface one scenario drives, and the catalog
/// behind it.
private struct ScenarioSurface {
    /// The tools to register with the session, in the mount order the
    /// registry itself vends.
    let tools: [any Tool]

    /// Every `tools.*` path the mounted catalog actually defines — what an
    /// invented path is measured against.
    let catalogPaths: Set<String>
}

/// Builds the model-facing tool surface every scenario drives, by asking the
/// registry for it — `MultiTool.Registry.makeSessionTools(librarian:)`, the
/// same call `CLIRunner.runDemo` makes, backed by the resolved `.flash` slot
/// (the "librarian on flash" split the CLI ships).
///
/// Vended rather than assembled here on purpose. Under the suite's intent
/// statement the harness must mount `MultiTool` exactly the way a host does,
/// and mount order is part of what a host receives: hand-building the array
/// would let the suite measure an order the product does not recommend.
///
/// `searchTools`'s sample-snippet generator runs on the **`.standard` slot** —
/// the same model the scenario's own session uses — because the sample is code
/// the model is told to run, so its quality matters more than its cost. This
/// harness is therefore where the nested same-model call is measured, wall
/// clock included.
///
/// Two things that arm established, worth knowing before reading its numbers.
/// A gated n=5 (task `9zk44z6`) graded 13/20, the same value as the arm
/// without it, and the suite's wall clock roughly doubled with one run at
/// 16m35s — every `searchTools` call spawns a nested generation, so a thrashing
/// turn pays it repeatedly. And nothing here yet records whether a sample was
/// returned or whether the model ran it, so an arm measures "the generator is
/// wired" rather than "the sample was used"; a result cannot be attributed to
/// the sample until that diagnostic exists.
///
/// - Parameters:
///   - tools: the scenario's fixed tool set.
///   - fixture: the resolved live fixture whose `.flash` slot backs the
///     selection tier and whose `.standard` slot writes the sample snippet.
/// - Returns: the tools to register with the session, and the catalog paths
///   behind them.
/// - Throws: whatever `MultiTool.Builder.buildRegistry()` or
///   `MultiTool.Registry.makeSessionTools(librarian:sampleGenerator:)` throws.
private func makeScenarioSurface(
    over tools: [any Tool],
    on fixture: LiveRouterFixture
) throws -> ScenarioSurface {
    let registry = try MultiTool.Builder().addTools(tools).buildRegistry()
    return ScenarioSurface(
        tools: try registry.makeSessionTools(
            librarian: fixture.profile.flash,
            sampleGenerator: fixture.profile.standard
        ),
        // Unioned with the sibling paths the sandbox binds itself, so a
        // snippet calling `tools.searchTools` or `tools.runCode` is not
        // graded as having invented a path it can really call (task
        // `bwk7knm`). Read from `MultiTool`, never restated, so the
        // diagnostic and the sandbox cannot disagree about what exists.
        catalogPaths: Set(registry.surface.entries.map(\.path))
            .union(MultiTool.siblingToolPaths)
    )
}

// MARK: - Per-scenario grading and measurement

/// One graded condition in a gated scenario's verdict.
///
/// A scenario's conditions are collected before any of them is asserted, so
/// the same list drives both the recorded expectations and the per-scenario
/// `SCENARIO` line — the verdict a run reports can never drift from the
/// verdict it enforces.
struct ScenarioCheck {
    /// The short label naming this condition on the `SCENARIO` line.
    let name: String

    /// Whether the condition held on this run.
    let held: Bool

    /// What to say when it did not — the scenario label is prefixed by
    /// `grade(scenario:checks:)`.
    let failureMessage: String
}

/// Reports one scenario's verdict, then records an issue for each condition
/// that did not hold.
///
/// The reported line is the point of this function, and it exists because
/// suite totals hid where the failures actually were: across the recorded
/// baseline-versus-HEAD tables (task `tkrdwb8`), three of the four gated
/// scenarios were flat and one moved 5/5 → 2/5, which a total of 12/20
/// against 16/20 does not show. A `SCENARIO` line per scenario per run makes
/// each scenario's pass rate directly greppable out of a run's output, so
/// before-and-after comparisons are per scenario rather than per suite.
///
/// Printed before the expectations are recorded so the line survives however
/// the test then fails.
///
/// - Parameters:
///   - name: the scenario label.
///   - checks: every condition this scenario graded, in reporting order.
private func grade(scenario name: String, checks: [ScenarioCheck]) {
    let result = checks.allSatisfy(\.held) ? "PASS" : "FAIL"
    let breakdown = checks.map { "\($0.name)=\($0.held ? "pass" : "fail")" }.joined(separator: " ")
    print("SCENARIO [\(name)] result=\(result) \(breakdown)")

    for check in checks {
        #expect(check.held, "[\(name)] \(check.failureMessage)")
    }
}

/// The label of the check that grades the reply's *form* — the one
/// `ScenarioFailureModes` reads to tell a wrong-form answer from a right
/// one.
let validAnswerCheckName = "validAnswer"

/// The label of the check that grades the answer as grounded in the returns it
/// depends on.
let groundedCheckName = "grounded"

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
struct ScenarioEvidence {
    /// The model's final reply.
    let answer: String

    /// The `tools.*` paths the run's `runCode` snippets wrote — `NativeTranscript.typedToolPaths(in:)`.
    ///
    /// Reported in the grounding condition's failure message, and never graded
    /// on: a path the model merely typed never ran.
    let typedPaths: Set<String>

    /// The `tools.*` paths a fixture tool entered — `ScenarioCallLog.invokedPaths`.
    ///
    /// Reported in the grounding condition's failure message, and never graded
    /// on: a call that entered and then threw handed the snippet an error
    /// rather than data.
    let invokedPaths: Set<String>

    /// The `tools.*` paths whose call handed a value back — `ScenarioCallLog.returnedPaths`.
    let returnedPaths: Set<String>
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
func scenarioChecks(
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
private func answerChecks(
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
                name: "answerNotInvalidated",
                held: invalidating.isEmpty,
                failureMessage: "the answer contains \(invalidating), which invalidates it: \"\(answer)\""
            )
        )
    }
    return checks
}

/// Prints the standard note for a scenario skipped because this environment
/// has no live-inference path wired up.
///
/// - Parameter name: the scenario label.
private func printSkipNote(_ name: String) {
    print("SKIP [\(name)]: Router's live-inference path is not wired up in this environment.")
}
