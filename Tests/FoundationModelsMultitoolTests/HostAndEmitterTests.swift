import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// The wait window the elevating mount here detaches at.
///
/// Short enough that the gated inner call is still in flight when the outer
/// `runCode` run parks, which is the state the test is about.
private let hostWaitSeconds: TimeInterval = 0.2

/// The progress detail `AmbientRecordingTool(name: "recorder")` posts.
///
/// It goes out through whichever ambient context the tool ran under.
private let recorderProgressDetail = "recorder ran"

/// What `ResultRenderer` makes of that same tool's returned value.
private let renderedRecorderResult = "\"recorder-result\""

/// Phase-1 coverage for eventplan.md § "MultiTool is a host and an emitter".
///
/// `MultiTool` wires no emitter protocol, and it forks by identity.
///
/// The emitter half is the ambient route. A registered tool posts through
/// `ToolContext.current` and the event arrives at whichever sink the host bound
/// around `runCode` — no conformance cast, no registry wiring, no second tool
/// protocol. `RunBindingTests` already pins that route for a run that never
/// leaves its wait window; what is pinned here is the harder case, an
/// **elevated** run, where the outer call has already handed back its pending
/// envelope and the inner tool posts from the detached remainder.
///
/// The host half is `ForkableTool`, and what is pinned there is the discovery
/// shape, not fork semantics. `MultiTool` takes the protocol's blanket identity
/// `forked()` (see `MultiTool+Forking.swift` for why), so the value handed back
/// is the original and no assertion can tell the two apart. What can still
/// regress is the casting a host does to reach that value: the conformance
/// staying visible off an `any Tool` existential, and the erased `forked()`
/// return still downcasting to the `runCode` tool type a host mounts and runs.
@Suite("HostAndEmitter")
struct HostAndEmitterTests {
    // MARK: - The emitter half: events from an elevated run

    @Test("an inner tool's own event reaches the session sink after its runCode run has elevated")
    func innerToolEventsReachTheSessionSinkAfterTheRunElevates() async throws {
        let latch = ToolReleaseLatch()
        let recorder = AmbientRecordingTool(name: "recorder")
        let registry = try MultiTool.Builder()
            .addTool(GatedTool(latch: latch))
            .addTool(recorder)
            .buildRegistry()
        let mailbox = SessionMailbox()
        let sink = RecordingEventSink()
        let sessionID = ULID()
        let mounted = try #require(
            ToolDetachment.wrapping(
                MultiTool(registry: registry),
                sessionID: sessionID,
                mailbox: mailbox,
                sink: sink,
                configuration: DetachConfiguration(mode: .detaching, waitSeconds: hostWaitSeconds)
            ) as? any Tool<RunCodeArguments, String>
        )

        let rendered = try await mounted.call(
            arguments: RunCodeArguments(code: "await tools.gated(); return await tools.recorder();")
        )

        // The run parked with its snippet still inside the gated call, so the
        // recorder has not run yet and nothing of its own is on the sink.
        #expect(PendingRunEnvelope.isRendered(rendered))
        let beforeRelease = await sink.details(ofKind: .progress)
        #expect(!beforeRelease.contains(recorderProgressDetail))

        let token = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8)).completionToken
        latch.release()
        let settlement = await mailbox.wait(completionToken: token, seconds: scriptedRunSettlementSeconds)
        guard case .settled(let terminal) = settlement else {
            Issue.record("the elevated run never settled: \(settlement)")
            return
        }

        #expect(terminal.detail == renderedRecorderResult)
        // Posted after the envelope was already handed back, and still routed
        // to the one sink the host bound — on the outer run's correlation,
        // because `ToolContext.post` re-stamps what it forwards.
        let events = await sink.events
        let recorderEvent = try #require(events.first { $0.detail == recorderProgressDetail })
        #expect(recorderEvent.correlationID == token)
        // No wiring and no cast reached the tool: it read the context the
        // engine bound, which carries the host's session and its own token.
        let observation = try #require(recorder.observations.first)
        #expect(observation.sessionID == sessionID)
        #expect(observation.completionToken != token)
    }

    // MARK: - The host half: the ForkableTool discovery shape

    @Test("runCode casts to ForkableTool off an any Tool existential, and the erased forked() return downcasts and serves the registry")
    func runCodeCastsToForkableToolAndTheErasedForkDowncastsAndServesTheRegistry() async throws {
        let recorder = AmbientRecordingTool(name: "recorder")
        let registry = try MultiTool.Builder().addTool(recorder).buildRegistry()
        // Exactly how a host derives a child session's instance: a conformance
        // cast against the `any Tool` existential — the shape `ForkableTool`
        // declares no associated types to support — and then `forked()`. The
        // blanket `forked()` is identity, so `forked` IS `registered`; what the
        // assertions below can see is that both casts hold and that the value
        // they yield still runs the registry under the ambient context.
        let registered: any Tool = MultiTool(registry: registry)
        let forkable = try #require(registered as? any ForkableTool)
        let forked = try #require(forkable.forked() as? any Tool<RunCodeArguments, String>)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

        let output = try await ToolContext.$current.withValue(context) {
            try await forked.call(arguments: RunCodeArguments(code: "return await tools.recorder();"))
        }

        #expect(output == renderedRecorderResult)
        #expect(await sink.details(ofKind: .progress) == [recorderProgressDetail])
        #expect(recorder.observations.first?.sessionID == context.sessionID)
    }
}
