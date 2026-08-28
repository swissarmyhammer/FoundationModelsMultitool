// `ConcurrencyGate` — the one exclusive gate the test support code shares.
//
// Two suites hold a shared resource to one user at a time, and each one held it
// with a gate of its own before this file: `LoopbackHTTPServer` holds the HTTP
// loopbacks of the unit test process to one open SSE stream, and the
// integration target holds its scenarios to one resident live model profile.
// The two gates were the same actor with two sets of names. This file is that
// actor, written one time, and both of them use it.
//
// Test support, and no shipped target links it. The target stands under
// `Tests/Support/` and the root manifest exports it as a product, because the
// nested `IntegrationTests` package reaches this package by path and a package
// imports the products of another package only.

/// Lets one caller at a time hold a resource, and parks each other caller until
/// the holder gives the gate back.
///
/// A counting semaphore of one, written as an actor: each operation is a
/// decision on the state of the actor, and a caller that waits parks on a
/// continuation rather than blocking a thread.
///
/// ``acquire()`` and ``release()`` are a pair. A caller that takes the gate owes
/// a ``release()`` on every exit path, the failure paths included, because a
/// gate nobody releases parks every later caller for ever.
///
/// A gate is made for one named resource, and the resource states why it needs
/// one. See ``LoopbackHTTPServer`` in the `MCPTestServer` target, and
/// `liveProfileTurnstile` in the integration test target.
public actor ConcurrencyGate {
    /// Whether a caller holds the gate.
    private var isHeld = false

    /// The callers parked until the holder releases the gate, in arrival order.
    private var parked: [CheckedContinuation<Void, Never>] = []

    /// Creates a gate that no caller holds.
    public init() {}

    /// How many callers wait for the gate.
    ///
    /// A reading, and never a promise: the count moves as callers arrive and as
    /// the gate hands itself over. A test reads it to know that a caller it
    /// started is parked.
    public var waiterCount: Int { parked.count }

    /// Takes the gate, and waits for the holder to give it back when another
    /// caller holds it. The caller owes a matching ``release()``.
    public func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { parked.append($0) }
    }

    /// Gives the gate up. It goes to the caller that waited longest, or it opens
    /// for the next ``acquire()`` when no caller waits.
    public func release() {
        guard parked.isEmpty else {
            parked.removeFirst().resume()
            return
        }
        isHeld = false
    }
}
