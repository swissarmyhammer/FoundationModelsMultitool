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
//
// It also holds two waits that end on a second event (test rule T1). The
// first reads the notifications that a scripted server recorded after a
// disconnect: the end of the message loop of the server ends that wait.
// The second waits for an event of a client, and a ping ends it when the
// event does not come: ``MCPTestSupport/waitFor(_:orPingOf:)``.

import MCP
import MCPTestServer
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

    /// Disconnects `connection`, and then waits until `scripted` recorded at
    /// least `count` notifications — the wait of a test for a notification
    /// that the client sends.
    ///
    /// The wait ends on the first of two events: `scripted` recorded `count`
    /// notifications, or its message loop ended because the transport
    /// closed. `MCPServer.disconnect()` sends each pending
    /// `notifications/cancelled` of a cancelled calling task before it
    /// closes the transport. A send of `MCP.Client` returns when the
    /// notification is on the in-memory transport. The loop records each
    /// notification that came before the close, and only then ends. Thus a
    /// notification that the client sent is in the result, and a
    /// notification that the client did not send ends the wait with a
    /// shorter result: the check of the caller then fails, and the test does
    /// not hang.
    ///
    /// The connection is closed after this call. A test that reads the
    /// state of the connection reads it before this call.
    ///
    /// - Parameters:
    ///   - scripted: The scripted server that records the notifications.
    ///   - connection: The server or the client that sends them.
    ///   - count: The minimum number of recorded notifications to wait for.
    /// - Returns: The recorded notifications.
    static func notifications<Connection: Disconnectable>(
        recordedBy scripted: ScriptedServer, afterDisconnectOf connection: Connection, count: Int
    ) async -> [RecordedNotification] {
        await connection.disconnect()
        return await scripted.waitForRecordedNotifications(count: count)
    }

    /// Waits for the first of two events: `expected` returned, or a ping of
    /// `client` returned — the wait of a test for a notification that the
    /// server sent to `client`.
    ///
    /// The caller calls this after the send of the notification returned.
    /// `MCP.Client` reads the messages of its transport in order, and it runs
    /// each notification handler before it reads the next message. The
    /// answer of the ping comes after each message that the server sent
    /// before. Thus when the ping returned, the client handled each such
    /// notification: a notification that did not come ends the wait, the
    /// check of the caller then fails, and the test does not hang. The
    /// server answers each ping while the connection is open.
    ///
    /// - Parameters:
    ///   - expected: The wait for the handler of the notification. A cancel
    ///     must end it.
    ///   - client: The client that the server sent the notification to.
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   first event.
    static func waitFor(
        _ expected: @escaping @Sendable () async -> Void, orPingOf client: Client
    ) async throws {
        try await EventRace.firstOf(expected, or: { _ = try? await client.ping() })
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
