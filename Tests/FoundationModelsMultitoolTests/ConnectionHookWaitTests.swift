import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the ends of the two connection test hooks of `MCPServer`:
/// `waitUntilTransportDropped()` and
/// `waitUntilToolListChangedGeneration(reaches:)`.
///
/// Test rule T1: each wait must also end when its event cannot come any more.
/// A disconnect or a new connect ends the connection whose drop a wait waits
/// for. A transport drop or a disconnect ends the stream of notifications
/// whose count a wait waits for. Each test here shows that such an end ends
/// the wait with `ConnectionHookWaitError.connectionEnded`.
///
/// The order of each test is fixed. The test starts the wait, and waits for
/// the first of two events: the server recorded the wait, or the wait ended
/// — see ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``. Then the test
/// makes the end of the connection. Then it cancels the wait and reads its
/// result. A wait that the end of the connection did not end gets the cancel
/// as its end, thus the test fails and does not hang.
@Suite("ConnectionHookWaitTests")
struct ConnectionHookWaitTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with.
    private static let serverName = "connection-hook-wait-server"

    /// A count of `tools/list_changed` notifications that no server of this
    /// suite sends, thus only another event ends a wait for it.
    private static let unreachedGeneration = 1

    // MARK: - Helpers

    /// Starts `wait`, and returns once `server` recorded it, or once it
    /// ended — see ``EventRace/start(_:awaiting:cleaningUpOnThrow:)``.
    ///
    /// - Parameters:
    ///   - server: The server whose hook `wait` calls.
    ///   - wait: The call of one connection hook of `server`.
    /// - Returns: The task of `wait`.
    /// - Throws: When the task of the test is cancelled before the first
    ///   event.
    private static func startRecordedWait(
        on server: MCPServer, _ wait: @escaping @Sendable () async throws -> Void
    ) async throws -> Task<Void, any Error> {
        try await EventRace.start(
            wait, awaiting: { await server.waitUntilConnectionHookWaitIsRecorded() },
            cleaningUpOnThrow: EventRace.endWait)
    }

    /// Cancels `wait`, and records a failure unless it threw
    /// `ConnectionHookWaitError.connectionEnded` before the cancel.
    ///
    /// A hook ends a wait on a cancel with no error. Thus a wait that only the
    /// cancel ended returns, and the check fails.
    ///
    /// - Parameters:
    ///   - wait: The task of the wait.
    ///   - sourceLocation: The place in the test that the failure names.
    private static func expectEndedOnConnectionEnd(
        _ wait: Task<Void, any Error>, sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        wait.cancel()
        let result = await wait.result
        #expect(
            throws: ConnectionHookWaitError.connectionEnded, "the wait did not end on the end of the connection",
            sourceLocation: sourceLocation
        ) {
            try result.get()
        }
    }

    // MARK: - The transport drop wait

    @Test("a disconnect ends a wait for a transport drop")
    func aDisconnectEndsTheTransportDropWait() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(to: scripted, over: .inMemory, name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let wait = try await Self.startRecordedWait(on: server) {
                try await server.waitUntilTransportDropped()
            }

            await server.disconnect()

            await Self.expectEndedOnConnectionEnd(wait)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a new connect ends a wait for a transport drop")
    func aNewConnectEndsTheTransportDropWait() async throws {
        let respawning = RespawningTransport.makeServingFreshScriptedServers { ScriptedServer() }
        let server = MCPTestSupport.makeServer(name: Self.serverName)
        try await server.connect(via: respawning, backoffPolicy: .default)
        try await MCPTestSupport.withConnection(of: server) {
            let wait = try await Self.startRecordedWait(on: server) {
                try await server.waitUntilTransportDropped()
            }

            try await server.reconnect()

            await Self.expectEndedOnConnectionEnd(wait)
        }
    }

    // MARK: - The tool list generation wait

    @Test("a transport drop ends a wait for a count of tools/list_changed notifications")
    func aTransportDropEndsTheGenerationWait() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(to: scripted, over: .inMemory, name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let wait = try await Self.startRecordedWait(on: server) {
                try await server.waitUntilToolListChangedGeneration(reaches: Self.unreachedGeneration)
            }

            await scripted.dropTransport()
            // The drop is the event under test: the server reports it on a
            // task of its transport, after the drop above returned.
            try await server.waitUntilTransportDropped()

            await Self.expectEndedOnConnectionEnd(wait)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a disconnect ends a wait for a count of tools/list_changed notifications")
    func aDisconnectEndsTheGenerationWait() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(to: scripted, over: .inMemory, name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let wait = try await Self.startRecordedWait(on: server) {
                try await server.waitUntilToolListChangedGeneration(reaches: Self.unreachedGeneration)
            }

            await server.disconnect()

            await Self.expectEndedOnConnectionEnd(wait)
        }
        withExtendedLifetime(scripted) {}
    }
}
