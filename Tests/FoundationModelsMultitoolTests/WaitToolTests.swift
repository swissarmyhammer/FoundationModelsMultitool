import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `WaitTool` — the mounted tool a model calls when it has decided
/// to block until running work finishes (task `h773bed`).
///
/// What is covered here is what needs no session: the bound arithmetic, and the
/// two in-band reports a call makes when there is nothing to wait for. The
/// settlement path needs a `SessionMailbox` with a parked run, which is the
/// gated suite's territory.
@Suite("WaitTool")
struct WaitToolTests {
    // MARK: - Two ways to return, and no third

    @Test("a call naming no timeout waits for the run to finish rather than giving up on its own schedule")
    func absentTimeoutWaitsForTheRun() {
        // `wait` returns when the token settles, or at a timeout the caller
        // passed. A host-side cap would be a third way out, reporting
        // deadlineElapsed for work that is still running and sending the model
        // back around a loop it had already decided to stop for.
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

        #expect(output.contains(WaitTool.noRunPlaneState))
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

        #expect(named.contains(WaitTool.noRunPlaneState))
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
        #expect(description.contains(RunPlaneState.deadlineElapsed))
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
}
