// `GatedTransportFactory` — a transport factory whose call waits for a gate.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/GatedTransportFactory.swift`
// over `ReleaseGate`.

import MCP

/// Wraps a `TransportFactory`-shaped closure so a test holds its invocation
/// open past `BackoffPolicy.connectTimeout`, then releases it — the
/// factory-level counterpart of ``GatedConnectTransport``, which gates the
/// `connect()` of a transport instead.
///
/// This reproduces, without a real subprocess, the race
/// `StdioServerProcess.respawn()` is exposed to for real: the FACTORY CALL
/// itself — not the `connect()` of the transport — is what can still be
/// running when a newer connect attempt supersedes it. A double that gates
/// `connect()` cannot reach the post-factory guard of a connect attempt at
/// all: by the time its gate opens, the factory already returned.
actor GatedTransportFactory {
    /// The gate ``make()`` waits on.
    private let gate = ReleaseGate()

    /// The factory logic to run once ``make()`` is unblocked.
    private let build: @Sendable () async throws -> any Transport

    /// Creates a gated factory around `build`, with the gate closed.
    ///
    /// - Parameter build: The factory logic to run once ``make()`` is
    ///   unblocked — called one time per ``make()`` call, like a real
    ///   `TransportFactory`.
    init(build: @escaping @Sendable () async throws -> any Transport) {
        self.build = build
    }

    /// Blocks the calling factory invocation until ``release()`` is called,
    /// then invokes `build`.
    ///
    /// - Returns: What `build` returns.
    /// - Throws: What `build` throws.
    func make() async throws -> any Transport {
        await gate.wait()
        return try await build()
    }

    /// Opens the gate: resumes a ``make()`` already blocked on it, and lets
    /// every future ``make()`` proceed at once.
    func release() async {
        await gate.release()
    }
}
