import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// How long the slow fixture tool sleeps before returning — long enough that
/// a mount which handed back a handle at once would have answered long before
/// the real value arrived.
private let innerCallDelayNanoseconds: UInt64 = 200_000_000

/// Phase-1 coverage for `RunBinding` — eventplan.md § "Async JavaScript"
/// ("Session affinity across the seam"), § "Background tools and the completion
/// token" (the code-mode mount: the background off), and § "The constraint
/// boundary, and the escape hatch" (inner calls never go to the background).
///
/// The JS thread is not a Swift task: a JSC callback lands outside every task
/// tree, so nothing on the `tools.*` route may rely on task-local
/// inheritance. Every test here drives a real `runCode` snippet (or the
/// binding's own mount) under an ambient `ToolContext` a session controls, and
/// asserts what the inner calls actually saw.
@Suite("RunBinding")
struct RunBindingTests {
    // MARK: - The code-mode mount: run to completion

    @Test("the inner-call mount runs to completion, so a snippet never receives a handle in place of a value")
    func theInnerCallMountRunsToCompletion() {
        #expect(RunBinding.innerCallMount.mode == .runToCompletion)
        #expect(RunBinding.innerCallMount.timeout == ToolMount.defaultTimeoutSeconds)
    }

    @Test("a slow inner call still returns its real value, and never goes to the background")
    func slowInnerCallReturnsItsRealValueWithoutBackgrounding() async throws {
        let slowTool = WindowRecordingTool(name: "slow", delayNanoseconds: innerCallDelayNanoseconds)
        let mailbox = SessionMailbox()
        let sink = RecordingEventSink()
        let binding = RunBinding(context: makeOuterRunContext(mailbox: mailbox, sink: sink))

        let output = try await binding.invoke(slowTool, arguments: NoArguments(unused: nil))

        #expect(output == "slow-result")
        #expect(!PendingRunEnvelope.isRendered(text: output))
        #expect(await backgroundRuns(over: mailbox).backgroundRuns().isEmpty)
    }

    // MARK: - Parallel inner calls correlate independently

    @Test("two parallel inner calls under Promise.all carry distinct completion tokens and post to the same session")
    func parallelInnerCallsCorrelateIndependently() async throws {
        let alpha = AmbientRecordingTool(name: "alpha")
        let beta = AmbientRecordingTool(name: "beta")
        let registry = try MultiTool.Builder()
            .addTool(alpha)
            .addTool(beta)
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

        let output = try await ToolContext.$current.withValue(context) {
            try await multiTool.call(
                arguments: RunCodeArguments(code: "return await Promise.all([tools.alpha(), tools.beta()]);")
            )
        }

        #expect(output == "[\"alpha-result\",\"beta-result\"]")
        let observations = alpha.observations + beta.observations
        #expect(observations.count == 2)
        #expect(Set(observations.compactMap(\.completionToken)).count == 2)
        #expect(observations.allSatisfy { $0.completionToken != context.completionToken })
        #expect(observations.allSatisfy { $0.sessionID == context.sessionID })
        #expect(Set(await sink.details(ofKind: .progress)) == ["alpha ran", "beta ran"])
    }

    // MARK: - Binding capture, not inheritance

    @Test("two MultiTool instances over one registry never cross-route their runs' events")
    func concurrentInstancesOverOneRegistryNeverCrossRoute() async throws {
        let shared = AmbientRecordingTool(name: "shared")
        let registry = try MultiTool.Builder().addTool(shared).buildRegistry()
        let firstSink = RecordingEventSink()
        let secondSink = RecordingEventSink()
        let firstContext = makeOuterRunContext(mailbox: SessionMailbox(), sink: firstSink)
        let secondContext = makeOuterRunContext(mailbox: SessionMailbox(), sink: secondSink)
        let code = "return await tools.shared();"
        let first = MultiTool(registry: registry)
        let second = MultiTool(registry: registry)

        async let firstOutput = ToolContext.$current.withValue(firstContext) {
            try await first.call(arguments: RunCodeArguments(code: code))
        }
        async let secondOutput = ToolContext.$current.withValue(secondContext) {
            try await second.call(arguments: RunCodeArguments(code: code))
        }
        _ = try await (firstOutput, secondOutput)

        for (sink, context) in [(firstSink, firstContext), (secondSink, secondContext)] {
            let events = await sink.events
            #expect(!events.isEmpty)
            #expect(events.allSatisfy { $0.correlationID == context.completionToken })
        }
        #expect(
            Set(shared.observations.compactMap(\.sessionID)) == [firstContext.sessionID, secondContext.sessionID]
        )
    }

    // MARK: - Explicit re-bind across the JS seam

    @Test("a tools.* call re-binds the ambient context explicitly, and work that inherits no task-locals inside it sees none")
    func innerCallRebindsTheAmbientContextExplicitly() async throws {
        let recorder = AmbientRecordingTool(name: "recorder")
        let registry = try MultiTool.Builder().addTool(recorder).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        _ = try await ToolContext.$current.withValue(context) {
            try await multiTool.call(arguments: RunCodeArguments(code: "return await tools.recorder();"))
        }

        let observation = try #require(recorder.observations.first)
        #expect(observation.completionToken != nil)
        #expect(observation.completionToken != context.completionToken)
        #expect(observation.sessionID == context.sessionID)
        #expect(observation.uninheritedContextWasNil)
    }
}
