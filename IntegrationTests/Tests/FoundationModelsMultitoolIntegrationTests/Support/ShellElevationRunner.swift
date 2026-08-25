import Foundation
import Testing

import FoundationModelsRouter

@testable import FoundationModelsMultitool

// MARK: - The shell elevation scenario
//
// eventplan.md § "Phases", phase 2: "Shell is the reference emitter. Its
// detached commands prove the elevation path end to end."
//
// One live turn drives the elevation, and the harness reads the run plane while
// the run is still going. The split is deliberate, and it is the split the
// product itself makes:
//
// - The MODEL owns discovery and elevation. It finds `tools.shell.execute`
//   through `searchTools` and starts the command from a `runCode` snippet. Every
//   mounted `runCode` call answers a wait clock of zero
//   (`MultiTool.detachmentClocks(from:)`), so that outer run elevates and hands
//   back a pending envelope on every turn.
// - The HARNESS owns the readings that follow, because a live model cannot be
//   asked to make them reliably and a scenario that asked would be grading the
//   model rather than the elevation path. Each reading is taken through the
//   product's own surface: the run plane `status()` reports
//   (`ToolContext.parkedRuns()`), the live verb `tools.shell.getLines`, the
//   canceler `cancel()` invokes (`ToolContext.cancel(completionToken:)`), and
//   the session's own run journal.
//
// **The mailbox's retained outcome is never read here.** Router's ^vbja15j:
// `DetachingTool.settle` builds its terminal from `terminalFacts(for:)`, which
// sees only whether the wrapped Swift call returned. A `.process` run stopped by
// `killpg` lets `Execute.call` return normally, so the mailbox retains
// `OperationOutcome.succeeded` for a run a SIGKILL ended. `wait(completionToken:)`
// and a late `cancel(completionToken:)` both answer with that retained value, so
// an assertion on either would be asserting the defect. What this scenario reads
// instead is honest on both sides: `cancel()` on a run still going reports the
// CANCELER's own answer, and the journal carries what the sink saw.
//
// The defect is visible in this scenario's own recorded journal, and the reading
// below steps around it rather than over it. Measured on 2026-08-25, one run:
// the outer `runCode` run's terminal is journaled `outcome: succeeded` with the
// shell run's pending envelope as its detail, while the shell run swept at
// `close()` is journaled `outcome: stopped` under its own completion token. The
// second is what this scenario grades.

/// The command the scenario asks the model to start.
///
/// Three properties, each of them load-bearing:
///
/// 1. **It never ends.** The run therefore certainly still stands on the run
///    plane while the harness reads it, so what ends it is the cancel and never
///    the command ending by itself.
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
private let shellElevationCommand = "echo $$ ; while true ; do echo tick ; sleep 1 ; done"

/// The request the model is given.
///
/// A user's own words, and the whole product surface is the two mounted tools:
/// no session instruction, exactly as every other runner in this target mounts
/// its scenario. The command is quoted in the prompt because the scenario is
/// about the elevation path rather than about which command a model invents, and
/// the process group the harness probes has to be one this scenario's own
/// command created.
///
/// It asks for the background start explicitly, in the words the verb's own
/// description uses ("start a long command in the background and get its
/// completion token back at once"). A call that waits instead still elevates —
/// `Execute.detachmentMount` answers a 30-second block window and this command
/// outlives it — so the scenario does not depend on which of the two the model
/// chose.
private let shellElevationPrompt = """
    Start this shell command running in the background and tell me the completion token it hands \
    back. Do not wait for it to finish, because it never finishes.

    \(shellElevationCommand)
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
/// exists so that one shell run is still parked when `close()` sweeps, and the
/// only reading taken of it is the terminal event `close()` journals. It sleeps
/// far longer than the whole suite, so it cannot end by itself and be swept as a
/// finished run.
private let sweptRunSleepSeconds = 600

/// How many seconds the harness waits for the model to reach
/// `tools.shell.execute`.
///
/// This bounds the whole model-driven half: discovery, the `runCode` call, and
/// the snippet reaching the verb. It is generous because a live turn on the
/// shipped 30-billion-parameter pin takes minutes, and it is bounded because a
/// turn that never calls the verb must report that rather than hang until the
/// suite's own time limit fires and reads as a hang of something else.
private let shellRunArrivalDeadlineSeconds = 480

/// How long the harness waits for the model to reach `tools.shell.execute`.
private let shellRunArrivalDeadline = Duration.seconds(shellRunArrivalDeadlineSeconds)

/// How many seconds the harness waits for the started run to reach the run
/// plane.
///
/// Longer than `Execute`'s own 30-second block window, because a call that did
/// not ask to skip the wait parks only when that window elapses.
private let shellRunParkDeadlineSeconds = 90

/// How long the harness waits for the started run to reach the run plane.
private let shellRunParkDeadline = Duration.seconds(shellRunParkDeadlineSeconds)

/// How many seconds the harness waits for the live run to have written a line.
private let shellRunOutputDeadlineSeconds = 30

/// How long the harness waits for the live run to have written a line.
private let shellRunOutputDeadline = Duration.seconds(shellRunOutputDeadlineSeconds)

/// How many seconds the harness waits for the killed process group to go away.
///
/// A poll and not slack: `killpg` kills the tree at once, and the leader of the
/// group then stays an unreaped child of this process until swift-subprocess
/// reaps it. A group that still holds a zombie still answers the probe.
private let killedProcessGroupDeadlineSeconds = 30

/// How long the harness waits for the killed process group to go away.
private let killedProcessGroupDeadline = Duration.seconds(killedProcessGroupDeadlineSeconds)

/// How many seconds the harness waits for the swept terminal to reach the
/// transcript.
///
/// `RoutedSessionActor.close()` journals the sweep's terminals before it
/// returns, and the journal write is chained through the outbox — but the
/// recorder writes the transcript to disk, and this poll is the synchronization
/// point onto that file rather than a claim about how long the write takes.
private let journaledTerminalDeadlineSeconds = 30

/// How long the harness waits for the swept terminal to reach the transcript.
private let journaledTerminalDeadline = Duration.seconds(journaledTerminalDeadlineSeconds)

/// The signal `killpg` takes to ASK whether a process group is still there.
///
/// Signal 0 sends NOTHING. `killpg` performs the checks of a signal it is about
/// to send and then sends none, thus this is the one reading that answers "does
/// this group still hold a process" with no risk to what stands in the group.
/// The only group this scenario ever names is the one its own command printed.
private let existenceProbeSignal: Int32 = 0

/// What `killpg` answers when it reached the group.
private let killpgReachedGroup: Int32 = 0

/// How many elevation reports one elevated run makes.
///
/// `DetachingTool` posts exactly one synthesized `progress` event as it parks a
/// run — `RunEventFunnel.markDetached(postingIfSilent:)` — and its `detail` is
/// the rendered pending envelope of that run.
private let elevationReportsPerRun = 1

/// How many terminal events one swept run gets.
///
/// `SessionMailbox.sweep()` states the invariant: exactly one for each run,
/// never two. `RoutedSessionActor.close()` journals exactly that list.
private let terminalEventsPerRun = 1

/// Runs the shell elevation scenario end to end against a freshly resolved live
/// profile, on the shipped configuration.
///
/// The surface is `MultiTool.Builder().withShell(...)` vended through
/// `MultiTool.Registry.makeSessionTools(librarian:)` and mounted on a
/// `RoutedSession` the resolved `.standard` slot vends — the same wiring
/// `CLIRunner.runDemo` ships, with `searchTools` backed by the resolved `.flash`
/// slot. Never a bare `LanguageModelSession`: elevation exists only under
/// Router's own per-session tool wiring, so a bare session would have no
/// elevation path to prove.
///
/// The turn is streamed rather than driven through `respond(to:)`, for the
/// reason `runNativeIntegrationScenario` states at length: `respond` blocks and
/// drains, so a backgrounded run is collected before the caller sees it and the
/// pending envelope this scenario grades would never surface.
///
/// **Skip, not failure.** Identical to every other runner here: a
/// `GenerationError.notWiredForLiveInference` prints a note and records no
/// issue.
///
/// - Parameter name: a short label identifying the scenario, used in the printed
///   result and skip lines.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`.
func runShellElevationScenario(name: String) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        let probe = ShellRunContextProbe()
        let registry = try MultiTool.Builder()
            .withShell(storeDirectory: LiveRouterFixture.makeTempDir(), sandbox: probe)
            .buildRegistry()
        // No instructions, for the same reason as every other runner here:
        // mounting the tools is the whole product surface, and their own
        // descriptions carry the contract.
        let session = fixture.profile.standard.makeSession(
            tools: try registry.makeSessionTools(librarian: fixture.profile.flash),
            discoveryPriming: scenarioDiscoveryPriming
        )

        // Started before the turn and read after it. The run plane has to be
        // read WHILE the run is going — a reading taken after the turn would
        // find whatever Router's own end-of-turn handling left, which is a
        // different question from the one this scenario asks.
        let watcher = Task { await observeShellRunPlane(probe: probe, registry: registry) }
        let start = Date()
        let turn = try await streamTurn(of: session, prompt: shellElevationPrompt)
        let elapsed = Date().timeIntervalSince(start)
        let plane = await watcher.value

        // The journal half of task ^1hq8xny's split: `RoutedSessionActor.close()`
        // journals exactly what `SessionMailbox.sweep()` answers with, through
        // `SessionOutbox.journalWithoutStaging(event:)`, before it returns. That
        // half needs a loaded model to drive, which is why it stands here.
        await session.close()

        let elevated = elevatedRunToken(in: turn.toolOutputs)
        let journal = await journaledRunEvents(
            awaiting: plane.sweptRunToken, in: fixture)
        let evidence = ShellElevationEvidence(
            elevatedRunToken: elevated,
            elevationReports: elevationReportCount(in: journal, of: elevated),
            declaredJournalOp: registry.surface.entries
                .first { $0.path == shellExecutePath }?.journalOp,
            plane: plane,
            sweptRunTerminals: terminals(in: journal, of: plane.sweptRunToken)
        )
        grade(scenario: name, checks: shellElevationChecks(for: evidence))

        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) "
                + "elevatedRun=\(evidence.elevatedRunToken ?? "none") "
                + "elevationReports=\(evidence.elevationReports) "
                + "parked=\(plane.parkedRun?.description ?? "none") "
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
                + "reply=\"\(turn.answer.prefix(shellElevationReplyPreviewCharacters))\""
        )
    }
}

/// How many leading characters of the model's reply the `RESULT` line prints.
///
/// The same bound the other gated runners' reply previews use, so one run of the
/// whole target reads as one log.
private let shellElevationReplyPreviewCharacters = 120

// MARK: - What the harness read off the run plane

/// One parked shell run, as the run plane reports it.
///
/// The four fields stand together or not at all — a run is on the plane with all
/// of them, or it is not on the plane — so they are one value rather than four
/// optionals a reader would have to check for agreement.
///
/// Plain values rather than Router's own `ParkedRun`, for the reason
/// `InBandCollectionEvidence` states: that type has no public initializer, so a
/// record built from it could be graded only by a live run, and the grading rule
/// would then be checkable nowhere.
struct ParkedShellRun: Sendable, CustomStringConvertible {

    /// The `tool` the run stands under — the verb's own name.
    let tool: String

    /// The `op` the run stands under — the `"verb noun"` pair the registration
    /// site derived.
    let op: String

    /// What kind of work the run is. A shell run declares `RunKind.process`,
    /// which is what makes its stop authoritative.
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

    /// The model's own shell run, as the run plane reported it, or `nil` when it
    /// never reached the plane.
    var parkedRun: ParkedShellRun?

    /// The lines `tools.shell.getLines` read back while the run was still
    /// going, each one formatted `"{lineNumber}: {text}"`.
    var liveLines: [String] = []

    /// The process group of the child, read out of the run's own first output
    /// line.
    var childProcessGroup: pid_t?

    /// What the run's own canceler reported when the harness cancelled it.
    var cancelOutcome: OperationOutcome?

    /// Whether the child's process group held nothing at all before the
    /// deadline — the proof that the tree died and left no orphan.
    var childGone = false

    /// The completion token of the second shell run, left parked for the
    /// session-end sweep.
    var sweptRunToken: String?
}

/// Reads the run plane of the live session while the model's turn is going.
///
/// Every step is a poll rather than one read, because a live model decides when
/// each of them becomes possible and because the engine parks a run as it takes
/// it. A step that never becomes possible leaves its readings unset and the
/// verdict says which one stopped.
///
/// - Parameters:
///   - probe: the sandbox the shell capability was built with, which hands over
///     the ambient context of each `tools.shell.execute` run.
///   - registry: the built registry, whose `tools` hold the live
///     `tools.shell.getLines` verb over the same store.
/// - Returns: what the harness managed to read.
private func observeShellRunPlane(
    probe: ShellRunContextProbe, registry: MultiTool.Registry
) async -> ShellRunPlaneObservation {
    var observation = ShellRunPlaneObservation()

    var context: ToolContext?
    _ = await IntegrationPoll.holds(before: shellRunArrivalDeadline) {
        context = probe.observedContexts.first
        return context != nil
    }
    guard let context else { return observation }
    let token = context.completionToken

    // The run plane `status()` reports. `MultiTool`'s `status()` global is
    // `ToolContext.parkedRuns()` rendered as JS objects — see
    // `MultiTool.makeBackgroundRunHostFunctions(binding:)` — so this is the same
    // snapshot a snippet reads, taken through the same call.
    var parked: ParkedRun?
    _ = await IntegrationPoll.holds(before: shellRunParkDeadline) {
        parked = await context.parkedRuns().first { $0.completionToken == token }
        return parked != nil
    }
    guard let parked else { return observation }
    observation.parkedRun = ParkedShellRun(
        tool: parked.tool, op: parked.op, kind: parked.kind,
        completionToken: parked.completionToken)

    observation.liveLines = await liveOutput(of: token, in: registry)
    observation.childProcessGroup = processGroup(in: observation.liveLines)

    // Started BEFORE the cancel below, so the session certainly holds a parked
    // shell run when `close()` sweeps: the run the model started is the one this
    // scenario cancels, and a sweep needs one of its own to answer for.
    observation.sweptRunToken = await startSweptRun(
        under: context, alongside: token, in: registry)

    observation.cancelOutcome = cancelReport(of: await context.cancel(completionToken: token))
    if let group = observation.childProcessGroup {
        observation.childGone = await IntegrationPoll.holds(before: killedProcessGroupDeadline) {
            !processGroupStands(group)
        }
    }
    return observation
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
    _ = await IntegrationPoll.holds(before: shellRunOutputDeadline) {
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
/// Through a real `runCode` snippet under the session's own ambient context,
/// which is the path an inner `tools.*` call always takes (`RunBinding`): the
/// unmounted `MultiTool` runs the snippet inline, and the inner
/// `tools.shell.execute` call parks on the session's mailbox because
/// `Execute.detachmentMount` declares a detaching mount and `wait: false`
/// answers a block window of zero. The root package's `RegisteredJournalOpTests`
/// drives a snippet the same way.
///
/// It exists for one reading: `close()` has to have a parked shell run to sweep,
/// and the run the model started is the one this scenario cancels.
///
/// - Parameters:
///   - context: the ambient context of the model's own shell run, which carries
///     the session's mailbox.
///   - other: the completion token of that run, so the new one is told apart
///     from it on the plane.
///   - registry: the registry the session was mounted over, which is what makes
///     the new run stand on the same store and the same mailbox.
/// - Returns: the new run's completion token, or `nil` when it never parked.
private func startSweptRun(
    under context: ToolContext, alongside other: String, in registry: MultiTool.Registry
) async -> String? {
    let multiTool = MultiTool(registry: registry)
    _ = try? await ToolContext.$current.withValue(context) {
        try await multiTool.call(
            arguments: RunCodeArguments(
                code: """
                    return await tools.\(shellExecutePath)({ \
                    command: "sleep \(sweptRunSleepSeconds)", wait: false });
                    """
            )
        )
    }
    var token: String?
    _ = await IntegrationPoll.holds(before: shellRunParkDeadline) {
        token = await context.parkedRuns()
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
/// killed run — `DetachingTool.settle` builds it from `terminalFacts(for:)`, and
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
/// for an elevated call, so a run that reported its elevation and one that went
/// silent read identically there. Measured on 2026-08-25 — the recorded journal
/// held the elevation report and the swept terminal, and the stream's summary
/// held nothing.
///
/// Read after `close()`, so one snapshot carries the whole run: the elevation
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
    _ = await IntegrationPoll.holds(before: journaledTerminalDeadline) {
        events = journaledOperationEvents(in: (try? fixture.transcriptEvents()) ?? [])
        guard let token else { return true }
        return !terminals(in: events, of: token).isEmpty
    }
    return events
}

/// Every `OperationEvent` the recorded transcript carries.
///
/// The typed payload is what the run journal writes, and it is the only place a
/// run's own identity survives: a `.toolOutput` entry's id is a fresh ULID by
/// design, and the `correlationID` travels inside the segment.
///
/// Read off every entry rather than off `.toolOutput` entries alone, because
/// Router writes the same segment two ways — the run journal's own entry, and
/// the segments a drained event rides onto the turn's prompt entry.
///
/// - Parameter events: the merged transcript.
/// - Returns: the operation events, in transcript order.
private func journaledOperationEvents(in events: [TranscriptEvent]) -> [OperationEvent] {
    events.flatMap { event in
        (event.entry?.segments ?? []).compactMap { segment -> OperationEvent? in
            guard case .structure(let id, let schemaName, let contentJSON) = segment else {
                return nil
            }
            return try? OperationEventSegment(
                schemaName: schemaName, contentJSON: contentJSON, id: id
            )?.content
        }
    }
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

// MARK: - The elevated run

/// The completion token of the run that elevated, read off the pending envelope
/// it handed back.
///
/// Router's own byte-shape recognizer decides which output is an envelope, and
/// the token is decoded through the envelope's own `Codable` conformance rather
/// than parsed out of the rendered text: the frame is private to Router, so a
/// hand-written parse would be a second spelling of it.
///
/// The FIRST envelope, because that is the outer `runCode` run of the turn — the
/// one elevation point per snippet (`MultiTool+Detachment`).
///
/// - Parameter outputs: each completed tool call's own output text, in
///   completion order.
/// - Returns: the elevated run's completion token, or `nil` when no call
///   elevated.
private func elevatedRunToken(in outputs: [String]) -> String? {
    guard let rendered = outputs.first(where: PendingRunEnvelope.isRendered) else { return nil }
    return try? JSONDecoder()
        .decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
        .completionToken
}

/// How many elevation reports the session journaled for one run.
///
/// `DetachingTool` posts one synthesized `progress` event as it parks a run, and
/// that event's `detail` is the rendered pending envelope OF THAT RUN. Both
/// halves are needed to count it, and this is why:
///
/// - The `correlationID` alone is not enough. An inner `tools.*` run's events
///   reach the session re-stamped with the OUTER run's correlation
///   (`AmbientUpstreamSink`, `ToolContext.post(_:)`), so the shell run's own
///   elevation report is journaled under the `runCode` run's token too, and so
///   is every output chunk it reports.
/// - The envelope's own token tells them apart, because each report carries the
///   envelope of the run it is about.
///
/// Measured on 2026-08-25, one recorded run: four `progress` events stand under
/// the elevated run's correlation — its own elevation report, the shell run's,
/// one line of shell output, and the swept run's elevation report — and exactly
/// one of them carries an envelope naming the elevated run.
///
/// - Parameters:
///   - events: the journaled operation events.
///   - token: the elevated run's completion token, or `nil` when nothing
///     elevated.
/// - Returns: how many journaled events are this run's elevation report.
private func elevationReportCount(in events: [OperationEvent], of token: String?) -> Int {
    guard let token else { return 0 }
    return events.filter { event in
        guard event.kind == .progress,
            event.correlationID == token,
            PendingRunEnvelope.isRendered(text: event.detail)
        else {
            return false
        }
        let envelope = try? JSONDecoder()
            .decode(PendingRunEnvelope.self, from: Data(event.detail.utf8))
        return envelope?.completionToken == token
    }
    .count
}

// MARK: - Grading

/// Everything one shell elevation run produced that its verdict is graded on.
struct ShellElevationEvidence: Sendable {

    /// The completion token the elevated `runCode` call handed back.
    let elevatedRunToken: String?

    /// How many elevation reports the session journaled for that run.
    let elevationReports: Int

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

/// The label of the check that grades the elevated call as having handed a
/// pending envelope back.
private let shellPendingEnvelopeCheckName = "pendingEnvelope"

/// The label of the check that grades the elevation as having reported itself
/// exactly once.
private let shellElevationReportCheckName = "elevationReport"

/// The label of the check that grades the run plane as listing the shell run.
private let shellRunListedCheckName = "statusListsShellRun"

/// The label of the check that grades `tools.shell.getLines` as having read the
/// live run.
private let shellLiveOutputCheckName = "getLinesReadsLiveRun"

/// The label of the check that grades the cancel as having reported `.stopped`.
private let shellCancelStoppedCheckName = "cancelReportsStopped"

/// The label of the check that grades the child's process group as gone.
private let shellChildGoneCheckName = "childProcessGone"

/// The label of the check that grades the journal as holding exactly one
/// terminal event for the swept run.
private let shellJournaledTerminalCheckName = "oneJournaledTerminal"

/// Grades one shell elevation run into the conditions its verdict is the
/// conjunction of.
///
/// Separate from the run that produced the evidence, exactly as
/// `scenarioChecks(for:answerContainsOneOf:answerMustNotContain:groundedIn:)` is,
/// so the grading rule is a pure function over plain values rather than
/// something only a live run can exercise.
///
/// **No answer check.** The other runners in this target grade the model's reply
/// because the reply is the only evidence they have that the work happened. This
/// one has stronger evidence: a run stood on the run plane under the declared
/// journal op, a live verb read the output that run wrote, a canceler reported
/// the stop, and the process group is gone. A reply check beside those would add
/// nothing and would make the verdict depend on how a model chose to phrase a
/// completion token.
///
/// - Parameter evidence: what the run produced.
/// - Returns: every condition this run is graded on, in reporting order.
func shellElevationChecks(for evidence: ShellElevationEvidence) -> [ScenarioCheck] {
    let plane = evidence.plane
    return [
        ScenarioCheck(
            name: shellPendingEnvelopeCheckName,
            held: evidence.elevatedRunToken?.isEmpty == false,
            failureMessage:
                "expected a runCode call to elevate and hand back a pending envelope carrying a "
                + "completion token, but no tool output was one"
        ),
        ScenarioCheck(
            name: shellElevationReportCheckName,
            held: evidence.elevationReports == elevationReportsPerRun,
            failureMessage:
                "expected the journal to hold exactly \(elevationReportsPerRun) progress event "
                + "carrying the elevated run's own pending envelope, and it held "
                + "\(evidence.elevationReports)"
        ),
        ScenarioCheck(
            name: shellRunListedCheckName,
            held: plane.parkedRun?.kind == .process
                && plane.parkedRun?.op == evidence.declaredJournalOp,
            failureMessage:
                "expected the run plane to list the parked shell run as kind "
                + "\(RunKind.process.rawValue) under the declared op "
                + "\(evidence.declaredJournalOp ?? "none"), and it listed "
                + "\(plane.parkedRun?.description ?? "no run at all")"
        ),
        ScenarioCheck(
            name: shellLiveOutputCheckName,
            held: plane.childProcessGroup != nil,
            failureMessage:
                "expected tools.shell.getLines to read the live run's output under the same "
                + "completion token, and it read \(plane.liveLines)"
        ),
        ScenarioCheck(
            name: shellCancelStoppedCheckName,
            held: plane.cancelOutcome == .stopped,
            failureMessage:
                "expected the run's own canceler to report \(OperationOutcome.stopped.rawValue) — "
                + "a process group that took killpg(SIGKILL) is certainly dead — and it reported "
                + "\(plane.cancelOutcome?.rawValue ?? "nothing")"
        ),
        ScenarioCheck(
            name: shellChildGoneCheckName,
            held: plane.childGone,
            failureMessage:
                "expected the child's process group "
                + "\(plane.childProcessGroup.map { "\($0)" } ?? "(never read)") to hold nothing "
                + "after the cancel, and it still held a process"
        ),
        ScenarioCheck(
            name: shellJournaledTerminalCheckName,
            held: evidence.sweptRunTerminals.count == terminalEventsPerRun
                && evidence.sweptRunTerminals.allSatisfy {
                    $0.outcome == .stopped && $0.op == evidence.declaredJournalOp
                },
            failureMessage:
                "expected close() to journal exactly \(terminalEventsPerRun) terminal event for "
                + "the run still parked at teardown, under that run's own completion token, its "
                + "declared op \(evidence.declaredJournalOp ?? "none") and the outcome "
                + "\(OperationOutcome.stopped.rawValue); the journal held "
                + "\(evidence.sweptRunTerminals.map { "\($0.op)/\($0.outcome?.rawValue ?? "none")" })"
        ),
    ]
}
