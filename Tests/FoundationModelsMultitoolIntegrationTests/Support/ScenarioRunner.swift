import Foundation
import Testing

import FoundationModels
import FoundationModelsRouter

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
private func primingLabel(_ turn: StreamedTurn) -> String {
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
        let searchToolsFirst = NativeTranscript.searchToolsPrecedesRunCode(in: turn.calls)
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
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) "
                + "turn=\(turn.turnIdentity ?? "n/a") "
                + "typed=\(evidence.typedPaths.sorted()) "
                + "invoked=\(evidence.invokedPaths.sorted()) "
                + "returned=\(evidence.returnedPaths.sorted()) "
                + "groundedIn=\(groundedIn.sorted()) "
                + "searchToolsFirst=\(searchToolsFirst) "
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
                    searchToolsFirst: searchToolsFirst,
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
/// **Why a second runner exists.** `runNativeIntegrationScenario` builds a
/// bare `LanguageModelSession` over an `MLXLanguageModel`. That session has no
/// elevation mount: `DetachingTool` is applied only by Router's own
/// per-session tool wiring (`ToolDetachment.sessionMounted(tool:sessionID:
/// mailbox:sink:cappedToTokenLimit:)`), so on that path a slow snippet simply
/// blocks and a pending envelope can never appear. This runner vends a real
/// `RoutedSession` through `RoutedLLM.makeSession(instructions:tools:)`
/// instead, which mounts every tool under
/// `DetachConfiguration.nativeSessionMount` — elevation on, stock clocks —
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
private struct StreamedTurn {
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

    /// The turn's measured token usage, as the session reported it.
    ///
    /// The direct evidence for whether a turn is near its context ceiling.
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
private func streamTurn(of session: RoutedSession, prompt: String) async throws -> StreamedTurn {
    var turn = StreamedTurn()
    for try await event in await session.streamEvents(to: prompt) {
        switch event {
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
            // time, and one where it went silent and parked. The product
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
            turn.tokenUsage = "\(usage)"
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
/// **No sample-snippet generator, because the product ships without one.**
/// `makeSessionTools`'s `sampleGenerator:` defaults to `nil` and
/// `CLIRunner.runDemo` passes only `librarian:` (`CLIRunner.swift:390`), so an
/// arm that wires one measures a configuration no host runs.
///
/// It was wired here, and removing it was not a preference. Each generated
/// sample is a nested generation on the `.standard` slot with up to three
/// attempts, so every `searchTools` call paid two large-model generations
/// instead of one. Once discovery stopped detaching — it is a synchronous
/// prerequisite and must never park — that cost stopped being hidden by a
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

/// Drives one scenario through **both** surfaces and holds `respond(to:)` to
/// the rule that it must self-drain the run plane (task `^n6kgckr`).
///
/// Now that `runCode` always backgrounds (`^cv98vff`), a tool call no longer
/// returns data on any surface — it returns a reference to work still running.
/// On streaming that is the feature. On `respond` it must be **invisible**:
/// the same final answer, just slower. A `respond` that returned while its own
/// turn's runs were still parked would hand the model a token and nothing
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
/// 3. **Nothing left parked.** After `respond` returns, the session's run
///    plane is empty. A dangling token means the drain is incomplete even if
///    the answer happened to be right.
/// 4. **No `wait` call.** If the model had to call `wait` to reach its answer,
///    the drain is not doing its job — `wait` is the streaming surface's tool.
///
/// **Router's drain rule, which this scenario is written against.** `respond`
/// runs its own turn, then snapshots **every** run parked on the session —
/// not only the ones its own turn parked — waits for all of them to settle,
/// and runs one more ordinary turn carrying their results. It repeats, so a
/// run parked from inside a drained turn is drained too, bounded at four
/// continuation turns (`RoutedSessionActor.parkedRunDrainRoundLimit`): one
/// `respond` costs at most five model turns.
///
/// Two consequences for a scenario written here. A prompt whose answer needs
/// more than four continuation turns fails for a reason that is not a drain
/// defect, so keep scenarios inside that budget. And a cancelled turn is never
/// drained: whatever it parked stays parked, because ending a parked run is
/// `close()`'s job rather than cancellation's. A cancelling scenario is
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
        let parkedAfterRespond = await respondLog.parkedRuns()
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
            parked=\(parkedAfterRespond.count) waitCalls=\(waitCalls) \
            groundedIn=\(respondGrounding.sorted()) accepted=\(respondAccepted.sorted())
            RESPOND-DRAIN \(name) stream groundedIn=\(streamGrounding.sorted()) \
            accepted=\(streamAccepted.sorted())
            """
        )

        // 1. Grounded: the answer rests on data a tool really returned.
        #expect(respondGrounding.isSuperset(of: groundedIn))
        #expect(!respondAccepted.isEmpty)
        // 2. Parity of substance with the drained stream.
        #expect(respondAccepted == streamAccepted)
        // 3. Nothing survives the call.
        #expect(parkedAfterRespond.isEmpty)
        // 4. The model never had to ask for its own result.
        #expect(waitCalls == 0)
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
