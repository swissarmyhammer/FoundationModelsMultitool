import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// A notice of a snippet (`notify()` or `progress()`) holds a
/// `.noticeDelivery` lease in the `WorkRegistry` of the session of the
/// `runCode` call, until the notice reached the sink of the session.
@Suite("NoticeLeaseTests")
struct NoticeLeaseTests {
    /// The detail of the notice of the notice snippet.
    private static let noticeDetail = "lease notice"

    // MARK: - Notices

    @Test("a notice that waits for its delivery holds a noticeDelivery lease until it is delivered")
    func aNoticeHoldsALeaseUntilItIsDelivered() async throws {
        let delivery = TestGate()
        let session = LeasedSession(holdingProgress: delivery)
        let multiTool = MultiTool(registry: try MultiTool.Builder().buildRegistry())
        let context = session.context
        let sink = session.sink.recording

        let call = try await EventRace.watch(
            {
                try await ToolContext.$current.withValue(context) {
                    try await multiTool.call(
                        arguments: RunCodeArguments(code: "notify(\"\(Self.noticeDetail)\"); return 1;"))
                }
            }, awaiting: { await sink.waitUntilEvent { $0.detail == Self.noticeDetail } },
            requiring: { session.registry.hasWork }, orFail: "the notice holds no lease")

        #expect(session.openKinds == [.noticeDelivery])
        #expect(session.registry.openWork.first?.id == context.completionToken)

        delivery.open()
        _ = try await call.task.value
        #expect(session.registry.openWork.isEmpty)
    }

    @Test("a notice that waits for its delivery is not work after the registry closed")
    func aNoticeIsNotWorkAfterTheRegistryClosed() async throws {
        let delivery = TestGate()
        let session = LeasedSession(holdingProgress: delivery)
        let multiTool = MultiTool(registry: try MultiTool.Builder().buildRegistry())
        let context = session.context
        let sink = session.sink.recording

        let call = try await EventRace.watch(
            {
                try await ToolContext.$current.withValue(context) {
                    try await multiTool.call(
                        arguments: RunCodeArguments(code: "notify(\"\(Self.noticeDetail)\"); return 1;"))
                }
            }, awaiting: { await sink.waitUntilEvent { $0.detail == Self.noticeDetail } },
            requiring: { session.registry.hasWork }, orFail: "the notice holds no lease")

        session.registry.close()
        #expect(!session.registry.hasWork)

        delivery.open()
        _ = try await call.task.value
    }

}
