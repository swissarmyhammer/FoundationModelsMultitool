import Testing
import os

import FoundationModelsRouter

@testable import MultitoolCLI

/// Coverage for `CLIRunner.drainTurn(_:output:)` — the streaming drain the CLI
/// demo runs its one turn through — exercised with **no model at all**, by
/// handing it a scripted `SessionEvent` stream.
///
/// The drain is what makes the demo the host contract's reference host: a
/// `RoutedSession` is driven by `streamEvents(to:)`, so a tool that is still
/// working reports itself while it works instead of going silent. That
/// property is asserted here, in the unit suite, because the demo's own
/// fixtures answer instantly and no live run will ever show it.
@Suite("CLIRunner turn drain")
struct CLITurnDrainTests {
    @Test("the answer is every text fragment, in production order")
    func answerAccumulatesTextDeltas() async throws {
        let output = DrainOutputCollector()
        let answer = try await CLIRunner.drainTurn(
            scriptedEvents([.textDelta("NYC"), .textDelta(" is warmest")]),
            output: output.append
        )

        #expect(answer == "NYC is warmest")
    }

    @Test("a text reset drops the superseded answer, keeping only what followed it")
    func textResetDropsSupersededAnswer() async throws {
        let output = DrainOutputCollector()
        let answer = try await CLIRunner.drainTurn(
            scriptedEvents([
                .textDelta("I have no weather data"),
                .textReset,
                .textDelta("NYC, 24C"),
            ]),
            output: output.append
        )

        #expect(answer == "NYC, 24C")
    }

    @Test("a tool call names the tool as it is called")
    func toolCallIsPrinted() async throws {
        let output = DrainOutputCollector()
        _ = try await CLIRunner.drainTurn(
            scriptedEvents([
                .toolCall(id: "call-1", name: "runCode", argumentsJSON: "{\"code\":\"return 1\"}")
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("runCode") })
    }

    @Test("a still-running tool reports its progress under the tool's own name")
    func runningToolProgressIsPrinted() async throws {
        let output = DrainOutputCollector()
        _ = try await CLIRunner.drainTurn(
            scriptedEvents([
                .toolCall(id: "call-1", name: "runCode", argumentsJSON: "{}"),
                .toolStatus(id: "call-1", status: .running, summary: "scanning 3 of 9", output: nil),
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("runCode") && $0.contains("scanning 3 of 9") })
    }

    @Test("a failed tool call is reported under the tool's own name")
    func failedToolCallIsPrinted() async throws {
        let output = DrainOutputCollector()
        _ = try await CLIRunner.drainTurn(
            scriptedEvents([
                .toolCall(id: "call-1", name: "getWeather", argumentsJSON: "{}"),
                .toolStatus(id: "call-1", status: .failed, summary: "no such city", output: nil),
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("getWeather") && $0.contains("no such city") })
    }

    @Test("a stalled turn says so, so a long run does not read as a stuck one")
    func generationStallIsPrinted() async throws {
        let output = DrainOutputCollector()
        _ = try await CLIRunner.drainTurn(
            scriptedEvents([
                .generationStalled(
                    GenerationStall(
                        timeWithoutProgress: .seconds(30),
                        timeInFlight: .seconds(45),
                        visibility: .fragments(observed: 12)
                    )
                )
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("no fragment") && $0.contains("in flight") })
    }

    @Test("a background run that settles is reported under its tool, its token and its outcome")
    func runSettlementIsPrinted() async throws {
        let output = DrainOutputCollector()
        _ = try await CLIRunner.drainTurn(
            scriptedEvents([
                .runSettled(
                    OperationEvent(
                        tool: "execute",
                        op: "execute command",
                        correlationID: "run-7",
                        kind: .completed,
                        detail: "{\"exitCode\":0}",
                        outcome: .succeeded
                    )
                )
            ]),
            output: output.append
        )

        #expect(
            output.lines.contains {
                $0.contains("execute") && $0.contains("run-7") && $0.contains("succeeded")
            })
    }

    @Test("an error on the stream propagates to the caller")
    func streamErrorPropagates() async {
        let output = DrainOutputCollector()
        await #expect(throws: DrainTestsError.injectedStreamFailure) {
            try await CLIRunner.drainTurn(
                AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("partial"))
                    continuation.finish(throwing: DrainTestsError.injectedStreamFailure)
                },
                output: output.append
            )
        }
    }
}

// MARK: - Fixtures

/// Errors this test file's scripted streams throw.
private enum DrainTestsError: Error, Equatable {
    /// The scripted failure `streamErrorPropagates` puts on the stream.
    case injectedStreamFailure
}

/// Builds a finished event stream over `events`, in the given order.
///
/// The scripted stand-in for `RoutedSession.streamEvents(to:)`, so the drain
/// is exercised with no model, no Router and no network.
///
/// - Parameter events: the events to yield, in order.
/// - Returns: a stream that yields each event and then finishes.
private func scriptedEvents(_ events: [SessionEvent]) -> AsyncThrowingStream<SessionEvent, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    }
}

/// A thread-safe collector for the lines `CLIRunner.drainTurn(_:output:)`
/// writes.
///
/// `final class ... Sendable` for the same reason as this target's other
/// lock-boxed fixtures: `append` is handed over as a `@Sendable` closure.
private final class DrainOutputCollector: Sendable {
    /// Every line appended so far, in append order.
    private let linesBox = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Creates an empty collector.
    init() {}

    /// Every line appended so far, in append order.
    var lines: [String] { linesBox.withLock { $0 } }

    /// Appends one line — `CLIRunner.drainTurn(_:output:)`'s `output`
    /// parameter.
    ///
    /// - Parameter line: the line to record.
    func append(_ line: String) {
        linesBox.withLock { $0.append(line) }
    }
}
