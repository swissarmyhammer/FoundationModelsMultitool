// `Rendezvous` — a meeting point for a party of a fixed size, and the tool
// that puts a snippet at it.
//
// A test that must have two `runCode` calls in flight at the same time, before
// either makes its mutation, needs each snippet to stop and wait for the
// other. The rendezvous counts arrivals on a `TestCountdown`: each arrival
// before the last waits on it, and the last arrival opens it. A cancel of the
// task of an arrival ends its wait, as it ends each wait of that countdown.

import FoundationModels

/// A meeting point for a party of a fixed size: each arrival waits until the
/// whole party has arrived, and every arrival then proceeds at once.
final class Rendezvous: Sendable {
    /// The count of arrivals that opens when the whole party came.
    private let countdown: TestCountdown

    /// Makes a rendezvous for `partySize` arrivals.
    ///
    /// - Parameter partySize: how many arrivals open the gate.
    init(partySize: Int) {
        countdown = TestCountdown(count: partySize)
    }

    /// Records one arrival, and waits until the party is complete or the
    /// task of the caller is cancelled.
    ///
    /// The arrival that completes the party opens the countdown, thus each
    /// earlier arrival resumes, and its own wait returns at once. A cancelled
    /// arrival goes on, and the cancel that its task carries ends the run
    /// after the wait.
    func arrive() async {
        countdown.arrive()
        try? await countdown.wait()
    }
}

/// A standalone tool that puts the calling snippet at a ``Rendezvous``.
///
/// A snippet reaches it as `await tools.rendezvous()`, and the call returns
/// when the whole party has called it.
struct RendezvousTool: Tool {
    /// The `tools.*` name this tool installs under.
    static let toolName = "rendezvous"

    let name = RendezvousTool.toolName
    let description = "Returns when every member of the party has called it."

    /// The meeting point each call arrives at.
    let rendezvous: Rendezvous

    func call(arguments: NoArguments) async throws -> String {
        await rendezvous.arrive()
        return "arrived"
    }
}
