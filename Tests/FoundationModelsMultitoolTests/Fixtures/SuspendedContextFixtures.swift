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
    private let releasedBox = OSAllocatedUnfairLock(initialState: false)

    /// Whether ``release()`` has already been called.
    var isReleased: Bool { releasedBox.withLock { $0 } }

    /// Lets every blocked — and every later — `GatedTool` call through.
    func release() { releasedBox.withLock { $0 = true } }
}

/// A tool whose call blocks until its latch is released, recording that it
/// started and whether it was cancelled instead of released.
///
/// `final class … Sendable` (rather than a `struct`), the same pattern as
/// `DelayedTool`/`WindowRecordingTool`: the test inspects `hasStarted` and
/// `wasCancelled` while the call is still in flight, backed by
/// `OSAllocatedUnfairLock` so the type stays `Sendable`.
final class GatedTool: Tool, Sendable {
    let name = "gated"
    let description = "Blocks until the test releases it, then returns a fixed value."

    private let latch: ToolReleaseLatch
    private let startedBox = OSAllocatedUnfairLock(initialState: false)
    private let cancelledBox = OSAllocatedUnfairLock(initialState: false)

    /// Creates a tool gated on `latch`.
    ///
    /// - Parameter latch: the latch whose release lets this tool's calls
    ///   finish.
    init(latch: ToolReleaseLatch) {
        self.latch = latch
    }

    /// Whether `call` has begun at least once — the evidence that an inner
    /// `tools.*` call was genuinely in flight when its snippet elevated.
    var hasStarted: Bool { startedBox.withLock { $0 } }

    /// Whether a call ended by cancellation rather than by release — the
    /// evidence that tearing the suspended context down reached the pending
    /// promise's own work.
    var wasCancelled: Bool { cancelledBox.withLock { $0 } }

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
