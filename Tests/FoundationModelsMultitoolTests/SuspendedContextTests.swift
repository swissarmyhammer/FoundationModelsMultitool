import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Phase-1 coverage for the `runCode` background mount and its work bound.
///
/// The suspended JSC contexts that mount governs are eventplan.md § "The
/// constraint boundary, and the escape hatch".
///
/// A mounted `runCode` call hands back a pending envelope at once and keeps
/// running: the pending items are the promise the snippet is awaiting *and*
/// the suspended JSC context holding it. Everything here is about that state —
/// that the interpreter's own watchdog does not kill the context at the instant
/// the call returns, that the run settles into exactly one terminal event when
/// its inner call finally returns, that too many live contexts is a repairable
/// error rather than a pile-up, and that `cancel()` genuinely tears one down.
///
/// Every test mounts `MultiTool` exactly as Router's native session does —
/// `ToolMounting.makeWrapped` under `synchronous` — so what is exercised
/// is the real composition, not a stand-in for it.
@Suite("SuspendedContext")
struct SuspendedContextTests {
    // MARK: - The declared mount and the work bound

    @Test("runCode declares the background mount, so no site can make it block")
    func runCodeDeclaresTheBackgroundMount() throws {
        let multiTool = MultiTool(registry: try Self.registry(exposing: GatedTool(latch: ToolReleaseLatch())))

        #expect(multiTool.mount == ToolMount(mode: .background, timeout: nil))
    }

    @Test("the work bound is the configured ceiling, and no call can raise or lower it")
    func theWorkBoundIsAlwaysTheConfiguredCeiling() throws {
        let ceiling: TimeInterval = 30
        let multiTool = MultiTool(
            registry: try Self.registry(exposing: GatedTool(latch: ToolReleaseLatch())),
            configuration: MultiToolConfiguration(executionTimeLimit: ceiling)
        )

        // `RunCodeArguments` carries no clock, so there is nothing to clamp:
        // the host's ceiling is the whole answer. A background snippet is
        // exactly what needs one, because nothing is blocking on it to notice
        // that it ran away.
        #expect(Self.workBound(of: multiTool) == ceiling)
        #expect(Self.workBound(of: MultiTool(registry: try Self.registry(exposing: GatedTool(latch: ToolReleaseLatch()))))
            == MultiToolConfiguration.default.executionTimeLimit)
    }

    @Test("every mounted runCode call answers the pending envelope at once, whatever mount the site applies")
    func everyMountedCallAnswersThePendingEnvelope() async throws {
        // The harshest site there is: run to completion under no clock. The
        // tool's own declaration wins over it.
        let harness = try await Self.makeHarness(mount: .synchronousUnbounded)

        let start = ContinuousClock.now
        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet)
        )
        let elapsed = start.duration(to: .now)

        #expect(PendingRunEnvelope.isRendered(text: rendered))
        #expect(elapsed < Self.promptResponseBound)

        harness.latch.release()
        _ = try await Self.settledTerminal(
            of: try Self.completionToken(of: rendered), on: harness.run.context
        )
    }

    // MARK: - The suspended context stays alive after the call returned

    @Test("a snippet whose call returned the envelope is still alive well after it, and still settles with its real result")
    func backgroundSnippetStaysAliveWellPastItsCall() async throws {
        let harness = try await Self.makeHarness()

        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet)
        )
        let token = try Self.completionToken(of: rendered)
        try await Task.sleep(nanoseconds: Self.aliveWindowNanoseconds)

        // Alive: the mailbox still holds the background run, and the promise
        // the snippet is awaiting has not been torn down under it.
        let backgrounded = await harness.run.context.backgroundRuns()
        #expect(backgrounded.contains { $0.completionToken == token })
        #expect(!harness.gated.wasCancelled)

        // Resumable: releasing the inner call still produces the snippet's own
        // value, long after the call returned.
        harness.latch.release()
        let terminal = try await Self.settledTerminal(of: token, on: harness.run.context)
        #expect(terminal.detail == Self.renderedGatedResult)
        #expect(terminal.outcome == .succeeded)
    }

    // MARK: - The background run composes

    @Test("a snippet whose inner call is in flight settles into exactly one terminal event carrying its result")
    func backgroundSnippetSettlesIntoExactlyOneTerminalEvent() async throws {
        let harness = try await Self.makeHarness()

        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet)
        )

        #expect(PendingRunEnvelope.isRendered(text: rendered))
        // The inner fixture call runs under the background run — the pending
        // promise, not a finished one. Awaited rather than read at the instant
        // the envelope returned: that instant races JSC start-up, which made a
        // true statement about the product fail whenever the machine was
        // loaded. The latch is still closed here, so the call starting at all
        // is what the assertion was always after.
        try await TestPoll.waitUntil("the gated call started") { harness.gated.hasStarted }
        #expect(!harness.gated.wasCancelled)

        let token = try Self.completionToken(of: rendered)
        // Subscribed BEFORE the latch releases the run; the stream is live and
        // has no replay.
        let collecting = Task {
            // By correlation, not by arrival position: the snippet's inner call
            // settles its own run too, and its terminal reaches the stream
            // first. This assertion is about the OUTER run.
            await settledEvents(on: harness.run.session, correlationID: token)
        }
        harness.latch.release()
        let terminal = try await Self.settledTerminal(of: token, on: harness.run.context)

        #expect(terminal.detail == Self.renderedGatedResult)
        // The terminal event is read off the session outbox rather than the
        // journal. `ToolContext.post` re-stamps what it forwards with the
        // mounting run's identity, so the outbox carries the OUTER run's
        // correlation; the journal keeps each run's own. This assertion is
        // about the re-stamped view.
        let completions = await collecting.value
        #expect(completions.count == 1)
        #expect(completions.first?.correlationID == token)
        #expect(completions.first?.detail == Self.renderedGatedResult)
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
        let held = Task { try await multiTool.call(arguments: RunCodeArguments(code: Self.gatedSnippet)) }
        try await TestPoll.waitUntil("the gated call started") { gated.hasStarted }

        let refused = try await multiTool.call(arguments: RunCodeArguments(code: "return 1 + 1;"))

        #expect(refused.contains("Too many runCode snippets are running at once"))
        #expect(refused.contains(RepairDirective.repairSnippet.closingLine))
        latch.release()
        #expect(try await held.value == Self.renderedGatedResult)
    }

    // MARK: - The hard unblock

    @Test("cancel(completionToken) on a suspended snippet tears its context down within the time limit")
    func cancellingASuspendedRunTearsDownItsContext() async throws {
        let harness = try await Self.makeHarness()
        let rendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: Self.gatedSnippet)
        )
        let token = try Self.completionToken(of: rendered)

        // A second snippet, in the same session and through the same mounted
        // tool, cancels the first through the sandbox's own `cancel()` global.
        //
        // That second snippet goes to the background as well — every mounted
        // `runCode` call does — so the call hands back its own token and its
        // answer is collected from the background run rather than read off the
        // call. The cancel still happens on its own run; only where its result
        // is read from changed.
        let cancelRendered = try await harness.mounted.call(
            arguments: RunCodeArguments(code: "return await cancel(\"\(token)\");")
        )
        let cancelTerminal = try await Self.settledTerminal(
            of: try Self.completionToken(of: cancelRendered), on: harness.run.context
        )
        #expect(cancelTerminal.detail.contains("\"result\":\"cancelled\""))

        let start = ContinuousClock.now
        let terminal = try await Self.settledTerminal(of: token, on: harness.run.context)
        #expect(start.duration(to: .now) < Self.promptResponseBound)
        #expect(terminal.outcome == .cancelled)
        // The pending promise's own work was torn down with the context —
        // nothing released the gate. `wasCancelled` is written by the tool's
        // own task as it unwinds, and the terminal event above can be observed
        // before that write lands, so wait for it the way
        // ``TestPoll.waitUntil(_:before:_:)`` exists to — sampling it here is a
        // race, not a check.
        try await TestPoll.waitUntil("the gated call unwound") { harness.gated.wasCancelled }
        #expect(!harness.latch.isReleased)
        let backgrounded = await harness.run.context.backgroundRuns()
        #expect(backgrounded.isEmpty)
    }

    // MARK: - Fixtures

    /// How long after its call returned a suspended run must still be alive.
    ///
    /// Long enough that a watchdog armed at the moment the call returned would
    /// have fired, and short enough that the suite stays fast.
    private static let aliveWindowNanoseconds: UInt64 = 600_000_000

    /// The bound every "this happened promptly" assertion uses.
    ///
    /// Generous against scheduling jitter, and far below any clock it proves
    /// was not the one enforced.
    private static let promptResponseBound: Duration = .seconds(3)

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
    /// Carries the gated tool its snippets call, and the session mailbox its
    /// runs background and post on.
    private struct Harness {
        /// The gated tool `gatedSnippet` calls.
        let gated: GatedTool

        /// The latch that releases `gated`.
        let latch: ToolReleaseLatch

        /// `MultiTool` wrapped in the shared engine.
        let mounted: any Tool<RunCodeArguments, String>

        /// The stub run whose context background runs are tracked on.
        let run: StubRun
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
    /// The mount is exactly the one Router's native session builds, unless a
    /// test asks for another site configuration to prove the tool's own
    /// declaration wins over it.
    ///
    /// - Parameters:
    ///   - configuration: the `MultiTool` knobs under test. Defaults to
    ///     `.default`, so what the tests prove holds at stock settings.
    ///   - mount: the site's own mount, which `runCode`'s declaration overrides.
    /// - Returns: the harness.
    private static func makeHarness(
        configuration: MultiToolConfiguration = .default,
        mount: ToolMount = .synchronous
    ) async throws -> Harness {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let multiTool = MultiTool(
            registry: try Self.registry(exposing: gated),
            configuration: configuration
        )
        let run = try await makeStubRun()
        let mounted = run.context.mount(multiTool, as: mount)
        return Harness(
            gated: gated,
            latch: latch,
            mounted: try #require(mounted as? any Tool<RunCodeArguments, String>),
            run: run
        )
    }

    /// The per-call work bound `multiTool` reports for one `runCode` call.
    ///
    /// The round trip through `GeneratedContent` the engine itself makes.
    ///
    /// - Parameter multiTool: the tool answering the bound.
    /// - Returns: the bound the engine would use, or `nil` for the mount's own.
    private static func workBound(of multiTool: MultiTool) -> TimeInterval? {
        multiTool.timeout(from: RunCodeArguments(code: "return 1;").generatedContent)
    }

    /// The completion token of a rendered pending envelope.
    ///
    /// - Parameter rendered: the tool output a mounted call handed back.
    /// - Returns: the background run's completion token.
    private static func completionToken(of rendered: String) throws -> String {
        try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8)).completionToken
    }

    /// Awaits a background run's settlement through the mailbox.
    ///
    /// - Parameters:
    ///   - completionToken: the background run's token.
    ///   - context: the session context the run is tracked on.
    /// - Returns: the run's terminal event.
    private static func settledTerminal(
        of completionToken: String, on context: ToolContext
    ) async throws -> OperationEvent {
        let settlement = await context.wait(
            completionToken: completionToken, seconds: scriptedRunSettlementSeconds
        )
        guard case .settled(let terminal) = settlement else {
            Issue.record("run \(completionToken) did not settle: \(settlement)")
            throw FixtureError()
        }
        return terminal
    }
}
