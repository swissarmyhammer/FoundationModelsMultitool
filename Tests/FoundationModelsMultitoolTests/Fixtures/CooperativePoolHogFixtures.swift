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

/// The value `CooperativePoolHogTool` returns when it stops.
let cooperativePoolHogResult = "hog-result"

/// The time one child of `CooperativePoolHogTool` spins before it yields.
///
/// Short, so that another task at the same priority gets a thread soon. That is
/// also how the children of a real grep behave: each one is a short job.
private let hogSliceDuration: Duration = .milliseconds(5)

/// The longest time `CooperativePoolHogTool` keeps the CPUs busy.
///
/// A test releases the latch long before this. The ceiling stops the spin of a
/// test that failed before it released the latch, so that no other test runs
/// beside a busy CPU for the rest of the suite.
private let hogCeiling: Duration = .seconds(10)

/// A tool that keeps each thread of the cooperative pool busy until its latch
/// is released.
///
/// The children run at `.high`. That is the priority a real inner `tools.*`
/// call gets, because the sandbox thread that starts it runs at QoS
/// userInitiated. The priority is stated here so that the fixture does not
/// depend on the thread that calls it.
///
/// `final class … Sendable` with lock-guarded state, the same pattern as
/// `GatedTool`: a test reads ``hasStarted`` while the call is in flight.
final class CooperativePoolHogTool: Tool, Sendable {
    /// The `Tool` name this fixture installs under.
    ///
    /// A snippet reaches it as `tools.hog()`.
    let name = "hog"

    /// The model-facing description this fixture carries.
    let description = "Keeps every CPU busy until the test releases it, then returns a fixed value."

    /// The latch whose release stops every child.
    private let latch: ToolReleaseLatch

    /// Whether a child of a call spins now.
    private let startedBox = OSAllocatedUnfairLock(initialState: false)

    /// Creates a tool that stops when `latch` is released.
    ///
    /// - Parameter latch: the latch whose release stops the call.
    init(latch: ToolReleaseLatch) {
        self.latch = latch
    }

    /// Whether a child of a call spins now: the cooperative pool is busy.
    var hasStarted: Bool { startedBox.withLock { $0 } }

    /// Keeps one busy child on each CPU until the latch is released, the
    /// ceiling elapses, or the call is cancelled.
    ///
    /// - Parameter arguments: unused — this tool takes none.
    /// - Returns: ``cooperativePoolHogResult``.
    func call(arguments: NoArguments) async throws -> String {
        let deadline = ContinuousClock.now + hogCeiling
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
                group.addTask(priority: .high) { await self.spin(until: deadline) }
            }
        }
        try Task.checkCancellation()
        return cooperativePoolHogResult
    }

    /// Spins one slice at a time, and yields between the slices, until the
    /// latch is released, `deadline` is reached, or the task is cancelled.
    ///
    /// - Parameter deadline: the instant the spin stops at the latest.
    private func spin(until deadline: ContinuousClock.Instant) async {
        startedBox.withLock { $0 = true }
        while !latch.isReleased, ContinuousClock.now < deadline, !Task.isCancelled {
            let sliceEnd = ContinuousClock.now + hogSliceDuration
            while ContinuousClock.now < sliceEnd {}
            await Task.yield()
        }
    }
}
