import Foundation
import FoundationModels
import FoundationModelsExtras
import Synchronization
import Testing
import ULID

@testable import FoundationModelsMultitool

// MARK: - A session whose work registry the test reads
//
// Each piece of work that lives past its call holds a `BackgroundWork` lease
// in the `WorkRegistry` of its session. The run plane of a Router session is
// internal to Router, thus a stub run gives no registry to a test. These
// fixtures make the session from its parts: the registry, a run plane over
// it, a sink that records which leases are open when each event arrives, and
// a context of one call. A test then reads the registry directly.

/// The open leases of a registry at the moment that one event reached the
/// sink.
struct LeaseSnapshot: Sendable {
    /// The event that reached the sink.
    let event: OperationEvent

    /// The leases that were open when the event reached the sink.
    let openWork: [WorkItem]
}

/// A sink that records each event with the open leases of one registry, and
/// forwards each post to a ``RecordingEventSink``.
///
/// A test that gives ``holdingProgress`` holds each `progress` event in the
/// post until the test opens that gate. Thus a notice waits for its delivery
/// for as long as the test needs.
final class LeaseRecordingSink: OperationEventSink {
    /// The registry whose open leases each snapshot records.
    private let registry: WorkRegistry

    /// The sink that each post goes on to. Its waits tell a test that an
    /// event came.
    let recording = RecordingEventSink()

    /// The gate that each `progress` post waits on before it goes on, or
    /// `nil` for no hold.
    let holdingProgress: TestGate?

    /// Each snapshot, in arrival order.
    private let snapshotsBox = Mutex<[LeaseSnapshot]>([])

    /// Makes a sink over `registry`.
    ///
    /// - Parameters:
    ///   - registry: The registry whose open leases each snapshot records.
    ///   - holdingProgress: The gate that holds each `progress` post, or
    ///     `nil` for no hold.
    init(registry: WorkRegistry, holdingProgress: TestGate? = nil) {
        self.registry = registry
        self.holdingProgress = holdingProgress
    }

    /// Each snapshot, in arrival order.
    var snapshots: [LeaseSnapshot] {
        snapshotsBox.withLock { $0 }
    }

    /// The snapshot of the first `completed` event of `correlationID`, or
    /// `nil` when none came.
    ///
    /// - Parameter correlationID: The correlation of the event.
    /// - Returns: The snapshot, or `nil`.
    func terminalSnapshot(of correlationID: String) -> LeaseSnapshot? {
        snapshots.first { $0.event.kind == .completed && $0.event.correlationID == correlationID }
    }

    func post(event: OperationEvent) async {
        let snapshot = LeaseSnapshot(event: event, openWork: registry.openWork)
        snapshotsBox.withLock { $0.append(snapshot) }
        if event.kind == .progress, let holdingProgress {
            await recording.post(event: event)
            try? await holdingProgress.wait()
            return
        }
        await recording.post(event: event)
    }

    func post(elicitationEnded elicitationId: ULID, response: ElicitationResponse) async {
        await recording.post(elicitationEnded: elicitationId, response: response)
    }

    func post(elicitationCompleted elicitationId: ULID) async {
        await recording.post(elicitationCompleted: elicitationId)
    }
}

/// One session that a test owns: its work registry, its run plane, its sink,
/// and the context of one call in it.
struct LeasedSession: Sendable {
    /// The tool name and the op of the call of ``context``.
    static let probeTool = "leaseProbe"

    /// The id of the session.
    let sessionID: ULID

    /// The registry of the background work of the session.
    let registry: WorkRegistry

    /// The run plane of the session, over ``registry``.
    let runPlane: RunPlane

    /// The sink of the session.
    let sink: LeaseRecordingSink

    /// The context of one call in the session.
    let context: ToolContext

    /// Makes a session with a new registry.
    ///
    /// - Parameters:
    ///   - runClock: The run clock of the run plane. The default is the real
    ///     time.
    ///   - inlineSettleGrace: The settle period of each background call that
    ///     the context mounts, in seconds. `0` sends a call to the background
    ///     at once.
    ///   - holdingProgress: The gate that holds each `progress` post, or
    ///     `nil` for no hold.
    init(
        runClock: any RunClock = ContinuousRunClock(),
        inlineSettleGrace: TimeInterval = 0,
        holdingProgress: TestGate? = nil
    ) {
        let sessionID = ULID()
        let registry = WorkRegistry(sessionID: sessionID)
        let runPlane = RunPlane(clock: runClock, workRegistry: registry)
        let sink = LeaseRecordingSink(registry: registry, holdingProgress: holdingProgress)
        self.init(
            sessionID: sessionID, registry: registry, runPlane: runPlane, sink: sink,
            context: ToolContext(
                sessionID: sessionID, runPlane: runPlane, sink: sink, tool: Self.probeTool, op: Self.probeTool,
                completionToken: ToolContext.makeCompletionToken(), isCancelled: { false },
                inlineSettleGrace: inlineSettleGrace))
    }

    /// Makes a session from its parts.
    ///
    /// - Parameters:
    ///   - sessionID: The id of the session.
    ///   - registry: The registry of the session.
    ///   - runPlane: The run plane of the session.
    ///   - sink: The sink of the session.
    ///   - context: The context of one call in the session.
    private init(
        sessionID: ULID, registry: WorkRegistry, runPlane: RunPlane, sink: LeaseRecordingSink, context: ToolContext
    ) {
        self.sessionID = sessionID
        self.registry = registry
        self.runPlane = runPlane
        self.sink = sink
        self.context = context
    }

    /// The kind of each open lease, in begin order.
    var openKinds: [WorkKind] {
        registry.openWork.map(\.kind)
    }

    /// Makes a child session of this session, for example a subagent, and
    /// gives the context of one call in it.
    ///
    /// The child has its own registry and its own run plane. The context
    /// comes from a real call that the child site mounts, thus its
    /// `parentSessionID` is the id of this session.
    ///
    /// - Returns: The child session.
    /// - Throws: When the mounted call read no context.
    func makeChild() async throws -> LeasedSession {
        let childID = ULID()
        let registry = WorkRegistry(sessionID: childID)
        let runPlane = RunPlane(workRegistry: registry)
        let sink = LeaseRecordingSink(registry: registry)
        let site = context.childSite(sessionID: childID, runPlane: runPlane, sink: sink)
        let box = CapturedContextBox()
        let mounted = try #require(
            ToolMounting.makeWrapped(tool: ContextCaptureTool(box: box), site: site, configuration: .synchronous)
                as? any Tool<CaptureArguments, String>)
        _ = try await mounted.call(arguments: CaptureArguments(note: "child"))
        let captured = try #require(box.context, "the call in the child session read no context")
        return LeasedSession(
            sessionID: childID, registry: registry, runPlane: runPlane, sink: sink,
            context: captured.settling(within: 0))
    }
}

/// Records each transition of one registry from the moment it is made.
///
/// The stream of the registry buffers each transition. ``close()`` closes
/// the registry, thus the stream ends, and the test reads each transition
/// that came. No wait can hang: a registry that gave no transition gives an
/// empty list.
struct WorkTransitionsRecorder {
    /// The registry that the recorder reads.
    private let registry: WorkRegistry

    /// The stream of the transitions, from the init on.
    private let stream: AsyncStream<WorkTransition>

    /// Starts to record the transitions of `registry`.
    ///
    /// - Parameter registry: The registry to read.
    init(_ registry: WorkRegistry) {
        self.registry = registry
        self.stream = registry.transitions()
    }

    /// Closes the registry, and gives each transition that came since the
    /// init.
    ///
    /// - Returns: The transitions, in order.
    func close() async -> [WorkTransition] {
        registry.close()
        var transitions: [WorkTransition] = []
        for await transition in stream {
            transitions.append(transition)
        }
        return transitions
    }
}
