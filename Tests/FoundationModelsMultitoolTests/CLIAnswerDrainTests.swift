import Foundation
import Testing

@testable import FoundationModelsExtras
@testable import FoundationModelsRouter
@testable import MultitoolCLI
@testable import MultitoolTestSupport

/// Coverage for the drains the CLI demo runs its answers through —
/// `CLIRunner.drainAnswer(_:output:)`, `CLIRunner.presentAnswer(_:output:)`
/// and `CLIRunner.drainMailAnswers(_:after:wait:cancel:output:)` — with **no
/// model at all**. Each test gives a scripted `SessionEvent` stream.
///
/// The drain is what makes the demo the reference host of the host contract:
/// a `RoutedSession` is driven by `streamEvents(to:)`, so a tool that is still
/// working reports itself while it works. The answer that mail starts
/// streams on `streamSessionEvents()`, and the CLI prints it before it exits.
/// These properties are asserted here, in the unit suite, because the demo
/// fixtures answer instantly and no live run shows them reliably.
///
/// `@testable import FoundationModelsRouter` and
/// `@testable import FoundationModelsExtras`: `SubmissionID` (Router) and
/// `MessageID` (Extras) have internal initializers only, and a scripted
/// submission frame needs both.
@Suite("CLIRunner answer drain")
struct CLIAnswerDrainTests {
    @Test("the answer is the reply of the answered event, not the joined text fragments")
    func answerIsTheReplyOfTheAnsweredEvent() async throws {
        let output = OutputCollector()
        let answer = try await CLIRunner.drainAnswer(
            scriptedEvents([.textDelta("NYC"), .textDelta(" is warm"), answered("NYC is warmest")]),
            output: output.append
        )

        #expect(answer.reply == "NYC is warmest")
    }

    @Test("two submissions that give one answer print the reply of that answer one time")
    func twoSubmissionsPrintTheReplyOneTime() async throws {
        let output = OutputCollector()
        let message = MessageID()
        let first = SubmissionID(firstSubmissionNumber)
        let continuation = SubmissionID(secondSubmissionNumber)
        _ = try await CLIRunner.presentAnswer(
            scriptedEvents([
                .submissionStarted(SubmissionStart(submissionId: first, messageIds: [message], cause: .message)),
                .textDelta("I have no weather data"),
                .submissionEnded(SubmissionEnd(submissionId: first, usage: nil, finishReason: .maxTokens)),
                .submissionStarted(
                    SubmissionStart(submissionId: continuation, messageIds: [message], cause: .continuation)),
                .textDelta("NYC is warmest"),
                .submissionEnded(SubmissionEnd(submissionId: continuation, usage: nil, finishReason: .completed)),
                answered("NYC is warmest", messageIds: [message]),
            ]),
            output: output.append
        )

        #expect(output.lines.filter { $0.hasPrefix(answerPrefix) } == ["\(answerPrefix)NYC is warmest"])
    }

    @Test("a failed answer gives an error line, a non-zero exit code, and no answer line")
    func answerFailedGivesAnErrorAndNoAnswerLine() async throws {
        let output = OutputCollector()
        let errorOutput = OutputCollector()
        let failure = AnswerFailure(messageIds: [], reason: .error("the model stopped"))
        let error = await #expect(throws: CLIAnswerError.failed(failure)) {
            try await CLIRunner.presentAnswer(
                scriptedEvents([.textDelta("partial"), .answerFailed(failure)]),
                output: output.append
            )
        }
        let exitCode = CLIRunner.exitCode(
            for: try #require(error), output: output.append, errorOutput: errorOutput.append)

        #expect(exitCode == CLIRunner.ExitCode.answerFailed)
        #expect(exitCode != CLIRunner.ExitCode.success)
        #expect(errorOutput.lines.count == 1)
        #expect(errorOutput.lines.first?.contains("the model stopped") == true)
        #expect(!output.lines.contains { $0.hasPrefix(answerPrefix) })
    }

    @Test("the error that ends the stream after a failed answer reports as that failure")
    func streamErrorAfterAnswerFailedReportsTheFailure() async {
        let output = OutputCollector()
        let failure = AnswerFailure(messageIds: [], reason: .cancelled)
        await #expect(throws: CLIAnswerError.failed(failure)) {
            try await CLIRunner.drainAnswer(
                AsyncThrowingStream { continuation in
                    continuation.yield(.answerFailed(failure))
                    continuation.finish(throwing: DrainTestsError.injectedStreamFailure)
                },
                output: output.append
            )
        }
    }

    @Test("a stream that ends with no end of the answer is an error")
    func streamWithNoEndOfTheAnswerIsAnError() async {
        let output = OutputCollector()
        await #expect(throws: CLIAnswerError.missing) {
            try await CLIRunner.drainAnswer(scriptedEvents([.textDelta("partial")]), output: output.append)
        }
    }

    @Test("a tool call names the tool as it is called")
    func toolCallIsPrinted() async throws {
        let output = OutputCollector()
        _ = try await CLIRunner.drainAnswer(
            scriptedEvents([
                .toolCall(id: "call-1", name: "runCode", argumentsJSON: "{\"code\":\"return 1\"}"),
                answered("1"),
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("runCode") })
    }

    @Test("a still-running tool reports its progress under the tool's own name")
    func runningToolProgressIsPrinted() async throws {
        let output = OutputCollector()
        _ = try await CLIRunner.drainAnswer(
            scriptedEvents([
                .toolCall(id: "call-1", name: "runCode", argumentsJSON: "{}"),
                .toolStatus(id: "call-1", status: .running, summary: "scanning 3 of 9", output: nil),
                answered("done"),
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("runCode") && $0.contains("scanning 3 of 9") })
    }

    @Test("a failed tool call is reported under the tool's own name")
    func failedToolCallIsPrinted() async throws {
        let output = OutputCollector()
        _ = try await CLIRunner.drainAnswer(
            scriptedEvents([
                .toolCall(id: "call-1", name: "getWeather", argumentsJSON: "{}"),
                .toolStatus(id: "call-1", status: .failed, summary: "no such city", output: nil),
                answered("no answer"),
            ]),
            output: output.append
        )

        #expect(output.lines.contains { $0.contains("getWeather") && $0.contains("no such city") })
    }

    @Test("a stalled answer says so, so a long run does not read as a stuck one")
    func generationStallIsPrinted() async throws {
        let output = OutputCollector()
        let stall = GenerationStall(
            timeWithoutProgress: .seconds(30),
            timeInFlight: .seconds(45),
            visibility: .fragments(observed: 12),
            lastProgress: .fragment
        )
        _ = try await CLIRunner.drainAnswer(
            scriptedEvents([.generationStalled(stall), answered("done")]),
            output: output.append
        )

        // The CLI prints Router's own one-line report. Compared against that
        // report, not against its words, so a reword in Router reaches here.
        #expect(output.lines.contains(stall.description))
    }

    @Test("a repetition stop is one output line and leaves the answer as it is")
    func repetitionStopIsPrinted() async throws {
        let output = OutputCollector()
        let stop = RepetitionStop(
            generatedTokens: 3_000,
            countedLines: 40,
            newLines: 6,
            tokensWithoutNewLine: 2_100,
            detection: RepetitionDetection(),
            recovery: 1
        )
        let answer = try await CLIRunner.drainAnswer(
            scriptedEvents([
                .textDelta("NYC"), .repetitionStopped(stop), .textDelta(" is warmest"), answered("NYC is warmest"),
            ]),
            output: output.append
        )

        // The CLI prints the one-line report of Router. The test compares the
        // line with that report and not with its words, so that a change of
        // the words in Router gets to this test.
        #expect(output.lines == [stop.description])
        #expect(answer.reply == "NYC is warmest")
    }

    @Test("a reasoning stop is one output line and leaves the answer as it is")
    func reasoningStopIsPrinted() async throws {
        let output = OutputCollector()
        let stop = ReasoningStop(
            reasoningTokens: 3_000,
            limit: 2_048,
            passFinishReason: .reasoningTokenLimit,
            detection: RepetitionDetection(),
            recovery: 1
        )
        let answer = try await CLIRunner.drainAnswer(
            scriptedEvents([
                .textDelta("NYC"), .reasoningStopped(stop), .textDelta(" is warmest"), answered("NYC is warmest"),
            ]),
            output: output.append
        )

        // The line is the one-line report of Router, for the reason the
        // repetition test above gives.
        #expect(output.lines == [stop.description])
        #expect(answer.reply == "NYC is warmest")
    }

    @Test("a background run that settles is reported under its tool, its token and its outcome")
    func runSettlementIsPrinted() async throws {
        let output = OutputCollector()
        _ = try await CLIRunner.drainAnswer(
            scriptedEvents([.runSettled(settledRun("run-7")), answered("done")]),
            output: output.append
        )

        #expect(
            output.lines.contains {
                $0.contains("execute") && $0.contains("run-7") && $0.contains("succeeded")
            })
    }

    @Test("an error on the stream propagates to the caller")
    func streamErrorPropagates() async {
        let output = OutputCollector()
        await #expect(throws: DrainTestsError.injectedStreamFailure) {
            try await CLIRunner.drainAnswer(
                AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("partial"))
                    continuation.finish(throwing: DrainTestsError.injectedStreamFailure)
                },
                output: output.append
            )
        }
    }

    /// The clock holds every quiet period until the drain printed the mail
    /// answer. Thus the drain cannot stop between two events of that answer,
    /// whatever the load on the machine. The clock never ends the time limit.
    @Test("a background run that settles after the first answer gives a mail answer, and the CLI prints it")
    func mailAnswerIsPrintedBeforeExit() async throws {
        let output = OutputCollector()
        let cancels = OutputCollector()
        let clock = GatedClock()
        let script = MailScript()
        let events = AsyncStream<SessionEvent> { continuation in
            for event in script.firstAnswerEvents + script.mailAnswerEvents {
                continuation.yield(event)
            }
        }

        let drain = Task {
            try await CLIRunner.drainMailAnswers(
                events, after: script.firstAnswer, wait: gatedMailWait(on: clock),
                cancel: { cancels.append("cancel") }, output: output.append)
        }
        try await TestPoll.waitUntil("the drain printed the mail answer") {
            output.lines.contains("\(mailAnswerPrefix)Tokyo is warmest")
        }
        clock.open(sleepsOf: testQuietPeriod)
        try await drain.value

        #expect(!output.lines.contains { $0.hasPrefix(answerPrefix) })
        #expect(cancels.lines.isEmpty)
    }

    /// The first answer ends while its background run is still open. Only
    /// that open run keeps the drain from its quiet period, thus a drain that
    /// ignored the run stops before the mail comes.
    @Test("the drain is not settled after the first answer while its background run is open, and is settled after the mail answer")
    func openRunKeepsTheDrainUnsettled() throws {
        let script = MailScript()
        var drain = CLIMailDrain(following: script.firstAnswer, output: OutputCollector().append)

        for event in script.firstAnswerEvents {
            try drain.apply(event)
        }
        #expect(!drain.isSettled)

        for event in script.mailAnswerEvents {
            try drain.apply(event)
        }
        #expect(drain.isSettled)
    }

    /// The clock ends the time limit at once. The run never settles, thus the
    /// drain asks for no quiet period, and the time limit is its one sleep.
    @Test("a background run that never settles stops the drain at the time limit, and the session is cancelled")
    func openRunStopsAtTheTimeLimit() async throws {
        let output = OutputCollector()
        let cancels = OutputCollector()
        let clock = GatedClock()
        clock.open()
        let script = MailScript()
        let (events, continuation) = AsyncStream<SessionEvent>.makeStream()
        for event in script.firstAnswerEvents {
            continuation.yield(event)
        }

        try await CLIRunner.drainMailAnswers(
            events, after: script.firstAnswer, wait: gatedMailWait(on: clock, timeLimit: shortTimeLimit),
            cancel: { cancels.append("cancel") }, output: output.append)
        continuation.finish()

        #expect(cancels.lines == ["cancel"])
        #expect(!output.lines.contains { $0.hasPrefix(mailAnswerPrefix) })
        #expect(clock.recordedSleeps == [shortTimeLimit])
    }

    /// The clock never ends a quiet period, thus the drain reads the failed
    /// answer, whatever the time between the events.
    @Test("a failed mail answer is an error")
    func failedMailAnswerIsAnError() async {
        let output = OutputCollector()
        let script = MailScript()
        let failure = AnswerFailure(messageIds: [], reason: .error("the mail answer stopped"))
        let events = AsyncStream<SessionEvent> { continuation in
            for event in script.firstAnswerEvents {
                continuation.yield(event)
            }
            continuation.yield(.runSettled(settledRun(script.runToken)))
            continuation.yield(.answerFailed(failure))
        }

        await #expect(throws: CLIAnswerError.failed(failure)) {
            try await CLIRunner.drainMailAnswers(
                events, after: script.firstAnswer, wait: gatedMailWait(on: GatedClock()),
                cancel: {}, output: output.append)
        }
    }
}

// MARK: - Fixtures

/// The prefix of the line that prints the first answer.
private let answerPrefix = "Answer: "

/// The prefix of the line that prints an answer that mail started.
private let mailAnswerPrefix = "Answer from mail: "

/// The number of the first submission of a scripted session.
private let firstSubmissionNumber: UInt64 = 1

/// The number of the second submission of a scripted session.
private let secondSubmissionNumber: UInt64 = 2

/// The quiet period of the mail drain in these tests, in milliseconds.
///
/// The `GatedClock` of each test measures it, thus the value takes no real
/// time. It only names the sleeps the test opens: a value different from each
/// time limit below.
private let testQuietPeriodMilliseconds = 50

/// The time limit of `openRunStopsAtTheTimeLimit`, in milliseconds.
private let shortTimeLimitMilliseconds = 300

/// The time limit of the mail drain in the tests whose clock never ends it,
/// in seconds.
private let heldTimeLimitSeconds = 30

/// The quiet period of the mail drain in these tests.
private let testQuietPeriod: Duration = .milliseconds(testQuietPeriodMilliseconds)

/// The time limit of `openRunStopsAtTheTimeLimit`.
private let shortTimeLimit: Duration = .milliseconds(shortTimeLimitMilliseconds)

/// The time limit of the tests whose clock never ends it.
private let heldTimeLimit: Duration = .seconds(heldTimeLimitSeconds)

/// The bounds of the mail drain in these tests, measured on `clock`.
///
/// No test checks the speed of the machine (card `^pfvdg5b`). The test opens
/// `clock` for the bound it wants to end, and a bound the test does not open
/// never ends.
///
/// - Parameters:
///   - clock: The clock that measures both bounds.
///   - timeLimit: The time limit of the wait.
/// - Returns: The bounds.
private func gatedMailWait(on clock: GatedClock, timeLimit: Duration = heldTimeLimit) -> CLIMailWait {
    CLIMailWait(quietPeriod: testQuietPeriod, timeLimit: timeLimit, clock: clock)
}

/// Errors this test file's scripted streams throw.
private enum DrainTestsError: Error, Equatable {
    /// The scripted failure some tests put on the stream.
    case injectedStreamFailure
}

/// One scripted session: a first answer that starts a background run, and a
/// mail answer after the run settles.
private struct MailScript {
    /// The completion token of the background run.
    let runToken = "run-1"

    /// The caller message of the first answer.
    let message = MessageID()

    /// The session the run belongs to.
    let sessionID = ULID.generate()

    /// When the background run opened.
    let openedAt = Date()

    /// The end of the first answer, as `drainAnswer` gives it.
    var firstAnswer: SessionAnswer {
        SessionAnswer(
            reply: "The result comes back later", messageIds: [message], usage: nil, compactions: [],
            toolCalls: [], toolInvocations: [openRecord])
    }

    /// The open record of the background run.
    var openRecord: ToolInvocationRecord {
        ToolInvocationRecord(
            tool: "runCode", op: "runCode", correlationID: runToken, sessionID: sessionID, openedAt: openedAt)
    }

    /// Every event of the first answer, as `streamSessionEvents()` gives it.
    var firstAnswerEvents: [SessionEvent] {
        let submission = SubmissionID(firstSubmissionNumber)
        return [
            .submissionStarted(SubmissionStart(submissionId: submission, messageIds: [message], cause: .message)),
            .toolCall(id: "call-1", name: "runCode", argumentsJSON: "{}"),
            .toolInvocation(openRecord),
            .textDelta("The result comes back later"),
            .submissionEnded(SubmissionEnd(submissionId: submission, usage: nil, finishReason: .completed)),
            .answered(firstAnswer),
        ]
    }

    /// The settlement of the run, and every event of the answer that its
    /// mail starts.
    var mailAnswerEvents: [SessionEvent] {
        let submission = SubmissionID(secondSubmissionNumber)
        return [
            .toolInvocation(openRecord.closed(at: Date())),
            .runSettled(settledRun(runToken)),
            .submissionStarted(SubmissionStart(submissionId: submission, messageIds: [], cause: .mail)),
            .textDelta("Tokyo is warmest"),
            .submissionEnded(SubmissionEnd(submissionId: submission, usage: nil, finishReason: .completed)),
            answered("Tokyo is warmest"),
        ]
    }
}

/// The terminal event of one background run that succeeded.
///
/// - Parameter token: the completion token of the run.
/// - Returns: the terminal event.
private func settledRun(_ token: String) -> OperationEvent {
    OperationEvent(
        tool: "execute",
        op: "execute command",
        correlationID: token,
        kind: .completed,
        detail: "{\"exitCode\":0}",
        outcome: .succeeded
    )
}

/// The end of one answer that gives `reply`.
///
/// - Parameters:
///   - reply: the final reply of the answer.
///   - messageIds: the caller messages the answer answers.
/// - Returns: the `SessionEvent.answered` event.
private func answered(_ reply: String, messageIds: [MessageID] = []) -> SessionEvent {
    .answered(
        SessionAnswer(
            reply: reply, messageIds: messageIds, usage: nil, compactions: [], toolCalls: [], toolInvocations: []))
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
