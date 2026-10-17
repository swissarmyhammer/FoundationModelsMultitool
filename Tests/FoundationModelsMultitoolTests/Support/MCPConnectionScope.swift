// `MCPConnectionScope` — the one scoped teardown of an MCP connection that
// the MCP suites share.
//
// Test rule T1: a fixture closes also when the test body throws. Swift has no
// `defer` that can wait for an `async` call, and a `defer { Task { ... } }`
// does not wait: the test can end before the disconnect runs. Thus each test
// that connects a server gives its body to
// ``MCPTestSupport/withConnection(of:_:)``, which awaits the disconnect on
// each path.

import MCP

@testable import FoundationModelsMultitool

/// A connection that a test closes with one awaited `disconnect()`.
///
/// The connect helpers of ``MCPTestSupport`` return an `MCPServer` or an
/// `MCP.Client`. Both conform, thus one helper closes each of them.
protocol Disconnectable: Actor {
    /// Closes the connection. A second call does nothing.
    func disconnect() async
}

extension MCPServer: Disconnectable {}

extension Client: Disconnectable {}

extension MCPTestSupport {
    /// Runs `body`, and then disconnects `connection`, also when `body` throws.
    ///
    /// The test awaits the disconnect on each path, thus the connection is
    /// closed before the test ends. A `.http` connection holds a process-wide
    /// registry entry of `LoopbackHTTPServer` until it closes, thus a
    /// connection that stays open after its test is a fixture that leaks into
    /// the next test.
    ///
    /// `disconnect()` is idempotent. Thus `body` can disconnect the
    /// connection itself, for example to test a call after the disconnect.
    ///
    /// - Parameters:
    ///   - connection: The connected server or client to disconnect.
    ///   - body: The work of the test on `connection`.
    /// - Returns: What `body` returned.
    /// - Throws: What `body` threw, after the disconnect.
    static func withConnection<Connection: Disconnectable, Result>(
        of connection: Connection, _ body: () async throws -> Result
    ) async throws -> Result {
        try await ensuring({ await connection.disconnect() }, after: body)
    }
}
