import struct Foundation.Data
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Tests of `DropObservingTransport` — how the mirrored receive stream ENDS.
///
/// The message loop of `MCP.Client` is
/// `repeat { for try await data in await connection.receive() } while true`. It
/// leaves that loop when its task is cancelled, or when the stream ends with a
/// throw, which its `catch` breaks on. A stream that ends with no error sends
/// the loop straight back to `receive()`, which gives back that same ended
/// stream, and the loop then spins on one cooperative-pool thread for the life
/// of the process.
///
/// So every end of the mirror carries an error. The end of the wrapped stream
/// is one of two ends, and each case here reads one of them: a drop, which the
/// client did not ask for, and a disconnect this wrapper's own ``disconnect()``
/// caused. The teardown of the server can disconnect the wrapper while the loop
/// of the client still runs, thus the second end throws as well, and so does
/// each receive stream after that end.
///
/// What the report of a drop then does — `handleTransportDrop(generation:)` and
/// the `.lost` calls that follow — is read by `LostCallTests`.
///
/// Each test waits on an event and never on a time. No test checks the speed
/// of the machine (card `^tm4x2hp`).
@Suite("DropObservingTransport")
struct DropObservingTransportTests {

    // MARK: - Shared test constants

    /// How many drop reports a dropped transport gives.
    private static let oneDropReport = 1

    /// How many drop reports a transport the host disconnected gives.
    private static let noDropReports = 0

    // MARK: - Helpers

    /// Counts the drop reports of one `DropObservingTransport`.
    private actor DropReporter {
        /// How many reports arrived.
        private(set) var count = 0

        /// Records one report.
        func record() {
            count += 1
        }

        /// The report closure a `DropObservingTransport` is built with.
        nonisolated var onDrop: @Sendable () async -> Void {
            { await self.record() }
        }
    }

    /// A transport whose ``RespawningTransport/disconnect()`` scripts a drop:
    /// every connect starts a fresh `ScriptedServer` over an in-memory pair,
    /// and a disconnect of the client end ends that end's receive stream with
    /// no error of its own — the end this suite classifies.
    ///
    /// - Returns: The transport.
    private static func droppableTransport() -> RespawningTransport {
        RespawningTransport.makeServingFreshScriptedServers { ScriptedServer() }
    }

    /// Reads `stream` to its end and reports what ended it.
    ///
    /// - Parameter stream: The mirrored receive stream.
    /// - Returns: What the stream threw, or `nil` when it ended with no error.
    private static func endOf(
        _ stream: AsyncThrowingStream<Data, any Error>
    ) async -> (any Error)? {
        do {
            for try await _ in stream {}
            return nil
        } catch {
            return error
        }
    }

    // MARK: - A drop

    @Test("a drop ends the mirrored receive stream with connectionClosed, and reports the drop")
    func aDropEndsTheMirroredStreamWithAnError() async throws {
        let droppable = Self.droppableTransport()
        let reporter = DropReporter()
        let observed = DropObservingTransport(wrapping: droppable, onDrop: reporter.onDrop)
        try await observed.connect()
        let mirrored = await observed.receive()

        await droppable.disconnect()
        let thrown = await Self.endOf(mirrored)

        guard case .connectionClosed? = thrown as? MCPError else {
            Issue.record(
                "expected MCPError.connectionClosed, got \(String(describing: thrown)); an end with no error spins the message loop of MCP.Client"
            )
            return
        }
        #expect(await reporter.count == Self.oneDropReport)
    }

    // MARK: - A disconnect the host asked for

    /// The order is fixed, and each read ends: the wrapped in-memory stream
    /// ends when the wrapper disconnects, thus the mirror ends, and the
    /// second stream is taken only after that end.
    ///
    /// 1. The test takes the mirrored stream, and then disconnects the wrapper.
    /// 2. The test reads the mirror to its end. The end must throw.
    /// 3. The test takes a second receive stream, the one the message loop of
    ///    `MCP.Client` takes next, and reads it. Its end must throw too.
    ///
    /// An end with no error at step 2 or step 3 sends the loop of the client
    /// back to `receive()`, and the loop spins.
    @Test("a disconnect of this wrapper ends the mirror and each later receive stream with an error, and reports no drop")
    func aDisconnectEndsEachReceiveStreamWithAnError() async throws {
        let (clientEnd, serverEnd) = await InMemoryTransport.createConnectedPair()
        let reporter = DropReporter()
        let observed = DropObservingTransport(wrapping: clientEnd, onDrop: reporter.onDrop)
        try await observed.connect()
        let mirrored = await observed.receive()

        await observed.disconnect()

        await #expect(throws: DropObservingTransport.Disconnected.self) {
            for try await _ in mirrored {}
        }
        let later = await observed.receive()
        await #expect(throws: DropObservingTransport.Disconnected.self) {
            for try await _ in later {}
        }
        #expect(await reporter.count == Self.noDropReports)
        withExtendedLifetime(serverEnd) {}
    }

    // MARK: - Before any connect

    @Test("the receive stream of a wrapper that never connected ends with an error")
    func theStreamBeforeAnyConnectEndsWithAnError() async throws {
        let reporter = DropReporter()
        let observed = DropObservingTransport(
            wrapping: Self.droppableTransport(), onDrop: reporter.onDrop)

        let thrown = await Self.endOf(await observed.receive())

        guard case .connectionClosed? = thrown as? MCPError else {
            Issue.record(
                "expected MCPError.connectionClosed, got \(String(describing: thrown)); an end with no error spins the message loop of MCP.Client"
            )
            return
        }
    }
}
