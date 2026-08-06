import Foundation
import FoundationModels
import os

// MARK: - Phase-1 suspended-context fixtures (eventplan.md § "The constraint
// boundary, and the escape hatch")
//
// A snippet only stays alive past its wait window because something inside it
// is still pending. These fixtures are that something: a tool whose call blocks
// until the test releases it, so a test decides exactly when the suspended JSC
// context resumes — and can observe whether the context was torn down instead.

/// How often `GatedTool` re-reads its latch while blocked.
///
/// Short enough that releasing the latch resumes the call promptly, and
/// `Task.sleep`-based so cancelling the call's `Task` ends it at once rather
/// than leaving a continuation suspended forever.
private let gateRecheckIntervalNanoseconds: UInt64 = 5_000_000

/// The value `GatedTool` returns once it is released.
let gatedToolResult = "gated-result"

/// The one-way latch a test flips to let every `GatedTool` call finish.
///
/// A lock-guarded `final class` rather than an `actor` because `GatedTool`
/// reads it from inside a polling loop and the test writes it from outside any
/// isolation — neither side has an `await` to spare, and the state is one
/// `Bool`.
final class ToolReleaseLatch: Sendable {
    /// The one piece of state this latch holds.
    ///
    /// Whether ``release()`` has been called, lock-guarded because the blocked
    /// call polls it from the sandbox's own thread while the test flips it
    /// from its own.
    private let releasedBox = OSAllocatedUnfairLock(initialState: false)

    /// Whether ``release()`` has already been called.
    var isReleased: Bool { releasedBox.withLock { $0 } }

    /// Lets every blocked — and every later — `GatedTool` call through.
    func release() { releasedBox.withLock { $0 = true } }
}

/// A tool whose call blocks until its latch is released.
///
/// Each call records that it started, and whether it ended by cancellation
/// instead of by release.
///
/// `final class … Sendable` (rather than a `struct`), the same pattern as
/// `DelayedTool`/`WindowRecordingTool`: the test inspects `hasStarted` and
/// `wasCancelled` while the call is still in flight, backed by
/// `OSAllocatedUnfairLock` so the type stays `Sendable`.
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

    /// The latch every call polls; releasing it lets all of them finish.
    private let latch: ToolReleaseLatch

    /// Whether ``call(arguments:)`` has entered at least once.
    ///
    /// Lock-guarded so a test may read it while a call is still in flight on
    /// another thread.
    private let startedBox = OSAllocatedUnfairLock(initialState: false)

    /// Whether a call ended by cancellation rather than by release.
    ///
    /// Lock-guarded for the same reason as ``startedBox``.
    private let cancelledBox = OSAllocatedUnfairLock(initialState: false)

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
    /// its snippet elevated.
    var hasStarted: Bool { startedBox.withLock { $0 } }

    /// Whether a call was cancelled instead of released.
    ///
    /// The evidence that tearing the suspended context down reached the
    /// pending promise's own work.
    var wasCancelled: Bool { cancelledBox.withLock { $0 } }

    /// Blocks until the latch is released, then returns ``gatedToolResult``.
    ///
    /// This is the whole point of the fixture: the call never returns on its
    /// own, so the snippet awaiting it stays pending — and its JSC context
    /// stays suspended — until the test either releases the latch or cancels
    /// the call. The wait is a `Task.sleep` poll on
    /// ``gateRecheckIntervalNanoseconds`` rather than a continuation, so
    /// cancelling the call's `Task` ends it immediately; that cancellation is
    /// recorded (see ``wasCancelled``) and rethrown, never swallowed.
    ///
    /// - Parameter arguments: unused — this tool takes none.
    /// - Returns: ``gatedToolResult``, once the latch has been released.
    /// - Throws: `CancellationError` when the call's `Task` is cancelled
    ///   before the latch is released.
    func call(arguments: NoArguments) async throws -> String {
        startedBox.withLock { $0 = true }
        do {
            while !latch.isReleased {
                try await Task.sleep(nanoseconds: gateRecheckIntervalNanoseconds)
            }
        } catch {
            cancelledBox.withLock { $0 = true }
            throw error
        }
        return gatedToolResult
    }
}
