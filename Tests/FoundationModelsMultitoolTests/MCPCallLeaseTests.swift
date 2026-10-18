import Foundation
import FoundationModels
import FoundationModelsExtras
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// An MCP call holds an `.mcpCall` lease in the `WorkRegistry` of the session
/// of the call while the request is in flight, also when it ends with an
/// error or a cancel. While the server waits only for the answer of the user,
/// the lease is suspended, thus the session has no work.
@Suite("MCPCallLeaseTests", .serialized)
struct MCPCallLeaseTests {
    /// The name of the scripted MCP server.
    private static let serverName = "leases"

    /// The name of the held MCP tool.
    private static let heldToolName = "holdOpen"

    /// The name of a tool that the MCP server does not serve.
    private static let unknownToolName = "notServed"

    // MARK: - MCP calls

    @Test("an MCP call holds an mcpCall lease while it is in flight")
    func anMCPCallHoldsALeaseWhileInFlight() async throws {
        let session = LeasedSession()
        let held = HeldScriptedTool(named: Self.heldToolName)
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(
            serving: [held.scriptedTool], name: Self.serverName)
        let context = session.context
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({ await held.release() }) {
                let call = try await EventRace.watch(
                    {
                        try await ToolContext.$current.withValue(context) {
                            try await server.call(name: Self.heldToolName)
                        }
                    }, untilArrivalAt: held, orFail: "the call ended before it arrived at the server")

                #expect(session.openKinds == [.mcpCall])

                await held.release()
                _ = try await call.task.value
                #expect(session.registry.openWork.isEmpty)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("an MCP call that the server answers with an error ends its lease")
    func anMCPCallThatFailsEndsItsLease() async throws {
        let session = LeasedSession()
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(serving: [], name: Self.serverName)
        let context = session.context
        let recorder = WorkTransitionsRecorder(session.registry)
        try await MCPTestSupport.withConnection(of: server) {
            _ = await #expect(throws: (any Error).self) {
                try await ToolContext.$current.withValue(context) {
                    _ = try await server.call(name: Self.unknownToolName)
                }
            }
        }
        #expect(session.registry.openWork.isEmpty)
        #expect(await recorder.close() == [.workStarted, .noWork])
        withExtendedLifetime(scripted) {}
    }

    @Test("a cancel of an MCP call ends its lease")
    func aCancelOfAnMCPCallEndsItsLease() async throws {
        let session = LeasedSession()
        let held = HeldScriptedTool(named: Self.heldToolName)
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(
            serving: [held.scriptedTool], name: Self.serverName)
        let context = session.context
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({ await held.release() }) {
                let call = try await EventRace.watch(
                    {
                        try await ToolContext.$current.withValue(context) {
                            try await server.call(name: Self.heldToolName)
                        }
                    }, untilArrivalAt: held, orFail: "the call ended before it arrived at the server")
                #expect(session.openKinds == [.mcpCall])

                call.task.cancel()
                _ = await call.task.result

                #expect(session.registry.openWork.isEmpty)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("an MCP call that waits only for the user is not work, and is work again after the answer")
    func anMCPCallThatWaitsForTheUserIsSuspended() async throws {
        let session = LeasedSession()
        let (scripted, server) = try await MCPTestSupport.connectedLoopbackMCPServer(
            over: .inMemory, name: Self.serverName)
        let context = session.context
        let sink = session.sink.recording
        try await MCPTestSupport.withConnection(of: server) {
            let call = try await EventRace.start(
                {
                    try await ToolContext.$current.withValue(context) {
                        try await server.call(name: ScriptedServer.elicitEchoToolName)
                    }
                }, awaiting: { await sink.waitUntilEvent { $0.kind == .elicitation } })
            let request = try #require(
                await sink.events.first { $0.kind == .elicitation }?.elicitation,
                "the call ended before the question came")

            #expect(!session.registry.hasWork)
            let recorder = WorkTransitionsRecorder(session.registry)

            _ = await session.runPlane.respond(
                elicitationId: request.elicitationId,
                .accept(content: [ScriptedServer.elicitEchoAnswerField: .string("42")]))
            _ = try await call.value

            #expect(await recorder.close() == [.workStarted, .noWork])
        }
        withExtendedLifetime(scripted) {}
    }

}
