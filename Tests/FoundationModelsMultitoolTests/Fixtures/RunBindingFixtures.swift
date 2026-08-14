import Foundation
import FoundationModels
import FoundationModelsRouter
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

    /// The run's `completionToken`, or `nil` when the call ran with no
    /// ambient context bound at all.
    let completionToken: String?

    /// The owning session's identity, or `nil` when the call ran with no
    /// ambient context bound at all.
    let sessionID: ULID?

    /// Whether a `Task.detached` started inside the call saw no ambient
    /// context — the capture-at-start rule the ambient design enforces
    /// (a detached task inherits no task locals).
    let detachedContextWasNil: Bool
}

/// An `OperationEventSink` that keeps every event posted to it, so a test can
/// assert which session's sink a run's events actually reached.
///
/// An `actor` rather than a lock-guarded class because `post(_:)` is already
/// `async`: the protocol's own shape makes actor isolation the cheaper
/// synchronization.
actor RecordingEventSink: OperationEventSink {
    /// Every event posted to this sink, in arrival order.
    private(set) var events: [OperationEvent] = []

    func post(event: OperationEvent) async {
        events.append(event)
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
        let detachedContextWasNil = await Task.detached { ToolContext.current == nil }.value
        await context?.progress("\(name) ran")
        observationsBox.withLock {
            $0.append(
                AmbientObservation(
                    toolName: name,
                    completionToken: context?.completionToken,
                    sessionID: context?.sessionID,
                    detachedContextWasNil: detachedContextWasNil
                )
            )
        }
        return "\(name)-result"
    }
}

/// Builds the ambient `ToolContext` a Router session binds around one
/// `runCode` call — the context `MultiTool` captures into its `RunBinding`.
///
/// Stamped with `runCode`'s own tool name, exactly as `DetachingTool` stamps a
/// wrapped tool's context, and given a freshly minted `completionToken` so a
/// test can tell the outer run's correlation from every inner one.
///
/// - Parameters:
///   - mailbox: the session's mailbox.
///   - sink: the session's upstream sink.
/// - Returns: the outer `runCode` run's ambient context.
func makeOuterRunContext(mailbox: SessionMailbox, sink: any OperationEventSink) -> ToolContext {
    ToolContext(
        sessionID: ULID(),
        mailbox: mailbox,
        sink: sink,
        tool: "runCode",
        op: "runCode",
        completionToken: SessionMailbox.makeCompletionToken(),
        isCancelled: { false }
    )
}
