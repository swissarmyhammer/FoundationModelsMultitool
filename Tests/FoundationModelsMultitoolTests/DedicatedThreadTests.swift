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

    /// A started body also runs with no current task, and the caller gets
    /// no result. The body gives its one fact to a stream, and the test
    /// waits for that event, not for a time. A stream that ends with no
    /// fact gives `nil`, and the check fails.
    @Test func theStartedBodyRunsWithNoCurrentTask() async {
        let (facts, factsContinuation) = AsyncStream.makeStream(of: Bool.self)

        DedicatedThread.start {
            factsContinuation.yield(withUnsafeCurrentTask { $0 != nil })
            factsContinuation.finish()
        }

        var iterator = facts.makeAsyncIterator()
        let ranInATask = await iterator.next()
        #expect(ranInATask == false)
    }
}
