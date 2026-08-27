// `TransportContracts` — the two contracts a transport can state to the server
// that connects through it: "this failure is permanent, do not retry it", and
// "this instance owns a resource, release it if you never connect it".
//
// A behavioral port of the `NonRetryableConnectError` and
// `DisposableTransport` protocols of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`. They
// stand in a file of their own here because `StdioServerProcess` conforms to
// both, and it lands before `MCPServer`, the one reader of both. That reader
// comes with the task that ports the connection lifecycle.
//
// **Why the sdk's own `Transport` cannot carry either.** `Transport` is the
// protocol of the `MCP` module, and this package does not own it, so it
// cannot add a requirement to it. Its one lifecycle requirement,
// `disconnect()`, is documented as "tear down an established connection", and
// nothing states what it does on an instance that was never connected. A host
// can supply any `Transport` it likes through a factory, so the release of a
// never-connected resource is an opt-in convention beside the protocol, and
// not a reuse of `disconnect()`.
//
// **The types are internal.** The Shell capability keeps its types internal,
// and this folder does the same. A public error type can conform to an
// internal protocol: the conformance is internal, and the type stays public.

import MCP

/// Marks an error a transport factory throws as a CANDIDATE permanent
/// configuration failure — a stdio server's absent or non-executable
/// `command`, for example — and not a transient connectivity failure that a
/// retry schedule should retry.
///
/// A server that connects through a factory fails at once on an error that
/// conforms to this protocol with ``isNonRetryable`` `true`: after exactly
/// one attempt, with no backoff delay. To retry the same `command`, `args` and
/// `env` cannot give a different outcome once it failed this way, so a retry
/// would only burn the attempts and the wall-clock delay of the schedule on a
/// failure already known to be permanent.
///
/// ``isNonRetryable`` exists — this is not a plain marker protocol — because
/// not every conforming TYPE is permanent in every INSTANCE.
/// ``StdioServerProcess/StdioServerProcessError`` conforms as a whole and
/// answers per case: a pipe that cannot be created (fd exhaustion in the
/// parent) is plausibly transient, unlike a bad `command` path. The default
/// (`true`) fits the usual case: a type that conforms at all usually does so
/// because every case it has is permanent.
protocol NonRetryableConnectError: Error, Sendable {
    /// Whether this specific error instance is a permanent configuration
    /// failure that a retry cannot fix, as opposed to a transient one.
    // `MCPServer` (task ^832pg8r) reads this through the protocol on its
    // connect path; today only the concrete conformer is read, by a test.
    // periphery:ignore
    var isNonRetryable: Bool { get }
}

extension NonRetryableConnectError {
    /// Permanent by default — see the doc of the protocol for why a
    /// conforming type overrides this only when some of its cases are
    /// transient.
    // The one conformer of this package overrides this; `MCPServer` (task
    // ^832pg8r) reads it through the protocol for a conformer that does not.
    // periphery:ignore
    var isNonRetryable: Bool { true }
}

/// A `Transport` that owns an external resource — above all a spawned
/// subprocess — which must be released explicitly when the transport is
/// discarded before it was ever handed to `MCP.Client.connect(transport:)`.
///
/// A factory can spawn a subprocess as a side effect of BUILDING the
/// transport, before the server decides whether it will use it. A connect
/// attempt that a newer attempt superseded then holds a transport nothing
/// will ever connect, and a transport that conforms here is how that attempt
/// releases the resource instead of leaving it to run.
///
/// A transport that never conforms behaves as before: the discard path simply
/// drops the reference.
///
/// - SeeAlso: `StdioServerProcess.swift`, whose private transport is the one
///   conforming implementation of this package.
protocol DisposableTransport: Transport {
    /// Releases whatever resource this transport owns, given that this
    /// instance will never be connected.
    ///
    /// A server calls this exactly one time, on its discard path for a
    /// superseded connect attempt — never after a successful
    /// `client.connect(transport:)`, and never more than one time for the same
    /// instance. The implementation must be safe on an instance that was
    /// never connected, because that is the only circumstance it runs in.
    func dispose() async
}
