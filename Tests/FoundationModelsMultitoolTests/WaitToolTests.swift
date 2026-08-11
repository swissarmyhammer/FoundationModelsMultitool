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
    // MARK: - The bound is a ceiling, not a suggestion

    @Test("a call naming no timeout waits within the host's own bound")
    func absentTimeoutUsesTheHostBound() {
        #expect(WaitTool.bounded(nil) == WaitTool.defaultTimeoutSeconds)
    }

    @Test("a call naming a shorter timeout waits within that")
    func shorterTimeoutIsHonoured() {
        let shorter = WaitTool.defaultTimeoutSeconds / 2

        #expect(WaitTool.bounded(shorter) == shorter)
    }

    @Test("a call naming a longer timeout is capped at the host's bound, however long it asks for")
    func longerTimeoutIsCapped() {
        // The model does not get to hold a turn open longer than the host
        // allows, which is the whole reason the bound is applied here rather
        // than passed through.
        #expect(WaitTool.bounded(WaitTool.defaultTimeoutSeconds * 10) == WaitTool.defaultTimeoutSeconds)
        #expect(WaitTool.bounded(.infinity) == WaitTool.defaultTimeoutSeconds)
    }

    @Test("a zero or negative timeout falls back to the host's bound rather than returning at once")
    func nonPositiveTimeoutFallsBack() {
        // A model that asked to wait has said it cannot proceed. Honouring `0`
        // literally would return `deadlineElapsed` immediately and send it
        // straight back around the same loop, which is the failure this tool
        // exists to remove.
        #expect(WaitTool.bounded(0) == WaitTool.defaultTimeoutSeconds)
        #expect(WaitTool.bounded(-30) == WaitTool.defaultTimeoutSeconds)
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
