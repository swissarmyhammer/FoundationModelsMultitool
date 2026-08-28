import struct Foundation.Data
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

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
/// So the end of the wrapped stream is one of two ends, and each case here
/// reads one of them: a drop, which the client did not ask for and must end the
/// mirror with an error, and a disconnect this wrapper's own ``disconnect()``
/// caused, which needs no error because `MCP.Client.disconnect()` cancels its
/// message loop first.
///
/// What the report of a drop then does — `handleTransportDrop(generation:)` and
/// the `.lost` calls that follow — is read by `LostCallTests`.
@Suite("DropObservingTransport", .timeLimit(.minutes(1)))
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

    @Test("a disconnect of this wrapper ends the mirrored receive stream with no error, and reports no drop")
    func aDisconnectEndsTheMirroredStreamWithNoError() async throws {
        let droppable = Self.droppableTransport()
        let reporter = DropReporter()
        let observed = DropObservingTransport(wrapping: droppable, onDrop: reporter.onDrop)
        try await observed.connect()
        let mirrored = await observed.receive()

        await observed.disconnect()
        let thrown = await Self.endOf(mirrored)

        #expect(thrown == nil, "the host asked for this end, thus it is not a fault: \(String(describing: thrown))")
        #expect(await reporter.count == Self.noDropReports)
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
