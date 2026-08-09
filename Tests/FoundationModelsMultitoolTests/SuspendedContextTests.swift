import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Phase-1 coverage for the `runCode` envelope's two clocks.
///
/// The suspended JSC contexts those clocks govern are eventplan.md § "The
/// constraint boundary, and the escape hatch".
///
/// A `runCode` call that outlives its wait window hands back a pending envelope
/// and keeps running: the pending items are the promise the snippet is awaiting
/// *and* the suspended JSC context holding it. Everything here is about that
/// state — that the interpreter's own watchdog does not kill the context at the
/// instant the run elevates, that the run settles into exactly one terminal
/// event when its inner call finally returns, that too many live contexts is a
/// repairable error rather than a pile-up, and that `cancel()` genuinely tears
/// one down.
///
/// Every test mounts `MultiTool` exactly as Router's native session does —
/// `ToolElevation.wrapping` with an elevating configuration — so what is
/// exercised is the real composition, not a stand-in for it.
@Suite("SuspendedContext")
struct SuspendedContextTests {
    // MARK: - Clocks

    @Test("the stock work clock outlives the stock wait clock, so a run never meets the watchdog at the instant it elevates")
    func stockWorkClockOutlivesStockWaitClock() throws {
        let multiTool = MultiTool(registry: try Self.registry(exposing: GatedTool(latch: ToolReleaseLatch())))

        let clocks = Self.clocks(of: multiTool)

        // The regression this test exists for: `MultiToolConfiguration
        // .executionTimeLimit` and `ElevationConfiguration.defaultWaitSeconds`
        // were both 5 seconds, so the JSC watchdog force-terminated the
        // suspended context at exactly the moment elevation parked it.
        let timeout = try #require(clocks.timeout)
        #expect(timeout > ElevationConfiguration.defaultWaitSeconds)
        #expect(timeout == MultiToolConfiguration.default.executionTimeLimit)
        // No `waitSeconds` in the envelope leaves the wait clock to the mount.
        #expect(clocks.waitSeconds == nil)
    }

    @Test("the envelope's timeout is clamped to the configured ceiling, and an absent one defaults to it")
    func perCallTimeoutIsBoundedByTheConfiguredCeiling() throws {
        let ceiling: TimeInterval = 30
        let underCeiling: TimeInterval = 5
        let multiTool = MultiTool(
            registry: try Self.registry(exposing: GatedTool(latch: ToolReleaseLatch())),
            configuration: MultiToolConfiguration(executionTimeLimit: ceiling)
        )

        #expect(Self.clocks(of: multiTool, timeout: underCeiling).timeout == underCeiling)
        #expect(Self.clocks(of: multiTool, timeout: ceiling * 2).timeout == ceiling)
        #expect(Self.clocks(of: multiTool, timeout: -1).timeout == 0)
        #expect(Self.clocks(of: multiTool).timeout == ceiling)
    }

    @Test("waitSeconds crosses the envelope untouched, including the immediate-detach zero")
    func waitSecondsCrossesTheEnvelopeUntouched() throws {
        let multiTool = MultiTool(registry: try Self.registry(exposing: GatedTool(latch: ToolReleaseLatch())))

        #expect(Self.clocks(of: multiTool, waitSeconds: 0).waitSeconds == 0)
        #expect(Self.clocks(of: multiTool, waitSeconds: Self.shortWaitSeconds).waitSeconds == Self.shortWaitSeconds)
    }

    // MARK: - The suspended context stays alive past waitSeconds

    @Test("a snippet that elevates at waitSeconds is still alive at 3x waitSeconds, and still settles with its real result")
    func elevatedSnippetStaysAliveWellPastItsWaitWindow() async throws {
        let harness = try Self.makeHarness()

        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet, waitSeconds: Self.shortWaitSeconds)
        )
        let token = try Self.completionToken(of: rendered)
        try await Task.sleep(nanoseconds: Self.aliveWindowNanoseconds)

        // Alive: the mailbox still holds the parked run, and the promise the
        // snippet is awaiting has not been torn down under it.
        let parked = await harness.mailbox.status()
        #expect(parked.contains { $0.completionToken == token })
        #expect(!harness.gated.wasCancelled)

        // Resumable: releasing the inner call still produces the snippet's own
        // value, long after the wait window closed.
        harness.latch.release()
        let terminal = try await Self.settledTerminal(of: token, in: harness.mailbox)
        #expect(terminal.detail == Self.renderedGatedResult)
        #expect(terminal.outcome == .succeeded)
    }

    // MARK: - Outer elevation composes

    @Test("a snippet that elevates while its inner call is in flight settles into exactly one terminal event carrying its result")
    func elevatedSnippetSettlesIntoExactlyOneTerminalEvent() async throws {
        let harness = try Self.makeHarness()

        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet, waitSeconds: Self.shortWaitSeconds)
        )

        #expect(PendingRunEnvelope.isRendered(rendered))
        // The envelope came back while the inner fixture call was still
        // running — the pending promise, not a finished one.
        #expect(harness.gated.hasStarted)
        #expect(!harness.gated.wasCancelled)

        let token = try Self.completionToken(of: rendered)
        harness.latch.release()
        let terminal = try await Self.settledTerminal(of: token, in: harness.mailbox)

        #expect(terminal.detail == Self.renderedGatedResult)
        let completions = await harness.sink.events.filter { $0.kind == .completed }
        #expect(completions.count == 1)
        #expect(completions.first?.correlationID == token)
        #expect(completions.first?.detail == Self.renderedGatedResult)
    }

    @Test("waitSeconds: 0 in the envelope detaches the run immediately, whatever the mount's own wait clock says")
    func zeroWaitSecondsDetachesImmediately() async throws {
        let harness = try Self.makeHarness(waitSeconds: Self.generousWaitSeconds)

        let start = ContinuousClock.now
        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet, waitSeconds: 0)
        )
        let elapsed = start.duration(to: .now)

        #expect(PendingRunEnvelope.isRendered(rendered))
        // Far below the mount's own generous wait window: only the envelope's
        // own zero, read through `ElevationParameterProviding`, detaches here.
        #expect(elapsed < Self.promptResponseBound)

        harness.latch.release()
        _ = try await Self.settledTerminal(
            of: try Self.completionToken(of: rendered), in: harness.mailbox
        )
    }

    // MARK: - The cap on live contexts

    @Test("a run beyond the live-context cap is a repairable in-band error, not a crash")
    func exceedingTheLiveContextCapIsARepairableError() async throws {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let multiTool = MultiTool(
            registry: try Self.registry(exposing: gated),
            configuration: MultiToolConfiguration(liveContextLimit: 1)
        )
        let parked = Task { try await multiTool.call(arguments: RunCodeArguments(code: Self.gatedSnippet)) }
        try await Self.waitUntil { gated.hasStarted }

        let refused = try await multiTool.call(arguments: RunCodeArguments(code: "return 1 + 1;"))

        #expect(refused.contains("Too many runCode snippets are running at once"))
        #expect(refused.contains(RepairDirective.repairSnippet.closingLine))
        latch.release()
        #expect(try await parked.value == Self.renderedGatedResult)
    }

    // MARK: - The hard unblock

    @Test("cancel(completionToken) on a suspended snippet tears its context down within the time limit")
    func cancellingASuspendedRunTearsDownItsContext() async throws {
        let harness = try Self.makeHarness()
        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet, waitSeconds: Self.shortWaitSeconds)
        )
        let token = try Self.completionToken(of: rendered)

        // A second snippet, in the same session and through the same mounted
        // tool, cancels the first through the sandbox's own `cancel()` global.
        let cancelOutput = try await harness.mounted.call(
            arguments: RunCodeArguments(code: "return await cancel(\"\(token)\");")
        )
        #expect(cancelOutput.contains("\"state\":\"reported\""))

        let start = ContinuousClock.now
        let terminal = try await Self.settledTerminal(of: token, in: harness.mailbox)
        #expect(start.duration(to: .now) < Self.promptResponseBound)
        #expect(terminal.outcome == .cancelled)
        // The pending promise's own work was torn down with the context —
        // nothing released the gate. `wasCancelled` is written by the tool's
        // own task as it unwinds, and the terminal event above can be observed
        // before that write lands, so wait for it the way ``waitUntil(_:)``
        // exists to — sampling it here is a race, not a check.
        try await Self.waitUntil { harness.gated.wasCancelled }
        #expect(!harness.latch.isReleased)
        let parked = await harness.mailbox.status()
        #expect(parked.isEmpty)
    }

    // MARK: - Fixtures

    /// The soft deadline every elevating test detaches at.
    ///
    /// Also the unit each test's "still alive well past it" assertion is
    /// measured in.
    private static let shortWaitSeconds: TimeInterval = 0.2

    /// A wait window no test could ever sit through.
    ///
    /// Only a per-call `waitSeconds` can detach a call mounted with this one.
    private static let generousWaitSeconds: TimeInterval = 30

    /// How long past its wait window a suspended run must still be alive.
    ///
    /// Three wait windows, per the card's regression bound.
    private static let aliveWindowNanoseconds = UInt64(shortWaitSeconds * 3 * 1_000_000_000)

    /// The bound every "this happened promptly" assertion uses.
    ///
    /// Generous against scheduling jitter, and far below the clock it proves
    /// was not the one enforced.
    private static let promptResponseBound: Duration = .seconds(3)

    /// How often ``waitUntil(_:)`` re-reads its condition.
    private static let readinessPollIntervalNanoseconds: UInt64 = 5_000_000

    /// How long ``waitUntil(_:)`` keeps polling before recording a failure.
    private static let readinessDeadlineSeconds: TimeInterval = 10

    /// The snippet every suspended-context test runs.
    ///
    /// One awaited `tools.*` call that cannot return until the test releases
    /// it.
    private static let gatedSnippet = "return await tools.gated();"

    /// What `ResultRenderer` makes of `GatedTool`'s returned value.
    ///
    /// The text a settled run's terminal event carries.
    private static let renderedGatedResult = "\"\(gatedToolResult)\""

    /// Thrown by a fixture whose own setup or synchronization failed.
    ///
    /// Always thrown after the fixture has already recorded the `Issue`
    /// explaining what went wrong.
    private struct FixtureError: Error, Equatable {}

    /// One `runCode` tool mounted the way Router's native session mounts it.
    ///
    /// Carries the gated tool its snippets call, and the session plane its runs
    /// park and post on.
    private struct Harness {
        /// The gated tool `gatedSnippet` calls.
        let gated: GatedTool

        /// The latch that releases `gated`.
        let latch: ToolReleaseLatch

        /// `MultiTool` wrapped in the elevation engine.
        let mounted: any Tool<RunCodeArguments, String>

        /// The session mailbox elevated runs park in.
        let mailbox: SessionMailbox

        /// The session's upstream sink.
        let sink: RecordingEventSink
    }

    /// A registry exposing one gated tool as `tools.gated`.
    ///
    /// - Parameter gated: the tool to expose.
    /// - Returns: the registry.
    private static func registry(exposing gated: GatedTool) throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(gated).buildRegistry()
    }

    /// Mounts a `runCode` tool over one gated tool.
    ///
    /// The mount is exactly the one Router's native session builds.
    ///
    /// - Parameters:
    ///   - configuration: the `MultiTool` knobs under test. Defaults to
    ///     `.default`, so what the tests prove holds at stock settings.
    ///   - waitSeconds: the mount's own wait clock, overridden per call by any
    ///     `waitSeconds` in the envelope.
    /// - Returns: the harness.
    private static func makeHarness(
        configuration: MultiToolConfiguration = .default,
        waitSeconds: TimeInterval = ElevationConfiguration.defaultWaitSeconds
    ) throws -> Harness {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let multiTool = MultiTool(
            registry: try Self.registry(exposing: gated),
            configuration: configuration
        )
        let mailbox = SessionMailbox()
        let sink = RecordingEventSink()
        let mounted = ToolElevation.wrapping(
            multiTool,
            sessionID: ULID(),
            mailbox: mailbox,
            sink: sink,
            configuration: ElevationConfiguration(mode: .elevating, waitSeconds: waitSeconds)
        )
        return Harness(
            gated: gated,
            latch: latch,
            mounted: try #require(mounted as? any Tool<RunCodeArguments, String>),
            mailbox: mailbox,
            sink: sink
        )
    }

    /// The clocks `multiTool` reports for an envelope requesting these ones.
    ///
    /// The round trip through `GeneratedContent` the elevation engine itself
    /// makes.
    ///
    /// - Parameters:
    ///   - multiTool: the tool reading the envelope.
    ///   - waitSeconds: the envelope's own `waitSeconds`, or `nil` for a call
    ///     that supplies none.
    ///   - timeout: the envelope's own `timeout`, or `nil` for a call that
    ///     supplies none.
    /// - Returns: the clocks the elevation engine would use.
    private static func clocks(
        of multiTool: MultiTool,
        waitSeconds: TimeInterval? = nil,
        timeout: TimeInterval? = nil
    ) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) {
        multiTool.elevationClocks(
            from: RunCodeArguments(code: "return 1;", waitSeconds: waitSeconds, timeout: timeout).generatedContent
        )
    }

    /// The completion token of a rendered pending envelope.
    ///
    /// - Parameter rendered: the tool output an elevated call handed back.
    /// - Returns: the parked run's completion token.
    private static func completionToken(of rendered: String) throws -> String {
        try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8)).completionToken
    }

    /// Awaits a parked run's settlement through the mailbox.
    ///
    /// - Parameters:
    ///   - completionToken: the parked run's token.
    ///   - mailbox: the session mailbox the run parked in.
    /// - Returns: the run's terminal event.
    private static func settledTerminal(
        of completionToken: String, in mailbox: SessionMailbox
    ) async throws -> OperationEvent {
        let settlement = await mailbox.wait(
            completionToken: completionToken, seconds: scriptedRunSettlementSeconds
        )
        guard case .settled(let terminal) = settlement else {
            Issue.record("run \(completionToken) did not settle: \(settlement)")
            throw FixtureError()
        }
        return terminal
    }

    /// Polls `condition` until it holds.
    ///
    /// A synchronization point, not a timing assertion, so the deadline only
    /// bounds a genuine hang.
    ///
    /// - Parameter condition: the state a test is waiting to observe.
    private static func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(readinessDeadlineSeconds)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("condition never held within \(readinessDeadlineSeconds)s")
                throw FixtureError()
            }
            try await Task.sleep(nanoseconds: readinessPollIntervalNanoseconds)
        }
    }
}
