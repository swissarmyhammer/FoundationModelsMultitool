import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// An inner `tools.*` call that outlives the code of its snippet holds an
/// `.innerCall` lease in the `WorkRegistry` of the session of the `runCode`
/// call, until the inner call ends. An inner call that the snippet awaited
/// holds no lease, and a background `runCode` run holds only the
/// `.backgroundRun` lease of the run plane.
@Suite("InnerCallLeaseTests")
struct InnerCallLeaseTests {
    // MARK: - Inner calls

    @Test("an inner call that outlives its snippet holds an innerCall lease until it ends")
    func anUnawaitedInnerCallHoldsALeaseUntilItEnds() async throws {
        let session = LeasedSession()
        let delayed = DelayedTool()
        let snippetEnded = TestGate()
        let multiTool = MultiTool(
            registry: try MultiTool.Builder().addTool(delayed).buildRegistry(),
            interpreter: SnippetEndSignalingInterpreter(opening: snippetEnded))
        let context = session.context

        let call = try await EventRace.watch(
            {
                try await ToolContext.$current.withValue(context) {
                    try await multiTool.call(arguments: RunCodeArguments(code: "tools.delayed(); return \"done\";"))
                }
            }, untilOpen: snippetEnded, orFail: "the run ended before its snippet code ended")

        #expect(session.openKinds == [.innerCall])
        #expect(session.registry.openWork.first?.id.hasSuffix("tools.delayed") == true)

        delayed.hold.release.open()
        _ = try await call.task.value
        #expect(session.registry.openWork.isEmpty)
    }

    @Test("an awaited inner call holds no lease")
    func anAwaitedInnerCallHoldsNoLease() async throws {
        let session = LeasedSession()
        let delayed = DelayedTool()
        let multiTool = MultiTool(registry: try MultiTool.Builder().addTool(delayed).buildRegistry())
        let context = session.context
        let recorder = WorkTransitionsRecorder(session.registry)

        _ = try await delayed.hold.releaseOnArrival {
            try await ToolContext.$current.withValue(context) {
                try await multiTool.call(arguments: RunCodeArguments(code: "return await tools.delayed();"))
            }
        }

        #expect(await recorder.close().isEmpty)
    }

    @Test("a cancel of the run ends the lease of an inner call that outlives its snippet")
    func aCancelEndsTheLeaseOfAnUnawaitedInnerCall() async throws {
        let session = LeasedSession()
        let delayed = DelayedTool()
        let snippetEnded = TestGate()
        let multiTool = MultiTool(
            registry: try MultiTool.Builder().addTool(delayed).buildRegistry(),
            interpreter: SnippetEndSignalingInterpreter(opening: snippetEnded))
        let context = session.context

        let call = try await EventRace.watch(
            {
                try await ToolContext.$current.withValue(context) {
                    try await multiTool.call(arguments: RunCodeArguments(code: "tools.delayed(); return \"done\";"))
                }
            }, untilOpen: snippetEnded, orFail: "the run ended before its snippet code ended")

        #expect(session.openKinds == [.innerCall])

        call.task.cancel()
        _ = await call.task.result

        await session.registry.awaitNoWork()
        #expect(session.registry.openWork.isEmpty)
    }

    // MARK: - runCode

    @Test("a background runCode run holds only the backgroundRun lease of the run plane")
    func aBackgroundRunCodeRunHoldsOneLease() async throws {
        let session = LeasedSession()
        let delayed = DelayedTool()
        let multiTool = MultiTool(
            registry: try MultiTool.Builder().addTool(delayed).buildRegistry(),
            configuration: MultiToolConfiguration(inlineSettleGrace: 0))
        let engine = SessionMount.synchronous(multiTool, on: session.context)
        let typed = try #require(engine as? any FoundationModels.Tool<RunCodeArguments, String>)

        let output = try await typed.call(arguments: RunCodeArguments(code: "return await tools.delayed();"))
        try #require(PendingRunEnvelope.isRendered(text: output), "answer was: \(output)")
        let token = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(output.utf8)).completionToken
        try await EventRace.firstOf(
            { try? await delayed.hold.arrival.wait() },
            or: { await TerminalDetail.waitForEnd(of: token, in: session.context) })

        #expect(session.registry.openWork == [WorkItem(kind: .backgroundRun, id: token, sessionID: session.sessionID)])

        delayed.hold.release.open()
        _ = try await TerminalDetail.settledEvent(of: token, in: session.context)
        #expect(session.registry.openWork.isEmpty)
    }

}
