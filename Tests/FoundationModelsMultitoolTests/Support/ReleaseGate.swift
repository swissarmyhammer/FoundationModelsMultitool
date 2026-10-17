// `ReleaseGate` — the one gate every gated test double of this target waits
// on.
//
// The source of these doubles carried the same `released` flag, the same
// stored continuation and the same `release()` in three files
// (`GatedConnectTransport`, `GatedDisconnectTransport` and
// `GatedTransportFactory` of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/`). Here the
// gate stands one time, and each double holds one. It waits on a `TestGate`,
// thus a cancel ends each wait as it ends each wait of that gate.

/// A gate that holds each waiter until it is released, and lets every later
/// waiter through at once.
///
/// A cancel of the task of a waiter also ends its wait. The waiter then goes
/// on as if the gate opened, and the cancel that its task carries ends the
/// work after the wait. Thus a double whose gate the test never releases
/// does not hold its task for ever.
actor ReleaseGate {
    /// The gate that ``release()`` opens.
    private let gate = TestGate()

    /// Blocks the caller until ``release()`` is called or the task of the
    /// caller is cancelled. Returns at once when the gate was released.
    func wait() async {
        // A cancel ends the wait: the caller goes on, and its cancelled task
        // ends the work after the gate.
        try? await gate.wait()
    }

    /// Opens the gate: resumes each ``wait()`` already blocked on it, and lets
    /// every future ``wait()`` proceed at once.
    func release() {
        gate.open()
    }
}
