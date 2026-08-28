import Testing
import TestConcurrency

/// Tests of ``ConcurrencyGate``, the one exclusive gate the test support code
/// shares.
///
/// The two cases are the whole contract of the gate. One caller holds it at a
/// time, and a caller that waits gets it in arrival order.
///
/// The time limit bounds a gate that never hands itself over: a defect of that
/// shape parks every caller for ever, and a parked task fails as a hang and not
/// as an assertion.
@Suite("ConcurrencyGate", .timeLimit(.minutes(1)))
struct ConcurrencyGateTests {
    /// How many callers each case starts.
    private static let callerCount = 8

    /// Counts the callers that hold the gate at the same time.
    private actor OverlapCounter {
        /// How many callers hold the gate now.
        private var current = 0

        /// The largest number of callers that held the gate at one time.
        private(set) var maximum = 0

        /// Records that one more caller holds the gate.
        func enter() {
            current += 1
            maximum = max(maximum, current)
        }

        /// Records that one caller gave the gate back.
        func leave() {
            current -= 1
        }
    }

    /// Records the order the callers took the gate in.
    private actor ArrivalLog {
        /// The callers, in the order they took the gate.
        private(set) var order: [Int] = []

        /// Records that one caller took the gate.
        ///
        /// - Parameter index: Which caller took the gate.
        func append(_ index: Int) {
            order.append(index)
        }
    }

    @Test("the gate keeps every caller but one out of the critical section")
    func oneHolderAtATime() async {
        let gate = ConcurrencyGate()
        let counter = OverlapCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.callerCount {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    // Gives the other callers a turn. Without the gate one of
                    // them enters here, and the count of holders goes past one.
                    await Task.yield()
                    await counter.leave()
                    await gate.release()
                }
            }
        }

        let maximum = await counter.maximum
        #expect(maximum == 1)
    }

    @Test("the gate goes to the waiting callers in arrival order")
    func handsTheGateOverInArrivalOrder() async throws {
        let gate = ConcurrencyGate()
        let log = ArrivalLog()
        await gate.acquire()

        // Each caller starts, and then the test waits until the gate counts it.
        // A caller that the gate counts is parked, thus the arrival order of
        // the callers is the order of this loop.
        var callers: [Task<Void, Never>] = []
        for index in 0..<Self.callerCount {
            callers.append(
                Task {
                    await gate.acquire()
                    await log.append(index)
                    await gate.release()
                })
            try await TestPoll.waitUntil("caller \(index) waiting for the gate") {
                await gate.waiterCount == index + 1
            }
        }

        await gate.release()
        for caller in callers {
            await caller.value
        }

        let order = await log.order
        #expect(order == Array(0..<Self.callerCount))
    }
}
