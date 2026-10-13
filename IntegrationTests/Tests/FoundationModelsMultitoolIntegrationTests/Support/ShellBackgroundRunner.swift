import Foundation
import Testing

import FoundationModelsRouter

@testable import FoundationModelsMultitool
import ScenarioGrading

// MARK: - The shell background scenario
//
// eventplan.md § "Phases", phase 2: "Shell is the reference emitter. Its
// detached commands prove the background path end to end."
//
// One live turn sends the run to the background, and the harness reads the run
// plane while the run is still going. The split is deliberate, and it is the
// split the product itself makes:
//
// - The MODEL owns discovery and the start. It finds `tools.shell.execute`
//   through `searchTools` and starts the command from a `runCode` snippet.
//   The settle-period rule (card `^38j4bbn`) decides which run goes to the
//   background, and it applies to the outer `runCode` call only (card
//   `^6nnykct`). An inner `tools.shell.execute` call runs to completion, so
//   the snippet waits for the command. The command never ends, so the
//   `runCode` call answers with its pending envelope when its settle period
//   ends, and the snippet goes on in the background with the shell run inside
//   it. Thus the background run of this scenario is the RUNCODE run, and the
//   shell run is an inner run of it.
// - The HARNESS owns the readings that follow, because a live model cannot be
//   asked to make them reliably and a scenario that asked would be grading the
//   model rather than the background path. Each reading is taken through the
//   product's own surface: the run plane `status()` reports
//   (`ToolContext.backgroundRuns()`), the live verb `tools.shell.getLines`, the
//   canceler `cancel()` invokes (`ToolContext.cancel(completionToken:)`), and
//   the session's own run journal.
//
// **The mailbox's retained outcome is never read here.** Router's ^vbja15j:
// `ToolRun` builds its terminal from `terminalFacts(for:)`, which
// sees only whether the wrapped Swift call returned. A `.process` run stopped by
// `killpg` lets `Execute.call` return normally, so the mailbox retains
// `OperationOutcome.succeeded` for a run a SIGKILL ended. `wait(completionToken:)`
// and a late `cancel(completionToken:)` both answer with that retained value, so
// an assertion on either would be asserting the defect. What this scenario reads
// instead is honest on both sides: `cancel()` on a run still going reports the
// CANCELER's own answer, and the journal carries what the sink saw.
//
// The defect is visible in this scenario's own recorded journal, and the reading
// below steps around it rather than over it. Measured on 2026-08-25, one run,
// before the settle-period rule: the outer `runCode` run's terminal was
// journaled `outcome: succeeded` with the shell run's pending envelope as its
// detail, while the shell run swept at `close()` was journaled
// `outcome: stopped` under its own completion token. The second is what this
// scenario grades.

/// The command the scenario asks the model to start.
///
/// Three properties, each of them load-bearing:
///
/// 1. **It never ends.** The snippet that awaits it therefore certainly still
///    stands on the run plane while the harness reads it, so what ends it is
///    the cancel and never the command ending by itself.
/// 2. **Its first line is its own process group.** `ShellRunner` spawns each
///    child with `platformOptions.processGroupID = 0`, so the child is its own
///    process-group leader and the `$$` of that shell IS the identifier of the
///    group. Printing it is how this scenario learns the group to probe without
///    reaching into a `ShellState` it does not own — the store's process map is
///    per-instance and in memory, so a second `ShellState` over the same
///    directory would read nothing.
/// 3. **It writes output as it goes.** `tools.shell.getLines` has to read a
///    LIVE run, and a run that wrote nothing would let an empty read pass.
///
/// It carries no quotation mark and no nonce, because the model has to reproduce
/// it verbatim inside a JavaScript string literal and every character it has to
/// escape is a character it can get wrong.
private let shellBackgroundCommand = "echo $$ ; while true ; do echo tick ; sleep 1 ; done"

/// The request the model is given.
///
/// A user's own words, and the whole product surface is the two mounted tools:
/// no session instruction, exactly as every other runner in this target mounts
/// its scenario. The command is quoted in the prompt because the scenario is
/// about the background path rather than about which command a model invents, and
/// the process group the harness probes has to be one this scenario's own
/// command created.
///
/// It asks for the background start explicitly, in the words the verb's own
/// description uses ("start a long command in the background and get its
/// completion token back at once"). The wording does not decide the outcome:
/// `runCode` declares a background mount for itself, so every snippet that
/// runs longer than its settle period goes to the background whatever the
/// model asked for, and a snippet that awaits this command never ends.
///
/// "Reply in one short sentence" keeps the reply as long as the scenario needs
/// and no longer: no check reads the reply (see `shellBackgroundChecks(for:)`),
/// and the final reply of CI run `36951032341` was 177 generated tokens,
/// approximately 33 s on the CI runner `mini` (card `^3vtvrzg`).
private let shellBackgroundPrompt = """
    Start this shell command running in the background and tell me the completion token it hands \
    back. Do not wait for it to finish, because it never finishes. Reply in one short sentence.

    \(shellBackgroundCommand)
    """

/// The snippet call path of the verb that reads one run's stored output.
///
/// `MultiTool.Registry.tools` is keyed by the snippet call path, so this is how
/// the harness reaches the live verb over the same store the run wrote into.
private let shellGetLinesPath = "shell.getLines"

/// The snippet call path of the run-plane verb of the shell capability.
private let shellExecutePath = "shell.execute"

/// How long the command that is left standing for the session-end sweep sleeps.
///
/// A bare `sleep`, because nothing about that run is read while it is going: it
/// exists so that one shell run is still in the background when `close()`
/// sweeps, and the only reading taken of it is the terminal event `close()`
/// journals. It sleeps far longer than the whole suite, so it cannot end by
/// itself and be swept as a finished run.
private let sweptRunSleepSeconds = 600

/// The signal `killpg` takes to ASK whether a process group is still there.
///
/// Signal 0 sends NOTHING. `killpg` performs the checks of a signal it is about
/// to send and then sends none, thus this is the one reading that answers "does
/// this group still hold a process" with no risk to what stands in the group.
/// The only group this scenario ever names is the one its own command printed.
private let existenceProbeSignal: Int32 = 0

/// What `killpg` answers when it reached the group.
private let killpgReachedGroup: Int32 = 0

/// How many background reports one background run makes.
///
/// `BackgroundToolRunner` posts exactly one synthesized `progress` event as it
/// sends a run to the background, and its `detail` is the rendered pending
/// envelope of that run.
private let backgroundReportsPerRun = 1

/// How many terminal events one swept run gets.
///
/// `SessionMailbox.sweep()` states the invariant: exactly one for each run,
/// never two. `RoutedSessionActor.close()` journals exactly that list.
private let terminalEventsPerRun = 1

/// The `Tool` name of the `runCode` tool, which is the `tool` its background
/// run stands under on the run plane.
private let runCodeToolName = "runCode"

/// Runs the shell background scenario end to end against a freshly resolved live
/// profile, on the shipped configuration.
///
/// The surface is `MultiTool.Builder().withShell(...)` vended through
/// `MultiTool.Registry.makeSessionTools(selection:embedder:sampleModel:)`,
/// with the seams of `LiveRouterFixture.discoverySeams`, and mounted on a
/// `RoutedSession` the resolved `.standard` slot vends — the same wiring a
/// Router host makes, with `searchTools` backed by the resolved `.flash`
/// slot. Never a bare `LanguageModelSession`: the background path exists only
/// under Router's own per-session tool wiring, so a bare session would have no
/// background path to prove.
///
/// The turn is streamed rather than driven through `respond(to:)`, for the
/// reason `runNativeIntegrationScenario` states at length: `respond` blocks and
/// drains, so a backgrounded run is collected before the caller sees it and the
/// background run this scenario reads would not stand on the run plane.
///
/// **Skip, not failure.** Identical to every other runner here: a
/// `GenerationError.notWiredForLiveInference` prints a note and records no
/// issue.
///
/// - Parameter name: a short label identifying the scenario, used in the printed
///   result and skip lines.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runShellBackgroundScenario(name: String) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        let probe = ShellRunContextProbe()
        let registry = try MultiTool.Builder()
            .withShell(storeDirectory: LiveRouterFixture.makeTempDir(), sandbox: probe)
            .buildRegistry()
        let declaredJournalOp = registry.surface.entries.first { $0.path == shellExecutePath }?.journalOp
        // No instructions, for the same reason as every other runner here:
        // mounting the tools is the whole product surface, and their own
        // descriptions carry the contract.
        let seams = fixture.discoverySeams
        let session = fixture.profile.standard.makeSession(
            tools: try registry.makeSessionTools(selection: seams.selection, embedder: seams.embedder),
            discoveryPriming: scenarioDiscoveryPriming
        )

        // Started before the turn and read after it. The run plane has to be
        // read WHILE the run is going — a reading taken after the turn would
        // find whatever Router's own end-of-turn handling left, which is a
        // different question from the one this scenario asks.
        let watcher = Task {
            await observeShellRunPlane(probe: probe, registry: registry, declaredJournalOp: declaredJournalOp)
        }
        let start = Date()
        let turn = try await streamTurn(of: session, prompt: shellBackgroundPrompt)
        let elapsed = Date().timeIntervalSince(start)
        var plane = await watcher.value
        // The cancel comes after the turn. Until its settle period ends, the
        // `runCode` call of the turn waits for the snippet in band, and a
        // cancel then would end that call of the turn and not a background
        // run.
        await cancelSnippetRun(observed: &plane, probe: probe)

        // The journal half of task ^1hq8xny's split: `RoutedSessionActor.close()`
        // journals exactly what `SessionMailbox.sweep()` answers with, through
        // `SessionOutbox.journalWithoutStaging(event:)`, before it returns. That
        // half needs a loaded model to drive, which is why it stands here.
        await session.close()

        let journal = await journaledRunEvents(
            awaiting: plane.sweptRunToken, in: fixture)
        let evidence = ShellBackgroundEvidence(
            backgroundReports: backgroundReportCount(in: journal, of: plane.backgroundRun?.completionToken),
            declaredJournalOp: declaredJournalOp,
            plane: plane,
            sweptRunTerminals: terminals(in: journal, of: plane.sweptRunToken)
        )
        grade(scenario: name, checks: shellBackgroundChecks(for: evidence))

        reportGatedResult(
            scenario: name,
            line: "elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) "
                + "executeToken=\(plane.executeRunToken ?? "none") "
                + "backgroundReports=\(evidence.backgroundReports) "
                + "background=\(plane.backgroundRun?.description ?? "none") "
                + "declaredOp=\(evidence.declaredJournalOp ?? "none") "
                + "liveLines=\(plane.liveLines.count) "
                + "processGroup=\(plane.childProcessGroup.map { "\($0)" } ?? "none") "
                + "cancel=\(plane.cancelOutcome?.rawValue ?? "none") "
                + "childGone=\(plane.childGone) "
                + "sweptRun=\(plane.sweptRunToken ?? "none") "
                + "journaledEvents=\(journal.count) "
                + "sweptTerminals=\(evidence.sweptRunTerminals.count) "
                + "priming=\(primingLabel(turn)) "
                + "failedCalls=\(turn.failedCalls.count)\(turn.failedCalls.isEmpty ? "" : " \(turn.failedCalls)") "
                + "reply=\"\(turn.answer.prefix(shellBackgroundReplyPreviewCharacters))\""
        )
    }
}

/// How many leading characters of the model's reply the `RESULT` line prints.
///
/// The same bound the other gated runners' reply previews use, so one run of the
/// whole target reads as one log.
private let shellBackgroundReplyPreviewCharacters = 120

// MARK: - What the harness read off the run plane

/// One background run, as the run plane reports it.
///
/// The four fields stand together or not at all — a run is on the plane with all
/// of them, or it is not on the plane — so they are one value rather than four
/// optionals a reader would have to check for agreement.
///
/// Plain values rather than Router's own `BackgroundRun`, for the reason
/// `MailCollectionEvidence` states: that type has no public initializer, so a
/// record built from it could be graded only by a live run, and the grading rule
/// would then be checkable nowhere.
struct BackgroundShellRun: Sendable, CustomStringConvertible {

    /// The `tool` the run stands under — the tool's own name.
    let tool: String

    /// The `op` the run stands under.
    let op: String

    /// What kind of work the run is. A `runCode` run is a `RunKind.swiftTask`,
    /// and its cancel reaches the inner shell run through the cancellation of
    /// the snippet.
    let kind: RunKind

    /// The run's completion token.
    let completionToken: String

    /// The run as the `RESULT` line prints it.
    var description: String {
        "\(tool)/\(op)/\(kind.rawValue)"
    }
}

/// Everything the harness read off the run plane while the shell run was going,
/// plus what it left standing for the session-end sweep.
struct ShellRunPlaneObservation: Sendable {

    /// The completion token of the model's own `tools.shell.execute` run, or
    /// `nil` when no execute run started.
    ///
    /// It is read off the run's own ambient context, which the probe sandbox
    /// keeps. The token is also the `commandID` under which the store keeps the
    /// output of the run. The run is an inner run, so it never stands on the
    /// run plane (card `^6nnykct`).
    var executeRunToken: String?

    /// The model's own `runCode` run, which holds the shell run, as the run
    /// plane reported it, or `nil` when it never reached the plane.
    var backgroundRun: BackgroundShellRun?

    /// The lines `tools.shell.getLines` read back while the run was still
    /// going, each one formatted `"{lineNumber}: {text}"`.
    var liveLines: [String] = []

    /// The process group of the child, read out of the run's own first output
    /// line.
    var childProcessGroup: pid_t?

    /// What the canceler of the `runCode` run reported when the harness
    /// cancelled it.
    var cancelOutcome: OperationOutcome?

    /// Whether the child's process group held nothing at all before the
    /// deadline — the proof that the cancel of the snippet reached the shell
    /// run, and that the tree died and left no orphan.
    var childGone = false

    /// The completion token of the second shell run, left in the background for
    /// the session-end sweep.
    var sweptRunToken: String?
}

/// Reads the run plane of the live session while the model's turn is going.
///
/// Every step is a poll rather than one read, because a live model decides when
/// each of them becomes possible and because the engine sends a run to the
/// background as it takes it. A step that never becomes possible leaves its
/// readings unset and the verdict says which one stopped.
///
/// - Parameters:
///   - probe: the sandbox the shell capability was built with, which hands over
///     the ambient context of each `tools.shell.execute` run.
///   - registry: the built registry, whose `tools` hold the live
///     `tools.shell.getLines` verb over the same store.
///   - declaredJournalOp: the op the registration site declared for
///     `tools.shell.execute`, which the swept run stands under.
/// - Returns: what the harness managed to read.
private func observeShellRunPlane(
    probe: ShellRunContextProbe, registry: MultiTool.Registry, declaredJournalOp: String?
) async -> ShellRunPlaneObservation {
    var observation = ShellRunPlaneObservation()

    // Every wait below is a poll with the one shared hang-guard deadline of
    // this target, `IntegrationPoll.deadline`, and never a deadline of its
    // own: a live model decides when each reading becomes possible, and no
    // test checks the speed of the machine (card `^kdtrmhv`).
    var context: ToolContext?
    _ = await IntegrationPoll.holds {
        context = probe.observedContexts.first
        return context != nil
    }
    guard let context else { return observation }
    let token = context.completionToken
    observation.executeRunToken = token

    // The run plane `status()` reports. `MultiTool`'s `status()` global is
    // `ToolContext.backgroundRuns()` rendered as JS objects — see
    // `MultiTool.makeBackgroundRunHostFunctions(binding:)` — so this is the same
    // snapshot a snippet reads, taken through the same call.
    var background: BackgroundRun?
    _ = await IntegrationPoll.holds {
        background = await context.backgroundRuns().first { $0.tool == runCodeToolName }
        return background != nil
    }
    guard let background else { return observation }
    observation.backgroundRun = BackgroundShellRun(
        tool: background.tool, op: background.op, kind: background.kind,
        completionToken: background.completionToken)

    observation.liveLines = await liveOutput(of: token, in: registry)
    observation.childProcessGroup = processGroup(in: observation.liveLines)

    // Started BEFORE the cancel of `cancelSnippetRun(observed:probe:)`, so the
    // session certainly holds a background shell run when `close()` sweeps:
    // the run the model started is the one this scenario cancels, and a sweep
    // needs one of its own to answer for.
    observation.sweptRunToken = await startSweptRun(
        under: context, alongside: background.completionToken, in: registry, op: declaredJournalOp)
    return observation
}

/// Cancels the background `runCode` run of the model, and reads whether the
/// cancel reached the inner shell run.
///
/// Called after the turn, when the `runCode` call of the turn already answered
/// with its pending envelope, so the cancel ends a background run.
///
/// - Parameters:
///   - observation: what the harness read off the run plane; the outcome of the
///     cancel and the state of the process group go into it.
///   - probe: the sandbox the shell capability was built with, whose first
///     context carries the session's mailbox.
private func cancelSnippetRun(
    observed observation: inout ShellRunPlaneObservation, probe: ShellRunContextProbe
) async {
    guard let context = probe.observedContexts.first, let token = observation.backgroundRun?.completionToken else {
        return
    }
    observation.cancelOutcome = cancelReport(of: await context.cancel(completionToken: token))
    guard let group = observation.childProcessGroup else { return }
    // A poll and not slack: the cancel of the snippet cancels the inner call,
    // `ShellRunner` then kills the tree, and the leader of the group stays an
    // unreaped child of this process until swift-subprocess reaps it. A group
    // that still holds a zombie still answers the probe.
    observation.childGone = await IntegrationPoll.holds {
        !processGroupStands(group)
    }
}

/// Reads the stored output of a run that is still going, through the live
/// `tools.shell.getLines` verb.
///
/// The verb rather than the store, because the store is not reachable: a
/// `ShellState` keeps its records in memory, so a second one built over the same
/// directory would answer for no run at all. The verb the registry holds is the
/// one the capability built, over the one store the run wrote into.
///
/// - Parameters:
///   - token: the run's completion token, which is also its `commandID`.
///   - registry: the built registry holding the live verb.
/// - Returns: the lines read, or an empty array when the verb is not there or
///   the run wrote nothing before the deadline.
private func liveOutput(of token: String, in registry: MultiTool.Registry) async -> [String] {
    guard let getLines = registry.tools[shellGetLinesPath] as? GetLines else { return [] }
    var lines: [String] = []
    _ = await IntegrationPoll.holds {
        lines = (try? await getLines.call(arguments: GetLinesArguments(commandID: token)))?.lines ?? []
        return !lines.isEmpty
    }
    return lines
}

/// The separator a stored line puts between its number and its text.
private let storedLineSeparator: Character = ":"

/// The process group the run's own first output line named.
///
/// The command echoes `$$` before anything else, and `ShellRunner` spawns each
/// child into a process group of its own, so that number is the identifier of
/// the group the whole command tree stands in.
///
/// - Parameter lines: the stored lines, each one formatted
///   `"{lineNumber}: {text}"`.
/// - Returns: the process group, or `nil` when no line carried one.
private func processGroup(in lines: [String]) -> pid_t? {
    for line in lines {
        guard let separator = line.firstIndex(of: storedLineSeparator) else { continue }
        let text = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        if let group = pid_t(text) { return group }
    }
    return nil
}

/// Whether any process still stands in the process group that `group` leads.
///
/// Every group this is asked about is one this scenario's own command created
/// and printed.
///
/// - Parameter group: the identifier of the process group to ask about.
/// - Returns: `true` while the group still holds a process.
private func processGroupStands(_ group: pid_t) -> Bool {
    killpg(group, existenceProbeSignal) == killpgReachedGroup
}

/// Starts one more background shell run on the same session, and answers with
/// its completion token.
///
/// The verb is mounted on the session's own mailbox through the context of the
/// model's shell run, the way a session mounts a tool. `Execute.mount` declares
/// a background mount, and the `sleep` runs longer than the settle period, so
/// the run goes to the background as a `RunKind.process` run. A `runCode`
/// snippet cannot start this run: an inner call runs to completion (card
/// `^6nnykct`), so the snippet would wait for the whole `sleep`.
///
/// It exists for one reading: `close()` has to have a background shell run to
/// sweep, and the run the model started is the one this scenario cancels.
///
/// - Parameters:
///   - context: the ambient context of the model's own shell run, which carries
///     the session's mailbox.
///   - other: the completion token of the model's background run, so the new
///     one is told apart from it on the plane.
///   - registry: the registry the session was mounted over, which is what makes
///     the new run stand on the same store and the same mailbox.
///   - op: the op the new run stands under: the declared op of the verb.
/// - Returns: the new run's completion token, or `nil` when it never went to
///   the background.
private func startSweptRun(
    under context: ToolContext, alongside other: String, in registry: MultiTool.Registry, op: String?
) async -> String? {
    guard let execute = registry.tools[shellExecutePath] as? Execute else { return nil }
    let mounted = context.mount(execute, op: op)
    _ = try? await mounted.call(arguments: ExecuteArguments(command: "sleep \(sweptRunSleepSeconds)"))
    var token: String?
    _ = await IntegrationPoll.holds {
        token = await context.backgroundRuns()
            .first { $0.kind == .process && $0.completionToken != other }?
            .completionToken
        return token != nil
    }
    return token
}

/// The outcome a cancel reported, or `nil` when there was nothing to report.
///
/// Only `CancelOutcome.reported` is read. `.alreadySettled` hands back the
/// mailbox's RETAINED terminal event, which Router's ^vbja15j makes wrong for a
/// killed run — `ToolRun` builds it from `terminalFacts(for:)`, and
/// a `.process` run stopped by `killpg` lets the wrapped call return normally,
/// so the retained outcome reads `succeeded` for a run a SIGKILL ended. Reading
/// it here would assert the defect. A run still going has no retained event, so
/// `.reported` is the case a cancel of a live run takes, and the value it
/// carries is the canceler's own answer.
///
/// - Parameter outcome: what `ToolContext.cancel(completionToken:)` answered.
/// - Returns: the canceler's own outcome, or `nil` for any other case.
private func cancelReport(of outcome: CancelOutcome) -> OperationOutcome? {
    guard case .reported(let reported) = outcome else { return nil }
    return reported
}

// MARK: - The journal

/// Every operation event the session journaled, read once the swept run's
/// terminal has landed.
///
/// The journal is where BOTH of this scenario's event assertions are read, and
/// it is the only plane that can carry either one. The turn's own stream cannot:
/// `SessionEvent.toolStatus(.running, summary:)` arrives with an empty summary
/// for a background call, so a run that reported its background handoff and one
/// that went silent read identically there. Measured on 2026-08-25 — the
/// recorded journal held the background report and the swept terminal, and the
/// stream's summary held nothing.
///
/// Read after `close()`, so one snapshot carries the whole run: the background
/// report the turn wrote, and the terminal the sweep wrote.
///
/// A poll, because the transcript is a file: `close()` journals before it
/// returns, and this is the synchronization point onto the write rather than a
/// claim about how long it takes.
///
/// - Parameters:
///   - token: the swept run's completion token, or `nil` when no run was left to
///     sweep — in which case there is no terminal to wait for and the journal is
///     read once.
///   - fixture: the resolved fixture, whose recording root holds the transcript.
/// - Returns: every journaled operation event, in transcript order.
private func journaledRunEvents(
    awaiting token: String?, in fixture: LiveRouterFixture
) async -> [OperationEvent] {
    var events: [OperationEvent] = []
    _ = await IntegrationPoll.holds {
        events = journaledOperationEvents(in: (try? fixture.transcriptEvents()) ?? [])
        guard let token else { return true }
        return !terminals(in: events, of: token).isEmpty
    }
    return events
}

/// Every `OperationEvent` the recorded transcript carries.
///
/// `TranscriptEvent.operationEvents` is Router's own reader for this, and it
/// already reads every entry rather than `.toolOutput` entries alone — Router
/// writes the same segment two ways, and the knowledge of that belongs on the
/// side that makes both writes. This fixture used to destructure the segment
/// itself and name the internal `OperationEventSegment`; it names neither now.
///
/// - Parameter events: the merged transcript.
/// - Returns: the operation events, in transcript order.
private func journaledOperationEvents(in events: [TranscriptEvent]) -> [OperationEvent] {
    events.flatMap(\.operationEvents)
}

/// The journaled terminal events of one run.
///
/// - Parameters:
///   - events: the journaled operation events.
///   - token: the run's completion token, or `nil` when there is no run to ask
///     about.
/// - Returns: the terminal events under that token.
private func terminals(in events: [OperationEvent], of token: String?) -> [OperationEvent] {
    guard let token else { return [] }
    return events.filter { $0.correlationID == token && $0.kind == .completed }
}

// MARK: - The background report

/// How many background reports the session journaled for one run.
///
/// `BackgroundToolRunner` posts one synthesized `progress` event as it starts a
/// background run, and that event's `detail` is the rendered pending envelope
/// OF THAT RUN. The envelope's own token is the only key that names the run,
/// and the `correlationID` of the event is not:
///
/// - The report of a run can stand under the correlation of another run. An
///   event that an inner run posts reaches the session re-stamped with the
///   OUTER run's correlation (`AmbientUpstreamSink`, `ToolContext.post(_:)`).
/// - The swept run is a second background run, and its report can stand under
///   any correlation. Its envelope names the swept run, and thus it is not
///   counted for the run the model started.
///
/// Router's own byte-shape recognizer decides which detail is an envelope, and
/// it decodes the token through the envelope's own `Codable` conformance. The
/// frame is Router's, so a hand-written parse would be a second spelling of it.
///
/// - Parameters:
///   - events: the journaled operation events.
///   - token: the completion token of the run, or `nil` when the harness saw
///     no run.
/// - Returns: how many journaled events are this run's background report.
func backgroundReportCount(in events: [OperationEvent], of token: String?) -> Int {
    guard let token else { return 0 }
    return events.filter { event in
        event.kind == .progress
            && PendingRunEnvelope.makeDecoded(fromRendered: event.detail)?.completionToken == token
    }
    .count
}

// MARK: - Grading

/// Everything one shell background run produced that its verdict is graded on.
struct ShellBackgroundEvidence: Sendable {

    /// How many background reports the session journaled for the background
    /// `runCode` run, counted by the token of
    /// `ShellRunPlaneObservation.backgroundRun`.
    let backgroundReports: Int

    /// The `"verb noun"` pair the registration site declared for
    /// `tools.shell.execute`, read off the rendered surface.
    ///
    /// The expected value is read from the surface rather than restated, so the
    /// assertion compares what a RUN carries against what the REGISTRATION SITE
    /// declared, and the two cannot be made to agree by editing one of them.
    let declaredJournalOp: String?

    /// What the harness read off the run plane while the run was going.
    let plane: ShellRunPlaneObservation

    /// The terminal events the session journaled under the swept run's token.
    let sweptRunTerminals: [OperationEvent]
}

/// The label of the check that grades the model as having started a
/// `tools.shell.execute` run under a completion token of its own.
private let shellExecuteRunStartedCheckName = "executeRunStarted"

/// The label of the check that grades the background handoff as having reported
/// itself exactly once.
private let shellBackgroundReportCheckName = "backgroundReport"

/// The label of the check that grades the run plane as listing the `runCode`
/// run that holds the shell run.
private let snippetRunListedCheckName = "statusListsSnippetRun"

/// The label of the check that grades `tools.shell.getLines` as having read the
/// live run.
private let shellLiveOutputCheckName = "getLinesReadsLiveRun"

/// The label of the check that grades the cancel as having reported
/// `.cancelled`.
private let snippetCancelCheckName = "cancelReportsCancelled"

/// The label of the check that grades the child's process group as gone.
private let shellChildGoneCheckName = "childProcessGone"

/// The label of the check that grades the journal as holding exactly one
/// terminal event for the swept run.
private let shellJournaledTerminalCheckName = "oneJournaledTerminal"

/// Grades one shell background run into the conditions its verdict is the
/// conjunction of.
///
/// Separate from the run that produced the evidence, exactly as
/// `scenarioChecks(for:answerContainsOneOf:answerMustNotContain:readingContainsOneOf:groundedIn:)` is,
/// so the grading rule is a pure function over plain values rather than
/// something only a live run can exercise.
///
/// **No answer check.** The other runners in this target grade the model's reply
/// because the reply is the only evidence they have that the work happened. This
/// one has stronger evidence: the snippet stood on the run plane, a live verb
/// read the output that the inner shell run wrote, the canceler of the snippet
/// reported the cancel, and the process group is gone. A reply check beside
/// those would add nothing and would make the verdict depend on how a model
/// chose to phrase a completion token.
///
/// - Parameter evidence: what the run produced.
/// - Returns: every condition this run is graded on, in reporting order.
func shellBackgroundChecks(for evidence: ShellBackgroundEvidence) -> [ScenarioCheck] {
    let plane = evidence.plane
    return [
        ScenarioCheck(
            name: shellExecuteRunStartedCheckName,
            held: plane.executeRunToken?.isEmpty == false,
            failureMessage:
                "expected the model to start a tools.shell.execute run under a completion token "
                + "of its own, but no execute run reached the shell sandbox"
        ),
        ScenarioCheck(
            name: shellBackgroundReportCheckName,
            held: evidence.backgroundReports == backgroundReportsPerRun,
            failureMessage:
                "expected the journal to hold exactly \(backgroundReportsPerRun) progress event "
                + "carrying the pending envelope of the runCode run "
                + "\(plane.backgroundRun?.completionToken ?? "(never listed)"), and it held "
                + "\(evidence.backgroundReports)"
        ),
        ScenarioCheck(
            name: snippetRunListedCheckName,
            held: plane.backgroundRun?.kind == .swiftTask && plane.backgroundRun?.tool == runCodeToolName,
            failureMessage:
                "expected the run plane to list the background \(runCodeToolName) run as kind "
                + "\(RunKind.swiftTask.rawValue), and it listed "
                + "\(plane.backgroundRun?.description ?? "no run at all")"
        ),
        ScenarioCheck(
            name: shellLiveOutputCheckName,
            held: plane.childProcessGroup != nil,
            failureMessage:
                "expected tools.shell.getLines to read the live run's output under the same "
                + "completion token, and it read \(plane.liveLines)"
        ),
        ScenarioCheck(
            name: snippetCancelCheckName,
            held: plane.cancelOutcome == .cancelled,
            failureMessage:
                "expected the canceler of the runCode run to report "
                + "\(OperationOutcome.cancelled.rawValue), and it reported "
                + "\(plane.cancelOutcome?.rawValue ?? "nothing")"
        ),
        ScenarioCheck(
            name: shellChildGoneCheckName,
            held: plane.childGone,
            failureMessage:
                "expected the child's process group "
                + "\(plane.childProcessGroup.map { "\($0)" } ?? "(never read)") to hold nothing "
                + "after the cancel of the snippet, and it still held a process"
        ),
        ScenarioCheck(
            name: shellJournaledTerminalCheckName,
            held: evidence.sweptRunTerminals.count == terminalEventsPerRun
                && evidence.sweptRunTerminals.allSatisfy {
                    $0.outcome == .stopped && $0.op == evidence.declaredJournalOp
                },
            failureMessage:
                "expected close() to journal exactly \(terminalEventsPerRun) terminal event for "
                + "the run still in the background at teardown, under that run's own completion "
                + "token, its declared op \(evidence.declaredJournalOp ?? "none") and the outcome "
                + "\(OperationOutcome.stopped.rawValue); the journal held "
                + "\(evidence.sweptRunTerminals.map { "\($0.op)/\($0.outcome?.rawValue ?? "none")" })"
        ),
    ]
}
