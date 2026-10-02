import Foundation
import InMemoryTracing
import os
import TelemetryTestSupport
import Testing
import Tracing

@testable import MultitoolCLI
@testable import MultitoolTestSupport

/// Covers `CLIExitPath`, the one exit path of `multitool-cli`.
///
/// Each end of a run goes through `CLIExitPath.run(stoppingOn:_:)`: the normal
/// end, each error exit code, an error that the command throws, and a stop
/// signal. On each end the exit path ends the run span first, then it flushes
/// the exporters, and then it gives the exit code. Thus the last span of the
/// run is in the flush.
///
/// A test gives a flush that keeps the spans that ended before it. The spans
/// come from the in-memory tracer of `TelemetryCapture`. No test bootstraps a
/// telemetry system, and no test sends a real signal to the test process: a
/// test gives its own stream of stop signals.
///
/// No bound of the exit path sleeps on the real clock. A test that must not
/// reach the bound gives a `GatedClock` that it never opens, thus a wait that
/// never ends is a hang, and the hang guard of the suite reports it.
@Suite("CLITelemetryShutdown", .timeLimit(TestHangGuard.timeLimit))
struct CLITelemetryShutdownTests {
    /// The time bound that the tests give to the exit path. It is short, thus
    /// a test of the bound ends soon.
    private static let testBound: Duration = .milliseconds(200)

    /// How long a flush or a command that does not end by itself waits: one
    /// day. No test reaches it, thus only the bound of the exit path can end
    /// the wait while the test runs.
    private static let longWait: Duration = .seconds(86_400)

    /// The line that the command of the thrown-error test throws.
    private static let thrownText = "the command threw"

    // MARK: - Each end of a run exports the run span

    @Test(
        "each exit code of the CLI entry point ends the run span before the flush",
        arguments: [
            (["--help"], CLIRunner.ExitCode.success),
            (["--no-such-flag"], CLIRunner.ExitCode.usageError),
            ([], CLIRunner.ExitCode.unavailable),
        ])
    func eachExitCodeExportsTheRunSpan(arguments: [String], expectedCode: Int32) async throws {
        try await TelemetryCapture.run(forbidding: []) { context in
            let flushes = FlushRecorder(context: context)
            let output = OutputCollector()

            let code = await Self.exitPathWithUnreachedBound(flush: flushes.flush)
                .run(stoppingOn: Self.noStopSignals()) { cancellation in
                    await CLIRunner.run(
                        arguments: arguments, resolve: Self.failingResolve, output: output.append,
                        errorOutput: output.append, cancellation: cancellation)
                }

            #expect(code == expectedCode)
            #expect(flushes.count == 1)
            let span = try #require(flushes.runSpan)
            #expect(span.attributes[CLIExitPath.exitCodeAttribute]?.toSpanAttribute() == .int64(Int64(expectedCode)))
        }
    }

    @Test("an error that the command throws ends the run span, writes one line and gives the unavailable code")
    func thrownErrorExportsTheRunSpan() async throws {
        try await TelemetryCapture.run(forbidding: []) { context in
            let flushes = FlushRecorder(context: context)
            let errorOutput = OutputCollector()

            let code = await Self.exitPathWithUnreachedBound(flush: flushes.flush, errorOutput: errorOutput.append)
                .run(stoppingOn: Self.noStopSignals()) { _ in
                    throw CLITelemetryShutdownTestsError.thrown(Self.thrownText)
                }

            #expect(code == CLIRunner.ExitCode.unavailable)
            #expect(errorOutput.lines.count == 1)
            #expect(errorOutput.lines.first?.contains(Self.thrownText) == true, "lines were: \(errorOutput.lines)")
            let span = try #require(flushes.runSpan)
            #expect(span.status?.code == .error)
        }
    }

    // MARK: - A stop signal

    @Test(
        "a stop signal cancels the session, ends the run span before the flush, and gives 128 + the signal number",
        arguments: CLIStopSignal.allCases)
    func stopSignalCancelsAndExportsTheRunSpan(signal: CLIStopSignal) async throws {
        try await TelemetryCapture.run(forbidding: []) { context in
            let flushes = FlushRecorder(context: context)
            let cancels = CallCounter()
            let (signals, sender) = AsyncStream<CLIStopSignal>.makeStream()

            let code = await Self.exitPathWithUnreachedBound(flush: flushes.flush)
                .run(stoppingOn: signals) { cancellation in
                    await cancellation.onCancel { cancels.increment() }
                    sender.yield(signal)
                    try await Task.sleep(for: Self.longWait)
                    return CLIRunner.ExitCode.success
                }

            #expect(code == signal.exitCode)
            #expect(cancels.count == 1)
            #expect(flushes.count == 1)
            let span = try #require(flushes.runSpan)
            #expect(span.attributes[CLIExitPath.exitCodeAttribute]?.toSpanAttribute() == .int64(Int64(signal.exitCode)))
        }
    }

    @Test("the exit code of a stop signal is 128 + the signal number")
    func stopSignalExitCodes() {
        #expect(CLIStopSignal.interrupt.number == SIGINT)
        #expect(CLIStopSignal.terminate.number == SIGTERM)
        #expect(CLIStopSignal.interrupt.exitCode == 130)
        #expect(CLIStopSignal.terminate.exitCode == 143)
    }

    // MARK: - The bound and the path with no exporter

    /// The bound sleeps on a `GatedClock`, and the flush never ends while the
    /// test runs. Thus the exit path can end only when the test opens the
    /// clock, and the clock records the bound that the path armed. The test
    /// reads no real time (card `^tm4x2hp`: no test checks the speed of the
    /// machine). A path that waits for the flush past its bound hangs, and the
    /// hang guard fails the test.
    @Test("a flush that does not end holds the exit path for the bound only", .timeLimit(TestHangGuard.timeLimit))
    func flushThatDoesNotEndIsBounded() async throws {
        let clock = GatedClock()
        let path = CLIExitPath(
            flush: { try? await Task.sleep(for: Self.longWait) }, bound: Self.testBound,
            errorOutput: CLIRunner.standardErrorOutput, clock: clock)
        let run = Task {
            await path.run(stoppingOn: Self.noStopSignals()) { _ in CLIRunner.ExitCode.answerFailed }
        }

        try await TestPoll.waitUntil("the exit path armed its bound") { !clock.recordedSleeps.isEmpty }
        clock.open()
        let code = await run.value

        #expect(code == CLIRunner.ExitCode.answerFailed)
        #expect(clock.recordedSleeps == [Self.testBound])
    }

    @Test("with no exporter the exit path gives the exit code of the command")
    func noExporterGivesTheExitCode() async {
        let code = await CLIExitPath(flush: nil, bound: Self.testBound)
            .run(stoppingOn: Self.noStopSignals()) { _ in CLIRunner.ExitCode.answerFailed }

        #expect(code == CLIRunner.ExitCode.answerFailed)
    }

    @Test("a cancel action added after the cancel runs at once")
    func lateCancelActionRuns() async {
        let cancellation = CLIRunCancellation()
        let cancels = CallCounter()

        await cancellation.cancel()
        await cancellation.onCancel { cancels.increment() }
        await cancellation.cancel()

        #expect(cancels.count == 1)
    }

    // MARK: - Fixtures

    /// An exit path whose bound sleeps on a `GatedClock` that no test opens.
    ///
    /// Thus the bound never ends the wait for the flush or for the command,
    /// however slow the machine is, and the flush that the test records
    /// always runs to its end. With the real clock, a busy machine could let
    /// the bound end first, and the test would read no flush (card
    /// `^kdtrmhv`: no test checks the speed of the machine).
    ///
    /// - Parameters:
    ///   - flush: The flush that the path calls.
    ///   - errorOutput: Where the line of an error that the command throws
    ///     goes.
    /// - Returns: The exit path.
    private static func exitPathWithUnreachedBound(
        flush: @escaping @Sendable () async -> Void,
        errorOutput: @escaping @Sendable (String) -> Void = CLIRunner.standardErrorOutput
    ) -> CLIExitPath {
        CLIExitPath(flush: flush, bound: testBound, errorOutput: errorOutput, clock: GatedClock())
    }

    /// A stream of stop signals that never gives a signal.
    ///
    /// - Returns: The stream.
    private static func noStopSignals() -> AsyncStream<CLIStopSignal> {
        AsyncStream { _ in }
    }

    /// A resolve that fails before a model loads.
    private static let failingResolve: CLIRunner.ProfileResolver = { _, _, _ in
        throw CLITelemetryShutdownTestsError.injectedResolveFailure
    }
}

/// Keeps the spans that ended before each flush.
private final class FlushRecorder: Sendable {
    /// The capture whose spans the flush reads.
    private let context: TelemetryCapture.Context

    /// The spans that ended before each flush, one array for each flush.
    private let snapshots = OSAllocatedUnfairLock<[[FinishedInMemorySpan]]>(initialState: [])

    /// Makes a recorder over the spans of `context`.
    ///
    /// - Parameter context: The capture of the test.
    init(context: TelemetryCapture.Context) {
        self.context = context
    }

    /// The flush to give to the exit path: it keeps the spans that ended.
    var flush: @Sendable () async -> Void {
        { [self] in
            let spans = context.spans
            snapshots.withLock { $0.append(spans) }
        }
    }

    /// The number of flushes.
    var count: Int {
        snapshots.withLock { $0.count }
    }

    /// The run span in the first flush, or `nil` when the first flush did
    /// not have it.
    var runSpan: FinishedInMemorySpan? {
        snapshots.withLock { $0.first?.first { $0.operationName == CLIExitPath.spanName } }
    }
}

/// The errors of the fixtures of this suite.
private enum CLITelemetryShutdownTestsError: Error {
    /// The resolve of the stub fails, thus the run stops before a model loads.
    case injectedResolveFailure

    /// The command throws this error with the given text.
    case thrown(String)
}
