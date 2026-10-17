// `MCPConnectionScope` — the one scoped teardown of an MCP connection that
// the MCP suites share.
//
// Test rule T1: a fixture closes also when the test body throws. Swift has no
// `defer` that can wait for an `async` call, and a `defer { Task { ... } }`
// does not wait: the test can end before the disconnect runs. Thus each test
// that connects a server gives its body to
// ``MCPTestSupport/withConnection(of:_:)``, which awaits the disconnect on
// each path.
//
// The file also holds the shared checks of a specific `MCPError`, for
// example the error that a client disconnect gives to each request that is
// still pending: ``MCPTestSupport/expectClientDisconnected(_:)``.

import MCP
import Testing

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

    /// The detail of the `MCPError.internalError` that `MCP.Client.disconnect()`
    /// gives to each request that is still pending.
    static let clientDisconnectedDetail = "Client disconnected"

    /// Records a failure unless `body` throws an `MCPError` that `matches`
    /// accepts. A result, or another error, fails the test.
    ///
    /// `MCPError` is not `Equatable`: its `transportError` case holds an
    /// `Error`. Thus the caller gives a match of the case in place of a
    /// value to compare.
    ///
    /// - Parameters:
    ///   - expected: The name of the error, for the message of a failure.
    ///   - body: The work that must throw the error.
    ///   - matches: Whether the thrown `MCPError` is the expected one.
    static func expectMCPError(
        named expected: String, from body: () async throws -> Void,
        matching matches: (MCPError) -> Bool
    ) async {
        let thrown = await MCPCallProbe.thrownError(from: body)
        guard let error = thrown as? MCPError else {
            Issue.record("expected \(expected), got \(String(describing: thrown))")
            return
        }
        #expect(matches(error), "expected \(expected), got \(error)")
    }

    /// Records a failure unless `body` throws the `MCPError.internalError`
    /// that `MCP.Client.disconnect()` gives to each request that is still
    /// pending.
    ///
    /// - Parameter body: The wait for the request that a disconnect ended.
    static func expectClientDisconnected(_ body: () async throws -> Void) async {
        await expectMCPError(
            named: "the \"\(clientDisconnectedDetail)\" MCPError.internalError", from: body
        ) { error in
            guard case .internalError(let detail) = error else { return false }
            return detail == clientDisconnectedDetail
        }
    }

    /// Records a failure unless `body` throws `MCPError.connectionClosed`:
    /// the error that a failing attempt of `FlakyConnectTransport` throws
    /// by default.
    ///
    /// - Parameter body: The connect that must fail.
    static func expectConnectionClosed(_ body: () async throws -> Void) async {
        await expectMCPError(named: "MCPError.connectionClosed", from: body) { error in
            guard case .connectionClosed = error else { return false }
            return true
        }
    }
}
