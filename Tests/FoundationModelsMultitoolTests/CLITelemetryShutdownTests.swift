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
@Suite("CLITelemetryShutdown")
struct CLITelemetryShutdownTests {
    /// The time bound that the tests give to the exit path. It is short, thus
    /// a test of the bound ends soon.
    private static let testBound: Duration = .milliseconds(200)

    /// A time much longer than ``testBound``. A flush or a command that does
    /// not end by itself waits this long.
    private static let longWait: Duration = .seconds(60)

    /// The longest time a test of the bound lets the exit path take. It is
    /// much shorter than ``longWait`` and much longer than ``testBound``.
    private static let boundedEnd: Duration = .seconds(10)

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

            let code = await CLIExitPath(flush: flushes.flush, bound: Self.testBound)
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

            let code = await CLIExitPath(flush: flushes.flush, bound: Self.testBound, errorOutput: errorOutput.append)
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

            let code = await CLIExitPath(flush: flushes.flush, bound: Self.testBound)
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

    @Test("a flush that does not end holds the exit path for the bound only")
    func flushThatDoesNotEndIsBounded() async {
        let clock = ContinuousClock()
        let start = clock.now

        let code = await CLIExitPath(flush: { try? await Task.sleep(for: Self.longWait) }, bound: Self.testBound)
            .run(stoppingOn: Self.noStopSignals()) { _ in CLIRunner.ExitCode.answerFailed }

        #expect(code == CLIRunner.ExitCode.answerFailed)
        #expect(clock.now - start < Self.boundedEnd)
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
