// `CallEnd` — the event that a call ended, and what it returned.
//
// A test that waits for an effect of a call, for example a command that the
// call starts, also waits for the end of that call. When the call ends first,
// the effect never comes, and the test records an issue in place of a wait
// with no end.

import Synchronization

/// The end of one call, and a description of what it returned.
///
/// ``record(_:)`` is synchronous, and the first record wins. Each observer
/// that ``observe(_:)`` added before the record runs in that record. An
/// observer that comes after the record runs at once. Thus no order of the
/// record and of the observe loses the event.
final class CallEnd: Sendable {
    /// What the record and the observers change.
    private struct State {
        /// What the call returned, after the record.
        var returned: String?

        /// Each observer that waits for the record.
        var observers: [@Sendable (String) -> Void] = []
    }

    /// The state of the event.
    private let state = Mutex(State())

    /// Makes an event of a call that did not end.
    init() {}

    /// Records the end of the call, and runs each observer. A second record
    /// does nothing.
    ///
    /// - Parameter returned: A description of what the call returned.
    func record(_ returned: String) {
        let observers = state.withLock { current -> [@Sendable (String) -> Void] in
            guard current.returned == nil else { return [] }
            current.returned = returned
            defer { current.observers.removeAll() }
            return current.observers
        }
        for observer in observers {
            observer(returned)
        }
    }

    /// Runs `observer` with what the call returned, when the call ended. Runs
    /// it at once when the call already ended.
    ///
    /// - Parameter observer: The observer. It must not block.
    func observe(_ observer: @escaping @Sendable (String) -> Void) {
        let returned = state.withLock { current -> String? in
            if current.returned == nil {
                current.observers.append(observer)
            }
            return current.returned
        }
        if let returned {
            observer(returned)
        }
    }

    /// Runs `call`, and records its end with what it returned or threw.
    ///
    /// - Parameter call: The call.
    /// - Returns: What `call` returned.
    /// - Throws: What `call` threw.
    func recording<Value: Sendable>(_ call: () async throws -> Value) async throws -> Value {
        do {
            let value = try await call()
            record("returned \(String(describing: value))")
            return value
        } catch {
            record("threw \(String(describing: error))")
            throw error
        }
    }

    /// An event that records the end of a call that `end` waits for.
    ///
    /// Use it for a call that a test does not run itself, for example a
    /// background run of a session. The task that waits ends when `end`
    /// returns, thus `end` must be an event that the test also waits for.
    ///
    /// - Parameter end: Waits for the end of the call, and gives a
    ///   description of what it returned.
    /// - Returns: The event.
    static func after(_ end: @escaping @Sendable () async -> String) -> CallEnd {
        let callEnd = CallEnd()
        Task { callEnd.record(await end()) }
        return callEnd
    }
}
