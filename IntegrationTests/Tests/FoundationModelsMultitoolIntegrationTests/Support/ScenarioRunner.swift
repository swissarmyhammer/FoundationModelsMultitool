import Foundation
import Testing

import FoundationModels
// `@testable` for one reason, and only the nested-generation probe needs it:
// `RoutedModel.generationGate` and `AsyncSemaphore`'s `availablePermits` /
// `waiterCount` are `internal`, and they are the direct reading of the deadlock
// `runNestedGenerationProbe` exists to name. Router's package is not edited to
// expose them.
@testable import FoundationModelsRouter

/// How a run's seeding state reads on the RESULT line.
///
/// Three states, not two. An earlier version printed `ok` whenever no
/// `discoveryPrimingFailed` event arrived — which is also true when seeding was
/// never requested, so an unprimed run reported `priming=ok` and read as a
/// primed one that worked. That is the exact confusion this field exists to
/// prevent.
///
/// - Parameter turn: the streamed turn to describe.
/// - Returns: `off` when no seeding was requested, `ok` when it ran, or
///   `FAILED(reason)` when Router reported it downgraded.
func primingLabel(_ turn: StreamedTurn) -> String {
    if let failure = turn.discoveryPrimingFailure { return "FAILED(\(failure))" }
    return scenarioDiscoveryPriming == nil ? "off" : "ok"
}

/// Router's pre-discovery seeding opt-in for these scenarios — **off**.
///
/// Seeding runs a real `searchTools` call host-side before the model's first
/// token, so the turn it resumes already holds the discovery call and the typed
/// signatures it returned. RESOLUTION B (task `tkrdwb8`) predicted that would
/// eliminate the turn-with-no-snippet failure, because nothing would be left
/// for the model to decide.
///
/// Measured, it did the opposite. With seeding on, all four scenarios scored
/// **0/4** and none of them wrote a snippet at all (`typed=[] invoked=[]
/// returned=[]`), including `repairFromTripProneTool`, which had passed in
/// every previously recorded run. Its reply was "There are no available tools
/// or functions in this session that can interact with a booking system" —
/// with the seeded discovery call sitting in its own transcript. Unprimed runs
/// of the same suite score 1/4 to 3/4.
///
/// Kept as one named constant rather than deleted: this is the A/B switch, and
/// the two arms differ by this line alone. Set it to
/// `DiscoveryPriming(tool: MultiTool.searchToolsPath, queryProperty:
/// MultiTool.searchToolsTaskField)` to measure the primed arm again.
let scenarioDiscoveryPriming: DiscoveryPriming? = nil
@testable import FoundationModelsMultitool

/// Runs one gated scenario end to end against a freshly-resolved live
/// profile, using the session-driven design — no `MultiToolAgent`, no
/// `TurnFormat`, no hand-rolled turn parsing. Mounts what the registry vends
/// on a `RoutedSession` the resolved `.standard` slot vends
/// (`makeSession(tools:discoveryPriming:)`) — the exact wiring
/// `CLIRunner.runDemo` ships, never a reimplementation of it — with
/// `searchToolsTool` backed by the resolved `.flash` slot, mirroring the
/// "librarian on flash" split, and lets the session's own tool-calling loop
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
/// propagates as an ordinary test failure — real signal once a caller runs
/// this nested `IntegrationTests` package on capable hardware.
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
        let surface = try makeScenarioSurface(over: makeTools(log), on: fixture)
        // No instructions. Mounting the two tools is the whole product surface, so
        // the suite exercises exactly that: their descriptions carry the contract,
        // and a session instruction would be a harness-side assist a real host
        // never has to supply.
        //
        // Vended through Router rather than as a bare `LanguageModelSession`
        // (task `tkrdwb8` step 3). The configuration under test is "MultiTool
        // mounted on a Router", and pre-discovery seeding is a Router session
        // option, so a bare session cannot carry it: these scenarios ran
        // unprimed for as long as they bypassed Router.
        let session = fixture.profile.standard.makeSession(
            tools: surface.tools,
            discoveryPriming: scenarioDiscoveryPriming
        )

        let start = Date()
        // Streaming, drained to completion — and this is not a preference.
        //
        // **On `respond(to:)` the design under test does not exist.** `respond`
        // blocks and drains, so a backgrounded `runCode` is collected before the
        // caller sees it, a `wait` call has nothing left to wait for, and a
        // blocking `searchTools` is indistinguishable from a detaching one. A
        // gated suite driven through `respond` would go green while observing
        // none of the three rules it exists to check: searchTools blocks,
        // runCode always backgrounds, wait joins on a token.
        //
        // `respond` keeps exactly one job in this suite — proving the final
        // answer equals what a drained stream accumulates. Answer parity, and
        // nothing else. Asserted beside groundedness, never instead of it: two
        // surfaces can agree on a wrong answer, and both refusing identically
        // ("I don't have access to real-time weather data") satisfies equality
        // while proving nothing, which is what every recorded run of both
        // surfaces did.
        //
        // Draining also restores the route diagnostics. While this runner used
        // `respond`, four of the seven failure modes were unobservable and the
        // MODES line printed `0` for each — reading as "clean" when it meant
        // "not measured". That is what `routeObservable` exists to prevent.
        let turn = try await streamTurn(of: session, prompt: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let evidence = ScenarioEvidence(
            answer: turn.answer,
            typedPaths: NativeTranscript.typedToolPaths(in: turn.calls),
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

        let toolCallCount = turn.toolCallCount
        let searchedToolsFirst = NativeTranscript.searchToolsPrecedesRunCode(in: turn.calls)
        // plan.md acceptance: "the per-format results are recorded (test
        // attachment or log)" — the route details stay visible here as
        // diagnostics (see also `SelectionForkPerCallTests`, which reads the
        // selection tier's own recorded fork trace the same way), they just no
        // longer gate.
        //
        // All three path signals are printed, not just the graded one: a run
        // where `typed` names paths `invoked` does not is precisely the shape
        // that used to pass silently, and the line is where a reader sees it.
        // The scenario's declaration is printed beside them, so which of those
        // returns the grade required is readable off the run rather than only
        // off this file.
        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) "
                + "turn=\(turn.turnIdentity ?? "n/a") "
                + "typed=\(evidence.typedPaths.sorted()) "
                + "invoked=\(evidence.invokedPaths.sorted()) "
                + "returned=\(evidence.returnedPaths.sorted()) "
                + "groundedIn=\(groundedIn.sorted()) "
                + "searchedToolsFirst=\(searchedToolsFirst) "
                + "priming=\(primingLabel(turn)) "
                + "textResets=\(turn.supersededAnswers.count) "
                + "progress=\(turn.progressEvents.count) "
                + "compactions=\(turn.compactions.count) tokens=\(turn.tokenUsage ?? "n/a") "
                + "failedCalls=\(turn.failedCalls.count)\(turn.failedCalls.isEmpty ? "" : " \(turn.failedCalls)") "
                + "reply=\"\(turn.answer.prefix(80))\""
        )
        // The same run's failure modes, counted. Emitted alongside the
        // `SCENARIO` verdict, never instead of it: nothing below is
        // asserted, and the grade above is unchanged.
        print(
            ScenarioFailureModes(
                ScenarioObservation(
                    reply: turn.answer,
                    toolCallCount: toolCallCount,
                    typedPaths: evidence.typedPaths,
                    invokedPaths: evidence.invokedPaths,
                    catalogPaths: surface.catalogPaths,
                    searchedToolsFirst: searchedToolsFirst,
                    routeObservable: true,
                    returnedValues: NativeTranscript.returnedValues(in: turn.calls),
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
/// **Why a second runner exists — and it is not the session.** Both runners
/// build the same thing: `fixture.profile.standard.makeSession(tools:
/// discoveryPriming:)`, a real `RoutedSession`, which mounts every tool under
/// `DetachConfiguration.nativeSessionMount` — elevation on, stock clocks — and
/// gives the snippet the live background-run globals (`status()`, `wait()`,
/// `cancel()`) to collect a background run through. What differs is what each
/// one grades.
/// `runNativeIntegrationScenario` grades a valid, fixture-grounded answer and
/// reports route diagnostics; this runner grades a valid answer **and** that a
/// pending envelope really appeared, which is the one mechanism it exists to
/// prove.
///
/// It used to be the session. Until `f8964b4` the native runner built a bare
/// `LanguageModelSession` over an `MLXLanguageModel`, which carries no
/// elevation mount at all — `DetachingTool` is applied only by Router's own
/// per-session tool wiring (`ToolDetachment.sessionMounted(tool:sessionID:
/// mailbox:sink:cappedToTokenLimit:)`) — so on that path a slow snippet simply
/// blocked and a pending envelope could never appear. That is history, not the
/// reason this runner is still here.
///
/// **One turn, not two.** Splitting the scenario into a "start it" turn and a
/// "collect it" turn was tried on real hardware and is worse in both halves: a
/// turn that only asks to start the job gets an announcement and no `runCode`
/// call at all, and a second turn asked to report the result re-scans or
/// invents a code rather than reading the background run (one run answered the
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
///    Router's own byte-shape recognizer. Which background-run global the model
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
            tools: try makeScenarioSurface(over: makeTools(log), on: fixture).tools,
            discoveryPriming: scenarioDiscoveryPriming
        )

        let start = Date()
        let turn = try await streamTurn(of: session, prompt: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let pendingEnvelopes = turn.toolOutputs.filter(PendingRunEnvelope.isRendered)
        var checks = answerChecks(turn.answer, containsOneOf: answerContainsOneOf, mustNotContain: [])
        checks.append(
            ScenarioCheck(
                name: pendingEnvelopeCheckName,
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
                + "priming=\(primingLabel(turn)) "
                + "textResets=\(turn.supersededAnswers.count) "
                + "compactions=\(turn.compactions.count) tokens=\(turn.tokenUsage ?? "n/a") "
                + "failedCalls=\(turn.failedCalls.count)\(turn.failedCalls.isEmpty ? "" : " \(turn.failedCalls)") "
                + "reply=\"\(turn.answer.prefix(120))\""
        )
    }
}

/// Everything one streamed turn produced that an elevation scenario grades or
/// reports.
struct StreamedTurn {
    /// The turn's reply text, every `textDelta` in production order.
    var answer = ""

    /// How many tool calls the model made during the turn.
    var toolCallCount = 0

    /// Each completed tool call's own output text, in completion order.
    var toolOutputs: [String] = []

    /// Every tool call the stream reported, in order, with its output attached
    /// once it completed.
    ///
    /// `RoutedSession` publishes no transcript, so this is what the evidence
    /// extractors read instead — see `NativeTranscript.StreamedCall`.
    var calls: [NativeTranscript.StreamedCall] = []

    /// Where each call's `id` sits in ``calls``, so a later status event can
    /// attach its output to the call it belongs to.
    ///
    /// `SessionEvent.toolStatus` carries the call's id, not its name.
    var callIndexByID: [String: Int] = [:]

    /// Each answer superseded by a `.textReset`, oldest first.
    ///
    /// Kept rather than dropped: a turn that restarted its answer is a turn
    /// whose first pass is evidence — it is what the model said before it had
    /// tool output — and a non-empty list is the direct signal that the tool
    /// loop re-entered generation.
    var supersededAnswers: [String] = []

    /// Every compaction the session performed during this turn.
    ///
    /// Non-empty means the turn was rewritten mid-flight; a scored run that
    /// compacted is not measuring the same prompt the scenario set up.
    var compactions: [String] = []

    /// The turn's token usage, as the session reported it — **output only**.
    ///
    /// The input half is not a measurement and must not be read as one. The
    /// fork's `MLXLanguageModel.emitUsage` hands usage to a test-only
    /// `generationObserver` task local and deliberately never calls
    /// `channel.send`, so the whole usage event stops before the framework:
    /// an SDK symbol drift (`Response.Action.updateUsage` declares a
    /// `metadata:` parameter the shipping dylib does not export) made the send
    /// fatal, and it was removed rather than crash every `respond()`. Filed as
    /// `^z2996cp` on `mlx-swift-lm`'s board; it predates Muse Glimmer and is
    /// not reasoning-specific.
    ///
    /// The output count survives because the framework counts the tokens it
    /// receives. The input count only the fork can know, and it never crosses
    /// the boundary — so it arrives as `0`, which reads exactly like a real
    /// measurement of an empty prompt. `contextFill` is suspect for the same
    /// reason if it derives from the input count. Two consumers observed this
    /// independently: `FoundationModelsRouter`'s
    /// `LanguageModelSessionBackendTests` off a completed turn, and this
    /// runner off the stream.
    ///
    /// Rendered by ``usageForDisplay`` rather than printed raw, so a gated
    /// diagnostic never states a number nobody measured.
    var tokenUsage: String?

    /// The turn frame this run's events belong to, as `turnId/promptId`.
    ///
    /// Router reports it once per turn (`^way106d`). `direct` in the prompt
    /// half means the prompt was handed straight to `streamEvents(to:)` rather
    /// than queued — only a queued prompt carries an id to correlate, so this
    /// is the field a queued-prompt test reads to prove its prompt is the one
    /// that ran.
    var turnIdentity: String?

    /// Every progress report a still-running call made, as `name: detail`.
    ///
    /// The direct measure of the product goal: a slow tool must not go silent.
    /// It reports that it is in process and keeps streaming events until it is
    /// done, so a client can show a live view of work it did not have to poll
    /// for. An empty list on a turn that took minutes is the failure this
    /// records.
    ///
    /// Only the streaming surface can carry these. `respond(to:)` is
    /// FoundationModels semantics — one await that blocks until the answer —
    /// so a long tool makes it slower and never makes it chattier.
    var progressEvents: [String] = []

    /// Every tool call the session reported as failed, as `name: detail`.
    ///
    /// Kept because its absence hid a whole class of run: a turn whose calls
    /// all failed produced the same diagnostics as a turn that made none.
    var failedCalls: [String] = []

    /// Why Router's pre-discovery seeding did not run this turn, or `nil` when
    /// it ran (or was never asked for).
    ///
    /// Reported alongside the run's diagnostics: a scored run whose priming
    /// silently failed is not evidence about priming.
    var discoveryPrimingFailure: String?
}

/// How many characters of one call's arguments or output the trace prints.
///
/// Large enough to hold a whole scenario snippet, because a truncated snippet
/// hides the line that failed.
private let scenarioTraceLimit = 600

/// Puts one call's arguments or output on a single greppable line.
///
/// The `RESULT` line reports what a run *scored*. It cannot report why a run
/// scored that: a turn that called `runCode` 19 times, failed no call, and
/// still answered "I am unable to retrieve" prints `typed=[] invoked=[]
/// returned=[]` and says nothing about what the snippets asked for or what came
/// back. This is that missing evidence, so one gated run is enough to find the
/// fault instead of only enough to confirm it.
///
/// - Parameter text: the arguments JSON or output text to show.
/// - Returns: the text on one line, cut to ``scenarioTraceLimit``, with the cut
///   marked so a short trace is never read as a complete one.
private func traceExcerpt(_ text: String) -> String {
    let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ⏎ ")
    guard flattened.count > scenarioTraceLimit else { return flattened }
    return "\(flattened.prefix(scenarioTraceLimit))…[+\(flattened.count - scenarioTraceLimit) more]"
}

/// Drives one turn of a mounted session and harvests it.
///
/// - Parameters:
///   - session: the mounted session to drive.
///   - prompt: the user request driving this turn.
/// - Returns: the turn's reply, tool-call count, and tool outputs.
/// - Throws: whatever the session's event stream throws.
func streamTurn(of session: RoutedSession, prompt: String) async throws -> StreamedTurn {
    var turn = StreamedTurn()
    for try await event in await session.streamEvents(to: prompt) {
        switch event {
        case .generationStalled(let stall):
            // Router reports a stall rather than imposing a timeout
            // (`^z6xcmnh`): a signal a host may act on, never a cancellation.
            // Printed and not asserted, deliberately — a stall is "no token has
            // moved for a while", which on a real model under a hard scenario
            // is ordinary, and a suite that failed on it would be re-imposing
            // the timeout Router declined to impose.
            //
            // It is worth printing because it separates two of the three states
            // a long run can be in — still working, and stuck. It does NOT
            // separate either from the third, a model generating steadily and
            // achieving nothing, which is the shape `^wnfzwxg` records: every
            // token moves, so no stall is ever reported. If a scenario runs
            // long and this line is absent, that is the reading.
            print(
                """
                STALL withoutProgress=\(stall.timeWithoutProgress) \
                inFlight=\(stall.timeInFlight) visibility=\(stall.visibility)
                """
            )
        case .turnStarted(let start):
            // The frame this turn's later events belong to (Router ^way106d).
            // `promptId` is nil here by design: these scenarios hand the prompt
            // straight to `streamEvents(to:)` rather than queueing it, and only
            // a queued prompt has an id to correlate. A queued-prompt test is
            // what reads that field.
            turn.turnIdentity = "\(start.turnId)/\(start.promptId.map { "\($0)" } ?? "direct")"
        case .textDelta(let fragment):
            turn.answer += fragment
        case .textReset:
            // Everything delivered so far is superseded, not retracted: the
            // model produced a first pass, a tool ran, and generation resumed
            // on a fresh answer. Router surfaces this rather than hiding it
            // (^w8dzvee D2), and a consumer that ignores it accumulates
            // "PRETOOL FINAL-ANSWER" where `respond(to:)` returns
            // "FINAL-ANSWER". This suite grades the answer, so it keeps the
            // current one; the superseded text stays in the transcript.
            turn.supersededAnswers.append(turn.answer)
            turn.answer = ""
        case .toolCall(let id, let name, let argumentsJSON):
            turn.toolCallCount += 1
            turn.callIndexByID[id] = turn.calls.count
            turn.calls.append(
                NativeTranscript.StreamedCall(name: name, argumentsJSON: argumentsJSON, output: nil)
            )
            print("CALL [\(turn.toolCallCount)] \(name) args=\(traceExcerpt(argumentsJSON))")
        // `output` carries the call's full segments; this runner grades on
        // the flattened `summary` alone, so it is bound away here.
        case .toolStatus(let id, .completed, let summary, _):
            turn.toolOutputs.append(summary ?? "")
            if let index = turn.callIndexByID[id] {
                turn.calls[index].output = summary
            }
            let name = turn.callIndexByID[id].map { turn.calls[$0].name } ?? "?"
            print("DONE \(name) out=\(traceExcerpt(summary ?? ""))")
        // `output` carries the call's full segments; this runner grades on
        // the flattened `summary` alone, so it is bound away here.
        case .toolStatus(let id, .running, let summary, _):
            // A call reporting progress while it runs. Swallowed by the
            // catch-all until now, which made two very different runs look
            // identical: one where a slow call streamed progress the whole
            // time, and one where it went silent while it ran. The product
            // expectation is the first — a fast call returns inline, a slow one
            // reports "in process" and streams events until it is done — so a
            // run that shows none is evidence, not an absence of evidence.
            let name = turn.callIndexByID[id].map { turn.calls[$0].name } ?? "?"
            turn.progressEvents.append("\(name): \(summary ?? "no detail")")
            print("RUN  \(name) progress=\(traceExcerpt(summary ?? ""))")
        // `output` carries the call's full segments; this runner grades on
        // the flattened `summary` alone, so it is bound away here.
        case .toolStatus(let id, .failed, let summary, _):
            // A call the session could not complete. Previously invisible: the
            // catch-all below swallowed it, so a run where every call failed
            // looked identical to one where the model never called anything —
            // and both read as "the model would not use its tools".
            let name = turn.callIndexByID[id].map { turn.calls[$0].name } ?? "?"
            turn.failedCalls.append("\(name): \(summary ?? "no detail")")
        case .discoveryPrimingFailed(let reason):
            // Seeding is best-effort in Router: a failure downgrades the turn
            // to an unprimed one rather than failing it. Silence here would
            // read as "priming was on and did not help", so it is printed —
            // a run whose priming never happened must not be scored as one
            // that did.
            turn.discoveryPrimingFailure = "\(reason)"
        case .compaction(let result):
            // Swallowed until now, like `.toolStatus(.failed)` was. A turn that
            // compacted mid-flight can lose the tool definitions and the
            // discovery output it is meant to act on, which looks from the
            // outside exactly like a model that will not use its tools.
            turn.compactions.append("\(result)")
        case .turnEnded(let usage):
            // Output only, and the input half relabelled — see `tokenUsage`.
            turn.tokenUsage = usageForDisplay(usage)
        case .toolStatus, .reasoningDelta, .toolInvocation, .entryRecorded:
            // `.toolStatus` here is the residue of the three status cases
            // handled above. `.toolInvocation` carries the open/close record
            // of each call, and `.entryRecorded` announces a transcript entry;
            // both restate what `.toolCall`/`.toolStatus` already gave this
            // runner, which grades a scenario on its calls and its answer.
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
/// hardware: an elevation run collected the backgrounded scan correctly and answered
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
func withLiveRouterFixture(
    name: String,
    profile definition: ProfileDefinition = multitoolTinyProfile,
    _ body: (LiveRouterFixture) async throws -> Void
) async throws {
    let fixture: LiveRouterFixture
    do {
        fixture = try await LiveRouterFixture.resolve(definition)
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
/// **No sample-snippet generator, because the product ships without one.**
/// `makeSessionTools`'s `sampleGenerator:` defaults to `nil` and
/// `CLIRunner.runDemo` passes only `librarian:` (`CLIRunner.swift:390`), so an
/// arm that wires one measures a configuration no host runs.
///
/// It was wired here, and removing it was not a preference. Each generated
/// sample is a nested generation on the `.standard` slot with up to three
/// attempts, so every `searchTools` call paid two large-model generations
/// instead of one. Once discovery stopped detaching — it is a synchronous
/// prerequisite and must never background — that cost stopped being hidden by a
/// thrashing turn and became a hard failure: `DetachingToolError.timedOut(tool:
/// "searchTools", timeoutSeconds: 120.0)`, the whole turn dead in its first
/// call (task `h773bed`).
///
/// The arm was never worth its cost anyway. A gated n=5 (task `9zk44z6`) graded
/// 13/20, the same value as the arm without it, while roughly doubling the
/// suite's wall clock. And nothing recorded whether a sample was returned or
/// whether the model ran one, so it measured "the generator is wired" rather
/// than "the sample helped".
///
/// - Parameters:
///   - tools: the scenario's fixed tool set.
///   - fixture: the resolved live fixture whose `.flash` slot backs the
///     selection tier.
///   - direct: when `true`, apply `registry.directMode()` before the mount,
///     exactly as `CLIRunner.runDemo` does under its `--direct` flag. A
///     direct-mode registry vends `runCode` and `wait` and no `searchTools`,
///     so the scenario pays for no discovery. The `librarian:` argument stays
///     the same in both modes, because the CLI passes it in both modes and
///     this harness must mount what the CLI mounts.
/// - Returns: the tools to register with the session, and the catalog paths
///   behind them.
/// - Throws: whatever `MultiTool.Builder.buildRegistry()` or
///   `MultiTool.Registry.makeSessionTools(librarian:)` throws.
private func makeScenarioSurface(
    over tools: [any Tool],
    on fixture: LiveRouterFixture,
    direct: Bool = false
) throws -> ScenarioSurface {
    var registry = try MultiTool.Builder().addTools(tools).buildRegistry()
    if direct {
        registry = registry.directMode()
    }
    return ScenarioSurface(
        // `librarian:` alone, exactly as `CLIRunner.runDemo` mounts it
        // (`CLIRunner.swift:390`). No `sampleGenerator:` — it defaults to `nil`,
        // so the product ships without one and this harness must too.
        tools: try registry.makeSessionTools(librarian: fixture.profile.flash),
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
func grade(scenario name: String, checks: [ScenarioCheck]) {
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

/// The label of the check that grades the reply as carrying none of the
/// phrasings that invalidate it, even when a required substring matched.
let answerNotInvalidatedCheckName = "answerNotInvalidated"

/// The label of the check that grades the answer as grounded in the returns it
/// depends on.
let groundedCheckName = "grounded"

/// The label of the check that grades an elevated `runCode` call as having
/// handed a pending envelope back.
let pendingEnvelopeCheckName = "pendingEnvelope"

/// The label of the check that grades the model as having collected its own
/// background run in band, with a `wait` call of its own.
let inBandCollectionCheckName = "inBandCollection"

/// The label of the check that grades no background run as still running at the
/// instant the model's first turn ended.
let noBackgroundRunsAtAnswerCheckName = "noBackgroundRunsAtAnswer"

/// The label of the check that grades no background run as still running at the
/// instant `respond(to:)` returned.
let noBackgroundRunsAfterRespondCheckName = "noBackgroundRunsAfterRespond"

/// The label of the check that grades the nested-generation probe's tool as
/// having been entered at all.
let nestedCallEnteredCheckName = "nestedCallEntered"

/// The label of the check that grades the nested, ungrammared generation as
/// having come back.
let nestedGenerationReturnedCheckName = "nestedGenerationReturned"

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
                name: answerNotInvalidatedCheckName,
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

/// Drives one scenario through **both** surfaces and holds `respond(to:)` to
/// the rule that it must self-drain its own background runs (task `^n6kgckr`).
///
/// Now that `runCode` always backgrounds (`^cv98vff`), a tool call no longer
/// returns data on any surface — it returns a reference to work still running.
/// On streaming that is the feature. On `respond` it must be **invisible**:
/// the same final answer, just slower. A `respond` that returned while its own
/// turn's runs were still running would hand the model a token and nothing
/// else, which is exactly the measured failure this whole plan exists to end
/// (`invoked=[] returned=[]`, "I don't have access to real-time weather
/// data").
///
/// Four things are asserted, and the first two must both hold or the run
/// proves nothing:
///
/// 1. **Grounded.** The answer depends on what a fixture tool actually
///    returned, read off the run's own call log rather than off the reply.
/// 2. **Parity with a drained stream.** The same scenario through
///    `streamEvents` reaches the same answer.
/// 3. **Nothing left running.** After `respond` returns, the session holds no
///    background run. A dangling token means the drain is incomplete even if
///    the answer happened to be right.
/// 4. **`wait` calls, reported.** Not asserted — see below.
///
/// **What this scenario does not isolate, and a later reader must not assume
/// it does.** `backgroundRuns=0` on return is necessary but not sufficient
/// evidence that `respond` drained anything. There are two ways a backgrounded
/// run gets collected on this surface, and both end with no background run
/// left:
///
/// - the model collects it in-band, because the pending envelope instructs it
///   to (its `next` sentence, `MultiTool.detachmentCollectInstruction(forCompletionToken:)`:
///   "Call the wait tool with completionToken ...");
/// - the turn ends with runs still going, and `respond`'s drain settles them.
///
/// Measured on real hardware, the first happens: `waitCalls=2`. So this
/// scenario proves the *surface* is sound — grounded answer, parity with
/// streaming, nothing left running — while leaving Router's drain itself
/// unexercised, because the model left it nothing to do.
///
/// **No scenario here isolates the drain, and none can.** Isolating it needs a
/// turn that ends with something still running, and Router's `^466d38p` (their
/// commit `b4c0282`) says no host can produce one: every background run hands
/// the model a `PendingRunEnvelope` telling it to collect that run with a
/// `wait` call before it answers, and there is no background run without that
/// instruction. The scenario
/// written to try — task `^xeqs138` — measured the opposite and was inverted
/// into `runInBandCollectionCanaryScenario`, which now watches for the condition
/// becoming reachable. Cite no suite in this target for "the drain works".
///
/// **Router's drain rule, which this scenario is written against.** `respond`
/// runs its own turn, then snapshots **every** run still going on the session —
/// not only the ones its own turn started — waits for all of them to settle,
/// and runs one more ordinary turn carrying their results. It repeats, so a
/// run started from inside a drained turn is drained too, bounded at four
/// continuation turns (`RoutedSessionActor.parkedRunDrainRoundLimit`): one
/// `respond` costs at most five model turns.
///
/// Two consequences for a scenario written here. A prompt whose answer needs
/// more than four continuation turns fails for a reason that is not a drain
/// defect, so keep scenarios inside that budget. And a cancelled turn is never
/// drained: whatever it started keeps running, because ending a background run
/// is `close()`'s job rather than cancellation's. A cancelling scenario is
/// therefore asserting about `close()`, not about this rule. Nothing here
/// cancels.
///
/// A cancelling scenario *is* now possible, which it was not when this runner
/// was written: Router closed `^h3efdrc`, so a `respond` parked inside its
/// drain can be stopped by either route, and it returns the last turn's answer
/// rather than throwing.
///
/// **Parity is asserted on substance, not on bytes.** The card behind this
/// runner asks for equality of the two final answers. Two independent live
/// generations are not byte-equal, so a literal `==` would be a sampling
/// gate wearing an assertion's clothes: green or red by luck, and the first
/// thing a later reader would "fix" by loosening it. What is compared instead
/// is which accepted answers each reply contains — both surfaces must name the
/// same fixture value, and neither may name a different one. Two runs that
/// agree on a *wrong* answer still fail, because groundedness is asserted
/// beside this and never instead of it.
///
/// - Parameters:
///   - name: a short label identifying the scenario, used in the printed line.
///   - makeTools: builds the scenario's fixed tool set around a call log.
///   - prompt: the user request driving both surfaces.
///   - answerContainsOneOf: candidate substrings, at least one of which a
///     reply must contain (case-insensitively) to count as a valid answer.
///   - groundedIn: the `tools.*` paths whose returned data the answer must
///     depend on.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runRespondDrainScenario(
    name: String,
    tools makeTools: (ScenarioCallLog) -> [any Tool],
    prompt: String,
    answerContainsOneOf: [String],
    groundedIn: Set<String>
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        // The blocking surface first, on its own session and its own log.
        let respondLog = ScenarioCallLog()
        let respondSession = fixture.profile.standard.makeSession(
            tools: try makeScenarioSurface(over: makeTools(respondLog), on: fixture).tools,
            discoveryPriming: scenarioDiscoveryPriming
        )
        let start = Date()
        let respondAnswer = try await respondSession.respond(to: prompt)
        let respondElapsed = Date().timeIntervalSince(start)

        // Read immediately after the call returns: that is the instant the
        // rule is about. A run settling a moment later is precisely the
        // failure — the answer would already have been written without it.
        let backgroundRunsAfterRespond = await respondLog.backgroundRuns()
        let respondGrounding = await respondLog.returnedPaths
        let waitCalls = NativeTranscript.toolCallCount(
            in: await respondSession.transcript, named: WaitTool().name
        )

        // The streaming surface second, drained to completion, on a session of
        // its own so neither run can read back the other's transcript.
        let streamLog = ScenarioCallLog()
        let streamSession = fixture.profile.standard.makeSession(
            tools: try makeScenarioSurface(over: makeTools(streamLog), on: fixture).tools,
            discoveryPriming: scenarioDiscoveryPriming
        )
        let streamTurnResult = try await streamTurn(of: streamSession, prompt: prompt)
        let streamGrounding = await streamLog.returnedPaths

        let respondAccepted = accepted(answerContainsOneOf, in: respondAnswer)
        let streamAccepted = accepted(answerContainsOneOf, in: streamTurnResult.answer)

        print(
            """
            RESPOND-DRAIN \(name) elapsed=\(String(format: "%.1f", respondElapsed))s \
            backgroundRuns=\(backgroundRunsAfterRespond.count) waitCalls=\(waitCalls) \
            groundedIn=\(respondGrounding.sorted()) accepted=\(respondAccepted.sorted())
            RESPOND-DRAIN \(name) stream groundedIn=\(streamGrounding.sorted()) \
            accepted=\(streamAccepted.sorted())
            """
        )

        // 1. Grounded: the answer rests on data a tool really returned.
        #expect(respondGrounding.isSuperset(of: groundedIn))
        #expect(!respondAccepted.isEmpty)
        // 2. Parity of substance with the drained stream: both surfaces
        // reached the answer.
        //
        // Non-empty on both sides IS the parity, because an `answerContainsOneOf`
        // list holds spellings of ONE answer rather than a choice of answers.
        // `IntegrationScenarioAnswers.warmestCity` is
        // `[integrationWarmestCity.code, integrationWarmestCity.name]` — one
        // city, "by IATA code and by the spelled-out name models routinely
        // expand codes to. Any other city is wrong." So any non-empty set names
        // that city and nothing else can.
        //
        // Set EQUALITY was the assertion here, and it graded prose style. A run
        // on 2026-08-16 failed with `respondAccepted = ["SFO"]` against
        // `streamAccepted = ["SFO", "San Francisco"]`: both surfaces answered
        // San Francisco, from the same fixture data, and differed only because
        // one reply also spelled the code out. Equality demands the two replies
        // pick the same spellings, which is a property of phrasing, not of
        // substance — and this comment has said "substance" the whole time.
        #expect(!streamAccepted.isEmpty)
        // 3. Nothing survives the call.
        #expect(backgroundRunsAfterRespond.isEmpty)
        // 4. `wait` calls are REPORTED, not asserted on — see the type doc's
        // "what this scenario does not isolate". `^n6kgckr` asked for
        // `waitCalls == 0` on the reasoning that a model needing `wait` proves
        // the drain idle. Measured, it is 2, and the product is why: every
        // `runCode` backgrounds, and the pending envelope it returns *tells*
        // the model to call `wait` ("Call the wait tool with completionToken
        // ...", `MultiTool.detachmentCollectInstruction(forCompletionToken:)`).
        // The model obeying its own tool is not a drain failure, and an
        // assertion that fires on it would be demanding the model ignore the
        // instruction the product gives it.
        print("RESPOND-DRAIN \(name) waitCalls=\(waitCalls) (reported, not asserted)")
    }
}

/// Which of `candidates` a reply contains, case-insensitively.
///
/// - Parameters:
///   - candidates: the accepted answers for a scenario.
///   - reply: the model's final answer.
/// - Returns: the accepted answers present in `reply`.
private func accepted(_ candidates: [String], in reply: String) -> Set<String> {
    Set(candidates.filter { reply.localizedCaseInsensitiveContains($0) })
}

// MARK: - The in-band collection canary

/// How many leading characters of the model's reply the `IN-BAND-CANARY`
/// diagnostic line prints.
///
/// The reply is a whole sentence or two of prose, and the line already carries
/// five other fields, so it is truncated to keep one run to one readable line.
/// 120 characters because the one thing a reader chases here is the manifest
/// code, and a model that reports it puts it in the opening clause; the same
/// bound is what the other gated runners' reply previews use.
private let inBandCollectionReplyPreviewCharacters = 120

/// Drives one in-band collection scenario end to end, and holds the run to
/// what a live model really does with it: it collects its own background run
/// in band, and the turn ends with nothing still running (task `^xeqs138`).
///
/// Two shapes run through this one runner (task `^nhxj8hx`). The mechanism
/// shape mounts a direct-mode surface, drives the delayed echo by name, and
/// grades a nonce's round trip through a genuinely deferred settlement. The
/// teaching shape keeps the discovery surface and the "do not block" prompt,
/// and grades the instruction the handle carries against that prompt. Both
/// grade the same five conditions, through `inBandCollectionChecks`.
///
/// **This scenario is the inversion of the one it started as, and it is a
/// canary.** It was written to end a turn with a run still in flight, so that
/// Router's `respond` drain would be the only thing that could collect it. The
/// gated run reported the opposite and reported it cleanly: nothing still
/// running at the answer, beside `waitCalls=3`, with the manifest code in the
/// reply, in 635 seconds.
/// The model collected its own run and answered correctly.
///
/// Router then documented why no fixture could have changed that, in
/// `RoutedSessionActorGeneration`'s "How often this drain enters its loop"
/// comment (their commit `b4c0282`, card `^466d38p`): every background run hands
/// a `PendingRunEnvelope` whose text tells it to collect that run with a `wait`
/// call before it answers; `DetachingTool` writes that text, and `ToolContext`
/// starts no background run of its own — so **no host can start one without the
/// instruction**. A host whose tools always advise collection is every host, not
/// an unusual one. The condition is not hard to reach from here; it is
/// unreachable from anywhere, and the instruction sits upstream of anything a
/// fixture controls. That doc lands after the `c11fe07` this target's
/// `Package.resolved` pins, so a reader grepping the pinned checkout for it
/// should read the commit rather than the working copy.
///
/// So the assertions were inverted rather than loosened. A gated test that can
/// never pass is a liability: the next reader relaxes one condition until it
/// goes green, and it then passes vacuously forever.
///
/// **What the canary is for.** If a gated run ever fails
/// `noBackgroundRunsAtAnswer` — if a turn really does end with a run still
/// going — then the drain has become reachable from this host, and task
/// `^xeqs138`'s original question reopens with it: `respond`'s snapshot of
/// every background run, its continuation turn, and its bounded re-entry at
/// `RoutedSessionActor.parkedRunDrainRoundLimit` would be running for real, and
/// nothing in this target covers any of them. Read `inBandCollection` beside it:
/// those two failing together is the drain-reachable reading, and it is the one
/// to act on. Do not relax either of them.
///
/// **Why "nothing still running" means something although the fixture is
/// fast.** It is not read alone. `inBandCollection` is graded beside it, and
/// `wait` is the only in-band collector — so a `wait` call, no background run
/// left, and an answer carrying the manifest code together say the model
/// collected its own run.
/// None of the three is a statement about how long anything took, so a fixture
/// that stalled would strengthen none of them. What one cost this scenario when
/// it did stall is recorded on `IntegrationArchiveRebuildTool`.
///
/// **Why the answer is graded too, rather than only the background runs.**
/// Without it
/// the canary would assert that nothing happened, which a scenario that called
/// no tool at all would satisfy. The reply has to carry the rebuild's own
/// manifest code, a value that reaches the model only through the collected
/// run's terminal `detail` — it is in no prompt, no tool description and no
/// envelope — so nothing is left running *because the work was collected*, not
/// because it never started.
///
/// **What this says about the drain: nothing.** The drain is not entered on a
/// passing run — `settleParkedRuns` answers `false` on its first round and no
/// continuation turn runs — so this suite must never be cited for what the loop
/// does or for its re-entry bound. Router's own suite starts the runs it drains
/// and covers that; it proves what the loop does, not how often a real model
/// reaches it (`^466d38p`).
///
/// **Nothing here cancels.** A cancelled turn is never drained: whatever it
/// started keeps running, because ending a background run is `close()`'s job. A
/// cancelling scenario would therefore be asserting about `close()` instead.
///
/// - Parameters:
///   - name: a short label identifying the scenario, used in the printed lines.
///   - makeTools: builds the scenario's fixed tool set around the run's own call
///     log. A builder, for `runNativeIntegrationScenario`'s reason: exactly one
///     log exists per run, and no call site can hand the tools a different one
///     than this runner reads back.
///   - prompt: the user request driving the turn.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     final reply must contain (case-insensitively). Pick a value the reply
///     cannot carry unless the run really happened: the teaching shape uses a
///     value that reaches the model only through the collected run's terminal
///     `detail`, and the mechanism shape uses a fresh nonce whose round trip
///     the grounded and in-band-collection checks pin to the collected run.
///   - groundedIn: the `tools.*` paths whose returns the answer depends on — see
///     `IntegrationScenarioGrounding`.
///   - direct: when `true`, mount the surface in direct mode — `runCode` and
///     `wait`, no `searchTools` — so the scenario pays for no discovery. The
///     mechanism shape passes `true`; the teaching shape keeps the default,
///     the discovery surface its recorded evidence was measured on. See
///     `makeScenarioSurface(over:on:direct:)`.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runInBandCollectionCanaryScenario(
    name: String,
    tools makeTools: (ScenarioCallLog) -> [any Tool],
    prompt: String,
    answerContainsOneOf: [String],
    groundedIn: Set<String>,
    direct: Bool = false
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        let log = ScenarioCallLog()
        // No instructions, for the same reason as every other runner here:
        // mounting the tools is the whole product surface.
        let session = fixture.profile.standard.makeSession(
            tools: try makeScenarioSurface(over: makeTools(log), on: fixture, direct: direct).tools,
            discoveryPriming: scenarioDiscoveryPriming
        )

        // Subscribed on this task, before the turn starts. A subscription opened
        // from inside the child below could register after the turn had already
        // ended, and the one event this whole scenario is built around would be
        // gone — leaving `noBackgroundRunsAtAnswer` graded on an empty snapshot
        // nobody took.
        let sessionEvents = await session.streamSessionEvents()
        async let firstTurnRuns = backgroundRuns(atFirstTurnEndIn: sessionEvents, reading: log)

        let start = Date()
        let answer = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let evidence = InBandCollectionEvidence(
            answer: answer,
            backgroundRunsAtAnswer: await firstTurnRuns.map(\.tool),
            // Read the instant the call returns: that is what "nothing survives
            // `respond`" is a statement about.
            backgroundRunsAfterRespond: await log.backgroundRuns().map(\.tool),
            returnedPaths: await log.returnedPaths,
            waitCalls: NativeTranscript.toolCallCount(
                in: await session.transcript, named: WaitTool().name
            )
        )
        grade(
            scenario: name,
            checks: inBandCollectionChecks(
                for: evidence, answerContainsOneOf: answerContainsOneOf, groundedIn: groundedIn
            )
        )

        print(
            "IN-BAND-CANARY [\(name)] elapsed=\(String(format: "%.1f", elapsed))s "
                + "backgroundRunsAtAnswer=\(evidence.backgroundRunsAtAnswer) "
                + "backgroundRunsAfterRespond=\(evidence.backgroundRunsAfterRespond) "
                + "waitCalls=\(evidence.waitCalls) "
                + "returned=\(evidence.returnedPaths.sorted()) "
                + "groundedIn=\(groundedIn.sorted()) "
                + "reply=\"\(answer.prefix(inBandCollectionReplyPreviewCharacters))\""
        )
    }
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
struct InBandCollectionEvidence {
    /// The model's final reply — the last drained turn's, when the drain ran one.
    let answer: String

    /// The tools owning the runs still going at the instant the model's first
    /// turn ended.
    ///
    /// The owning tools' names rather than the `ParkedRun` rows themselves, for
    /// the reason `ScenarioEvidence` carries paths: a `ParkedRun` is Router's
    /// own type — its spelling, for the row this package calls a background run
    /// — and its memberwise initializer is internal to that module, so a record
    /// built from rows could be graded only by a live run. The name is all the
    /// verdict and the diagnostic line ever read.
    let backgroundRunsAtAnswer: [String]

    /// The tools owning the runs still going when `respond(to:)` returned.
    let backgroundRunsAfterRespond: [String]

    /// The `tools.*` paths a fixture tool handed a value back from.
    let returnedPaths: Set<String>

    /// How many `wait` calls the model made — the whole of the in-band
    /// collection surface, so any call at all is the model collecting its own
    /// run and none is something else having collected it.
    let waitCalls: Int
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
func inBandCollectionChecks(
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

/// Snapshots the session's background runs at the end of the model's first
/// turn.
///
/// The first turn, not the last: `respond(to:)` runs a continuation turn for
/// every round its drain takes, and the canary's question is about the turn
/// that carried the model's own answer. Reading a later one would grade a
/// snapshot the drain had already emptied.
///
/// Nothing here releases anything, so nothing the runner itself did can have
/// ended a run it reads.
///
/// - Parameters:
///   - events: the session's own event feed, subscribed before the turn started.
///   - log: the run's call log, which holds the handle onto the session's
///     background runs.
/// - Returns: the runs still going at that instant, or an empty array when no
///   turn ended on this feed.
private func backgroundRuns(
    atFirstTurnEndIn events: AsyncStream<SessionEvent>,
    reading log: ScenarioCallLog
) async -> [ParkedRun] {
    for await event in events {
        guard case .turnEnded = event else { continue }
        return await log.backgroundRuns()
    }
    return []
}

/// Renders a turn's usage for a gated diagnostic line, without stating a
/// number nobody measured.
///
/// The output count is real. The input count never reaches the framework
/// (`^z2996cp` on `mlx-swift-lm`'s board), so it is reported as `unavailable`
/// rather than as the `0` it arrives as — a printed zero reads as a
/// measurement of an empty prompt, and a reader chasing a failure would spend
/// time on it. `contextFill` is carried through with the same caveat, since it
/// may derive from the missing input count.
///
/// - Parameter usage: the usage the turn reported.
/// - Returns: the display string for the `tokens=` field.
private func usageForDisplay(_ usage: TokenUsage) -> String {
    "out:\(usage.tokensOut) in:unavailable(^z2996cp) contextFill:\(usage.contextFill)?"
}

// MARK: - The nested-generation probe

/// How often the shared generation gate is sampled while the probe's turn runs.
///
/// Frequent enough that even a run killed at the suite's three-minute limit
/// leaves dozens of readings, and cheap enough to be free: one sample is two
/// lock-guarded integer reads.
private let generationGateSampleInterval: Duration = .seconds(5)

/// How many leading characters of the model's reply the `NESTED-GENERATION`
/// diagnostic line prints.
///
/// More than the canary's `inBandCollectionReplyPreviewCharacters`, on purpose
/// and not by drift. That line carries six fields and a reader chases one
/// number in the opening clause; this line carries three, and the reply is the
/// only prose a completed probe run leaves — how the model described a nested
/// call that came back is worth reading whole.
private let nestedGenerationReplyPreviewCharacters = 200

/// Prints the shared generation gate's own state, once every
/// ``generationGateSampleInterval``, until this task is cancelled.
///
/// This is Router's own check for the deadlock the probe is built to name. At
/// the hang the gate must read zero permits and exactly one waiter: the outer
/// turn holding the permit `beginTurn()` took, and the nested `respond` parked
/// on `generationGate.wait()`. Nothing else produces that pair.
///
/// Sampled while the turn is in flight rather than read afterwards, because a
/// deadlocked run has no afterwards. `AsyncSemaphore.wait()` is a bare
/// `withCheckedContinuation` with no cancellation handler, so a parked caller
/// cannot be unwound and no later line of this suite's own code ever runs. The
/// last printed reading is what a killed run leaves behind, which is why this
/// prints rather than asserts.
///
/// - Parameter slot: the resolved slot whose resident container owns the gate.
private func sampleGenerationGate(on slot: RoutedLLM) async {
    while !Task.isCancelled {
        let gate = slot.generationGate
        print("GATE permits=\(gate.availablePermits) waiters=\(gate.waiterCount)")
        try? await Task.sleep(for: generationGateSampleInterval)
    }
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
struct NestedGenerationEvidence {
    /// The model's final reply.
    let answer: String

    /// The `tools.*` paths a fixture tool entered, recorded on the way in —
    /// `ScenarioCallLog.enteredPaths`, never `invokedPaths`.
    let enteredPaths: Set<String>

    /// The `tools.*` paths a fixture tool handed a value back from.
    let returnedPaths: Set<String>
}

/// Grades one nested-generation probe run into the conditions its verdict is
/// the conjunction of.
///
/// - Parameter evidence: what the run produced.
/// - Returns: every condition this run is graded on, in reporting order.
func nestedGenerationChecks(for evidence: NestedGenerationEvidence) -> [ScenarioCheck] {
    let path = IntegrationNestedGenerationTool.path
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

/// Runs the nested-generation probe: one turn whose single mounted tool
/// generates, without any grammar, on the very model that turn is running on.
///
/// **The question.** A gated scenario hangs for ever — 0% CPU, ~19GB resident,
/// every thread parked on a condition variable — when both profile slots name
/// one `ModelRef`, because `searchTools` generates from inside the outer turn's
/// tool call. Two explanations fit, and only one of them needs a grammar:
///
/// - MLX's grammar-constrained decode deadlocks, its xgrammar path keeping
///   shared per-model caches; or
/// - Router's `RoutedModel.generationGate` — an `AsyncSemaphore(value: 1)` per
///   resident container — is taken by `beginTurn()` and held for the whole
///   turn, tool calls included, so a nested `respond` on that container parks
///   on `generationGate.wait()` and can never be admitted: the permit comes
///   back only from `endTurn()`, which waits on the tool call, which waits on
///   the nested `respond`.
///
/// This run carries no grammar anywhere. A hang here belongs to the gate and
/// nothing about MLX is implicated; a return here leaves the grammar as the
/// thing that matters. That is the whole design, and it is why nothing else may
/// be mounted.
///
/// **`searchTools` is deliberately absent.** The tool list is
/// `[IntegrationNestedGenerationTool]` and not what
/// `MultiTool.Registry.makeSessionTools(librarian:)` vends, so no discovery
/// call, no selection tier and no `MetadataSearcher` is in the picture — every
/// one of them generates under a grammar, and any of them present would put the
/// grammar back into the run this exists to hold it out of.
///
/// **What a hang looks like from outside.** The turn stops making progress, so
/// the suite's own `.timeLimit` is what ends it. The evidence is the `GATE`
/// lines this prints throughout, and the `CallTrace` span the fixture opens:
/// `log show --predicate 'subsystem == "com.swissarmyhammer.multitool" AND
/// category == "NestedGenerationProbe"'` shows `enter nestedRespond` with no
/// matching `exit` for as long as the run lasts.
///
/// **What the first run measured, on 2026-08-16.** It hung, with both slots
/// pinned to `mlx-community/Muse-Glimmer-30B-4bit`:
///
/// ```
/// GATE permits=1 waiters=0        <- before the turn
/// GATE permits=0 waiters=0        <- beginTurn() took the permit
/// GATE permits=0 waiters=1        <- and held to the end of the run
/// ...
/// ✘ Time limit was exceeded: 180.000 seconds
/// NESTED-GENERATION [nestedGeneration] elapsed=174.9s entered=[] returned=[] reply=""
/// ```
///
/// beside, in the unified log:
///
/// ```
/// 08:15:49.698 enter nestedRespond #1 checkModelReadiness
/// 08:18:34.135 exit  nestedRespond #1 threw CancellationError()
/// ```
///
/// 165 seconds inside one nested `respond` with no grammar anywhere in the run,
/// and the exit arrives only once the harness cancels the outer turn — which is
/// the mechanism itself: the permit comes back from `endTurn()`, and cancelling
/// the turn is what let the parked waiter through. **Router's generation gate is
/// the deadlock, and MLX's grammar path is not needed to explain it.**
///
/// The `entered=[]` on that line is not the model declining to call the tool.
/// `ScenarioCallLog` recorded a call only on the way out at the time, so a call
/// that never came back was invisible; `enteredPaths` was added for this, and a
/// rerun of the same hang reads `entered=[checkModelReadiness] returned=[]`.
///
/// - Parameters:
///   - name: a short label identifying the run, used in the printed lines.
///   - prompt: the user request driving the turn.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runNestedGenerationProbe(name: String, prompt: String) async throws {
    // `plumbingProbeProfile`, not the shipped pin every other runner in this
    // file resolves. This probe grades **plumbing**: whether a nested
    // generation on a held container comes back. The answer belongs to
    // Router's `generationGate` and is the same whatever model is resident, so
    // the 17GB generation pin bought nothing here but load time — most of this
    // probe's runtime was weights coming off disk. See `plumbingProbeModel`
    // for the rule, and for why no other suite in this target may take it.
    try await withLiveRouterFixture(name: name, profile: plumbingProbeProfile) { fixture in
        let log = ScenarioCallLog()
        let slot = fixture.profile.standard
        // One tool, mounted directly rather than through the registry. See this
        // runner's own documentation for why `searchTools` must not be here.
        //
        // No instructions either, matching every other runner in this file: the
        // tool's own description is the whole surface a host gives a model.
        let session = slot.makeSession(tools: [IntegrationNestedGenerationTool(slot: slot, log: log)])

        let start = Date()
        let turn = try await withThrowingTaskGroup(of: Void.self, returning: StreamedTurn.self) { group in
            group.addTask { await sampleGenerationGate(on: slot) }
            // Cancelled on every exit path, so the sampler cannot outlive the
            // turn it is sampling — including the path where the turn throws.
            defer { group.cancelAll() }
            return try await streamTurn(of: session, prompt: prompt)
        }
        let elapsed = Date().timeIntervalSince(start)

        let evidence = NestedGenerationEvidence(
            answer: turn.answer,
            // `enteredPaths`, never `invokedPaths`: the log records a call in
            // `invokedPaths` on the way *out*, so a call parked for ever is
            // absent from it — the same reading a model that never called the
            // tool produces. Measured: the first gated run of this probe
            // reported `entered=[]` for a call that had been open 165 seconds.
            enteredPaths: await log.enteredPaths,
            returnedPaths: await log.returnedPaths
        )
        grade(scenario: name, checks: nestedGenerationChecks(for: evidence))

        print(
            "NESTED-GENERATION [\(name)] elapsed=\(String(format: "%.1f", elapsed))s "
                + "entered=\(evidence.enteredPaths.sorted()) "
                + "returned=\(evidence.returnedPaths.sorted()) "
                + "reply=\"\(turn.answer.prefix(nestedGenerationReplyPreviewCharacters))\""
        )
    }
}
