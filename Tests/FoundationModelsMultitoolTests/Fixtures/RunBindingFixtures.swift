import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import TestConcurrency
import os

// MARK: - Phase-1 `RunBinding` fixtures (eventplan.md § "Async JavaScript" —
// "Session affinity across the seam")
//
// The pieces a test needs to stand a `runCode` call up inside a session it
// controls: a sink it can read back, a tool that reports the ambient
// `ToolContext` its own call ran under, and the outer `ToolContext` a Router
// session binds around `runCode` itself.

/// What one `AmbientRecordingTool` call observed about the ambient
/// `ToolContext` its invoker bound around it — the evidence that the
/// `tools.*` seam re-binds the context explicitly from the captured
/// `RunBinding` rather than relying on task-local inheritance the JS thread
/// cannot provide.
struct AmbientObservation: Sendable, Equatable {
    /// The observing tool's own `tools.*` name.
    let toolName: String

    /// The `tool` the run's ambient context is stamped with, or `nil` when the
    /// call ran with no ambient context bound at all. Always the tool's own
    /// name, whatever noun it was registered under.
    let stampedTool: String?

    /// The `op` the run's ambient context is stamped with, or `nil` when the
    /// call ran with no ambient context bound at all — the canonical
    /// `"verb noun"` pair for a tool registered under a noun, and the tool's own
    /// name for one registered with none.
    ///
    /// This is the one stamp both run-plane readings are made from:
    /// `RunPlane.start(tool:op:...)` fills `BackgroundRun.op` from it, and
    /// `ToolInvocationRecord` carries it too. The event journal of an enclosing
    /// snippet never shows it, because `ToolContext.post(_:)` re-stamps every
    /// forwarded event with the outer run's own identity.
    let stampedOp: String?

    /// The run's `completionToken`, or `nil` when the call ran with no
    /// ambient context bound at all.
    let completionToken: String?

    /// The owning session's identity, or `nil` when the call ran with no
    /// ambient context bound at all.
    let sessionID: ULID?

    /// Whether work that inherits no task-locals, started inside the call, saw
    /// no ambient context — the capture-at-start rule the ambient design
    /// enforces.
    let uninheritedContextWasNil: Bool
}

/// An `OperationEventSink` that keeps every event posted to it, so a test can
/// assert which session's sink a run's events actually reached.
///
/// An `actor` rather than a lock-guarded class because `post(_:)` is already
/// `async`: the protocol's own shape makes actor isolation the cheaper
/// synchronization.
actor RecordingEventSink: OperationEventSink {
    /// One question that the run plane ended with a decline or a cancel, as
    /// `post(elicitationEnded:response:)` gave it.
    struct EndedElicitation: Equatable {
        /// The id of the question.
        let elicitationId: ULID

        /// The decline or the cancel that ended the question.
        let response: ElicitationResponse
    }

    /// What one wait of this sink waits for.
    private enum AwaitedPost: Sendable {
        /// An event that the test accepts — a wait of
        /// ``waitUntilEvent(where:)``.
        case event(@Sendable (OperationEvent) -> Bool)

        /// A URL flow that completed or ended — a wait of
        /// ``waitUntilElicitationSettled()``.
        case settledElicitation
    }

    /// Every event posted to this sink, in arrival order.
    private(set) var events: [OperationEvent] = []

    /// The id of each completed URL flow posted to this sink, in arrival
    /// order.
    private(set) var completedElicitationIds: [ULID] = []

    /// Each question that the run plane ended, in arrival order.
    private(set) var endedElicitations: [EndedElicitation] = []

    /// Each wait of ``waitUntilEvent(where:)`` and of
    /// ``waitUntilElicitationSettled()`` that did not end yet.
    private let waiters = WaitList<AwaitedPost>()

    func post(event: OperationEvent) async {
        events.append(event)
        waiters.resume { awaited in
            guard case .event(let isMet) = awaited else { return false }
            return isMet(event)
        }
    }

    func post(elicitationEnded elicitationId: ULID, response: ElicitationResponse) async {
        endedElicitations.append(EndedElicitation(elicitationId: elicitationId, response: response))
        resumeSettleWaiters()
    }

    func post(elicitationCompleted elicitationId: ULID) async {
        completedElicitationIds.append(elicitationId)
        resumeSettleWaiters()
    }

    /// Ends each wait of ``waitUntilElicitationSettled()``.
    private func resumeSettleWaiters() {
        waiters.resume { awaited in
            guard case .settledElicitation = awaited else { return false }
            return true
        }
    }

    /// Waits until this sink recorded an event that `isMet` accepts. Returns
    /// at once when it recorded one before. The wait is an event: no clock
    /// and no poll.
    ///
    /// A cancel of the calling task ends the wait, also a cancel that came
    /// before the call. Thus a test that cancels this wait when the event
    /// cannot come any more leaves no continuation open.
    ///
    /// - Parameter isMet: The test of one event.
    func waitUntilEvent(where isMet: @escaping @Sendable (OperationEvent) -> Bool) async {
        await waiters.wait(for: .event(isMet), unless: { events.contains(where: isMet) })
    }

    /// Waits until this sink recorded one URL flow that completed or ended.
    /// Returns at once when it recorded one before. The wait is an event: no
    /// clock and no poll.
    ///
    /// The wait ends on the first of two events: a completion, or an end with
    /// a decline or a cancel. A flow that does not complete ends some other
    /// way, thus a test that waits here for a completion fails, and does not
    /// wait for ever, when the flow ends with no completion. A cancel of the
    /// calling task also ends the wait, also a cancel that came before the
    /// call, as it ends a wait of ``waitUntilEvent(where:)``.
    func waitUntilElicitationSettled() async {
        await waiters.wait(
            for: .settledElicitation, unless: { !completedElicitationIds.isEmpty || !endedElicitations.isEmpty })
    }

    /// The `detail` of every recorded event of one kind, in arrival order.
    ///
    /// - Parameter kind: the event kind to filter by.
    /// - Returns: each matching event's `detail`.
    func details(ofKind kind: OperationEventKind) -> [String] {
        events.filter { $0.kind == kind }.map(\.detail)
    }
}

/// A tool that records the ambient `ToolContext` its call ran under, posts one
/// progress event through it, and returns a name-derived result.
///
/// `final class … Sendable` (rather than a `struct`), the same pattern as
/// `DelayedTool`/`WindowRecordingTool`: the test inspects `observations` after
/// `MultiTool.call` returns, backed by an `OSAllocatedUnfairLock` so the type
/// stays `Sendable`.
final class AmbientRecordingTool: Tool, Sendable {
    let name: String
    let description = "Reports the ambient tool context its own call ran under."

    private let observationsBox = OSAllocatedUnfairLock<[AmbientObservation]>(initialState: [])

    /// Creates an ambient-recording tool.
    ///
    /// - Parameter name: this tool's `tools.*` name, also the prefix of its
    ///   posted progress detail and of its returned result.
    init(name: String) {
        self.name = name
    }

    /// Every call's observation, in completion order — empty until `call` has
    /// run at least once.
    var observations: [AmbientObservation] {
        observationsBox.withLock { $0 }
    }

    func call(arguments: NoArguments) async throws -> String {
        let context = ToolContext.current
        // A raw thread inherits no task-locals, so the probe reads the context
        // the way any non-inheriting work would.
        let uninheritedContextWasNil = await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: ToolContext.current == nil) }.start()
        }
        await context?.progress("\(name) ran")
        observationsBox.withLock {
            $0.append(
                AmbientObservation(
                    toolName: name,
                    stampedTool: context?.tool,
                    stampedOp: context?.op,
                    completionToken: context?.completionToken,
                    sessionID: context?.sessionID,
                    uninheritedContextWasNil: uninheritedContextWasNil
                )
            )
        }
        return "\(name)-result"
    }
}

/// The ambient `ToolContext` a Router session binds around one `runCode`
/// call — the context `MultiTool` captures into its `RunBinding`.
///
/// Taken from a real session over the stub model, because `ToolContext` has no
/// public initializer and the run plane of a session is internal to Router. See
/// `StubRouterFixtures.swift` for the stack that stands the session up.
///
/// The helper gives the context to `body`, and closes the session of the
/// context when `body` returns or throws. A close inside a helper that
/// returns the context would end the session while the test still uses the
/// context. A session that is not closed has no contract: its tasks can
/// still run after the test.
///
/// - Parameters:
///   - runClock: the run clock of the session, or `nil` for the real time.
///     See ``makeStubProfile(recorder:loader:standardModel:in:runClock:)``.
///   - body: the work that uses the outer run's ambient context.
/// - Returns: what `body` returned.
/// - Throws: whatever standing up the stub session throws, or what `body`
///   threw.
func withOuterRunContext<Result>(
    runClock: (any RunClock)? = nil, _ body: (ToolContext) async throws -> Result
) async throws -> Result {
    try await withStubRun(runClock: runClock) { run in try await body(run.context) }
}
