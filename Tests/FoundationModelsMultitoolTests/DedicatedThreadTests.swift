import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for ``DedicatedThread``: a blocking call runs on a thread
/// of its own, and not on a thread of the Swift cooperative pool.
@Suite struct DedicatedThreadTests {
    /// The body runs with no current task. A body that runs inline in the
    /// task that awaits it runs on a thread of the cooperative pool, and
    /// there it reads the task of the caller. The check needs no wait and
    /// no clock: the body reads one fact, and gives it back.
    @Test func theBodyRunsWithNoCurrentTask() async {
        let ranInATask = await DedicatedThread.run {
            withUnsafeCurrentTask { $0 != nil }
        }

        #expect(!ranInATask)
    }
}
