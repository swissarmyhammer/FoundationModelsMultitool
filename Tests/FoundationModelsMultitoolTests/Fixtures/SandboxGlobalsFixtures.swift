import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter

@testable import MultitoolTestSupport

// MARK: - Phase-1 sandbox-globals fixtures (eventplan.md § "The sandbox
// globals")
//
// The background runs a snippet's `status()`/`cancel()` observe are
// the session's own runs, and the answer its `elicit()` waits for arrives
// through the same session mailbox. Both are scripted here rather than
// simulated: a real mailbox, a real background run, and a real elicitation
// reply — so what these tests exercise is the actual Router surface, not a
// stand-in.
//
// A run goes to the background the way a real one does. The site mounts the
// call in the background, so the mount engine backgrounds it and hands back
// the pending envelope. Nothing here registers a run by hand: the mailbox's
// bookkeeping is Router's own wiring, and a host reads it only through
// `ToolContext` (Router task ^k0mecjp).

/// A one-shot gate that holds a scripted background run going until a test
/// decides it should finish.
///
/// An `actor` rather than a lock-guarded class because both sides of the gate
/// are already `async`: the background run's finishing `Task` suspends on
/// ``wait()``, and the test resumes it from ``open()``.
actor SettlementGate {
    /// Whether ``open()`` has already been called — a run that arrives late
    /// must not suspend forever.
    private var isOpen = false

    /// Every settling `Task` currently suspended on this gate.
    private var suspended: [CheckedContinuation<Void, Never>] = []

    /// Suspends until ``open()`` is called, or returns immediately when it
    /// already has been.
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { suspended.append($0) }
    }

    /// Resumes every suspended waiter and lets every later ``wait()`` through.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiting = suspended
        suspended = []
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// One scripted background run: the row a snippet's `status()` lists, and the
/// gate that decides when the run finishes.
struct ScriptedRun: Sendable {
    /// The run's completion token — also its terminal event's
    /// `correlationID`. Minted by the engine, read back out of the pending
    /// envelope the backgrounded call returned.
    let completionToken: String

    /// The tool's name that owns the run.
    let tool: String

    /// The op string of the backgrounded operation. The engine stamps a run
    /// with its tool's own name, so this is `tool` — assert against this field
    /// rather than a literal, and the fixture stays the one source of it.
    let op: String

    /// The gate that holds the run going.
    let gate: SettlementGate
}

/// The outcome a scripted run's cancellation reports — cooperative
/// cancellation of a `RunKind/swiftTask`, requested but not certain. The
/// engine's own canceler reports it; this names the value a test expects.
let scriptedRunCancelOutcome: OperationOutcome = .cancelled

/// The deadline a fixture gives `ToolContext.wait(completionToken:seconds:)`
/// when it waits for a mailbox to record a settlement: `nil`, no deadline.
///
/// This is a synchronization point, not a timing assertion — the wait
/// resolves the instant the mailbox records the terminal event. No clock ends
/// it (card `^tm4x2hp`: no test checks the speed of the machine). A run that
/// never settles makes the test hang, and that hang is the failure.
let scriptedRunSettlementSeconds: Double? = nil

/// What a scripted run could not do.
enum ScriptedRunFailure: Error, CustomStringConvertible {
    /// The call returned something other than a pending envelope, so the run
    /// never went to the background — the text it returned instead.
    case didNotBackground(String)

    /// The run posted its progress detail, but the run's status row did not
    /// show it — the detail that was awaited.
    case progressNeverArrived(String)

    var description: String {
        switch self {
        case .didNotBackground(let text):
            return "the call returned \"\(text)\" instead of going to the background"
        case .progressNeverArrived(let detail):
            return "progress \"\(detail)\" never reached the run's status row"
        }
    }
}

/// The failure a scripted run raises when a test asks it to fail rather than
/// deliver a result.
///
/// Thrown from the tool's own `call(arguments:)`, so the terminal event the
/// engine records carries the outcome a genuinely failing tool produces —
/// which is what a run reporting `error` has to be measured against.
struct ScriptedToolFailure: Error, CustomStringConvertible {
    /// What the tool reports as its reason for failing.
    let description: String
}

/// A tool whose call blocks until its gate opens.
///
/// Genuinely slow: the call blocks until its gate opens, so the run stays
/// going while a test reads it and drives it.
final class GatedScriptedTool: Tool, Sendable {
    let name: String
    let description = "Blocks until its gate opens, then returns its scripted detail."

    /// The gate that holds the call — and so the run — open.
    private let gate: SettlementGate

    /// The gate the fixture opens once the run is in the background.
    private let backgrounded: SettlementGate

    /// The gate the call opens once its progress post returned.
    private let progressPosted: SettlementGate

    /// What the call returns once the gate opens; the terminal event's
    /// detail. Also the reason it throws, when `fails` is set.
    private let detail: String

    /// The progress detail to post once backgrounded, or `nil` to post none.
    private let progress: String?

    /// Whether the call throws once its gate opens rather than returning.
    private let fails: Bool

    /// Creates a gated tool.
    ///
    /// - Parameters:
    ///   - name: the tool's name, which the engine also stamps as the run's op.
    ///   - gate: the gate to block on.
    ///   - backgrounded: the gate that reports the run is in the background.
    ///   - progressPosted: the gate the call opens once its progress post
    ///     returned.
    ///   - detail: what to return once the gate opens.
    ///   - progress: the progress detail to post once backgrounded, or `nil`.
    ///   - fails: whether to throw once the gate opens rather than return.
    init(
        name: String,
        gate: SettlementGate,
        backgrounded: SettlementGate,
        progressPosted: SettlementGate,
        detail: String,
        progress: String?,
        fails: Bool
    ) {
        self.name = name
        self.gate = gate
        self.backgrounded = backgrounded
        self.progressPosted = progressPosted
        self.detail = detail
        self.progress = progress
        self.fails = fails
    }

    func call(arguments: NoArguments) async throws -> String {
        if let progress {
            // Only once the run is in the background. The mount engine
            // records a progress detail against the run's status row
            // (`SessionMailbox.updateProgress`). `SessionMailbox.track` makes
            // that row, and a post that arrives before it updates nothing.
            // `BackgroundToolRunner` holds this body on a start gate until
            // after it tracks the run, so that order already holds. This gate
            // states the order at the fixture too, and the tests that read
            // `latestProgress` do not depend on that internal step.
            await backgrounded.wait()
            // The run records the detail on its status row before this post
            // returns (`ToolRun.post(event:)` awaits
            // `RunPlane.updateProgress`). Thus the gate opens after the row
            // shows the detail, in a fixed order.
            await ToolContext.current?.progress(progress)
            await progressPosted.open()
        }
        await gate.wait()
        if fails { throw ScriptedToolFailure(description: detail) }
        return detail
    }
}

// The run plane is read through the `ToolContext` a stub session hands out.
// `SessionMailbox` is internal to Router, so a test cannot own one; what it
// owns instead is a real session, and the context that session binds around a
// tool call reads that session's own run plane. See `StubRouterFixtures.swift`.

/// Starts a scripted background run in `mailbox` and returns the handle a test
/// drives it through.
///
/// The run keeps going — and so stays visible to `status()` — until
/// ``settle(_:on:)`` opens its gate.
///
/// The call waits for the settle period of the session before it answers
/// with the pending envelope. That period waits on `clock`, and this moves
/// `clock` past it after its timer waits
/// (``callPastSettlePeriod(on:grace:timers:_:)``). Thus no real time passes.
///
/// - Parameters:
///   - context: the session context to start the run on.
///   - clock: the run clock of the session of `context`.
///   - tool: the tool's name that owns the run; also the run's op.
///   - detail: what the call returns once it finishes — the detail a finished
///     run reports. Also the reason it throws when `failing`.
///   - progress: the latest progress detail `status()` should report, or
///     `nil` to let the run post none. When given, this returns only once that
///     detail has reached the run's status row, so a following assertion never
///     races the post.
///   - failing: whether the run throws once its gate opens rather than
///     returning `detail`, so its terminal event reports a failure.
/// - Returns: the background run's handle.
/// - Throws: ``ScriptedRunFailure`` when the call never went to the
///   background, or when a requested progress detail never arrived.
func startScriptedRun(
    on context: ToolContext,
    clock: ManualRunClock,
    tool: String = "shell",
    detail: String = "scripted-terminal-detail",
    progress: String? = nil,
    failing: Bool = false
) async throws -> ScriptedRun {
    let gate = SettlementGate()
    let backgrounded = SettlementGate()
    let progressPosted = SettlementGate()
    let engine = context.mount(
        GatedScriptedTool(
            name: tool,
            gate: gate,
            backgrounded: backgrounded,
            progressPosted: progressPosted,
            detail: detail,
            progress: progress,
            fails: failing
        ),
        // The scripted tool declares no mount of its own, so the site puts it
        // in the background: the call answers the envelope when the settle
        // period of the session ends, and the body goes on behind it under no
        // timeout.
        as: ToolMount(mode: .background, timeout: nil)
    )
    // The gate holds the body, thus the call answers only when the clock
    // moves past the settle period.
    let rendered = try await callPastSettlePeriod(
        on: clock, grace: context.inlineSettleGrace, timers: settlePeriodTimers
    ) {
        try await engine.call(arguments: NoArguments())
    }
    guard PendingRunEnvelope.isRendered(text: rendered) else {
        throw ScriptedRunFailure.didNotBackground(rendered)
    }
    let completionToken = try JSONDecoder()
        .decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
        .completionToken
    if let progress {
        // The envelope is proof the run is in the background, so the call may
        // post now.
        await backgrounded.open()
        await progressPosted.wait()
        try await expectProgress(progress, of: completionToken, on: context)
    }
    return ScriptedRun(completionToken: completionToken, tool: tool, op: tool, gate: gate)
}

/// Checks one time that the run's status row reports `detail` as its latest
/// progress.
///
/// The caller calls this after the post of the tool returned. The run records
/// the detail on the status row before that post returns, thus one read is
/// enough, and nothing waits on a clock or polls.
///
/// - Parameters:
///   - detail: the progress detail to find.
///   - completionToken: the run that posted it.
///   - context: the session context the run is registered on.
/// - Throws: ``ScriptedRunFailure/progressNeverArrived(_:)`` when the row does
///   not show it.
private func expectProgress(
    _ detail: String, of completionToken: String, on context: ToolContext
) async throws {
    let row = await context.backgroundRuns().first { $0.completionToken == completionToken }
    guard row?.latestProgressDetail == detail else {
        throw ScriptedRunFailure.progressNeverArrived(detail)
    }
}

/// Settles a scripted background run and returns only once the mailbox has
/// recorded its terminal event — a synchronization point, so a following
/// `status()` or `cancel()` assertion never races the settlement.
///
/// - Parameters:
///   - run: the background run to settle.
///   - context: the session context the run is registered on.
func settle(_ run: ScriptedRun, on context: ToolContext) async {
    await run.gate.open()
    _ = await context.wait(
        completionToken: run.completionToken, seconds: scriptedRunSettlementSeconds
    )
}

/// Answers every elicitation a run raises with one scripted response.
///
/// A consumer cannot inject an `OperationEventSink`, so this cannot observe
/// events by being handed them. It watches the run's journal instead — the
/// route that does carry `.elicitation` events — and answers through
/// `RoutedSession.respond(elicitationId:response:)`.
///
/// The watch starts as soon as this is made, so build it BEFORE the snippet
/// that elicits. A URL-mode accept is a two-step flow: `respond` records the
/// accept and the snippet stays suspended, so an `.acceptedAwaitingCompletion`
/// delivery is followed by `complete(elicitationId:)`, exactly as a real
/// host's out-of-band flow would.
///
/// The watch waits on the recorder of the run
/// (``CollectingTranscriptRecorder/waitUntil(_:)``): it wakes when the journal
/// gets an elicitation that it did not answer yet. It reads no clock and does
/// not poll. A test can drop this answerer at once: the watch task holds the
/// log and the run, not the answerer, and it keeps answering for the life of
/// the run.
final class ScriptedElicitationSink: Sendable {
    /// What the watch observed and what the session reported.
    private let log: ElicitationAnswerLog

    /// Makes an answerer and starts watching at once.
    ///
    /// - Parameters:
    ///   - run: the run to watch and answer through.
    ///   - response: the answer to give.
    init(run: StubRun, answering response: ElicitationResponse) {
        let log = ElicitationAnswerLog()
        self.log = log
        Task { await Self.watch(run, answering: response, into: log) }
    }

    /// Every elicitation request observed, in arrival order.
    var requests: [ElicitationRequest] {
        get async { await log.requests }
    }

    /// What the session reported for each delivered answer, in delivery order.
    var deliveries: [ElicitationAnswerDelivery] {
        get async { await log.deliveries }
    }

    /// What the session reported for each URL-mode completion.
    var completions: [ElicitationCompletionDelivery] {
        get async { await log.completions }
    }

    /// The first observed request, or `nil` when none arrived.
    var observedRequest: ElicitationRequest? {
        get async { await log.requests.first }
    }

    /// Answers each elicitation of the journal of `run` exactly one time.
    ///
    /// Each turn waits until the journal holds an elicitation that the log
    /// did not claim, and then answers each new one. `SessionEvent` carries no
    /// elicitation case, and the journal is where a drained elicitation lands.
    ///
    /// - Parameters:
    ///   - run: the run to watch and answer through.
    ///   - response: the answer to give.
    ///   - log: where the watch records what it observed.
    private static func watch(
        _ run: StubRun, answering response: ElicitationResponse, into log: ElicitationAnswerLog
    ) async {
        while !Task.isCancelled {
            let answered = await log.answered
            let arrived = await run.recorder.waitUntil { events in
                events.contains { event in
                    guard event.kind == .elicitation, let request = event.elicitation else { return false }
                    return !answered.contains(request.elicitationId.description)
                }
            }
            guard arrived else { return }
            for event in await recordedOperationEvents(of: run, ofKind: .elicitation) {
                guard let request = event.elicitation, await log.claim(request) else { continue }
                let id = request.elicitationId.description
                let delivery = await run.session.respond(elicitationId: id, response: response)
                await log.record(delivery: delivery)
                guard delivery == .acceptedAwaitingCompletion else { continue }
                await log.record(completion: await run.session.complete(elicitationId: id))
            }
        }
    }
}

/// What a ``ScriptedElicitationSink`` observed, and what the session reported
/// for each answer.
actor ElicitationAnswerLog {
    /// Every elicitation request claimed, in arrival order.
    private(set) var requests: [ElicitationRequest] = []

    /// What the session reported for each delivered answer, in delivery order.
    private(set) var deliveries: [ElicitationAnswerDelivery] = []

    /// What the session reported for each URL-mode completion.
    private(set) var completions: [ElicitationCompletionDelivery] = []

    /// The elicitation ids already claimed, so the watch answers each one time.
    private(set) var answered: Set<String> = []

    /// Claims `request` for one answer.
    ///
    /// - Parameter request: the observed request.
    /// - Returns: `true` the first time, `false` when it was claimed before.
    func claim(_ request: ElicitationRequest) -> Bool {
        guard answered.insert(request.elicitationId.description).inserted else { return false }
        requests.append(request)
        return true
    }

    /// Records what the session reported for one answer.
    ///
    /// - Parameter delivery: the report of the session.
    func record(delivery: ElicitationAnswerDelivery) {
        deliveries.append(delivery)
    }

    /// Records what the session reported for one URL-mode completion.
    ///
    /// - Parameter completion: the report of the session.
    func record(completion: ElicitationCompletionDelivery) {
        completions.append(completion)
    }
}
