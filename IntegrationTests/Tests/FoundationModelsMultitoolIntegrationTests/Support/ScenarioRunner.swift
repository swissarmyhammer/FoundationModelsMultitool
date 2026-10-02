import Foundation
import Testing

import FoundationModels
import ScenarioGrading
@testable import FoundationModelsMultitool
// `@testable` for one reason, and only the nested-generation probe needs it:
// `RoutedModel.container` and `GenerationQueue`'s `isRunning` /
// `waitingCount` are `internal`, and they are the direct reading of the queue
// state `runNestedGenerationProbe` samples. Router's package is not edited to
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
/// answerMustNotContain:readingContainsOneOf:groundedIn:)`, which is where the grading rule itself
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
///   - readingContainsOneOf: candidate substrings for a tool reading the
///     reply must also state, at least one of which it must contain
///     (case-insensitively), graded as `readingReported`. Empty by default,
///     which adds no check: only the discovery scenario asks for a reading.
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
    readingContainsOneOf: [String] = [],
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
        // **`respond(to:)` gives one final text and nothing else.** The
        // stream gives each tool call, each tool status and each submission
        // of the turn, and the grading and the route diagnostics read them.
        // A gated suite driven through `respond` would see the answer and not
        // the route: whether `searchTools` preceded `runCode`, and what each
        // call returned.
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
            readingContainsOneOf: readingContainsOneOf,
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
        reportGatedResult(
            scenario: name,
            line: "elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) "
                + "submissions=\(turn.submissionIdentity ?? "n/a") "
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
                + "reply=\"\(turn.answer.prefix(nativeReplyPreviewCharacters))\""
        )
        // The same run's failure modes, counted. Emitted alongside the
        // `SCENARIO` verdict, never instead of it: nothing below is
        // asserted, and the grade above is unchanged.
        reportTraceLine(
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

/// How many leading characters of the model's reply the `RESULT` line of
/// `runNativeIntegrationScenario` prints: enough for the opening clause that
/// carries the answer, and short, because that line carries many other
/// fields.
private let nativeReplyPreviewCharacters = 80

/// Everything one streamed turn produced that a scenario grades or reports.
struct StreamedTurn {
    /// The turn's reply text: `SessionAnswer.reply` of the `answered` event
    /// that ended the turn, or the empty string when no answer ended it.
    ///
    /// Taken from `answered` and not joined from the `textDelta` fragments.
    /// Router states that `SessionAnswer.reply` is character-equal to what
    /// `respond(to:)` returns for the same message, so the stream path and the
    /// respond path grade the same text. A submission that gives its reply
    /// whole sends no fragment at all.
    var answer = ""

    /// The `textDelta` fragments since the last `.textReset`, in production
    /// order. Kept only for ``supersededAnswers``; the graded text is
    /// ``answer``.
    var streamedText = ""

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

    /// The submissions of the answer that ended this turn, as
    /// `<submission ids>/<cause>` — for example `1,2/message` for a first
    /// submission and one continuation.
    ///
    /// Router reports one `submissionStarted` for each SDK call of the chain
    /// (`generation-queue.md`, section 5.6). The cause is the cause of the
    /// first submission: `message` for the prompt of this turn, `mail` for an
    /// answer that no caller asked for. `nil` when no answer ended the turn.
    var submissionIdentity: String?

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
    var events: [SessionEvent] = []
    for try await event in await session.streamEvents(to: prompt) {
        events.append(event)
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
            reportTraceLine(
                """
                STALL withoutProgress=\(stall.timeWithoutProgress) \
                inFlight=\(stall.timeInFlight) visibility=\(stall.visibility)
                """
            )
        case .repetitionStopped(let stop):
            // Router stopped a generation call that wrote the same lines again.
            // This is the third state in the stall note above: the model
            // generates steadily and gets no result. Router now finds that
            // state and reports it. The line is printed and not asserted, for
            // the same reason as the stall line: the stop is Router's recovery,
            // and it is not a failure of the scenario.
            reportTraceLine("REPEAT \(stop)")
        case .reasoningStopped(let stop):
            // Router stopped a pass that only reasoned past its reasoning
            // limit. A recovery submission follows, or the answer ends. The
            // line is printed and not asserted, for the same reason as the
            // repeat line: the stop is Router's recovery, and it is not a
            // failure of the scenario.
            reportTraceLine("REASONING-STOP \(stop)")
        case .textDelta(let fragment):
            turn.streamedText += fragment
        case .textReset:
            // Everything delivered so far is superseded, not retracted: the
            // model produced a first pass, a tool ran, and generation resumed
            // on a fresh answer. Router surfaces this rather than hiding it
            // (^w8dzvee D2), and a consumer that ignores it accumulates
            // "PRETOOL FINAL-ANSWER" where `respond(to:)` returns
            // "FINAL-ANSWER". This suite grades the reply of `answered`, so
            // the fragments are kept only as the superseded first pass; the
            // superseded text stays in the transcript.
            turn.supersededAnswers.append(turn.streamedText)
            turn.streamedText = ""
        case .toolCall(let id, let name, let argumentsJSON):
            turn.toolCallCount += 1
            turn.callIndexByID[id] = turn.calls.count
            turn.calls.append(
                NativeTranscript.StreamedCall(name: name, argumentsJSON: argumentsJSON, output: nil)
            )
            reportTraceLine("CALL [\(turn.toolCallCount)] \(name) args=\(traceExcerpt(argumentsJSON))")
        // `output` carries the call's full segments; this runner grades on
        // the flattened `summary` alone, so it is bound away here.
        case .toolStatus(let id, .completed, let summary, _):
            turn.toolOutputs.append(summary ?? "")
            if let index = turn.callIndexByID[id] {
                turn.calls[index].output = summary
            }
            let name = turn.callIndexByID[id].map { turn.calls[$0].name } ?? "?"
            reportTraceLine("DONE \(name) out=\(traceExcerpt(summary ?? ""))")
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
            reportTraceLine("RUN  \(name) progress=\(traceExcerpt(summary ?? ""))")
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
        case .toolStatus, .reasoningDelta, .toolInvocation, .toolCallReport, .entryRecorded,
            .elicitationRequested, .runSettled, .generationCall, .submissionQueued, .submissionStarted,
            .submissionEnded, .answered, .answerFailed, .mailDeliveryPaused:
            // `.toolStatus` here is the residue of the three status cases
            // handled above. `.toolInvocation` carries the open/close record
            // of each call, and `.entryRecorded` announces a transcript entry;
            // both restate what `.toolCall`/`.toolStatus` already gave this
            // runner, which grades a scenario on its calls and its answer.
            // `.toolCallReport` carries the structured records a call attached
            // — the file-change set of a mutating `tools.files` call — which
            // `FileChangeAttachmentTests` grades with no model at all.
            // `.elicitationRequested` announces a question a run raised, and no
            // tool of these scenarios raises one. `.runSettled` announces a
            // background run's terminal event, which the journal readings below
            // already grade. `.generationCall` reports the usage of one
            // generation call; the `answered` event gives the sum of the
            // chain. `.submissionQueued` and `.mailDeliveryPaused` report a
            // wait of the model queue and a hold of mail, and no scenario here
            // grades either. The submission and answer events are read after
            // the loop, as one fold — see `settle(from:)`.
            break
        }
    }
    turn.settle(from: SubmissionLog.fold(events: events))
    return turn
}

extension StreamedTurn {
    /// Takes the graded reply, the submission identity and the token usage
    /// from the last answer chain that ended in the turn.
    ///
    /// **The end of the reply is `answered`, not `submissionEnded`.** The
    /// event the old Router sent at the end of a turn meant "the reply of this
    /// turn ended", so the three
    /// fields read the `answered` event of the chain: its reply, and its usage,
    /// which is the sum over each `submissionEnded` of the chain. One
    /// `submissionEnded` is the end of one SDK call only, and a chain that
    /// continues after a compaction or a stop sends more than one. The
    /// identity names each submission of the chain, from its
    /// `submissionStarted` events.
    ///
    /// - Parameter records: every answer chain that ended in the turn, in
    ///   the order the chains ended.
    mutating func settle(from records: [AnswerRecord]) {
        guard let last = records.last else { return }
        answer = last.reply ?? ""
        let ids = last.submissionIds.map(\.description).joined(separator: ",")
        submissionIdentity = "\(ids)/\(last.cause?.rawValue ?? "none")"
        guard case .answered(let final) = last.outcome, let usage = final.usage else { return }
        // Output only, and the input half relabelled — see `tokenUsage`.
        tokenUsage = usageForDisplay(usage)
    }
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
struct ScenarioSurface {
    /// The tools to register with the session, in the mount order the
    /// registry itself vends.
    let tools: [any Tool]

    /// Every `tools.*` path the mounted catalog actually defines — what an
    /// invented path is measured against.
    let catalogPaths: Set<String>
}

/// Builds the model-facing tool surface every scenario drives, by asking the
/// registry for it — `MultiTool.Registry.makeSessionTools(selection:embedder:sampleSession:)`,
/// with the seams of `LiveRouterFixture.discoverySeams`: the same call
/// `CLIRunner.runDemo` makes, with the selection tier on the resolved `.flash`
/// slot (the "librarian on flash" split the CLI ships).
///
/// Vended rather than assembled here on purpose. Under the suite's intent
/// statement the harness must mount `MultiTool` exactly the way a host does,
/// and mount order is part of what a host receives: hand-building the array
/// would let the suite measure an order the product does not recommend.
///
/// **No sample-snippet generator, because the product ships without one.**
/// `makeSessionTools`'s `sampleSession:` defaults to `nil`, and the
/// `RouterDiscoverySeams` that `CLIRunner.runDemo` makes carries none, so an
/// arm that wires one measures a configuration no host runs.
///
/// It was wired here, and removing it was not a preference. Each generated
/// sample is a nested generation on the `.standard` slot with up to three
/// attempts, so every `searchTools` call paid two large-model generations
/// instead of one. Once discovery stopped backgrounding — it is a synchronous
/// prerequisite and must never background — that cost stopped being hidden by a
/// thrashing turn and became a hard failure: `ToolMountError.timedOut(tool:
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
///     direct-mode registry vends `runCode` and no `searchTools`, so the
///     scenario pays for no discovery. The discovery seams stay the same in
///     both modes, because the CLI passes them in both modes and this harness
///     must mount what the CLI mounts.
/// - Returns: the tools to register with the session, and the catalog paths
///   behind them.
/// - Throws: whatever `MultiTool.Builder.buildRegistry()` or
///   `MultiTool.Registry.makeSessionTools(selection:embedder:sampleSession:)`
///   throws.
func makeScenarioSurface(
    over tools: [any Tool],
    on fixture: LiveRouterFixture,
    direct: Bool = false
) throws -> ScenarioSurface {
    var registry = try MultiTool.Builder().addTools(tools).buildRegistry()
    if direct {
        registry = registry.directMode()
    }
    let seams = fixture.discoverySeams
    return ScenarioSurface(
        // The selection and embedder seams, exactly as `CLIRunner.runDemo`
        // mounts them. No `sampleSession:` — the seams carry none, so the
        // product ships without one and this harness must too.
        tools: try registry.makeSessionTools(
            selection: seams.selection, embedder: seams.embedder, sampleSession: seams.sampleSession),
        // Unioned with the sibling paths the sandbox binds itself, so a
        // snippet calling `tools.searchTools` or `tools.runCode` is not
        // graded as having invented a path it can really call (task
        // `bwk7knm`). Read from `MultiTool`, never restated, so the
        // diagnostic and the sandbox cannot disagree about what exists.
        catalogPaths: Set(registry.surface.entries.map(\.path))
            .union(MultiTool.siblingToolPaths)
    )
}

// MARK: - Reporting one run's verdict

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
    reportTraceLine("SCENARIO [\(name)] result=\(result) \(breakdown)")

    for check in checks {
        #expect(check.held, "[\(name)] \(check.failureMessage)")
    }
}

/// Prints the standard note for a scenario skipped because this environment
/// has no live-inference path wired up.
///
/// Each gated suite that resolves a live fixture writes its skip note through
/// this function, so the text of the note is in one location.
///
/// - Parameter name: the scenario label.
func printSkipNote(_ name: String) {
    reportTraceLine("SKIP [\(name)]: Router's live-inference path is not wired up in this environment.")
}

// MARK: - The mail collection canary

/// How many leading characters of the model's reply the `MAIL-CANARY`
/// diagnostic line prints.
///
/// The reply is a whole sentence or two of prose, and the line already carries
/// six other fields, so it is truncated to keep one run to one readable line.
/// 120 characters because the one thing a reader chases here is the echoed
/// value, and a model that reports it puts it in the opening clause; the same
/// bound is what the other gated runners' reply previews use.
private let mailCanaryReplyPreviewCharacters = 120

/// Drives the mail collection scenario end to end, and holds the run to the
/// contract of the work-queue Router: a `runCode` call goes to the background
/// and hands the model a pending envelope, the background run settles after
/// the answer ends, comes back to the session as mail, and the model answers
/// it.
///
/// **One runner for three former scenarios.** Card `^3vtvrzg` merged the
/// background-in-code-mode scenario (`BackgroundTests`, which had its own
/// runner) and the "do not block" teaching shape of the canary into the
/// delayed-echo mechanism shape, which already graded every condition they
/// graded but one. That one, the `pendingEnvelope` check of the
/// background-in-code-mode runner, is graded here now. The surface is the
/// direct-mode surface — `runCode`, no `searchTools` — exactly as
/// `CLIRunner.runDemo` mounts it under `--direct`, so the run pays for no
/// discovery. A pending envelope on the discovery surface is graded by
/// `ShellBackgroundTests`.
///
/// **One turn, not two.** Splitting a background scenario into a "start it"
/// turn and a "collect it" turn was tried on real hardware and is worse in
/// both halves: a turn that only asks to start the job gets an announcement
/// and no `runCode` call at all, and a second turn asked to report the result
/// re-scans or invents a code rather than reading the background run (one run
/// answered the right code in the opening turn and a made-up `8472` in the
/// closing one). The single turn is also the honest unit of the claim — the
/// model receives the pending envelope and still finishes the job it was
/// given.
///
/// **What changed, and why.** The old Router drained the background runs of a
/// turn inside `respond(to:)`, and the old surface mounted a `wait` tool that
/// the model called to collect a run in band. The work-queue Router removed
/// the drain and the `wait` tool. A run that settles after the answer ends now
/// sends its result to the session as mail, and the session starts a new
/// answer for it, whose first submission reports
/// `SubmissionStart.cause == .mail`. So this runner no longer stops at the end
/// of the first answer: it reads the session events until an answer that mail
/// started ends, or until the shared poll hang guard `IntegrationPoll.deadline`.
/// That bound is a hang guard and never a speed check (card `^kdtrmhv`): a
/// run that gets no mail answer fails `mailCollection` with a reading, inside
/// `IntegrationHangGuard.timeLimit`.
///
/// **What is graded.** Some tool output of the first answer must be exactly
/// `PendingRunEnvelope.rendered`, checked with Router's own byte-shape
/// recognizer. The last answer the runner read must be a valid answer that
/// carries the value, grounded in the fixture's own return; at least one
/// answer must start from mail; and no background run may still be going when
/// that last answer ends. The value reaches the model only through the settled
/// run, so an answer that carries it proves the mail brought it.
///
/// The first answer is driven through `streamTurn(of:prompt:)` and not
/// through `respond(to:)`, because only the stream carries the tool outputs
/// the envelope check reads.
///
/// **Nothing here cancels.** Ending a background run is `close()`'s job, so a
/// cancelling scenario would be asserting about `close()` instead.
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
///     cannot carry unless the run really happened: the canary uses a fresh
///     nonce whose round trip the grounded and mail collection checks pin to
///     the settled run.
///   - groundedIn: the `tools.*` paths whose returns the answer depends on — see
///     `IntegrationScenarioGrounding`.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runInBandCollectionCanaryScenario(
    name: String,
    tools makeTools: (ScenarioCallLog) -> [any Tool],
    prompt: String,
    answerContainsOneOf: [String],
    groundedIn: Set<String>
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        let log = ScenarioCallLog()
        // No instructions, for the same reason as every other runner here:
        // mounting the tools is the whole product surface.
        let session = fixture.profile.standard.makeSession(
            tools: try makeScenarioSurface(over: makeTools(log), on: fixture, direct: true).tools,
            discoveryPriming: scenarioDiscoveryPriming
        )

        // Subscribed on this task, before the turn starts. A subscription
        // opened later could register after an answer had already ended, and
        // the reading would then miss it.
        let sessionEvents = await session.streamSessionEvents()
        async let mailReading = MailAnswerReading.read(
            sessionEvents, backgroundRunsOf: log, within: IntegrationPoll.deadline)

        let start = Date()
        let turn = try await streamTurn(of: session, prompt: prompt)
        let reading = await mailReading
        let elapsed = Date().timeIntervalSince(start)
        let answers = SubmissionLog.fold(events: reading.events)

        let evidence = MailCollectionEvidence(
            // The last answer is the answer that mail started, when one ran.
            answer: answers.last?.reply ?? "",
            returnedPaths: await log.returnedPaths,
            pendingEnvelopes: turn.toolOutputs.filter(PendingRunEnvelope.isRendered).count,
            mailAnswers: answers.filter { $0.cause == .mail }.count,
            backgroundRunsAtLastAnswer: reading.backgroundRuns.map(\.tool)
        )
        grade(
            scenario: name,
            checks: mailCollectionChecks(
                for: evidence, answerContainsOneOf: answerContainsOneOf, groundedIn: groundedIn
            )
        )

        reportTraceLine(
            "MAIL-CANARY [\(name)] elapsed=\(String(format: "%.1f", elapsed))s "
                + "pendingEnvelopes=\(evidence.pendingEnvelopes) "
                + "answers=\(answers.count) mailAnswers=\(evidence.mailAnswers) "
                + "backgroundRunsAtLastAnswer=\(evidence.backgroundRunsAtLastAnswer) "
                + "returned=\(evidence.returnedPaths.sorted()) "
                + "groundedIn=\(groundedIn.sorted()) "
                + "reply=\"\(evidence.answer.prefix(mailCanaryReplyPreviewCharacters))\""
        )
    }
}

/// What the canary read at the end of the answer that mail started.
private struct MailAnswerReading {
    /// The session events through the end of the first answer that mail
    /// started, or every event before the deadline when no such answer ended.
    let events: [SessionEvent]

    /// The background runs still going at the instant the reading ended.
    let backgroundRuns: [BackgroundRun]

    /// Reads the session events until an answer that mail started ends, or
    /// until `limit` passes, and then snapshots the background runs.
    ///
    /// Two child tasks race: one reads the events, and one sleeps `limit`.
    /// When the sleep wins, the reader is cancelled, and an `AsyncStream`
    /// ends its iteration on cancellation, so the reader gives back the
    /// events it read so far.
    ///
    /// - Parameters:
    ///   - events: the session's own event feed, subscribed before the turn
    ///     started.
    ///   - log: the run's call log, which holds the handle onto the session's
    ///     background runs.
    ///   - limit: how long to wait, counted from this call.
    /// - Returns: the events read, and the runs still going at that instant.
    static func read(
        _ events: AsyncStream<SessionEvent>,
        backgroundRunsOf log: ScenarioCallLog,
        within limit: Duration
    ) async -> MailAnswerReading {
        let collected = await withTaskGroup(of: [SessionEvent]?.self) { group in
            group.addTask { await eventsThroughMailAnswer(in: events) }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            var read: [SessionEvent] = []
            for await finished in group {
                group.cancelAll()
                if let finished {
                    read = finished
                    break
                }
            }
            return read
        }
        return MailAnswerReading(events: collected, backgroundRuns: await log.backgroundRuns())
    }

    /// Reads events until an answer chain that mail started ends.
    ///
    /// "The end of the answer" is `answered` — or `answerFailed` in its place
    /// — and never one `submissionEnded`, which ends one SDK call only. See
    /// `SubmissionLog.endsAnswer(event:)`.
    ///
    /// - Parameter events: the session's own event feed.
    /// - Returns: the events through the end of the first answer that mail
    ///   started, or every event read when the feed ended or the task was
    ///   cancelled first.
    private static func eventsThroughMailAnswer(in events: AsyncStream<SessionEvent>) async -> [SessionEvent] {
        var collected: [SessionEvent] = []
        for await event in events {
            collected.append(event)
            if SubmissionLog.endsAnswer(event: event), SubmissionLog.fold(events: collected).last?.cause == .mail {
                break
            }
        }
        return collected
    }
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

/// How many seconds pass between two samples of the shared generation queue
/// while the probe's turn runs.
///
/// Frequent enough that even a run killed at the suite's one-minute limit
/// leaves a dozen readings, and cheap enough to be free: one sample is two
/// reads of the queue worker's state.
private let generationQueueSampleIntervalSeconds = 5

/// How often the shared generation queue is sampled while the probe's turn
/// runs — ``generationQueueSampleIntervalSeconds`` as a `Duration`.
private let generationQueueSampleInterval = Duration.seconds(generationQueueSampleIntervalSeconds)

/// How many leading characters of the model's reply the `NESTED-GENERATION`
/// diagnostic line prints.
///
/// More than the canary's `mailCanaryReplyPreviewCharacters`, on purpose
/// and not by drift. That line carries six fields and a reader chases one
/// number in the opening clause; this line carries three, and the reply is the
/// only prose a completed probe run leaves — how the model described a nested
/// call that came back is worth reading whole.
private let nestedGenerationReplyPreviewCharacters = 200

/// Prints the state of the shared generation queue of the model, once every
/// ``generationQueueSampleInterval``, until this task is cancelled.
///
/// The work-queue Router replaced the old per-container `generationGate`
/// with one FIFO `GenerationQueue` for each model. This reads the same two
/// things the gate reading gave: whether the worker runs a submission, and
/// how many submissions wait for it. A nested `respond` on the same model
/// gets `GenerationQueueError.waitInsideOpenSubmission` at once and never
/// waits, so a healthy run never reads `waiting=1`. A run that hangs reads
/// `running=true waiting=1` for the rest of its life, and that is the reading
/// a run killed by the hang guard leaves.
///
/// Sampled while the turn is in flight rather than read afterwards, because a
/// hung run has no afterwards. The last printed reading is what a killed run
/// leaves behind, which is why this prints rather than asserts.
///
/// - Parameter slot: the resolved slot whose resident container owns the
///   queue.
private func sampleGenerationQueue(on slot: RoutedLLM) async {
    guard let queue = slot.residentGenerationQueue else {
        reportTraceLine("QUEUE none: the backend of this model names no generation queue")
        return
    }
    while !Task.isCancelled {
        reportTraceLine("QUEUE running=\(await queue.isRunning) waiting=\(await queue.waitingCount)")
        try? await Task.sleep(for: generationQueueSampleInterval)
    }
}

extension RoutedLLM {
    /// The generation queue of the resident model of this slot, or `nil` when
    /// the backend of the model names none.
    ///
    /// Read through a session backend made only to reach the queue of the
    /// container. It generates nothing, and every session of the model shares
    /// its queue. `container` is `internal` to Router, thus this extension
    /// stays in this file, next to the `@testable` import that reaches it.
    /// The queue sampler above and `IntegrationNestedGenerationTool` both
    /// read the queue through it.
    var residentGenerationQueue: GenerationQueue? {
        container.makeSession(instructions: nil).generationQueue
    }
}

/// Runs the nested-generation probe: one turn whose single mounted tool
/// generates, without any grammar, on the very model that turn is running on.
///
/// **The question.** `searchTools` generates from inside the outer turn's tool
/// call. When the nested generation needs the model that the outer submission
/// holds open, the work-queue Router must refuse it at once with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`. This run makes
/// exactly that nested call and grades how it ended, through
/// `nestedGenerationChecks(for:)`: entered, refused, and refused at once —
/// while the outer submission still ran, and with no job queued behind it.
/// The order of events decides, and no real-time bound (card `^kdtrmhv`).
///
/// **What it replaced.** The old Router's `RoutedModel.generationGate` — an
/// `AsyncSemaphore(value: 1)` per resident container, taken by `beginTurn()`
/// and held across the tool rounds of the turn — parked the same nested call
/// for ever. Measured on 2026-08-16 with both slots on
/// `mlx-community/Muse-Glimmer-30B-4bit`: the gate read
/// `permits=0 waiters=1` to the end of the run, and the unified log read
/// `enter nestedRespond` at 08:15:49.698 and
/// `exit nestedRespond threw CancellationError()` at 08:18:34.135 — 165
/// seconds, unwound only when the hang guard cancelled the outer turn.
///
/// **`searchTools` is deliberately absent.** The tool list is
/// `[IntegrationNestedGenerationTool]` and not what
/// `MultiTool.Registry.makeSessionTools(selection:embedder:sampleSession:)` vends, so no discovery
/// call, no selection tier and no `MetadataSearcher` is in the picture — every
/// one of them generates under a grammar on a slot of its own, and none of
/// them is the question.
///
/// **What a hang looks like from outside.** The turn stops making progress, so
/// the hang guard of the suite, `IntegrationHangGuard.timeLimit`, is what ends
/// it. The evidence is the `QUEUE`
/// lines this prints throughout, and the enter record of the span the fixture
/// opens: the swift-log output of the run shows
/// `enter FoundationModelsMultitoolIntegrationTests.nestedRespond`, and the
/// span of that call does not end for as long as the run lasts.
///
/// - Parameters:
///   - name: a short label identifying the run, used in the printed lines.
///   - prompt: the user request driving the turn.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runNestedGenerationProbe(name: String, prompt: String) async throws {
    // `plumbingProbeProfile`, not the shipped pin every other runner in this
    // file resolves. This probe grades **plumbing**: how a nested generation
    // on a held model ends. The answer belongs to Router's generation queue
    // and is the same whatever model is resident. See `plumbingProbeModel`
    // for the rule, and for why no other suite in this target may take it.
    try await withLiveRouterFixture(name: name, profile: plumbingProbeProfile) { fixture in
        let log = ScenarioCallLog()
        let outcomes = NestedGenerationOutcomeLog()
        let slot = fixture.profile.standard
        // One tool, mounted directly rather than through the registry. See this
        // runner's own documentation for why `searchTools` must not be here.
        //
        // No instructions either, matching every other runner in this file: the
        // tool's own description is the whole surface a host gives a model.
        let session = slot.makeSession(
            tools: [IntegrationNestedGenerationTool(slot: slot, log: log, outcomes: outcomes)])

        let start = Date()
        let turn = try await withThrowingTaskGroup(of: Void.self, returning: StreamedTurn.self) { group in
            group.addTask { await sampleGenerationQueue(on: slot) }
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
            outcome: await outcomes.outcome
        )
        grade(scenario: name, checks: nestedGenerationChecks(for: evidence))

        reportTraceLine(
            "NESTED-GENERATION [\(name)] elapsed=\(String(format: "%.1f", elapsed))s "
                + "entered=\(evidence.enteredPaths.sorted()) "
                + "outcome=\(evidence.outcome.map { "\($0)" } ?? "none") "
                + "reply=\"\(turn.answer.prefix(nestedGenerationReplyPreviewCharacters))\""
        )
    }
}
