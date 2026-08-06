import Foundation
import FoundationModels
import FoundationModelsRouter

// MARK: - Phase-1 sandbox-globals fixtures (eventplan.md § "The sandbox
// globals")
//
// The run plane a snippet's `status()`/`wait()`/`cancel()` observe is the
// session's own `SessionMailbox`, and the answer its `elicit()` waits for
// arrives through that same mailbox. Both are scripted here rather than
// simulated: a real mailbox, a real parked run, and a real elicitation reply —
// so what these tests exercise is the actual Router surface, not a stand-in.

/// A one-shot gate that holds a scripted parked run open until a test decides
/// it should settle.
///
/// An `actor` rather than a lock-guarded class because both sides of the gate
/// are already `async`: the parked run's settling `Task` suspends on
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

/// One scripted parked run: the mailbox row a snippet's `status()` lists, the
/// terminal event its `wait()` resolves to, and the gate that decides when the
/// run settles.
struct ScriptedRun: Sendable {
    /// The run's completion token — also its terminal event's
    /// `correlationID`.
    let completionToken: String

    /// The fused tool's name that owns the run.
    let tool: String

    /// The canonical op string of the parked operation.
    let op: String

    /// The terminal event the run settles with once its gate opens.
    let terminal: OperationEvent

    /// The gate that holds the run parked.
    let gate: SettlementGate
}

/// The outcome every scripted run's canceler reports — cooperative
/// cancellation of a `RunKind/swiftTask`, requested but not certain, exactly
/// as `SessionMailbox`'s own vocabulary requires.
let scriptedRunCancelOutcome: OperationOutcome = .cancelled

/// How long a fixture waits for a mailbox to record a settlement before
/// giving up. Generous: this is a synchronization point, not a timing
/// assertion — the wait resolves the instant the mailbox records the terminal
/// event.
let scriptedRunSettlementSeconds: Double = 10

/// Parks a scripted run in `mailbox` and returns the handle a test drives it
/// through.
///
/// The run stays parked — and so stays visible to `status()` and awaitable by
/// `wait()` — until ``settle(_:in:)`` opens its gate.
///
/// - Parameters:
///   - mailbox: the session mailbox to park the run in.
///   - tool: the fused tool's name that owns the run.
///   - op: the canonical op string of the parked operation.
///   - detail: the terminal event's detail — the bounded output tail a
///     `wait()` resolves to.
///   - progress: the latest progress detail `status()` should report, or
///     `nil` to leave the run silent.
/// - Returns: the parked run's handle.
func parkScriptedRun(
    in mailbox: SessionMailbox,
    tool: String = "shell",
    op: String = "run shell",
    detail: String = "scripted-terminal-detail",
    progress: String? = nil
) async -> ScriptedRun {
    let completionToken = SessionMailbox.makeCompletionToken()
    let terminal = OperationEvent(
        tool: tool,
        op: op,
        correlationID: completionToken,
        kind: .completed,
        detail: detail,
        outcome: .succeeded
    )
    let gate = SettlementGate()
    let settling = Task<OperationEvent, Never> {
        await gate.wait()
        return terminal
    }
    await mailbox.park(
        tool: tool,
        op: op,
        kind: .swiftTask,
        completionToken: completionToken,
        settling: settling,
        canceler: { scriptedRunCancelOutcome }
    )
    if let progress {
        await mailbox.updateProgress(completionToken: completionToken, detail: progress)
    }
    return ScriptedRun(completionToken: completionToken, tool: tool, op: op, terminal: terminal, gate: gate)
}

/// Settles a scripted parked run and returns only once `mailbox` has recorded
/// its terminal event — a synchronization point, so a following `status()` or
/// `wait()` assertion never races the settlement.
///
/// - Parameters:
///   - run: the parked run to settle.
///   - mailbox: the mailbox the run is parked in.
func settle(_ run: ScriptedRun, in mailbox: SessionMailbox) async {
    await run.gate.open()
    _ = await mailbox.wait(completionToken: run.completionToken, seconds: scriptedRunSettlementSeconds)
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

    func post(_ event: OperationEvent) async {
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
