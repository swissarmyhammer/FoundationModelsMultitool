import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `WaitTool` — the mounted tool a model calls when it has decided
/// to block until running work finishes (task `h773bed`).
///
/// Three things are covered: the bound arithmetic, the two in-band reports a
/// call makes when there is nothing to wait for, and — since a run can now be
/// backgrounded through the real detachment engine (`startScriptedRun(in:)`) —
/// the settlement path itself, with no live inference anywhere.
@Suite("WaitTool")
struct WaitToolTests {
    // MARK: - Two ways to return, and no third

    @Test("a call naming no timeout waits for the run to finish rather than giving up on its own schedule")
    func absentTimeoutWaitsForTheRun() {
        // `wait` returns when the token settles, or at a timeout the caller
        // passed. A host-side cap would be a third way out, reporting a
        // timeout for work that is still running and sending the model back
        // around a loop it had already decided to stop for.
        #expect(WaitTool.bounded(nil) == WaitTool.unboundedSeconds)
    }

    @Test("a caller's timeout is honoured exactly as passed, short or long")
    func aPassedTimeoutIsHonoured() {
        // Nothing second-guesses the number: it is the bound the model chose
        // when it decided to block.
        #expect(WaitTool.bounded(30) == 30)
        #expect(WaitTool.bounded(600) == 600)
        #expect(WaitTool.bounded(6_000) == 6_000)
    }

    @Test("a zero or negative timeout waits for the run rather than returning at once")
    func nonPositiveTimeoutWaitsForTheRun() {
        // A model that called `wait` has said it cannot proceed. Honouring `0`
        // literally would return immediately with nothing, which is the failure
        // this tool exists to remove.
        #expect(WaitTool.bounded(0) == WaitTool.unboundedSeconds)
        #expect(WaitTool.bounded(-30) == WaitTool.unboundedSeconds)
    }

    // MARK: - Nothing to wait for is reported, never trapped

    @Test("a call with no ambient session reports that there is nothing running, and says what to do instead")
    func aSessionlessCallReportsInBand() async throws {
        // The mode every unit suite in this package runs in: no session, so no
        // mailbox and no run plane. This must be a report the model can act on
        // rather than a trap or an empty answer.
        let output = try await WaitTool().call(arguments: WaitArguments())

        #expect(output.contains(WaitTool.noSessionResult))
        // Phrased as the next move, not as a diagnosis: the model is told to
        // answer from what it already has.
        #expect(output.contains("nothing running to wait for"))
        #expect(output.contains("already returned"))
    }

    @Test("a sessionless call reports the same way whether or not it named a token")
    func aSessionlessCallIgnoresItsArguments() async throws {
        let named = try await WaitTool().call(
            arguments: WaitArguments(completionToken: "01ARZ3NDEKTSV4RRFFQ69G5FAV", timeout: 30)
        )

        #expect(named.contains(WaitTool.noSessionResult))
    }

    // MARK: - The model-facing surface

    @Test("the description tells the model when to call wait and never suggests a number of seconds")
    func theDescriptionNamesNoDuration() {
        let description = WaitTool()
            .description
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        #expect(WaitTool().name == "wait")
        // The condition for calling it, stated as a condition rather than as an
        // invitation: this tool is a last resort, not a habit.
        #expect(description.contains("only when you cannot continue"))
        // Where the answer is.
        #expect(description.contains("`detail`"))
        // A still-running call is not a failure, and the description says so —
        // otherwise a model reads the bound elapsing as an error and gives up.
        #expect(description.contains(CallResult.timeout))
        #expect(description.contains("nothing has failed"))
        // No worked example carrying a duration. The whole defect this tool
        // replaces was a model copying `wait(token, 60)` out of an instruction,
        // so nothing here may hand it a number to copy.
        for duration in ["30", "60", "120", "300"] {
            #expect(!description.contains(duration))
        }
    }

    @Test("the arguments schema offers both a token and a bound, and requires neither")
    func bothArgumentsAreOptional() {
        // `wait()` with nothing at all is the primary form — wait for whatever
        // is running — so neither property may be required.
        let arguments = WaitArguments()

        #expect(arguments.completionToken == nil)
        #expect(arguments.timeout == nil)
    }

    // MARK: - The settlement path (^ddgjps6)

    /// A `wait` call against a real run plane, bound to `mailbox`.
    ///
    /// - Parameters:
    ///   - arguments: the call's arguments.
    ///   - mailbox: the session mailbox whose run plane is read.
    /// - Returns: the tool's rendered report.
    private static func waitCall(
        _ arguments: WaitArguments, against mailbox: SessionMailbox
    ) async throws -> String {
        try await ToolContext.$current.withValue(backgroundRuns(over: mailbox)) {
            try await WaitTool().call(arguments: arguments)
        }
    }

    @Test("wait blocks until a background run finishes, and answers with its terminal detail")
    func waitBlocksUntilTheRunSettles() async throws {
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox, detail: "the-collected-result")
        let heldOpen = Duration.milliseconds(300)

        // The run is deliberately held open for a known time after the wait is
        // issued, so the elapsed time below is what proves the call blocked.
        // Without it, a wait that returned at once from the retained terminal
        // event of an already-settled run would assert exactly the same way.
        let settling = Task {
            try await Task.sleep(for: heldOpen)
            await settle(run, in: mailbox)
        }
        let start = ContinuousClock.now
        let finished = try await Self.waitCall(
            WaitArguments(completionToken: run.completionToken), against: mailbox
        )
        let elapsed = start.duration(to: .now)
        try await settling.value

        #expect(finished.contains(RunState.complete))
        #expect(finished.contains("the-collected-result"))
        // No timeout was passed, so nothing but the settlement could have ended
        // this wait — and it could not have ended before the settlement it
        // reports.
        #expect(elapsed >= heldOpen)
    }

    @Test("a run that settles early returns early — the bound is not a floor")
    func anEarlySettlementReturnsEarly() async throws {
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox)
        let generousBound: Double = 600

        let start = ContinuousClock.now
        async let report = Self.waitCall(
            WaitArguments(completionToken: run.completionToken, timeout: generousBound), against: mailbox
        )
        await settle(run, in: mailbox)
        _ = try await report
        let elapsed = start.duration(to: .now)

        // Ten minutes was the bound; the run settled at once. A bound that
        // behaved as a floor would still be waiting.
        #expect(elapsed < .seconds(30))
    }

    @Test("a run still going at the caller's bound reports a timeout, not failure")
    func aRunStillGoingAtTheBoundReportsATimeout() async throws {
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox)

        // Never settled: the gate stays closed for the whole test, so the bound
        // is what ends the wait. Deterministic — nothing races the clock.
        let report = try await Self.waitCall(
            WaitArguments(completionToken: run.completionToken, timeout: 0.2), against: mailbox
        )

        #expect(report.contains(CallResult.timeout))
        #expect(report.contains(run.completionToken))
        // Still going is not failure, and the run is still there to collect.
        #expect(await backgroundRuns(over: mailbox).parkedRuns().map(\.completionToken) == [run.completionToken])
    }

    @Test("a finished run is told to answer with the detail this call just delivered")
    func aFinishedRunCarriesTheAnswerDirective() async throws {
        // The answer-level half of task `wnfzwxg`. A model that collected the
        // value and then replied that it would arrive later did everything
        // mechanical right: it spent the wait, the run finished, nothing was
        // left going. Nothing in band told it that a promise is not a report,
        // and this is the moment it had the value in hand.
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox, detail: "the-collected-result")
        await settle(run, in: mailbox)

        let finished = try await Self.waitCall(
            WaitArguments(completionToken: run.completionToken), against: mailbox
        )

        #expect(finished.contains("the-collected-result"))
        #expect(finished.contains(WaitTool.finishedRunDirective))
    }

    @Test("a run still going carries no answer directive, because it delivered no result")
    func aDeadlineThatElapsedCarriesNoAnswerDirective() async throws {
        // The directive names a `detail` this report carries. A report that
        // carries none would be telling the model to answer with nothing.
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox)

        let report = try await Self.waitCall(
            WaitArguments(completionToken: run.completionToken, timeout: 0.2), against: mailbox
        )

        #expect(report.contains(CallResult.timeout))
        #expect(!report.contains(WaitTool.finishedRunDirective))
    }

    @Test("waiting with no token waits for every pending run")
    func waitingWithNoTokenWaitsForEveryPendingRun() async throws {
        let mailbox = SessionMailbox()
        let first = try await startScriptedRun(in: mailbox, tool: "first", detail: "first-result")
        let second = try await startScriptedRun(in: mailbox, tool: "second", detail: "second-result")

        // Both runs are going before the wait is issued, and both are held
        // open past it, so the call snapshots two pending runs and blocks on
        // each. Settling them from the calling task instead would let the wait
        // start after they were already over, which proves nothing.
        let settling = Task {
            try await Task.sleep(for: .milliseconds(200))
            await settle(first, in: mailbox)
            await settle(second, in: mailbox)
        }
        let collected = try await Self.waitCall(WaitArguments(), against: mailbox)
        try await settling.value
        #expect(collected.contains("first-result"))
        #expect(collected.contains("second-result"))
    }

    @Test("a session whose runs have all finished says so, and points at the answer")
    func aSessionWithNothingPendingSaysSo() async throws {
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox)
        await settle(run, in: mailbox)

        let report = try await Self.waitCall(WaitArguments(), against: mailbox)

        // Not an error and not an empty wait: the runs are done, so the answer
        // is already in hand and the report says that rather than inviting
        // another wait.
        #expect(report.contains(WaitTool.nothingPendingResult))
        #expect(report.contains(WaitTool.nothingPendingDetail))
    }

    // MARK: - wait never backgrounds itself

    @Test("a wait call blocking past the mount's wait clock still returns its report, never a token")
    func waitNeverBackgroundsItself() async throws {
        let mailbox = SessionMailbox()
        let run = try await startScriptedRun(in: mailbox)

        // Mounted to detach immediately — harsher than the stock five seconds
        // that made this tool only accidentally safe. The tool answers both of
        // its own clocks at the ceiling, and a per-call answer overrides the
        // mount, so the wait runs to its own conclusion.
        let mounted = try #require(
            ToolDetachment.wrapping(
                tool: WaitTool(),
                sessionID: ULID(),
                mailbox: mailbox,
                sink: RecordingEventSink(),
                configuration: DetachConfiguration(mode: .detaching, waitSeconds: 0)
            ) as? any Tool<WaitArguments, String>
        )

        let report = try await ToolContext.$current.withValue(backgroundRuns(over: mailbox)) {
            try await mounted.call(
                arguments: WaitArguments(completionToken: run.completionToken, timeout: 0.2)
            )
        }

        #expect(!PendingRunEnvelope.isRendered(text: report))
        #expect(report.contains(CallResult.timeout))
    }
}
