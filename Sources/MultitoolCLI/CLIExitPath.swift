import Foundation
import Tracing

/// A signal that stops a run of `multitool-cli` before its command returns.
///
/// The process exits with the conventional code of a signal:
/// 128 + the signal number.
public enum CLIStopSignal: CaseIterable, Sendable {
    /// `SIGINT`, for example Control-C in a terminal. The exit code is 130.
    case interrupt

    /// `SIGTERM`, for example from `kill` or from a process manager. The exit
    /// code is 143.
    case terminate

    /// The value that the shell adds to the signal number to make the exit
    /// code of a process that a signal stopped.
    private static let signalExitCodeBase: Int32 = 128

    /// The POSIX number of the signal.
    public var number: Int32 {
        switch self {
        case .interrupt: SIGINT
        case .terminate: SIGTERM
        }
    }

    /// The exit code of a run that this signal stopped: 128 + ``number``.
    public var exitCode: Int32 {
        Self.signalExitCodeBase + number
    }

    /// Starts to watch each stop signal, and gives each one that comes.
    ///
    /// Call it one time, in the process entry point. Each signal gets a
    /// handler that does nothing, and a dispatch source that reads the
    /// signal. The handler stops the default action, which ends the process
    /// before the exporters flush. The handler is not `SIG_IGN`: a child
    /// process keeps an ignored signal after `exec`, and a child process
    /// that ignores `SIGTERM` does not stop when its parent asks. A handler
    /// goes back to the default action at `exec`.
    ///
    /// - Returns: A stream that gives each stop signal that the process gets.
    public static func makeSignalStream() -> AsyncStream<CLIStopSignal> {
        let (signals, continuation) = AsyncStream<CLIStopSignal>.makeStream()
        let sources = allCases.map { stop in
            signal(stop.number) { _ in }
            let source = DispatchSource.makeSignalSource(signal: stop.number, queue: .global())
            source.setEventHandler { continuation.yield(stop) }
            source.resume()
            return source
        }
        // The stream keeps the sources, and cancels them at its end.
        continuation.onTermination = { _ in
            for source in sources {
                source.cancel()
            }
        }
        return signals
    }
}

/// The cancel actions of the session that a run holds.
///
/// A run adds the cancel of its session when it makes the session. A stop
/// signal runs each action one time. An action that the run adds after the
/// cancel runs at once.
public actor CLIRunCancellation {
    /// The actions that the next ``cancel()`` runs.
    private var actions: [@Sendable () async -> Void] = []

    /// Whether ``cancel()`` ran.
    private var isCancelled = false

    /// Makes a cancellation with no action.
    public init() {}

    /// Adds an action that ``cancel()`` runs.
    ///
    /// - Parameter action: The action, for example the cancel of a session.
    ///   It runs at once when ``cancel()`` already ran.
    public func onCancel(_ action: @escaping @Sendable () async -> Void) async {
        guard !isCancelled else {
            await action()
            return
        }
        actions.append(action)
    }

    /// Runs each action one time, in the order they were added.
    public func cancel() async {
        isCancelled = true
        let pending = actions
        actions = []
        for action in pending {
            await action()
        }
    }
}

/// The one exit path of `multitool-cli`.
///
/// Each end of a run goes through ``run(stoppingOn:_:)``: each exit code of
/// the command, an error that the command throws, and a stop signal. The path
/// does these steps in this order:
///
/// 1. It ends the run span, ``spanName``, with the exit code in
///    ``exitCodeAttribute``.
/// 2. It flushes the exporters, for ``flushBound`` at most.
/// 3. It gives the exit code. The entry point then exits with it.
///
/// An OTLP exporter sends its records in batches from a background task, and
/// a process exit does not flush a batch. Thus without step 2 the last spans
/// of a run are lost.
///
/// The bound is a race of this type, and not the
/// `maximumGracefulShutdownDuration` of swift-service-lifecycle. That setting
/// changes a slow graceful shutdown into a cancellation, and its
/// `maximumCancellationDuration` changes a slow cancellation into a
/// `fatalError`, which would change the exit code of the run.
public struct CLIExitPath: Sendable {
    /// The name of the span that holds the whole run.
    public static let spanName = "multitool-cli.run"

    /// The span attribute that holds the exit code of the run. The name is
    /// the OpenTelemetry semantic convention for a process exit code.
    static let exitCodeAttribute = "process.exit.code"

    /// The number of seconds in ``flushBound``.
    private static let flushBoundSeconds = 2

    /// The longest time that the exporters get to flush, and that a stopped
    /// command gets to end. A collector that is not there, or that never
    /// answers, must not hold the process.
    public static let flushBound: Duration = .seconds(flushBoundSeconds)

    /// The flush of the exporters, or `nil` when no exporter was made.
    private let flush: (@Sendable () async -> Void)?

    /// The longest time of each wait of the path.
    private let bound: Duration

    /// Where the line of an error that the command throws goes.
    private let errorOutput: @Sendable (String) -> Void

    /// The clock that each wait of ``bound`` sleeps on.
    ///
    /// A host always gets the real clock. A test gives a clock that it opens
    /// on command, thus the test reads the bound that the path armed, and no
    /// real time.
    private let clock: any Clock<Duration>

    /// Makes the exit path.
    ///
    /// - Parameters:
    ///   - flush: The flush of the exporters. `nil` means that no exporter
    ///     was made, and then the path does not wait.
    ///   - bound: The longest time of each wait. The default is
    ///     ``flushBound``.
    ///   - errorOutput: Where the line of an error that the command throws
    ///     goes. The default is `CLIRunner.standardErrorOutput`.
    public init(
        flush: (@Sendable () async -> Void)?,
        bound: Duration = flushBound,
        errorOutput: @escaping @Sendable (String) -> Void = CLIRunner.standardErrorOutput
    ) {
        self.init(flush: flush, bound: bound, errorOutput: errorOutput, clock: ContinuousClock())
    }

    /// Makes the exit path whose waits sleep on `clock` — the initializer the
    /// public one forwards to.
    ///
    /// Internal: a host has no reason to move the clock of the bound, and the
    /// public initializer gives the real clock. A test calls this one through
    /// `@testable import`, with a clock it opens on command.
    ///
    /// - Parameters:
    ///   - flush: See the public initializer.
    ///   - bound: See the public initializer.
    ///   - errorOutput: See the public initializer.
    ///   - clock: The clock that each wait of `bound` sleeps on.
    init(
        flush: (@Sendable () async -> Void)?,
        bound: Duration,
        errorOutput: @escaping @Sendable (String) -> Void,
        clock: any Clock<Duration>
    ) {
        self.flush = flush
        self.bound = bound
        self.errorOutput = errorOutput
        self.clock = clock
    }

    /// Runs `command` in the run span, and flushes the exporters at its end.
    ///
    /// When a stop signal comes first, the path cancels the session through
    /// the ``CLIRunCancellation`` of the command, cancels the task of the
    /// command, and gives the command the bound of this path to end. The exit
    /// code is then ``CLIStopSignal/exitCode``. The run span ends in each
    /// case, also when the command does not end in the bound.
    ///
    /// - Parameters:
    ///   - signals: The stop signals of the process.
    ///   - command: The work of the run. It gets the cancellation of the run,
    ///     and it gives the exit code.
    /// - Returns: The exit code of the run, after the flush.
    public func run(
        stoppingOn signals: AsyncStream<CLIStopSignal>,
        _ command: @escaping @Sendable (CLIRunCancellation) async throws -> Int32
    ) async -> Int32 {
        let code = await InstrumentationSystem.tracer.withSpan(Self.spanName, ofKind: .internal) { span in
            let code = await runToEnd(command, stoppingOn: signals)
            span.attributes[Self.exitCodeAttribute] = Int64(code)
            if code != CLIRunner.ExitCode.success {
                span.setStatus(SpanStatus(code: .error))
            }
            return code
        }
        if let flush {
            await Self.wait(atMost: bound, on: clock, for: flush)
        }
        return code
    }

    /// Runs `command` until it returns or a stop signal comes.
    ///
    /// - Parameters:
    ///   - command: The work of the run.
    ///   - signals: The stop signals of the process.
    /// - Returns: The exit code of the command, or of the stop signal.
    private func runToEnd(
        _ command: @escaping @Sendable (CLIRunCancellation) async throws -> Int32,
        stoppingOn signals: AsyncStream<CLIStopSignal>
    ) async -> Int32 {
        let cancellation = CLIRunCancellation()
        let commandTask = Task { await exitCode(of: command, cancellation: cancellation) }
        switch await Self.firstEnd(of: commandTask, or: signals) {
        case .returned(let code):
            return code
        case .stopped(let stop):
            await cancellation.cancel()
            commandTask.cancel()
            await Self.wait(atMost: bound, on: clock) { _ = await commandTask.value }
            return stop.exitCode
        }
    }

    /// Runs `command`, and changes an error that it throws into an exit code.
    ///
    /// - Parameters:
    ///   - command: The work of the run.
    ///   - cancellation: The cancellation of the run.
    /// - Returns: The exit code of the command, or
    ///   `CLIRunner.ExitCode.unavailable` when it throws. A thrown error also
    ///   writes one line to the error output.
    private func exitCode(
        of command: @Sendable (CLIRunCancellation) async throws -> Int32,
        cancellation: CLIRunCancellation
    ) async -> Int32 {
        do {
            return try await command(cancellation)
        } catch {
            errorOutput("\(cliErrorPrefix) \(error)")
            return CLIRunner.ExitCode.unavailable
        }
    }

    /// How a run ended first.
    private enum RunEnd: Sendable {
        /// The command returned this exit code.
        case returned(Int32)

        /// This stop signal came before the command returned.
        case stopped(CLIStopSignal)
    }

    /// Waits for the first of two events: the command returns, or a stop
    /// signal comes.
    ///
    /// - Parameters:
    ///   - commandTask: The task of the command.
    ///   - signals: The stop signals of the process.
    /// - Returns: The first event.
    private static func firstEnd(
        of commandTask: Task<Int32, Never>, or signals: AsyncStream<CLIStopSignal>
    ) async -> RunEnd {
        let (ends, continuation) = AsyncStream<RunEnd>.makeStream()
        let returned = Task { continuation.yield(.returned(await commandTask.value)) }
        let stopped = Task {
            var stops = signals.makeAsyncIterator()
            if let stop = await stops.next() {
                continuation.yield(.stopped(stop))
            }
        }
        defer {
            returned.cancel()
            stopped.cancel()
        }
        var first = ends.makeAsyncIterator()
        if let end = await first.next() {
            return end
        }
        // The stream never finishes, and the returned task always yields. Thus
        // this line reads the value of the command, which is also the truth
        // when the stream gave nothing.
        return .returned(await commandTask.value)
    }

    /// Runs `work`, and waits until it ends or `bound` ends.
    ///
    /// The work goes on when the bound ends first. The caller exits the
    /// process soon after, and that ends the work.
    ///
    /// - Parameters:
    ///   - bound: The longest time to wait.
    ///   - clock: The clock that the wait of `bound` sleeps on.
    ///   - work: The work to wait for.
    private static func wait(
        atMost bound: Duration, on clock: any Clock<Duration>,
        for work: @escaping @Sendable () async -> Void
    ) async {
        let (ends, continuation) = AsyncStream<Void>.makeStream()
        let working = Task {
            await work()
            continuation.yield()
        }
        let timing = Task {
            try? await clock.sleep(for: bound)
            continuation.yield()
        }
        defer {
            working.cancel()
            timing.cancel()
        }
        var first = ends.makeAsyncIterator()
        _ = await first.next()
    }
}
