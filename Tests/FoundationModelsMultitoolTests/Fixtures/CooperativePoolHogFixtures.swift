import Foundation
import FoundationModels
import os

// MARK: - A slow tool that keeps every CPU busy (task ^cf57dtd)
//
// A real slow tool does not only wait. `GrepCode.run` of
// FoundationModelsCodeContext adds one CPU-bound child task for each index
// chunk, and the children keep every thread of the cooperative pool busy for
// the whole grep. While that is so, the kernel gives no new thread to a
// constrained global dispatch queue at the same QoS. This fixture does the same
// thing in a form that a test can stop.
//
// The fixture reads no clock. A child spins until the latch is released, and
// it measures one slice of work by a count of latch reads, not by time.

/// The value `CooperativePoolHogTool` returns when it stops.
let cooperativePoolHogResult = "hog-result"

/// How many times one child of `CooperativePoolHogTool` reads its latch in
/// one slice before it yields.
///
/// Each read takes a lock, thus the slice is real CPU work that the compiler
/// cannot remove. The count keeps a slice short, so that another task at the
/// same priority gets a thread soon. That is also how the children of a real
/// grep behave: each one is a short job.
private let hogSliceLatchReads = 10_000

/// A tool that keeps each thread of the cooperative pool busy until its latch
/// is released.
///
/// The children run at `.high`. That is the priority a real inner `tools.*`
/// call gets, because the sandbox thread that starts it runs at QoS
/// userInitiated. The priority is stated here so that the fixture does not
/// depend on the thread that calls it.
///
/// A child stops when the latch is released or when the call is cancelled.
/// A test that fails before it releases the latch releases it in a `defer`,
/// thus no spin outlives its test.
///
/// `final class … Sendable` with lock-guarded state, the same pattern as
/// `GatedTool`: a test waits for ``waitUntilStarted()`` and reads
/// ``isSpinning`` while the call is in flight.
final class CooperativePoolHogTool: Tool, Sendable {
    /// The `Tool` name this fixture installs under.
    ///
    /// A snippet reaches it as `tools.hog()`.
    let name = "hog"

    /// The model-facing description this fixture carries.
    let description = "Keeps every CPU busy until the test releases it, then returns a fixed value."

    /// The latch whose release stops every child.
    private let latch: ToolReleaseLatch

    /// The gate that the first child opens when it starts to spin.
    private let started = TestGate()

    /// The number of children that spin now.
    private let spinningChildren = OSAllocatedUnfairLock(initialState: 0)

    /// Creates a tool that stops when `latch` is released.
    ///
    /// - Parameter latch: the latch whose release stops the call.
    init(latch: ToolReleaseLatch) {
        self.latch = latch
    }

    /// Whether a child of a call started to spin: the cooperative pool became
    /// busy.
    var hasStarted: Bool { started.isOpen }

    /// Whether a child of a call spins now: the cooperative pool is still
    /// busy. It becomes `false` when the latch is released or the call is
    /// cancelled.
    var isSpinning: Bool { spinningChildren.withLock { $0 > 0 } }

    /// Waits until a child of a call started to spin.
    ///
    /// - Throws: `CancellationError` when the waiting task is cancelled first.
    func waitUntilStarted() async throws {
        try await started.wait()
    }

    /// Keeps one busy child on each CPU until the latch is released or the
    /// call is cancelled.
    ///
    /// - Parameter arguments: unused — this tool takes none.
    /// - Returns: ``cooperativePoolHogResult``.
    func call(arguments: NoArguments) async throws -> String {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
                group.addTask(priority: .high) { await self.spin() }
            }
        }
        try Task.checkCancellation()
        return cooperativePoolHogResult
    }

    /// Spins one slice at a time, and yields between the slices, until the
    /// latch is released or the task is cancelled.
    ///
    /// A slice is ``hogSliceLatchReads`` reads of the latch. The yield is part
    /// of the work, as in a real grep, and not a wait for time.
    private func spin() async {
        spinningChildren.withLock { $0 += 1 }
        defer { spinningChildren.withLock { $0 -= 1 } }
        started.open()
        while !latch.isReleased, !Task.isCancelled {
            for _ in 0..<hogSliceLatchReads where latch.isReleased {
                break
            }
            await Task.yield()
        }
    }
}
