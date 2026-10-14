import Foundation
import FoundationModels

// MARK: - Phase-1 suspended-context fixtures (eventplan.md § "The constraint
// boundary, and the escape hatch")
//
// A snippet stays alive after its call has answered because something inside it
// is still pending. These fixtures are that something: a tool whose call blocks
// until the test releases it, so a test decides exactly when the suspended JSC
// context resumes — and can observe whether the context was torn down instead.
//
// Each wait here is an event (a ``TestGate``), never a sleep or a poll. A test
// that must know that the call started, or that the call ended by a cancel,
// waits on the gate of that event.

/// The value `GatedTool` returns once it is released.
let gatedToolResult = "gated-result"

/// The one-way latch a test flips to let every `GatedTool` call finish.
///
/// A `final class` over a ``TestGate``: the test releases it from outside any
/// isolation with no `await`, and a blocked call waits on the gate. The wait
/// ends at the release, or with `CancellationError` when the task of the call
/// is cancelled.
final class ToolReleaseLatch: Sendable {
    /// The gate that ``release()`` opens.
    private let gate = TestGate()

    /// Whether ``release()`` has already been called.
    var isReleased: Bool { gate.isOpen }

    /// Lets every blocked — and every later — `GatedTool` call through.
    func release() { gate.open() }

    /// Waits until ``release()`` is called.
    ///
    /// - Throws: `CancellationError` when the task is cancelled first.
    func wait() async throws {
        try await gate.wait()
    }
}

/// A tool whose call blocks until its latch is released.
///
/// Each call records that it started, and whether it ended by cancellation
/// instead of by release. A test waits for each of those events with
/// ``waitUntilStarted()`` and ``waitUntilCancelled()``.
///
/// `final class … Sendable` (rather than a `struct`), the same pattern as
/// `DelayedTool`/`WindowRecordingTool`: the test reads `hasStarted` and
/// `wasCancelled` while the call is still in flight, and each event is a
/// ``TestGate``, so the type stays `Sendable`.
final class GatedTool: Tool, Sendable {
    /// The `Tool` name this fixture installs under.
    ///
    /// A snippet reaches it as `tools.gated()`.
    let name = "gated"

    /// The model-facing description this fixture carries.
    ///
    /// No test asserts on it, but `Tool` requires one and a registry renders
    /// it into the surface.
    let description = "Blocks until the test releases it, then returns a fixed value."

    /// The latch every call waits on; releasing it lets all of them finish.
    private let latch: ToolReleaseLatch

    /// The gate that the first call opens when it enters.
    private let started = TestGate()

    /// The gate that a call opens when it ends by cancellation rather than by
    /// release.
    private let cancelled = TestGate()

    /// Creates a tool gated on `latch`.
    ///
    /// - Parameter latch: the latch whose release lets this tool's calls
    ///   finish.
    init(latch: ToolReleaseLatch) {
        self.latch = latch
    }

    /// Whether `call` has begun at least once.
    ///
    /// The evidence that an inner `tools.*` call was genuinely in flight when
    /// its snippet went to the background.
    var hasStarted: Bool { started.isOpen }

    /// Whether a call was cancelled instead of released.
    ///
    /// The evidence that tearing the suspended context down reached the
    /// pending promise's own work.
    var wasCancelled: Bool { cancelled.isOpen }

    /// Waits until a call entered.
    ///
    /// - Throws: `CancellationError` when the waiting task is cancelled first.
    func waitUntilStarted() async throws {
        try await started.wait()
    }

    /// Waits until a call ended by cancellation.
    ///
    /// The call writes this event as its own task unwinds, which can be after
    /// the terminal event of its run. A test waits for the event, and does not
    /// sample the flag.
    ///
    /// - Throws: `CancellationError` when the waiting task is cancelled first.
    func waitUntilCancelled() async throws {
        try await cancelled.wait()
    }

    /// Blocks until the latch is released, then returns ``gatedToolResult``.
    ///
    /// This is the whole point of the fixture: the call never returns on its
    /// own, so the snippet awaiting it stays pending — and its JSC context
    /// stays suspended — until the test either releases the latch or cancels
    /// the call. The wait is on the gate of the latch, and a cancel of the
    /// call's `Task` ends it at once. That cancellation is recorded (see
    /// ``wasCancelled``) and rethrown, never swallowed.
    ///
    /// - Parameter arguments: unused — this tool takes none.
    /// - Returns: ``gatedToolResult``, once the latch has been released.
    /// - Throws: `CancellationError` when the call's `Task` is cancelled
    ///   before the latch is released.
    func call(arguments: NoArguments) async throws -> String {
        started.open()
        do {
            try await latch.wait()
        } catch {
            cancelled.open()
            throw error
        }
        return gatedToolResult
    }
}
