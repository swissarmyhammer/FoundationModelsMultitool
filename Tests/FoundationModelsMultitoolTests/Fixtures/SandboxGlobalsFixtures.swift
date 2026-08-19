import Foundation
import FoundationModels
import FoundationModelsRouter

// MARK: - Phase-1 sandbox-globals fixtures (eventplan.md § "The sandbox
// globals")
//
// The background runs a snippet's `status()`/`wait()`/`cancel()` observe are
// the session's own runs, and the answer its `elicit()` waits for arrives
// through the same session mailbox. Both are scripted here rather than
// simulated: a real mailbox, a real background run, and a real elicitation
// reply — so what these tests exercise is the actual Router surface, not a
// stand-in.
//
// A run goes to the background the way a real one does. A genuinely slow call
// is raced against a zero wait clock by the detachment engine, which
// backgrounds it and hands back the pending envelope. Nothing here registers a
// run by hand: the mailbox's bookkeeping is Router's own wiring, and a host
// reads it only through `ToolContext` (Router task ^k0mecjp).

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

/// How long a fixture waits for a mailbox to record a settlement before
/// giving up. Generous: this is a synchronization point, not a timing
/// assertion — the wait resolves the instant the mailbox records the terminal
/// event.
let scriptedRunSettlementSeconds: Double = 10

/// What a scripted run could not do.
enum ScriptedRunFailure: Error, CustomStringConvertible {
    /// The engine did not hand back a decorator this fixture can call.
    case notDetachable

    /// The call returned something other than a pending envelope, so the run
    /// never went to the background — the text it returned instead.
    case didNotBackground(String)

    /// The run's progress detail never reached the run's status row within
    /// ``scriptedRunSettlementSeconds`` — the detail that was awaited.
    case progressNeverArrived(String)

    var description: String {
        switch self {
        case .notDetachable:
            return "the detachment engine returned a decorator this fixture cannot call"
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
/// Genuinely slow, so the detachment engine backgrounds it for the real reason
/// a real tool is backgrounded: the work outlived the wait clock.
final class GatedScriptedTool: Tool, Sendable {
    let name: String
    let description = "Blocks until its gate opens, then returns its scripted detail."

    /// The gate that holds the call — and so the run — open.
    private let gate: SettlementGate

    /// The gate the fixture opens once the run is in the background.
    private let backgrounded: SettlementGate

    /// What the call returns once the gate opens; the terminal event's
    /// bounded output tail. Also the reason it throws, when `fails` is set.
    private let detail: String

    /// The progress detail to post once backgrounded, or `nil` to stay silent.
    private let progress: String?

    /// Whether the call throws once its gate opens rather than returning.
    private let fails: Bool

    /// Creates a gated tool.
    ///
    /// - Parameters:
    ///   - name: the tool's name, which the engine also stamps as the run's op.
    ///   - gate: the gate to block on.
    ///   - backgrounded: the gate that reports the run is in the background.
    ///   - detail: what to return once the gate opens.
    ///   - progress: the progress detail to post once backgrounded, or `nil`.
    ///   - fails: whether to throw once the gate opens rather than return.
    init(
        name: String,
        gate: SettlementGate,
        backgrounded: SettlementGate,
        detail: String,
        progress: String?,
        fails: Bool
    ) {
        self.name = name
        self.gate = gate
        self.backgrounded = backgrounded
        self.detail = detail
        self.progress = progress
        self.fails = fails
    }

    func call(arguments: NoArguments) async throws -> String {
        if let progress {
            // Only once the run is in the background. A progress detail is
            // recorded against a running row, so a post made while the call is
            // still inside its wait window updates nothing and is lost — and
            // it also makes the run non-silent, which suppresses the
            // synthesized progress the engine posts for a silent one.
            await backgrounded.wait()
            await ToolContext.current?.progress(progress)
        }
        await gate.wait()
        if fails { throw ScriptedToolFailure(description: detail) }
        return detail
    }
}

/// The session's background runs over `mailbox`, as a host reads them.
///
/// A `ToolContext` is the only route to them (Router task ^k0mecjp), and a
/// test owns its mailbox, so it can bind one over it and read the runs exactly
/// as the product does.
///
/// - Parameter mailbox: the session mailbox to read.
/// - Returns: a context bound over `mailbox`.
func backgroundRuns(over mailbox: SessionMailbox) -> ToolContext {
    makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
}

/// Starts a scripted background run in `mailbox` and returns the handle a test
/// drives it through.
///
/// The run keeps going — and so stays visible to `status()` and awaitable by
/// `wait()` — until ``settle(_:in:)`` opens its gate.
///
/// - Parameters:
///   - mailbox: the session mailbox to start the run in.
///   - tool: the tool's name that owns the run; also the run's op.
///   - detail: what the call returns once it finishes — the bounded output
///     tail a `wait()` resolves to. Also the reason it throws when `failing`.
///   - progress: the latest progress detail `status()` should report, or
///     `nil` to leave the run silent. When given, this returns only once that
///     detail has reached the run's status row, so a following assertion never
///     races the post.
///   - failing: whether the run throws once its gate opens rather than
///     returning `detail`, so its terminal event reports a failure.
/// - Returns: the background run's handle.
/// - Throws: ``ScriptedRunFailure`` when the call never went to the
///   background, or when a requested progress detail never arrived.
func startScriptedRun(
    in mailbox: SessionMailbox,
    tool: String = "shell",
    detail: String = "scripted-terminal-detail",
    progress: String? = nil,
    failing: Bool = false
) async throws -> ScriptedRun {
    let gate = SettlementGate()
    let backgrounded = SettlementGate()
    let mounted = ToolDetachment.wrapping(
        tool: GatedScriptedTool(
            name: tool,
            gate: gate,
            backgrounded: backgrounded,
            detail: detail,
            progress: progress,
            fails: failing
        ),
        sessionID: ULID(),
        mailbox: mailbox,
        sink: RecordingEventSink(),
        // A zero wait clock is detach-immediately, so the call goes to the
        // background on its first suspension rather than after a real five
        // seconds of test time.
        configuration: DetachConfiguration(mode: .detaching, waitSeconds: 0)
    )
    guard let engine = mounted as? any Tool<NoArguments, String> else {
        throw ScriptedRunFailure.notDetachable
    }
    let rendered = try await engine.call(arguments: NoArguments())
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
        try await awaitProgress(progress, of: completionToken, in: mailbox)
    }
    return ScriptedRun(completionToken: completionToken, tool: tool, op: tool, gate: gate)
}

/// Returns once the run's status row reports `detail` as its latest progress.
///
/// A progress post travels tool -> sink -> status row, so it lands shortly
/// after the call that made it. This is the synchronization point that closes
/// that gap; it is not a timing assertion, and it resolves the instant the
/// detail is recorded.
///
/// - Parameters:
///   - detail: the progress detail to wait for.
///   - completionToken: the run that posted it.
///   - mailbox: the session mailbox the run is registered in.
/// - Throws: ``ScriptedRunFailure/progressNeverArrived(_:)`` if it never lands.
private func awaitProgress(
    _ detail: String, of completionToken: String, in mailbox: SessionMailbox
) async throws {
    let context = backgroundRuns(over: mailbox)
    let deadline = ContinuousClock.now.advanced(by: .seconds(scriptedRunSettlementSeconds))
    while ContinuousClock.now < deadline {
        let row = await context.parkedRuns().first { $0.completionToken == completionToken }
        if row?.latestProgressDetail == detail { return }
        await Task.yield()
    }
    throw ScriptedRunFailure.progressNeverArrived(detail)
}

/// Settles a scripted background run and returns only once the mailbox has
/// recorded its terminal event — a synchronization point, so a following
/// `status()` or `wait()` assertion never races the settlement.
///
/// - Parameters:
///   - run: the background run to settle.
///   - mailbox: the mailbox the run is registered in.
func settle(_ run: ScriptedRun, in mailbox: SessionMailbox) async {
    await run.gate.open()
    _ = await backgroundRuns(over: mailbox).wait(
        completionToken: run.completionToken, seconds: scriptedRunSettlementSeconds
    )
}

/// An `OperationEventSink` that answers every elicitation it observes with one
/// scripted response, delivering it through `mailbox` from inside its own
/// `post(_:)`.
///
/// Answering from inside the post is deliberate and is what makes the
/// round-trip tests deterministic rather than timing-dependent:
/// `SessionMailbox.awaitAnswer(to:posting:)` installs the pending entry
/// *before* it starts the upstream post, so an answer delivered the instant a
/// host observes the event always finds that entry.
///
/// A URL-mode accept is a two-step flow — `respond` only records the accept —
/// so this sink follows it with `complete(elicitationId:)`, exactly as a real
/// host's out-of-band flow would.
actor ScriptedElicitationSink: OperationEventSink {
    /// The mailbox every answer is delivered through.
    private let mailbox: SessionMailbox

    /// The answer this sink gives to every elicitation it observes.
    private let response: ElicitationResponse

    /// Every event posted to this sink, in arrival order.
    private(set) var events: [OperationEvent] = []

    /// What the mailbox reported for each delivered answer, in delivery
    /// order.
    private(set) var deliveries: [SessionMailbox.ElicitationAnswerDelivery] = []

    /// What the mailbox reported for each URL-mode completion, in completion
    /// order.
    private(set) var completions: [SessionMailbox.ElicitationCompletionDelivery] = []

    /// Creates a sink that answers every elicitation with one scripted
    /// response.
    ///
    /// - Parameters:
    ///   - mailbox: the mailbox to deliver each answer through.
    ///   - response: the answer to give.
    init(mailbox: SessionMailbox, answering response: ElicitationResponse) {
        self.mailbox = mailbox
        self.response = response
    }

    /// Records `event` and, when it carries an elicitation, answers that
    /// request through the mailbox with this sink's one scripted response.
    ///
    /// Every event is kept, not only the elicitations: a test asserts on the
    /// full arrival order, and the non-elicitation events are what prove a
    /// run's notices reached the sink on the right correlation.
    ///
    /// The answer is delivered from inside the post — synchronously with
    /// observing the event, before this method returns — which is what makes
    /// the round trip deterministic rather than timing-dependent; see the
    /// type's own documentation for why the mailbox's ordering guarantees
    /// that.
    ///
    /// A URL-mode accept comes back as `.acceptedAwaitingCompletion`: the
    /// mailbox has recorded the accept, but the out-of-band flow is still
    /// open and the waiting snippet stays suspended until it closes. Only that
    /// delivery gets the second `complete(elicitationId:)` step, because every
    /// other delivery — a form accept, a decline, a cancel, or a rejected
    /// answer — already settled the request.
    ///
    /// - Parameter event: the operation event the observed run posted.
    func post(event: OperationEvent) async {
        events.append(event)
        guard let request = event.elicitation else { return }
        let delivery = await mailbox.respond(elicitationId: request.elicitationId, response)
        deliveries.append(delivery)
        guard delivery == .acceptedAwaitingCompletion else { return }
        completions.append(await mailbox.complete(elicitationId: request.elicitationId))
    }

    /// The elicitation request carried by the first elicitation-kind event
    /// this sink observed, or `nil` when it observed none.
    var observedRequest: ElicitationRequest? {
        events.compactMap(\.elicitation).first
    }
}
