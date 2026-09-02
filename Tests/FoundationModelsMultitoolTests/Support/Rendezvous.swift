// `Rendezvous` — a meeting point for a party of a fixed size, and the tool
// that puts a snippet at it.
//
// A test that must have two `runCode` calls in flight at the same time, before
// either makes its mutation, needs each snippet to stop and wait for the
// other. `ReleaseGate` holds ONE waiter, thus two snippets cannot both wait
// on one gate. The rendezvous counts arrivals instead: each arrival before
// the last waits on the gate, and the last arrival releases it. For a party
// of two, one waiter blocks at a time, and the gate stays what it is.

import FoundationModels

/// A meeting point for a party of a fixed size: each arrival waits until the
/// whole party has arrived, and every arrival then proceeds at once.
actor Rendezvous {
    /// The gate the early arrivals wait on.
    private let gate = ReleaseGate()

    /// How many arrivals open the gate.
    private let partySize: Int

    /// How many have arrived so far.
    private var arrivals = 0

    /// Makes a rendezvous for `partySize` arrivals.
    ///
    /// - Parameter partySize: how many arrivals open the gate.
    init(partySize: Int) {
        self.partySize = partySize
    }

    /// Records one arrival, and waits until the party is complete.
    ///
    /// The arrival that completes the party releases the gate, thus each
    /// earlier arrival resumes, and its own wait returns at once.
    func arrive() async {
        arrivals += 1
        if arrivals >= partySize {
            await gate.release()
        }
        await gate.wait()
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
