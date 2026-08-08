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
/// `multiTool` and `findAPIsTool` (the latter backed by the resolved
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
/// (correct grounded answer, unapproved path). So exactly three things are
/// asserted:
///
/// 1. **The answer is valid** — the reply contains at least one of
///    `answerContainsOneOf`, chosen per scenario to match the fixtures'
///    distinctive values (e.g. the weather fixture's 31°C reading for
///    Austin, and the single warmest trip city), so a hallucinated answer
///    cannot match.
/// 2. **The answer is grounded** — at least one fixture tool genuinely ran
///    and handed a value back to a `runCode` snippet, as that tool itself
///    recorded in the run's `ScenarioCallLog`. Which functions, in what
///    order, across how many calls is deliberately unasserted. Read off the
///    recorder rather than off the snippet source, because the source says
///    only what the model typed: a run whose two `tools.*` call sites named
///    functions no fixture defined once scored `grounded=pass` while both
///    calls threw and nothing ran (task `0981ar3`).
/// 3. **Side effects really happened** — when `mustReturn` is non-empty
///    (the booking scenario), those `tools.*` paths are among the paths that
///    *returned*: claiming "your booking is confirmed" is true only if
///    `confirmBooking` actually handed a confirmation back, and the booking
///    fixture throws rather than confirming when `confirm` is not `true`.
///    This is a containment check, never an equality — extra calls and any
///    ordering are fine.
///
/// The old route assertions (findAPIs-before-runCode ordering, exact
/// invoked-path sets, exact selection-tier picks, call-count budgets) are
/// printed as diagnostics on the `RESULT` line instead, so runs remain
/// comparable without gating on them.
///
/// **Per-scenario measurement.** Every one of those three conditions is
/// collected as a `ScenarioCheck` before any of them is asserted, so a run
/// reports its own verdict on a `SCENARIO` line — see
/// `grade(scenario:checks:)` for why suite totals alone are not enough.
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
///   - mustReturn: `tools.*` paths whose calls must genuinely have returned a
///     value — for scenarios whose valid answer *claims a side effect
///     happened* (booking confirmed). Empty (the default) for pure data-read
///     scenarios, where the answer-content check already proves grounding.
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
    mustReturn: Set<String> = []
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        // One fresh log per run, minted here and never shared: the tools this
        // scenario mounts record into it, so nothing another scenario did can
        // be read back below.
        let log = ScenarioCallLog()
        let mlxModel = CLIRunner.makeMLXLanguageModel(for: fixture.profile.standard)
        let surface = try makeScenarioSurface(over: makeTools(log), on: fixture)
        let session = LanguageModelSession(
            model: mlxModel,
            tools: surface.tools,
            // The production instructions, shared verbatim (see its doc
            // comment) — the suite measures exactly what the CLI ships.
            instructions: CLIRunner.toolUseInstructions
        )

        let start = Date()
        // Explicitly typed to pin the native FoundationModels API over
        // `FoundationModelsRanker`'s shadowing `respond(to:) -> String`
        // `AgentSession` extension.
        let response: LanguageModelSession.Response<String> = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let transcript = session.transcript
        // Three signals, three different questions, deliberately kept apart.
        // `typed` is what the model *wrote* into its snippets, read off the
        // transcript; `invoked` is what a fixture tool actually *entered*;
        // `returned` is what handed a value back. Only the first was ever
        // measured before, and it answered the other two wrongly.
        let typed = NativeTranscript.typedToolPaths(in: transcript)
        let invoked = await log.invokedPaths
        let returned = await log.returnedPaths

        var checks = answerChecks(
            response.content,
            containsOneOf: answerContainsOneOf,
            mustNotContain: answerMustNotContain
        )
        // Grounded answer — produced through the tools surface at all, by any
        // route. Graded on `returned`: a call that threw handed the snippet an
        // error, not data, so it grounds nothing, and a call site the model
        // merely typed never ran at all.
        checks.append(
            ScenarioCheck(
                name: "grounded",
                held: !returned.isEmpty,
                failureMessage:
                    "expected the answer to be grounded in at least one tools.* call that returned a value; "
                    + "the snippets wrote \(typed.sorted()), the fixtures ran \(invoked.sorted()), "
                    + "and none of them returned"
            )
        )
        // Claimed side effects really happened — containment, never equality;
        // extra calls and any ordering are fine. Also graded on `returned`:
        // the booking fixture throws instead of confirming when `confirm` is
        // not `true`, so an invocation alone confirms nothing.
        if !mustReturn.isEmpty {
            checks.append(
                ScenarioCheck(
                    name: "sideEffects",
                    held: mustReturn.isSubset(of: returned),
                    failureMessage:
                        "the answer claims an action that requires \(mustReturn.sorted()) to return, but only "
                        + "\(returned.sorted()) returned (\(invoked.sorted()) were invoked at all)"
                )
            )
        }
        grade(scenario: name, checks: checks)

        let toolCallCount = NativeTranscript.toolCallCount(in: transcript)
        let findAPIsFirst = NativeTranscript.findAPIsPrecedesRunCode(in: transcript)
        // plan.md acceptance: "the per-format results are recorded (test
        // attachment or log)" — the route details stay visible here as
        // diagnostics (see also `PrefixReuseTests` for the prefix-reuse
        // measurement's own recorded evidence), they just no longer gate.
        //
        // All three path signals are printed, not just the graded one: a run
        // where `typed` names paths `invoked` does not is precisely the shape
        // that used to pass silently, and the line is where a reader sees it.
        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(toolCallCount) "
                + "typed=\(typed.sorted()) "
                + "invoked=\(invoked.sorted()) "
                + "returned=\(returned.sorted()) "
                + "findAPIsFirst=\(findAPIsFirst) "
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
                    typedPaths: typed,
                    invokedPaths: invoked,
                    catalogPaths: surface.catalogPaths,
                    findAPIsFirst: findAPIsFirst,
                    returnedValues: NativeTranscript.returnedValues(in: transcript),
                    validAnswer: checks.contains { $0.name == validAnswerCheckName && $0.held }
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
        let session = fixture.profile.standard.makeSession(
            instructions: CLIRunner.toolUseInstructions,
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
/// - Parameters:
///   - tools: the scenario's fixed tool set.
///   - fixture: the resolved live fixture whose `.flash` slot backs the
///     selection tier.
/// - Returns: the tools to register with the session, and the catalog paths
///   behind them.
/// - Throws: whatever `MultiTool.Builder.buildRegistry()` or
///   `MultiTool.Registry.makeSessionTools(librarian:)` throws.
private func makeScenarioSurface(
    over tools: [any Tool],
    on fixture: LiveRouterFixture
) throws -> ScenarioSurface {
    let registry = try MultiTool.Builder().addTools(tools).buildRegistry()
    return ScenarioSurface(
        tools: try registry.makeSessionTools(librarian: fixture.profile.flash),
        catalogPaths: Set(registry.surface.entries.map(\.path))
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
