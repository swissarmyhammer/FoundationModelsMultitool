// `DedicatedThread` — the run of one blocking call on a thread of its own,
// and not on a thread of the Swift cooperative pool.
//
// A call such as `waitpid` or `waitid` with no `WNOHANG` holds the thread that
// makes it until the kernel answers. The cooperative pool has few threads.
// Each thread that such a call holds is lost to every other task until the
// call ends. Thus async code gives each blocking call to this type, and awaits
// the result.

import Foundation

/// The run of one blocking call on a thread of its own.
enum DedicatedThread {
    /// Runs `body` on a new thread, and gives back its result.
    ///
    /// The caller suspends and holds no thread while `body` runs. `body` runs
    /// with no current task.
    ///
    /// - Parameter body: The blocking call.
    /// - Returns: The value `body` returns.
    static func run<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            let thread = Thread {
                continuation.resume(returning: body())
            }
            thread.start()
        }
    }
}
