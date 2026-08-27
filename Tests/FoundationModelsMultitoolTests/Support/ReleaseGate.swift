// `ReleaseGate` — the one gate every gated test double of this target waits
// on.
//
// The source of these doubles carried the same `released` flag, the same
// stored continuation and the same `release()` in three files
// (`GatedConnectTransport`, `GatedDisconnectTransport` and
// `GatedTransportFactory` of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/`). Here the
// gate stands one time, and each double holds one.

/// A gate that holds one waiter until it is released, and lets every later
/// waiter through at once.
actor ReleaseGate {
    /// Whether ``release()`` ran.
    private var released = false

    /// The waiter blocked on the gate, when there is one.
    private var continuation: CheckedContinuation<Void, Never>?

    /// Blocks the caller until ``release()`` is called, or returns at once
    /// when it already was.
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
        }
    }

    /// Opens the gate: resumes a ``wait()`` already blocked on it, and lets
    /// every future ``wait()`` proceed at once.
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
