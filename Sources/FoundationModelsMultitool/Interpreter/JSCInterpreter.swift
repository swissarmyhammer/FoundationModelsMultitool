import Foundation
import JavaScriptCore
import Logging
import Metrics
import os

// MARK: - Private JSC watchdog symbols

// `JSContextGroupSetExecutionTimeLimit` / `JSContextGroupClearExecutionTimeLimit`
// are declared in JavaScriptCore's `JSContextRefPrivate.h`, which — per the
// plan's pin — is confirmed **not** part of the public SDK header set shipped
// under `JavaScriptCore.framework/Headers` (only `JSContextRef.h`, the public
// counterpart, ships there). `import JavaScriptCore` alone does not surface
// them, so we declare the prototypes ourselves, mirroring the WebKit source
// (https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextRefPrivate.h).
//
// **Pin (M1), confirmed on the OS-27 SDK (Xcode 27, Swift 6.4):** both
// symbols remain `JS_EXPORT` (default visibility) and are listed in
// `JavaScriptCore.framework/JavaScriptCore.tbd`
// (`_JSContextGroupSetExecutionTimeLimit`, `_JSContextGroupClearExecutionTimeLimit`),
// the linkable stub the linker resolves imported-framework symbols against —
// so an extern declaration links cleanly with no extra linker flags, and
// `swift build`/`swift test` confirm it at both compile and run time (see
// `JSCInterpreterTests.infiniteLoopTerminatedByWatchdog`). The documented
// fallback (a dedicated thread that abandons its `JSContext` on timeout) was
// **not** needed.

/// Mirrors `JSShouldTerminateCallback` from `JSContextRefPrivate.h`: invoked
/// after a context group's execution time limit has been exceeded. Per the
/// header's own documented contract, returning `true` terminates the running
/// script and `false` grants it one more time-limit window — **however**,
/// that "one more window" half of the contract does not hold on the OS-27
/// SDK actually measured here; see `WatchdogState`'s documentation for what
/// was observed and why this codebase re-arms the limit itself instead of
/// relying on it.
private typealias JSShouldTerminateCallback = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool

@_silgen_name("JSContextGroupSetExecutionTimeLimit")
private func JSContextGroupSetExecutionTimeLimit(
    _ group: JSContextGroupRef,
    _ limit: Double,
    _ callback: JSShouldTerminateCallback?,
    _ context: UnsafeMutableRawPointer?
)

@_silgen_name("JSContextGroupClearExecutionTimeLimit")
private func JSContextGroupClearExecutionTimeLimit(_ group: JSContextGroupRef)

/// Per-run watchdog state, threaded through the `@convention(c)` callback via
/// an `Unmanaged` raw pointer — a C function pointer cannot capture Swift
/// state directly, so this is how the callback reports back its decision to
/// the Swift code waiting on `evaluateScript` to return.
///
/// **M10 design note, empirically pinned against observed behavior on the
/// OS-27 SDK (Xcode 27, Swift 6.4).** Two distinct experiments, isolated from
/// the Sandbox/HostFunction/Interpreter machinery (raw `JSContextGroupCreate`
/// + a bare `@convention(c)` callback against `while (true) {}`):
///
/// 1. Re-arming a *running* group's limit via a second
///    `JSContextGroupSetExecutionTimeLimit(group, 0, ...)` call from
///    *another thread* does **not** force early termination — a run armed
///    with a 10s limit and re-armed to `0` after 200ms from a background
///    thread still ran for the full ~10s before terminating.
/// 2. Returning `false` from `JSShouldTerminateCallback` — the documented
///    contract for "not yet, give me one more window of the same
///    duration" — does **not** actually reschedule anything on this SDK:
///    armed with a 0.1s poll interval, the callback fires exactly **once**,
///    and if it returns `false` the script then runs **unchecked forever**
///    (measured directly: 8+ real seconds with zero further callback
///    invocations, for a script that should have terminated within ~0.5s).
///    This is what caused the original M10 diagnostic
///    (`diagnosticCancellationForcesEarlyTermination`) to hang.
///
/// What **does** work, also measured directly: calling
/// `JSContextGroupSetExecutionTimeLimit` again — with a fresh short
/// deadline — *synchronously, from within the callback itself*, on the same
/// thread, *before* that callback returns `false`. Doing this on every
/// invocation that decides "not yet" reliably produces one callback
/// invocation per `watchdogPollInterval` (5 invocations at ~100ms spacing,
/// clean termination at ~0.5s in the isolated repro) for as long as the
/// script keeps running. So the group is armed at `makeSandbox` time with a
/// short, fixed poll interval (`JSCInterpreter.watchdogPollInterval`) — far
/// below any realistic configured `timeLimit` — and this state's own
/// `shouldTerminate()` (called from `jscTerminateCallback` every time that
/// poll interval elapses) re-arms the *same* short interval itself whenever
/// it decides not to terminate yet, rather than relying on JSC's own
/// "return false" contract. `shouldTerminate()` is what actually decides, in
/// Swift, whether the *real* configured deadline is reached or
/// `isCancelled` has reported `true` — this state is effectively the *real*
/// watchdog, with JSC's own limit reduced to a self-renewing polling tick.
///
/// JSC's documentation does not commit to which thread invokes
/// `JSShouldTerminateCallback` (in practice it is checked from the
/// interpreter loop itself, but that is not a guarantee this code should
/// lean on) — so the recorded cause is lock-protected rather than a plain
/// `Bool`/enum, keeping correctness independent of that unstated
/// thread-affinity detail.
///
/// `@unchecked`: `group` is an opaque C pointer (`OpaquePointer` itself
/// isn't `Sendable`), used only to re-issue calls into the thread-safe JSC C
/// API — it's never dereferenced or mutated by this type. Every other
/// stored property is either immutable-and-`Sendable` or, for the one
/// genuinely mutable piece of state (`cause`), guarded by `lock`.
private final class WatchdogState: @unchecked Sendable {
    /// Why this state decided to terminate — recorded once; first cause
    /// wins, since a run ends with one error only.
    fileprivate enum Cause: Sendable {
        /// The run exceeded its configured wall-clock time limit.
        case timedOut
        /// The calling `Task` was cancelled before the real time limit
        /// elapsed.
        case cancelled
    }

    private let lock: OSAllocatedUnfairLock<Cause?>

    /// The *real* configured time limit this state enforces, as a deadline on
    /// the watchdog clock — independent of whatever short poll interval the
    /// group's own `JSContextGroupSetExecutionTimeLimit` was actually armed
    /// with (see this type's documentation). It is armed when this state is
    /// made.
    private let deadline: WatchdogDeadline

    /// Polled once per `jscTerminateCallback` invocation — the M10
    /// cancellation hook.
    private let isCancelled: @Sendable () -> Bool

    /// The group this state's watchdog is armed against — needed so
    /// `shouldTerminate()` can re-arm the next short poll window itself (see
    /// this type's documentation for why that self-re-arm, rather than
    /// JSC's own "return false" contract, is what actually works).
    private let group: JSContextGroupRef

    /// The short poll interval re-armed on every "not yet" decision — see
    /// `JSCInterpreter.watchdogPollInterval`.
    private let pollInterval: TimeInterval

    /// Arms a new watchdog state for one run.
    ///
    /// - Parameters:
    ///   - group: the context group this state's watchdog polls against.
    ///   - pollInterval: the short window re-armed on every callback
    ///     invocation that isn't yet ready to terminate.
    ///   - deadline: the real ceiling this state enforces, already armed.
    ///   - isCancelled: polled once per callback invocation to detect
    ///     external (M10 `Task`) cancellation.
    fileprivate init(
        group: JSContextGroupRef,
        pollInterval: TimeInterval,
        deadline: WatchdogDeadline,
        isCancelled: @escaping @Sendable () -> Bool
    ) {
        self.lock = OSAllocatedUnfairLock(initialState: nil)
        self.deadline = deadline
        self.group = group
        self.pollInterval = pollInterval
        self.isCancelled = isCancelled
    }

    /// Stops the deadline timer of this run. The sandbox calls it at
    /// teardown, thus no timer outlives its run.
    fileprivate func disarm() {
        deadline.disarm()
    }

    /// The recorded cause, or `nil` if this state hasn't decided to
    /// terminate yet.
    fileprivate var cause: Cause? {
        lock.withLock { $0 }
    }

    /// Called from `jscTerminateCallback` every time the group's short poll
    /// interval elapses. Decides — and records — whether the run should
    /// actually terminate now; when not, re-arms the same short window
    /// itself (see this type's documentation for why that self-re-arm is
    /// required — JSC's own "return `false`" contract does not reschedule
    /// anything on this SDK).
    ///
    /// - Returns: `true` (terminate) the first time either `isCancelled`
    ///   reports `true` or the clock reached the real deadline, recording which
    ///   caused it; `false` (having just re-armed one more poll-interval
    ///   window) otherwise.
    fileprivate func shouldTerminate() -> Bool {
        if isCancelled() {
            recordCause(.cancelled)
            return true
        }
        if deadline.isReached {
            recordCause(.timedOut)
            return true
        }
        rearm()
        return false
    }

    /// Records why this run is terminating, keeping whichever cause reached
    /// this method first.
    ///
    /// A run reports one cause (see `cause`), so a later decision must never
    /// overwrite the one already recorded. The run itself calls this too,
    /// from its job queue, when its wall-clock timer fires or a cancellation
    /// reaches it while no job executes JS: then no callback is there to
    /// decide.
    ///
    /// - Parameter cause: why the run terminates now.
    fileprivate func recordCause(_ cause: Cause) {
        lock.withLock { if $0 == nil { $0 = cause } }
    }

    /// Re-arms the group's execution time limit with a fresh short window,
    /// synchronously, from within the terminate callback itself — the
    /// mechanism empirically confirmed (see this type's documentation) to
    /// actually reschedule another `jscTerminateCallback` invocation on this
    /// SDK, unlike returning `false` alone.
    private func rearm() {
        let statePointer = Unmanaged.passUnretained(self).toOpaque()
        JSContextGroupSetExecutionTimeLimit(group, pollInterval, jscTerminateCallback, statePointer)
    }
}

/// The watchdog callback itself: defers the actual terminate/continue
/// decision to `WatchdogState.shouldTerminate()` — see that type's
/// documentation for why the group is armed with a short, fixed poll
/// interval rather than the run's real configured time limit.
private func jscTerminateCallback(_: JSContextRef?, _ info: UnsafeMutableRawPointer?) -> Bool {
    guard let info else { return true }
    return Unmanaged<WatchdogState>.fromOpaque(info).takeUnretainedValue().shouldTerminate()
}

/// The time limit of one run, as a deadline on the watchdog clock.
///
/// The deadline is reached by one of two paths:
///
/// 1. **The timer.** A task sleeps on the clock until the deadline, then
///    marks the deadline as reached and calls `onReached`. Thus the deadline
///    is an event of the clock. A run uses `onReached` as its wall-clock
///    timer: it ends a run that waits for a call past its time limit, while
///    no job executes JS. A clock that a test controls ends the sleep when
///    the test lets it, and the run ends at that event and at no real time
///    (`JSCInterpreter.init(timeLimit:watchdogClock:)`).
/// 2. **The reading of `now`.** Each check of the CPU watchdog also compares
///    the current instant of the clock with the deadline. The JS thread
///    makes the checks, thus this path needs no other thread. It is the
///    backstop when every thread of the cooperative pool is busy and the
///    timer cannot run.
private final class WatchdogDeadline: Sendable {
    /// Whether the clock reached the deadline, by either path.
    private let hasPassed: @Sendable () -> Bool

    /// The task that sleeps until the deadline. ``disarm()`` cancels it.
    private let timer: Task<Void, Never>

    /// Arms the deadline `timeLimit` after the current instant of `clock`.
    ///
    /// - Parameters:
    ///   - timeLimit: the time from now to the deadline.
    ///   - clock: the clock that the deadline is on.
    ///   - onReached: called one time, from the timer task, when the timer
    ///     reaches the deadline. It is not called after ``disarm()``.
    init<WatchdogClock: Clock<Duration>>(
        timeLimit: Duration,
        on clock: WatchdogClock,
        onReached: @escaping @Sendable () -> Void
    ) {
        let deadline = clock.now.advanced(by: timeLimit)
        let timerFired = OSAllocatedUnfairLock(initialState: false)
        hasPassed = { timerFired.withLock { $0 } || clock.now >= deadline }
        timer = Task {
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                // Cancelled by `disarm()`: the run ended first.
                return
            }
            timerFired.withLock { $0 = true }
            onReached()
        }
    }

    /// Whether the clock reached the deadline.
    var isReached: Bool {
        hasPassed()
    }

    /// Cancels the timer. A cancelled timer does not mark the deadline.
    func disarm() {
        timer.cancel()
    }
}

/// JavaScriptCore-backed `Interpreter`.
///
/// Each `run` gets a brand-new `JSContextGroup`/`JSContext` — deny-by-default,
/// reachable only from the standard ECMAScript globals JSC ships with
/// (`Math`, `JSON`, `Array`, …), the injected `console`, and whatever
/// `HostFunction`s/`AsyncHostFunction`s were installed for that run. Nothing
/// set by one run (a global, a host function) is visible to the next.
///
/// ## The event loop
///
/// A run executes JS only in short **jobs**, as the event loop of a browser
/// does (task `^cf57dtd`). Between two jobs a run is only data in memory —
/// its `JSContext`, its pending promises, and its `Run` record — and it
/// holds no thread. Thus a snippet that waits 95 seconds for a slow
/// `tools.*` call costs one context in memory for those 95 seconds, and no
/// thread. No number limits how many runs can wait at the same time: like
/// browser tabs, scores of waiting runs cost scores of contexts in memory.
///
/// There are three kinds of job:
///
/// - **The start job** makes the sandbox, installs the host functions,
///   evaluates the snippet, and drains the microtasks. It does not wait for
///   the promises.
/// - **A settle job** runs when the Swift `Task` of an
///   `AsyncHostFunction` call completes. It resolves or rejects the promise
///   of that call and drains the microtasks, which can start more calls.
/// - **The finish step** ends each job. When no bridge promise is pending,
///   the run settles: it records its result or its error, releases its
///   context, and resumes the caller of ``run(code:installing:installingAsync:)``.
///
/// **The job queue of each run is a private serial `DispatchQueue`, with no
/// constrained target.** Every touch of a run's `JSContext` and `JSValue`s
/// occurs in a job on that queue, so JSC is never used from two threads at
/// the same time. A queue made with `DispatchQueue(label:)` targets an
/// overcommit root queue: the kernel gives it a thread when it has a job,
/// also when every CPU is busy, and it holds no thread when it has no job. A
/// constrained global queue does not do this. `GrepCode.run` of
/// FoundationModelsCodeContext adds one CPU-bound child task for each index
/// chunk at the priority `.high`, and while such a grep ran, the kernel gave
/// `DispatchQueue.global(qos: .userInitiated)` no thread. A snippet sent
/// there did not start, and a snippet with no `await` at all went pending
/// behind the grep. Only a run that has a job ready uses a thread, and a job
/// is short, so no number in this type sets the concurrency.
///
/// `HostFunction` calls run synchronously, inline, in the job that calls
/// them. `AsyncHostFunction` calls return a JS `Promise` backed by its own
/// Swift `Task` on the cooperative pool, and no job waits for that `Task` —
/// eventplan.md "Async JavaScript": "We remove the v1 blocking bridge... We
/// do not build a semaphore-based park mechanism and its thread guards only
/// to delete them later."
///
/// Two clocks bound a run. The CPU watchdog (`WatchdogState`) stops a job
/// that executes JS for too long, such as `while (true) {}`. A wall-clock
/// timer stops a run that waits past its time limit for a call that does not
/// complete: when it fires, it puts a job on the job queue. Both read one
/// deadline (`WatchdogDeadline`) on the watchdog clock of the interpreter.
public final class JSCInterpreter: Interpreter {
    /// How often `WatchdogState.shouldTerminate()` is invoked while a job
    /// executes JS — see that type's documentation for why this, not the
    /// run's real configured `timeLimit`, is the value actually armed via
    /// `JSContextGroupSetExecutionTimeLimit`. 20ms bounds the latency of a
    /// cancellation that arrives while JS executes well below any realistic
    /// `timeLimit`, at negligible overhead. A run that executes no JS is not
    /// polled at all.
    private static let watchdogPollInterval: TimeInterval = 0.02

    /// Wall-clock ceiling for a single `run`, enforced by `WatchdogState`.
    private let timeLimit: TimeInterval

    /// The clock that the deadline of each run is on (see
    /// `WatchdogDeadline`). The CPU watchdog and the wall-clock timer of a
    /// run both use this one deadline.
    ///
    /// A host always gets the continuous clock. A test gives a clock that it
    /// opens on command. Thus the watchdog fires when the test lets it, and a
    /// busy machine cannot end a run that the test does not end (web.md §
    /// "Testing": no test checks the speed of the machine).
    private let watchdogClock: any Clock<Duration>

    /// The label the job queue of every run carries (see the type doc for
    /// why each run has a queue of its own). Shared rather than made unique
    /// per run: it names the role in a stack trace, and no dispatch behavior
    /// depends on it being distinct.
    private static let queueLabel = "FoundationModelsMultitool.JSCInterpreter"

    /// Creates a JavaScriptCore-backed interpreter that enforces the given
    /// per-run time limit.
    ///
    /// The default applies to an interpreter constructed without an explicit
    /// `timeLimit` and run directly. Standing alone like that, this watchdog
    /// is the only clock in play — there is no `runCode` wait clock for it to
    /// race, because the background path belongs to a `MultiTool` mount.
    ///
    /// It does not survive that mount. `MultiTool.init` arms every
    /// interpreter it runs — the sandbox it builds for itself, and one a
    /// caller hands it as its `interpreter:`, alike — with
    /// `MultiToolConfiguration.executionTimeLimit` through
    /// ``withTimeLimit(_:)``, so under a `MultiTool` the watchdog always
    /// fires at the configured ceiling, whatever this interpreter was
    /// constructed with. `MultiTool.timeout(from:)` answers that same ceiling
    /// as the per-call work bound (see that method's own documentation), so
    /// the watchdog and the engine's clock come from one value. An injecting
    /// caller does not have to align the two.
    ///
    /// - Parameter timeLimit: seconds a single `run` may execute before the
    ///   watchdog terminates it. Defaults to a ceiling sized for a
    ///   directly-constructed interpreter running a self-contained snippet;
    ///   a `MultiTool` replaces it with its own configured ceiling.
    public convenience init(timeLimit: TimeInterval = 5.0) {
        self.init(timeLimit: timeLimit, watchdogClock: ContinuousClock())
    }

    /// Creates a JavaScriptCore-backed interpreter whose watchdog deadline is
    /// on `watchdogClock` — the initializer every other one forwards to.
    ///
    /// - Parameters:
    ///   - timeLimit: See ``init(timeLimit:)``.
    ///   - watchdogClock: The clock that the deadline of each run is on — see
    ///     ``watchdogClock``. ``withTimeLimit(_:)`` keeps it.
    init(timeLimit: TimeInterval, watchdogClock: any Clock<Duration>) {
        self.timeLimit = timeLimit
        self.watchdogClock = watchdogClock
    }

    /// Returns a `JSCInterpreter` whose watchdog is armed with `seconds` in
    /// place of this one's own limit.
    ///
    /// A fresh instance rather than a mutation: the limit is the whole of
    /// this type's state, and the caller that constructed this interpreter
    /// keeps the ceiling it asked for. Every other piece of a run's state is
    /// created per `run` anyway (see this type's own documentation), so the
    /// returned interpreter differs in nothing but the ceiling. It keeps the
    /// watchdog clock of this one.
    ///
    /// - Parameter seconds: seconds a single `run` of the returned
    ///   interpreter may execute before its watchdog terminates it.
    /// - Returns: an interpreter that runs exactly as this one does, armed
    ///   with `seconds`.
    public func withTimeLimit(_ seconds: TimeInterval) -> any Interpreter {
        JSCInterpreter(timeLimit: seconds, watchdogClock: watchdogClock)
    }

    /// Runs `code` as jobs on a job queue of its own, in a fresh, isolated
    /// sandbox with `installing`/`installingAsync` made available as
    /// globals — the sole `run` requirement of `Interpreter` this type
    /// implements; `run(code:installing:)` reaches this one through
    /// `Interpreter`'s own default conformance.
    ///
    /// The caller suspends until the run settles, and no thread waits for
    /// it meanwhile (see the event-loop documentation of this type).
    /// Cancelling the calling `Task` cancels the run: a job that executes JS
    /// stops at the next watchdog poll, and the `Task` of each pending
    /// `AsyncHostFunction` call is cancelled at once.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run. A top-level `return` is
    ///     supported — the snippet does not need to be an IIFE itself.
    ///   - installing: synchronous host functions to expose as globals for
    ///     this run only.
    ///   - installingAsync: asynchronous host functions to expose as
    ///     globals for this run only — see the event-loop documentation of
    ///     this type for the jobs that settle them.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `CancellationError` if the calling `Task` was cancelled
    ///   before the run otherwise completed; `InterpreterError` for a
    ///   thrown/syntax exception, a timeout, or a floating rejection.
    public func run(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction]
    ) async throws -> InterpreterResult {
        // The job queue has no task-local value, thus the logger and the
        // metrics factory of the calling task are read here and given to the
        // run, which binds them again around each job. The start and the end
        // of the run are recorded here, in the calling task, where every
        // task-local value of the caller is still bound.
        let telemetry = RunTelemetry(logger: MultitoolTelemetry.logger, metricsFactory: MetricsSystem.factory)
        let start = ContinuousClock.now
        telemetry.recordStart(characterCount: code.count)
        let run = Run(
            snippet: Run.Snippet(code: code, installing: installing, installingAsync: installingAsync),
            timeLimit: timeLimit,
            watchdogClock: watchdogClock,
            telemetry: telemetry
        )
        do {
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    run.start(resuming: continuation)
                }
            } onCancel: {
                run.cancel()
            }
            telemetry.recordEnd(of: .success(result), since: start)
            return result
        } catch {
            telemetry.recordEnd(of: .failure(error), since: start)
            throw error
        }
    }

    /// Parses `code` — wrapped exactly as `run` wraps it — in a fresh
    /// `JSContext` with nothing installed, and throws when it does not parse.
    ///
    /// `JSCheckScriptSyntax` is JavaScriptCore's own parser entry point: it
    /// reports a `SyntaxError` for source it cannot parse and evaluates
    /// nothing at all, so an infinite loop parses instantly and a call to a
    /// global that was never installed parses too. That is the whole point —
    /// this answers "does this source parse", nothing more.
    ///
    /// - Parameter code: the JavaScript source to parse.
    /// - Throws: `InterpreterError` of kind `.exception`, carrying the
    ///   parser's own message and the line it blames, when `code` does not
    ///   parse.
    public func checkSyntax(of code: String) throws {
        try Self.parse(code: code)
    }

    // MARK: - Run

    /// Wraps a snippet in the async IIFE every evaluation of it runs inside.
    ///
    /// Wrapping in an *async* IIFE is what makes both a top-level `return`
    /// and a top-level `await` legal — models with async-JS priors routinely
    /// write `await tools.getWeather(...)`, and under a plain IIFE that is a
    /// bare syntax error whose message never mentions `await` ("Unexpected
    /// identifier 'tools'"), an unrecoverable dead end for the model. An
    /// outer plain IIFE holds the outcome object as a local (never a global —
    /// the sandbox's injected-global surface is pinned by `HardeningTests`)
    /// and returns it; the async IIFE's `.then` callbacks capture and mutate
    /// that same object. The whole prefix is prepended to the snippet's own
    /// first line (rather than on a line of its own) so every reported line
    /// number still matches the caller's original source 1:1. The settled
    /// result is readable by the time `evaluateScript` returns for any
    /// snippet whose awaits resolve without external events — host functions
    /// are synchronous, so their awaited results are already-settled values
    /// and JavaScriptCore drains the resulting microtasks when the
    /// evaluation's call stack empties.
    ///
    /// Shared by the start job of a `Run` and `parse(code:)` rather than written out at
    /// each: `checkSyntax(of:)` is only worth anything if it accepts and
    /// rejects exactly the sources `run` accepts and rejects, and one wrapper
    /// is what makes that true by construction.
    ///
    /// - Parameter code: the snippet source to wrap.
    /// - Returns: the wrapped source to evaluate or parse.
    private static func wrap(code: String) -> String {
        """
        (function(){ var outcome = {}; (async function(){\(code)
        })().then(function(v){ outcome.value = v; outcome.done = true; }, \
        function(e){ outcome.error = e; outcome.done = true; }); return outcome; })()
        """
    }

    /// Parses `wrap(code:)`'s output through `JSCheckScriptSyntax` and throws
    /// when the parser rejects it.
    ///
    /// The context is created solely to give the parser somewhere to allocate
    /// its exception value and to convert it back: nothing is installed into
    /// it, and nothing is evaluated in it.
    ///
    /// - Parameter code: the snippet source to parse.
    /// - Throws: `InterpreterError` of kind `.exception` when the parser
    ///   rejects the wrapped source.
    private static func parse(code: String) throws {
        guard let context = JSContext() else {
            throw InterpreterError(kind: .exception, message: "Failed to create a JSContext.")
        }
        let script = JSStringCreateWithCFString(wrap(code: code) as CFString)
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        guard !JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception) else { return }
        guard let exception, let reported = JSValue(jsValueRef: exception, in: context) else {
            throw InterpreterError(kind: .exception, message: unreadableExceptionMessage)
        }
        throw makeError(from: reported)
    }

    /// A single run's sandbox: the `JSContextGroup`/`JSContext` pair, the
    /// installed standard surface, the watchdog wired to that group, and the
    /// async host-function bridge's own state — bundled together so a `Run`
    /// does not have to juggle their lifetimes (and matching teardown order)
    /// inline.
    private struct Sandbox {
        fileprivate let group: JSContextGroupRef
        fileprivate let globalContextRef: JSGlobalContextRef
        fileprivate let context: JSContext
        fileprivate let consoleLines: ConsoleLines
        fileprivate let watchdogState: WatchdogState
        fileprivate let promiseRegistry: PromiseRegistry

        fileprivate func tearDown() {
            JSContextGroupClearExecutionTimeLimit(group)
            watchdogState.disarm()
            JSGlobalContextRelease(globalContextRef)
            JSContextGroupRelease(group)
        }
    }

    /// Creates a fresh, isolated sandbox with `installing` bound in and the
    /// watchdog armed — at `Self.watchdogPollInterval`, not `timeLimit`
    /// itself; see `WatchdogState`'s documentation for why. Cleans up any
    /// partially-created pieces on the way out if a later step fails.
    ///
    /// - Parameters:
    ///   - installing: the synchronous host functions to install.
    ///   - installingAsync: the asynchronous host functions to install.
    ///   - promiseRegistry: the registry the bridge records each promise of
    ///     an `installingAsync` call in.
    ///   - timeLimit: the real wall-clock ceiling the watchdog enforces.
    ///   - watchdogClock: the clock that the deadline of the run is on.
    ///   - isCancelled: read by the watchdog at each poll.
    ///   - onDeadline: called one time when the timer of the deadline fires
    ///     (see `WatchdogDeadline`). The sandbox arms the deadline only after
    ///     every step that can throw, thus a failed sandbox leaves no timer.
    /// - Returns: the sandbox, with its watchdog armed.
    /// - Throws: `InterpreterError` when JavaScriptCore cannot make the
    ///   group or the context.
    private static func makeSandbox(
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        promiseRegistry: PromiseRegistry,
        timeLimit: TimeInterval,
        watchdogClock: any Clock<Duration>,
        isCancelled: @escaping @Sendable () -> Bool,
        onDeadline: @escaping @Sendable () -> Void
    ) throws -> Sandbox {
        guard let group = JSContextGroupCreate() else {
            throw InterpreterError(kind: .exception, message: "Failed to create a JSContextGroup.")
        }
        guard let globalContextRef = JSGlobalContextCreateInGroup(group, nil) else {
            JSContextGroupRelease(group)
            throw InterpreterError(kind: .exception, message: "Failed to create a JSContext.")
        }
        guard let context = JSContext(jsGlobalContextRef: globalContextRef) else {
            JSGlobalContextRelease(globalContextRef)
            JSContextGroupRelease(group)
            throw InterpreterError(kind: .exception, message: "Failed to wrap the JSContext.")
        }

        let consoleLines = ConsoleLines()
        installConsole(into: context, capturing: consoleLines)
        for hostFunction in installing {
            install(hostFunction: hostFunction, into: context)
        }

        for asyncHostFunction in installingAsync {
            install(asyncHostFunction: asyncHostFunction, into: context, registry: promiseRegistry)
        }

        let watchdogState = WatchdogState(
            group: group,
            pollInterval: watchdogPollInterval,
            deadline: WatchdogDeadline(timeLimit: .seconds(timeLimit), on: watchdogClock, onReached: onDeadline),
            isCancelled: isCancelled
        )
        let statePointer = Unmanaged.passUnretained(watchdogState).toOpaque()
        JSContextGroupSetExecutionTimeLimit(group, watchdogPollInterval, jscTerminateCallback, statePointer)

        return Sandbox(
            group: group,
            globalContextRef: globalContextRef,
            context: context,
            consoleLines: consoleLines,
            watchdogState: watchdogState,
            promiseRegistry: promiseRegistry
        )
    }

    // MARK: - The event loop

    /// The logger and the metrics factory of the task that called `run`.
    ///
    /// The job queue of a run has no task-local value of its own, so the run
    /// binds these two again around each job. A host function that a job
    /// calls, and a `Task` that a job starts, then find the logger and the
    /// factory of the `runCode` call that started the run.
    private struct RunTelemetry: Sendable {
        /// The logger the run writes its start and end records to.
        let logger: Logging.Logger

        /// The factory the run records its duration to.
        let metricsFactory: any MetricsFactory

        /// Executes `job` with ``logger`` and ``metricsFactory`` bound as the
        /// task-local values.
        ///
        /// - Parameter job: the job to execute.
        func bound(_ job: () -> Void) {
            MultitoolTelemetry.$boundLogger.withValue(logger) {
                withMetricsFactory(metricsFactory) { job() }
            }
        }

        /// Logs the start of a run — plan.md M10: "at the seams — snippet
        /// start/end + duration." The record carries the size of the
        /// snippet, never its source, because the source can hold content.
        ///
        /// - Parameter characterCount: the size of the snippet source.
        func recordStart(characterCount: Int) {
            logger.log(
                .snippetStarted, level: .debug,
                metadata: [MultitoolTelemetry.LogMetadataKey.characterCount.rawValue: "\(characterCount)"])
        }

        /// Logs the end of a run (outcome + duration), and records its
        /// duration on the timer
        /// `MultitoolTelemetry.MetricName.interpreterRunDuration`, with the
        /// outcome as the one dimension. The record carries the type of an
        /// error, never its text, because the text can hold content.
        ///
        /// - Parameters:
        ///   - result: the outcome of the run.
        ///   - start: when the run started.
        func recordEnd(of result: Result<InterpreterResult, any Error>, since start: ContinuousClock.Instant) {
            let duration = ContinuousClock.now - start
            switch result {
            case .success:
                logger.log(.snippetFinished, level: .debug, metadata: MultitoolTelemetry.durationMetadata(since: start))
                MultitoolTelemetry.recordInterpreterRun(outcome: .succeeded, duration: duration, factory: metricsFactory)
            case .failure(let error):
                logger.log(
                    .snippetEnded, level: .debug,
                    metadata: MultitoolTelemetry.errorMetadata(of: error)
                        .merging(MultitoolTelemetry.durationMetadata(since: start)) { $1 })
                MultitoolTelemetry.recordInterpreterRun(
                    outcome: MultitoolTelemetry.interpreterOutcome(of: error), duration: duration,
                    factory: metricsFactory)
            }
        }
    }

    /// The exception the context's handler captured, if one was thrown out
    /// of a job. A box, because the handler is a closure the context keeps.
    private final class CapturedException {
        /// The captured exception, or `nil` while none was thrown.
        var value: JSValue?
    }

    /// The part of a run that exists from its start job to its finish step:
    /// the sandbox (with the deadline that is also the wall-clock timer of
    /// the run), the object the wrapped snippet reports its outcome into, and
    /// what the jobs record on the way.
    ///
    /// Confined to the job queue of its run, like every `JSValue` it holds.
    private final class LiveRun {
        /// The run's sandbox.
        let sandbox: Sandbox

        /// The exception the context's handler captured.
        let capturedException = CapturedException()

        /// The object `wrap(code:)` returns, into which the async IIFE writes
        /// `value`, `error` and `done`. `nil` until the start job evaluated
        /// the snippet, and `nil` after a syntax error.
        var outcome: JSValue?

        /// Each bridge-call rejection, in settle order, for the
        /// floating-rejection check of the finish step.
        var failures: [(name: String, message: String, consumed: ConsumedFlag?)] = []

        /// Creates the live part of a run.
        ///
        /// - Parameter sandbox: the run's sandbox, with its deadline armed.
        init(sandbox: Sandbox) {
            self.sandbox = sandbox
            sandbox.context.exceptionHandler = { [capturedException] _, exception in
                capturedException.value = exception
            }
        }

        /// Stops the timer, cancels each pending call, breaks the reference
        /// the context's exception handler holds, and releases the sandbox.
        func tearDown() {
            sandbox.promiseRegistry.cancelAllPending()
            sandbox.context.exceptionHandler = nil
            sandbox.tearDown()
        }
    }

    /// One snippet on the event loop: its own job queue, its own sandbox, and
    /// its state (see the event-loop documentation of `JSCInterpreter`).
    ///
    /// The `running` state of the design is the span of one job. The job
    /// queue is serial, so no other job can see a run in that state, and this
    /// type does not model it.
    // swiftlint:disable:next no_unchecked_sendable  `state` and `continuation` are read and written only in jobs on the serial `queue`; `cancelled` is lock-guarded; every other stored property is an immutable `let` of a `Sendable` type.
    private final class Run: @unchecked Sendable {
        /// What the start job installs and evaluates.
        ///
        /// Held only in the `queued` state. The start job takes it out, so a
        /// run that ended keeps no reference to a host function: the sandbox,
        /// which the run releases, was the only other holder.
        struct Snippet: Sendable {
            /// The snippet source, unwrapped.
            let code: String

            /// The synchronous host functions to install.
            let installing: [HostFunction]

            /// The asynchronous host functions to install.
            let installingAsync: [AsyncHostFunction]
        }

        /// Where a run is in its life.
        private enum State {
            /// The start job has not run yet.
            case queued(Snippet)

            /// No job executes JS, and at least one bridge promise is
            /// pending. The run holds memory only.
            case awaiting(LiveRun)

            /// The run ended with its result.
            case settled

            /// The run ended because the calling `Task` was cancelled.
            case cancelled

            /// The run ended with an error.
            case failed
        }

        /// The wall-clock ceiling of the run.
        private let timeLimit: TimeInterval

        /// The clock that the deadline of the run is on (see
        /// `JSCInterpreter.watchdogClock`).
        private let watchdogClock: any Clock<Duration>

        /// The telemetry of the calling task.
        private let telemetry: RunTelemetry

        /// The serial job queue of this run. A private queue with no
        /// constrained target: see the event-loop documentation of
        /// `JSCInterpreter` for why. Each job drains its own autorelease
        /// pool, so the Objective-C objects JavaScriptCore autoreleases in a
        /// job are released when that job ends, not when the thread next
        /// goes idle.
        private let queue = DispatchQueue(label: JSCInterpreter.queueLabel, autoreleaseFrequency: .workItem)

        /// Set when the calling `Task` is cancelled. The watchdog reads it
        /// while a job executes JS.
        private let cancelled = OSAllocatedUnfairLock(initialState: false)

        /// The state of the run. Read and written only in jobs.
        private var state: State

        /// The caller that waits for the result. Read and written only in
        /// jobs; resumed exactly one time.
        private var continuation: CheckedContinuation<InterpreterResult, Error>?

        /// Creates a run in the `queued` state. No job runs until
        /// ``start(resuming:)``.
        ///
        /// - Parameters:
        ///   - snippet: what the start job installs and evaluates.
        ///   - timeLimit: the wall-clock ceiling of the run.
        ///   - watchdogClock: the clock that the deadline of the run is on.
        ///   - telemetry: the telemetry of the calling task.
        init(snippet: Snippet, timeLimit: TimeInterval, watchdogClock: any Clock<Duration>, telemetry: RunTelemetry) {
            self.state = .queued(snippet)
            self.timeLimit = timeLimit
            self.watchdogClock = watchdogClock
            self.telemetry = telemetry
        }

        /// Puts the start job on the job queue.
        ///
        /// - Parameter continuation: the caller to resume when the run ends.
        func start(resuming continuation: CheckedContinuation<InterpreterResult, Error>) {
            enqueue { $0.startJob(resuming: continuation) }
        }

        /// Cancels the run. Callable from any thread.
        ///
        /// The flag stops a job that executes JS at its next watchdog poll,
        /// and the cancel job then cancels each pending call and ends the
        /// run.
        func cancel() {
            cancelled.withLock { $0 = true }
            enqueue { $0.cancelJob() }
        }

        /// Puts `job` on the job queue, with the telemetry of the calling task
        /// bound around it.
        ///
        /// - Parameter job: the job to run on this run.
        private func enqueue(_ job: @escaping @Sendable (Run) -> Void) {
            queue.async { [self] in
                telemetry.bound { job(self) }
            }
        }

        /// Puts the settle job of one completed bridge call on the job queue.
        /// Called from whichever thread the call's `Task` completed on.
        ///
        /// - Parameters:
        ///   - id: the registry id of the call's promise.
        ///   - outcome: what the call produced.
        private func enqueueSettle(id: Int, outcome: PromiseRegistry.Outcome) {
            enqueue { $0.settleJob(id: id, outcome: outcome) }
        }

        // MARK: Jobs

        /// The start job: makes the sandbox, evaluates the snippet, drains
        /// the microtasks, and ends with the finish step. It does not wait
        /// for the promises the snippet started.
        ///
        /// - Parameter continuation: the caller to resume when the run ends.
        private func startJob(resuming continuation: CheckedContinuation<InterpreterResult, Error>) {
            guard case .queued(let snippet) = state, !cancelled.withLock({ $0 }) else {
                state = .cancelled
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let live: LiveRun
            do {
                live = try makeLiveRun(for: snippet)
            } catch {
                complete(with: .failure(error))
                return
            }
            state = .awaiting(live)
            live.outcome = live.sandbox.context.evaluateScript(JSCInterpreter.wrap(code: snippet.code))
            endJob(live)
        }

        /// A settle job: resolves or rejects the promise of one completed
        /// bridge call, drains the microtasks, and ends with the finish step.
        ///
        /// A call that completes after the run ended finds no live run and
        /// changes nothing.
        ///
        /// - Parameters:
        ///   - id: the registry id of the call's promise.
        ///   - outcome: what the call produced.
        private func settleJob(id: Int, outcome: PromiseRegistry.Outcome) {
            guard case .awaiting(let live) = state,
                let pending = live.sandbox.promiseRegistry.take(id: id)
            else { return }
            JSCInterpreter.settle(pending, with: outcome, in: live.sandbox.context, recordingFailuresTo: &live.failures)
            endJob(live)
        }

        /// The cancel job: ends a run that waits, as cancelled. A run whose
        /// start job has not run yet is marked cancelled, and the start job
        /// resumes the caller.
        private func cancelJob() {
            switch state {
            case .queued:
                state = .cancelled
            case .awaiting(let live):
                live.sandbox.watchdogState.recordCause(.cancelled)
                endJob(live)
            case .settled, .cancelled, .failed:
                break
            }
        }

        /// The wall-clock timer job: ends a run that waits past its time
        /// limit, as timed out.
        private func wallClockExpired() {
            guard case .awaiting(let live) = state else { return }
            live.sandbox.watchdogState.recordCause(.timedOut)
            endJob(live)
        }

        /// The finish step that ends each job.
        ///
        /// A run whose watchdog recorded a cause (a timeout or a
        /// cancellation) ends now: each pending call is cancelled and its
        /// promise is not settled (see `PromiseRegistry.cancelAllPending`).
        /// Otherwise a run with a pending bridge promise keeps waiting, and a
        /// run with none ends with its outcome.
        ///
        /// - Parameter live: the live part of the run.
        private func endJob(_ live: LiveRun) {
            guard live.sandbox.watchdogState.cause != nil || live.sandbox.promiseRegistry.isEmpty else { return }
            let result = Result { try JSCInterpreter.outcome(of: live, timeLimit: timeLimit) }
            live.tearDown()
            complete(with: result)
        }

        /// Moves the run to its terminal state and resumes the caller.
        ///
        /// The caller is resumed in a job of its own, after this one. When the
        /// caller resumes, the job that ended the run has thus unwound and
        /// drained its autorelease pool, so the sandbox and every host
        /// function it held are already released. The caller records the end
        /// of the run (see `RunTelemetry.recordEnd(of:since:)`).
        ///
        /// - Parameter result: the outcome of the run.
        private func complete(with result: Result<InterpreterResult, Error>) {
            switch result {
            case .success:
                state = .settled
            case .failure(let error):
                state = error is CancellationError ? .cancelled : .failed
            }
            let caller = continuation
            continuation = nil
            queue.async { caller?.resume(with: result) }
        }

        // MARK: Setup

        /// Makes the sandbox and arms its deadline, which is also the
        /// wall-clock timer of the run.
        ///
        /// The timer of the deadline sleeps on ``watchdogClock`` and puts the
        /// wall-clock timer job on the job queue when it fires. It replaces a
        /// poll: a run that waits is not woken until a call completes, the
        /// run is cancelled, or the deadline fires.
        ///
        /// - Parameter snippet: the host functions to install.
        /// - Returns: the live part of the run.
        /// - Throws: `InterpreterError` when JavaScriptCore cannot make the
        ///   sandbox.
        private func makeLiveRun(for snippet: Snippet) throws -> LiveRun {
            let registry = PromiseRegistry { [weak self] id, outcome in
                self?.enqueueSettle(id: id, outcome: outcome)
            }
            let sandbox = try JSCInterpreter.makeSandbox(
                installing: snippet.installing,
                installingAsync: snippet.installingAsync,
                promiseRegistry: registry,
                timeLimit: timeLimit,
                watchdogClock: watchdogClock,
                isCancelled: { [cancelled] in cancelled.withLock { $0 } },
                onDeadline: { [weak self] in self?.enqueue { $0.wallClockExpired() } }
            )
            return LiveRun(sandbox: sandbox)
        }
    }

    /// Maps the state of a run that ended to its result: the return value
    /// and console lines, or the error.
    ///
    /// The order of the checks is the order of authority. A recorded
    /// watchdog cause comes first: a forced termination (timeout or
    /// cancellation) does not always also make a normal, catchable JS
    /// exception. A floating rejection — a bridge promise that rejected and
    /// that the snippet never consumed (`.then`/`.catch`/`.finally`/`await`)
    /// — becomes the run's error, per eventplan.md "Async JavaScript": "A
    /// floating rejection becomes the run's error. It does not disappear."
    /// It is decided one time, here, when no bridge promise is pending —
    /// never at each settlement (see `install(asyncHostFunction:into:registry:)`).
    ///
    /// - Parameters:
    ///   - live: the live part of the run.
    ///   - timeLimit: the wall-clock ceiling, named in a timeout message.
    /// - Returns: the result of the run.
    /// - Throws: `CancellationError` or `InterpreterError`.
    private static func outcome(of live: LiveRun, timeLimit: TimeInterval) throws -> InterpreterResult {
        switch live.sandbox.watchdogState.cause {
        case .cancelled:
            throw CancellationError()
        case .timedOut:
            throw InterpreterError(kind: .timeout, message: "Execution exceeded the \(timeLimit)s time limit.")
        case nil:
            break
        }
        if let exception = live.capturedException.value {
            throw makeError(from: exception)
        }
        if let floating = live.failures.first(where: { $0.consumed?.value != true }) {
            throw InterpreterError(kind: .exception, message: "\(floating.name): \(floating.message)")
        }
        // An async IIFE reports a thrown/rejected error through its
        // promise, not the context's exception handler — map it to the
        // same `InterpreterError` a synchronous throw produces.
        if let rejection = live.outcome?.objectForKeyedSubscript("error"), !rejection.isUndefined {
            throw makeError(from: rejection)
        }
        // Settled with neither value nor error, and no bridge promise
        // pending: the snippet awaited a promise no queued microtask could
        // ever settle (the sandbox has no timers or I/O), so its result will
        // never arrive.
        guard let settled = live.outcome?.objectForKeyedSubscript("done"), settled.toBool() else {
            throw InterpreterError(
                kind: .exception,
                message: "The snippet's result never settled — it awaited a promise that "
                    + "nothing in the sandbox can resolve (there are no timers or I/O here). "
                    + "Await only tool calls and already-resolved values."
            )
        }
        let returnValue = try jsonValue(of: live.outcome?.objectForKeyedSubscript("value"), in: live.sandbox.context)
        return InterpreterResult(returnValue: returnValue, consoleLines: live.sandbox.consoleLines.lines)
    }

    // MARK: - Standard surface

    /// Reference-type buffer so the `console.log` native block — which,
    /// being a `@convention(block)` closure, cannot mutate a Swift `inout`
    /// captured by value across calls — can append to a shared collection.
    private final class ConsoleLines {
        private(set) var lines: [String] = []
        fileprivate func append(_ line: String) { lines.append(line) }
    }

    /// Injects a `console` global whose `log` appends a joined,
    /// space-separated line to `lines`.
    private static func installConsole(into context: JSContext, capturing lines: ConsoleLines) {
        let console = JSValue(newObjectIn: context)
        let log: @convention(block) () -> Void = {
            let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
            let line = arguments
                // `toString()` is `String!`: an implicit-unwrap force-unwrap
                // hazard, not merely a style choice — it returns `nil`
                // (rather than trapping itself) when converting `$0` raises
                // a JS exception, e.g. a `wrapInForgotAwaitProxy` `get` trap
                // firing on `console.log(pendingResult)`'s own `ToPrimitive`
                // coercion (confirmed directly against JSC: an unguarded
                // force-unwrap here crashes the whole host process instead
                // of surfacing the trap's repairable error). `??` falls
                // back to a placeholder instead; `context.exceptionHandler`
                // has already captured the real exception by the time
                // `toString()` returns `nil`, so the run still reports it
                // as the run's `InterpreterError`, same as any other
                // exception raised mid-snippet.
                .map { $0.isUndefined ? "undefined" : ($0.toString() ?? "[unrepresentable value]") }
                .joined(separator: " ")
            lines.append(line)
        }
        console?.setObject(log, forKeyedSubscript: "log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    /// Installs `hostFunction` as a global callable in `context`, converting
    /// arguments/results through `InterpreterValue` and surfacing a Swift
    /// throw as a JS exception.
    private static func install(hostFunction: HostFunction, into context: JSContext) {
        let body: @convention(block) () -> JSValue? = {
            guard let currentContext = JSContext.current() else { return nil }
            do {
                let values = try convertArguments(in: currentContext)
                let resultValue = try hostFunction.call(values)
                return try jsValue(from: resultValue, in: currentContext)
            } catch {
                return setException(message: "\(hostFunction.name): \(error)", in: currentContext)
            }
        }
        context.setObject(body, forKeyedSubscript: hostFunction.name as NSString)
    }

    /// Converts the current native call's arguments (as JSC hands them to a
    /// `@convention(block)` body via `JSContext.currentArguments()`) through
    /// `InterpreterValue` — the shared first step `install(hostFunction:into:)`
    /// and `install(asyncHostFunction:into:registry:)` both take before
    /// dispatching to the host function's own `call`.
    private static func convertArguments(in context: JSContext) throws -> [InterpreterValue] {
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
        return try arguments.map { try jsonValue(of: $0, in: context) }
    }

    /// Sets `context`'s current exception to a JS `Error` carrying `message`
    /// and returns the `undefined` value a native callable's body should
    /// then return — the shared shape `install(hostFunction:into:)` and
    /// `install(asyncHostFunction:into:registry:)` both surface a Swift
    /// throw through.
    private static func setException(message: String, in context: JSContext) -> JSValue {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
        return JSValue(undefinedIn: context)
    }

    /// Reports whether `value` can actually run as a JS function — the real
    /// `IsCallable` abstract operation, used by `install(asyncHostFunction:
    /// into:registry:)`'s tracked `then` to decide whether a `.then`
    /// rejection-handler argument can genuinely handle a rejection.
    /// `JSValue` exposes no direct callability check: `isInstance(of:)`
    /// tests the `instanceof` prototype-chain relationship, which is
    /// neither necessary nor sufficient for callability —
    /// `Object.create(Function.prototype)` is `instanceof Function` but has
    /// no internal `[[Call]]`, while `Function.prototype` itself is
    /// callable but is not `instanceof Function`. This goes through the C
    /// API's `JSObjectIsFunction` instead, which matches `typeof value ===
    /// "function"` exactly, including for `undefined`/`null`/primitives
    /// (`JSValueToObject` boxes them into a non-function object rather than
    /// throwing, since the out-parameter exception slot is `nil`).
    private static func isCallable(_ value: JSValue, in context: JSContext) -> Bool {
        let contextRef = context.jsGlobalContextRef
        guard let object = JSValueToObject(contextRef, value.jsValueRef, nil) else { return false }
        return JSObjectIsFunction(contextRef, object)
    }

    // MARK: - Async host functions (the bridge)

    /// Whether `.then` was ever called on one bridge-created promise —
    /// `install(asyncHostFunction:into:registry:)` returns a thenable whose
    /// `then` method flips this before delegating to the real promise, so
    /// `await`, `.then(...)`, `.catch(...)`, `.finally(...)`, and
    /// `Promise.all([...])` (which all route through `.then` per spec) all
    /// mark it, however late. Checked only once, by the finish step of the
    /// run when no bridge promise is pending — see
    /// `outcome(of:timeLimit:)` and `install(asyncHostFunction:into:registry:)`
    /// for why checking per-settlement instead would be wrong.
    /// Confined to the job queue of its run, like `ConsoleLines`: `.then` is
    /// only ever invoked while a job executes JS.
    private final class ConsumedFlag {
        fileprivate var value = false
    }

    /// One pending bridge promise, taken out of the registry by the settle
    /// job of its call: its JS resolvers, the host function's name (for a
    /// consistent `"<name>: <error>"` rejection message, matching
    /// `install(hostFunction:into:)`'s sync counterpart), and the flag that
    /// tracks whether the snippet ever consumed it.
    private struct PendingPromise {
        /// The `resolve` function of the promise.
        let resolve: JSValue

        /// The `reject` function of the promise.
        let reject: JSValue

        /// The name of the host function the call went to.
        let name: String

        /// Whether the snippet consumed the promise; `nil` until the
        /// thenable that flips it is installed.
        let consumed: ConsumedFlag?
    }

    /// Every JS `Promise` the async host-function bridge has created for one
    /// run, tracked from creation until it settles — the settle-before-return
    /// registry: a run does not settle while this registry has an entry, so
    /// a floating call's work always completes (and a floating rejection is
    /// never silently dropped) before the run returns, even when the
    /// snippet's own top-level `return` never awaited it.
    ///
    /// Each entry's Swift `Task` reports its outcome through ``deliver``,
    /// from whichever thread the cooperative pool happens to run it on —
    /// genuine concurrency, so `Promise.all` over several calls runs them at
    /// once. ``deliver`` puts a settle job on the job queue of the run, and
    /// only that job touches the stored `resolve`/`reject`. No job holds the
    /// queue while a `Task` runs, so this hop back cannot deadlock.
    ///
    /// Confined to the job queue of its run, like `ConsoleLines`: `register`,
    /// `attachTask` and `attachConsumedFlag` run inside the promise executor,
    /// which only a job invokes, and `take`, `cancelAllPending` and `isEmpty`
    /// run only in jobs. Thus no lock is needed. The only thing that crosses
    /// threads is ``deliver``, a `Sendable` closure that carries only
    /// `Sendable` data (`Outcome`, not a raw `Result<InterpreterValue, Error>`
    /// — an existential `Error` isn't `Sendable`, so each `Task` renders its
    /// catch into a `String` immediately, matching
    /// `install(hostFunction:into:)`'s own `"\(error)"` interpolation).
    private final class PromiseRegistry {
        /// A settled async host function call: success carries its
        /// `InterpreterValue` result; failure carries the error already
        /// rendered to a message, since `Error` itself isn't `Sendable`.
        fileprivate enum Outcome: Sendable {
            case success(InterpreterValue)
            case failure(String)
        }

        /// One tracked promise: its JS resolvers, the host function's name,
        /// the flag tracking whether the snippet ever consumed it, and the
        /// backing `Task` — cancelled, rather than settled, when the run ends
        /// before this entry's result arrives (see `cancelAllPending`).
        private struct Entry {
            let resolve: JSValue
            let reject: JSValue
            let name: String
            var consumed: ConsumedFlag?
            var task: Task<Void, Never>?
        }

        /// The pending promises, keyed by id.
        private var entries: [Int: Entry] = [:]

        /// The id the next registered promise gets.
        private var nextID = 0

        /// Called by the backing `Task` of a call when it completes, from
        /// any thread. The run puts a settle job on its queue.
        fileprivate let deliver: @Sendable (Int, Outcome) -> Void

        /// Creates an empty registry.
        ///
        /// - Parameter deliver: called with the id and the outcome of each
        ///   call when its backing `Task` completes.
        fileprivate init(deliver: @escaping @Sendable (Int, Outcome) -> Void) {
            self.deliver = deliver
        }

        /// Registers a newly created promise's `resolve`/`reject` pair,
        /// returning the id ``deliver``, `attachTask(id:task:)`, and
        /// `attachConsumedFlag(id:flag:)` report against.
        fileprivate func register(resolve: JSValue, reject: JSValue, name: String) -> Int {
            let id = nextID
            nextID += 1
            entries[id] = Entry(resolve: resolve, reject: reject, name: name)
            return id
        }

        /// Attaches `id`'s backing `Task` handle to its entry, once created
        /// — a separate step from `register` because the `Task`'s own body
        /// needs `id` before it exists.
        fileprivate func attachTask(id: Int, task: Task<Void, Never>) {
            entries[id]?.task = task
        }

        /// Attaches `id`'s `ConsumedFlag`, once the `.then`-shadowing wrapper
        /// that flips it has been installed on the promise `id` names.
        fileprivate func attachConsumedFlag(id: Int, flag: ConsumedFlag) {
            entries[id]?.consumed = flag
        }

        /// Whether any promise this registry created is still awaiting
        /// settlement.
        fileprivate var isEmpty: Bool {
            entries.isEmpty
        }

        /// Removes and returns the pending promise `id` names, for the settle
        /// job of its call.
        ///
        /// - Parameter id: the id `register(resolve:reject:name:)` returned.
        /// - Returns: the pending promise, or `nil` when no entry has that id
        ///   any more (the run ended and dropped it).
        fileprivate func take(id: Int) -> PendingPromise? {
            guard let entry = entries.removeValue(forKey: id) else { return nil }
            return PendingPromise(
                resolve: entry.resolve, reject: entry.reject, name: entry.name, consumed: entry.consumed
            )
        }

        /// Cancels every still-pending entry's backing `Task` and drops it
        /// — used when a run ends (a timeout or a cancellation) before they
        /// settle. Never calls `resolve`/`reject`: doing so would resume
        /// author JS in a run that is ending, where no armed watchdog can
        /// stop it again (eventplan.md "Async JavaScript": "Cancellation is
        /// terminate-without-settling"), and tearing down the sandbox with
        /// these promises left permanently pending is the same supported path
        /// already exercised by an ordinary never-settling `await`.
        fileprivate func cancelAllPending() {
            for entry in entries.values {
                entry.task?.cancel()
            }
            entries.removeAll()
        }
    }

    /// Installs `asyncHostFunction` as a global callable in `context` that
    /// returns a JS *thenable* — not a native `Promise` instance, deliberately
    /// (see below) — per the promise-executor mechanism `JSValue` exposes:
    /// `JSValue(newPromiseIn:fromExecutor:)` runs its executor closure
    /// synchronously, so `resolve`/`reject` are captured into `registry`
    /// before this call even returns. Argument conversion happens
    /// synchronously, exactly like `install(hostFunction:into:)`; the call
    /// itself runs in its own `Task`, and its outcome settles the internal
    /// promise later, in a settle job of the run (see `PromiseRegistry`),
    /// never directly here.
    ///
    /// The value actually handed back to the snippet has `Promise.prototype`
    /// as its `[[Prototype]]` (via `Object.create`) but only one *own*
    /// property — a tracked `then` — not the internal promise itself.
    /// `await value` on a genuine native `Promise` instance resolves it via
    /// the internal `PerformPromiseThen` spec operation directly, which
    /// **never reads the `then` property at all**; shadowing `.then` on a
    /// real `Promise` therefore cannot observe a plain `await`, only an
    /// explicit `.then(...)`/`.catch(...)`/`.finally(...)` call (confirmed
    /// against JSC directly — an early version of this bridge did exactly
    /// that and silently missed every `await`). A *thenable* — any object
    /// with a callable `then`, promise or not — takes the opposite path:
    /// `PromiseResolve` only fast-paths a value whose `constructor` is the
    /// realm's own `Promise`, so for our thenable, `await`, `Promise.all`,
    /// `Promise.resolve`, and an async function's own `return` all resolve
    /// it by *calling* `.then` on it, same as any other thenable — which is
    /// exactly the observation point the finish step of a run needs for "was
    /// this rejection floating." Inheriting from `Promise.prototype` rather than
    /// `Object.prototype` additionally gives the value working `.catch`/
    /// `.finally` for free: both are defined there as thin wrappers that
    /// call `this.then(...)`, which resolves to *our* own `then` (an own
    /// property shadows an inherited one), so they route through tracking
    /// too — confirmed directly against JSC (`instanceof Promise`,
    /// `.catch(...)`, and `.finally(...)` all behave correctly; the wrapper
    /// itself still `JSON.stringify`s to `{}` and has no enumerable keys,
    /// since `then` is defined non-enumerable — though the snippet never
    /// sees this object directly; see the next paragraph).
    ///
    /// This thenable is never itself the value handed back to the snippet:
    /// it is, in turn, wrapped in a `Proxy` by `wrapInForgotAwaitProxy` —
    /// eventplan.md "Async JavaScript": "A Proxy trap catches property
    /// access on a pending result... For each property except then, catch,
    /// and finally, the get trap throws a precise repairable error." The
    /// Proxy is what the snippet actually receives; that function's own
    /// documentation covers the trap itself and why `then` is forwarded
    /// merely fetched (never bound) while `catch`/`finally` are the
    /// opposite — that asymmetry is what keeps this thenable's own
    /// `.then`/`.catch`/`.finally` behavior, described above, working
    /// unchanged underneath it.
    ///
    /// The internal promise itself is *never captured by the `then` block* —
    /// only read back via `JSContext.currentThis()` from a non-enumerable
    /// own property on the thenable. Capturing a `JSValue` directly in a
    /// native function installed into the very `JSContext` that `JSValue`
    /// belongs to is a retain cycle: the context's JS heap holds the
    /// function, the function holds the `JSValue`, and the `JSValue` holds
    /// its `JSContext` — `Sandbox.tearDown()`'s `JSGlobalContextRelease`
    /// then never reaches zero, leaking the whole sandbox on every run that
    /// makes an async host-function call (confirmed empirically: an earlier
    /// version of this bridge captured the internal promise directly and a
    /// canary object never deinitialized).
    private static func install(
        asyncHostFunction: AsyncHostFunction,
        into context: JSContext,
        registry: PromiseRegistry
    ) {
        let body: @convention(block) () -> JSValue? = {
            guard let currentContext = JSContext.current() else { return nil }
            do {
                let values = try convertArguments(in: currentContext)
                let (internalPromise, id) = try makeTrackedPromise(
                    for: asyncHostFunction, arguments: values, in: currentContext, registry: registry
                )
                let thenable = try makeThenable(wrapping: internalPromise, id: id, in: currentContext, registry: registry)
                guard let proxy = wrapInForgotAwaitProxy(thenable, callName: asyncHostFunction.name, in: currentContext) else {
                    throw InterpreterError(kind: .exception, message: "Proxy is unavailable.")
                }
                return proxy
            } catch {
                return setException(message: "\(asyncHostFunction.name): \(error)", in: currentContext)
            }
        }
        context.setObject(body, forKeyedSubscript: asyncHostFunction.name as NSString)
    }

    /// Creates the internal promise backing one async host-function call:
    /// registers its `resolve`/`reject` pair with `registry`, and starts the
    /// backing `Task` that will eventually settle it — the executor half of
    /// `install(asyncHostFunction:into:registry:)`, factored out to keep
    /// that function's own body a flat, linear `do`/`try`/`catch` chain.
    ///
    /// - Parameters:
    ///   - asyncHostFunction: the call being bridged — its `name` and `call`
    ///     are both used.
    ///   - values: the call's already-converted arguments.
    ///   - context: the sandbox's context, in which the internal promise is
    ///     created.
    ///   - registry: the settle-before-return registry this call's
    ///     `resolve`/`reject`/backing `Task` are registered against.
    /// - Returns: the internal promise and the id `registry` tracks it
    ///   under.
    /// - Throws: an `InterpreterError` if `JSValue(newPromiseIn:
    ///   fromExecutor:)` fails to produce a promise (never observed in
    ///   practice; defensive, matching every other "standard surface
    ///   unavailable" branch in this file).
    private static func makeTrackedPromise(
        for asyncHostFunction: AsyncHostFunction,
        arguments values: [InterpreterValue],
        in context: JSContext,
        registry: PromiseRegistry
    ) throws -> (promise: JSValue, id: Int) {
        var createdID: Int?
        let deliver = registry.deliver
        let internalPromise = JSValue(newPromiseIn: context) { resolve, reject in
            guard let resolve, let reject else { return }
            let id = registry.register(resolve: resolve, reject: reject, name: asyncHostFunction.name)
            createdID = id
            let task = Task {
                do {
                    let result = try await asyncHostFunction.call(values)
                    deliver(id, .success(result))
                } catch {
                    deliver(id, .failure("\(error)"))
                }
            }
            registry.attachTask(id: id, task: task)
        }
        guard let internalPromise, let id = createdID else {
            throw InterpreterError(kind: .exception, message: "failed to create a promise.")
        }
        return (internalPromise, id)
    }

    /// Builds the `thenable` `install(asyncHostFunction:into:registry:)`
    /// wraps in a `Proxy` for one pending call: a plain object inheriting
    /// `Promise.prototype`, holding `internalPromise` under
    /// `Self.internalPromisePropertyName` and a tracked `then` that shadows
    /// the inherited one — see `install(asyncHostFunction:into:registry:)`'s
    /// own documentation for the full rationale (the retain-cycle avoidance,
    /// the `ConsumedFlag`, and why a thenable rather than a real `Promise`
    /// subclass). Factored out to keep that function's own body a flat,
    /// linear `do`/`try`/`catch` chain.
    ///
    /// - Parameters:
    ///   - internalPromise: the promise `makeTrackedPromise` created for
    ///     this call.
    ///   - id: `internalPromise`'s id in `registry`, from
    ///     `makeTrackedPromise`.
    ///   - context: the sandbox's context.
    ///   - registry: the settle-before-return registry to attach this
    ///     call's `ConsumedFlag` to.
    /// - Returns: the thenable, ready for `wrapInForgotAwaitProxy`.
    /// - Throws: an `InterpreterError` if `Object`/`Promise` or
    ///   `Object.create` are unavailable, or `Object.create` fails to
    ///   produce a value (never observed in practice; defensive, matching
    ///   every other "standard surface unavailable" branch in this file).
    private static func makeThenable(
        wrapping internalPromise: JSValue,
        id: Int,
        in context: JSContext,
        registry: PromiseRegistry
    ) throws -> JSValue {
        guard
            let objectConstructor = context.objectForKeyedSubscript("Object"),
            let defineProperty = objectConstructor.objectForKeyedSubscript("defineProperty"),
            let create = objectConstructor.objectForKeyedSubscript("create"),
            let promiseConstructor = context.objectForKeyedSubscript("Promise"),
            let promisePrototype = promiseConstructor.objectForKeyedSubscript("prototype")
        else {
            throw InterpreterError(kind: .exception, message: "Object/Promise are unavailable.")
        }
        guard let thenable = create.call(withArguments: [promisePrototype]), !thenable.isUndefined else {
            throw InterpreterError(kind: .exception, message: "failed to create a thenable.")
        }
        defineHiddenProperty(name: Self.internalPromisePropertyName, value: internalPromise, on: thenable, using: defineProperty)
        let consumed = ConsumedFlag()
        let trackedThen: @convention(block) () -> JSValue? = {
            let thenArguments = (JSContext.currentArguments() as? [JSValue]) ?? []
            // A rejection is only genuinely handled — not merely
            // observed — when the caller supplies its own callable
            // `onRejected`; `await`/`Promise.all`/`.catch`/`.finally`
            // all do, per the spec forms this thenable is built to
            // intercept, but a bare `.then(onFulfilled)` does not, and
            // rejects a whole new (untracked) derived promise the model
            // likely never meant to create. `Promise.prototype.then`
            // itself only ever invokes `onRejected` when it is callable
            // (a non-callable second argument, e.g. `.then(undefined,
            // false)`, is treated the same as omitting it and rethrows
            // to the derived promise) — mirror that with `isCallable`
            // here, or a non-function second argument would mark a
            // rejection "handled" that no code can actually run to
            // handle. The context for that check is fetched fresh from
            // `JSContext.current()` on every call rather than captured
            // from the enclosing scope — capturing any `JSValue` here
            // would recreate the retain cycle this function's own
            // documentation warns about. See this function's
            // documentation for the known limitation this narrowing
            // accepts.
            if thenArguments.count > 1, let currentContext = JSContext.current(),
                isCallable(thenArguments[1], in: currentContext) {
                consumed.value = true
            }
            guard
                let this = JSContext.currentThis(),
                let realPromise = this.objectForKeyedSubscript(Self.internalPromisePropertyName),
                !realPromise.isUndefined
            else {
                return nil
            }
            return realPromise.invokeMethod("then", withArguments: thenArguments)
        }
        defineHiddenProperty(name: "then", value: trackedThen, on: thenable, using: defineProperty)
        registry.attachConsumedFlag(id: id, flag: consumed)
        return thenable
    }

    /// Defines `name` as a non-enumerable, non-configurable, non-writable
    /// own property of `object` holding `value` — the exact shape
    /// `thenable` needs for both its internal-promise marker
    /// (`Self.internalPromisePropertyName`) and its tracked `then`, factored
    /// out here so the two definitions can't drift apart.
    ///
    /// - Parameters:
    ///   - name: the property's key.
    ///   - value: the property's value.
    ///   - object: the object to define the property on.
    ///   - defineProperty: `Object.defineProperty`, passed in rather than
    ///     looked up again, since every caller already fetched it once.
    private static func defineHiddenProperty(name: String, value: Any, on object: JSValue, using defineProperty: JSValue) {
        defineProperty.call(withArguments: [
            object, name,
            ["value": value, "enumerable": false, "writable": false, "configurable": false],
        ])
    }

    /// Wraps `thenable` — the value `install(asyncHostFunction:into:
    /// registry:)` built for one pending call — in a JS `Proxy` whose `get`
    /// trap throws a precise, model-repairable error for every property
    /// except `then`, `catch`, and `finally` (eventplan.md "Async
    /// JavaScript": "A Proxy trap catches property access on a pending
    /// result... For each property except then, catch, and finally, the get
    /// trap throws a precise repairable error. The error names the call and
    /// the property. It asks 'did you forget await?'."). This is the third
    /// of the plan's four forgotten-`await` shapes; the plan frames the
    /// fourth — truthiness/arithmetic on the pending result — as this trap's
    /// uncaught backstop, covered only by description text and the repair
    /// loop. That holds exactly for bare truthiness (`if (r)`): `ToBoolean`
    /// on an object never performs a property lookup, per spec, so no `get`
    /// fires. Arithmetic and string coercion are narrower than the plan's
    /// wording suggests, though: `r + 1`, `` `${r}` ``, and similar reach
    /// `ToPrimitive`, which does `Get`s for `@@toPrimitive`, then `valueOf`,
    /// then `toString` (confirmed directly against JSC) — none of which are
    /// exempted below, so this trap catches those too, incidentally.
    ///
    /// `then` is forwarded to the exact value `target.then` already is,
    /// completely unwrapped — required, not merely simplest: `then` is a
    /// non-configurable, non-writable own property of `thenable` (see
    /// `install(asyncHostFunction:into:registry:)`), and the `Proxy`
    /// invariants (ECMA-262 `[[Get]]`) mandate that a `get` trap's result
    /// for such a property be `SameValue` as the target's own value — a
    /// bound copy would trip that invariant and JSC throws a native
    /// `TypeError` for it (confirmed directly against JSC). Because `then`
    /// itself can't be rebound, whatever calls it (`await`, `Promise.all`,
    /// or an explicit `.then(...)`) invokes it with the *Proxy* as `this` —
    /// unavoidable, since a property read never changes what a later call's
    /// own `this` will be; that is fixed by the call expression's own base
    /// reference. `trackedThen`'s body copes by reading its internal
    /// promise back through `this` (`JSContext.currentThis()`), so that
    /// property — `Self.internalPromisePropertyName`, likewise
    /// non-configurable/non-writable — is forwarded unwrapped for the exact
    /// same invariant reason, alongside `then`.
    ///
    /// `catch` and `finally`, by contrast, are *not* own properties of
    /// `thenable` — both are inherited from `Promise.prototype` — so no such
    /// invariant constrains them, and each is returned bound to `target`
    /// (`Function.prototype.bind`) rather than left to run with `this` as
    /// the Proxy. This matters because JSC's actual `Promise.prototype
    /// .finally` (unlike a naive `this.then(...)` polyfill) calls
    /// `SpeciesConstructor(this, %Promise%)` first, which reads `this
    /// .constructor` — a property this trap does not otherwise exempt.
    /// Binding to `target` makes that internal lookup, and `catch`'s own
    /// `this.then(...)` delegation, land directly on `thenable`, bypassing
    /// this trap entirely for those internal accesses (confirmed directly
    /// against JSC).
    ///
    /// - Parameters:
    ///   - thenable: the plain object `install(asyncHostFunction:into:
    ///     registry:)` built for this call.
    ///   - callName: the async host function's name, named in the trap's
    ///     error alongside the property that was accessed.
    ///   - context: the sandbox's context.
    /// - Returns: the proxy to hand back to the snippet in `thenable`'s
    ///   place, or `nil` if `Proxy` is unavailable on `context` — the caller
    ///   should raise a JS exception in that case, matching every other
    ///   "standard surface unavailable" branch in this file.
    private static func wrapInForgotAwaitProxy(
        _ thenable: JSValue,
        callName: String,
        in context: JSContext
    ) -> JSValue? {
        guard
            let proxyConstructor = context.objectForKeyedSubscript("Proxy"), !proxyConstructor.isUndefined,
            let handler = JSValue(newObjectIn: context)
        else {
            return nil
        }
        let getTrap: @convention(block) () -> JSValue? = {
            guard let currentContext = JSContext.current() else { return nil }
            let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
            guard arguments.count >= proxyGetTrapArgumentsRead else { return nil }
            let target = arguments[0]
            let propertyKey = arguments[1]
            let propertyName: String? = propertyKey.isString ? propertyKey.toString() : nil
            switch propertyName ?? "" {
            case "then", Self.internalPromisePropertyName:
                return target.objectForKeyedSubscript(propertyName ?? "")
            case "catch", "finally":
                guard let member = target.objectForKeyedSubscript(propertyName ?? "") else { return nil }
                return member.invokeMethod("bind", withArguments: [target])
            default:
                let displayName = describeNonExemptProperty(propertyKey, knownName: propertyName, in: currentContext)
                return setException(
                    message: "\(callName): accessed property \"\(displayName)\" on a pending result — "
                        + "did you forget `await`? Await the call (e.g. `await \(callName)(...)`) before "
                        + "reading a property, or use `.then`, `.catch`, or `.finally`.",
                    in: currentContext
                )
            }
        }
        handler.setObject(getTrap, forKeyedSubscript: "get" as NSString)
        guard
            let proxy = proxyConstructor.construct(withArguments: [thenable, handler]), !proxy.isUndefined
        else {
            return nil
        }
        return proxy
    }

    /// Describes `propertyKey` for the "did you forget `await`?" error
    /// message the `get` trap's default case throws: `knownName` when the
    /// key is already a string, otherwise `propertyKey` rendered through
    /// the global `String` function.
    ///
    /// `String(value)`, called as a function (not `new String(value)`), has
    /// a dedicated `Symbol` branch (`SymbolDescriptiveString`) that renders
    /// e.g. `"Symbol(Symbol.toPrimitive)"` without throwing — unlike
    /// ordinary `ToString` conversion (what `JSValue.toString()` performs),
    /// which throws for a `Symbol` per spec. This matters because arithmetic
    /// and string coercion on the pending result (`r + 1`, `` `${r}` ``)
    /// reach this trap through exactly such a key — `@@toPrimitive` — via
    /// `ToPrimitive` (confirmed directly against JSC; see
    /// `wrapInForgotAwaitProxy`'s own documentation).
    ///
    /// - Parameters:
    ///   - propertyKey: the `get` trap's raw property-key argument.
    ///   - knownName: `propertyKey` already converted to a `String`, when
    ///     the caller determined it is one; `nil` for a `Symbol` key.
    ///   - context: the sandbox's context.
    /// - Returns: `knownName` if given; otherwise `propertyKey` described via
    ///   the global `String` function, or `"a non-string property"` if even
    ///   that is unavailable.
    private static func describeNonExemptProperty(_ propertyKey: JSValue, knownName: String?, in context: JSContext) -> String {
        if let knownName {
            return knownName
        }
        guard
            let stringConstructor = context.objectForKeyedSubscript("String"),
            let described = stringConstructor.call(withArguments: [propertyKey]), described.isString,
            let text = described.toString()
        else {
            return "a non-string property"
        }
        return text
    }

    /// How many of a `get` trap's arguments `wrapInForgotAwaitProxy`'s trap
    /// reads: ECMA-262 calls a `get` trap with `(target, property, receiver)`,
    /// and the trap needs the first two — the object to forward an exempt
    /// property to, and the key that decides whether it is exempt.
    private static let proxyGetTrapArgumentsRead = 2

    /// The non-enumerable own property name `install(asyncHostFunction:into:
    /// registry:)` stashes the internal promise under, read back via
    /// `JSContext.currentThis()` inside the tracked `then` — see that
    /// function's documentation for why this indirection (rather than
    /// simply capturing the internal promise) is required.
    private static let internalPromisePropertyName = "__internalPromise"

    /// Settles one promise with its async host function's outcome, in the
    /// settle job of its call: resolves with the JSON-converted value on
    /// success, or rejects with an `"<name>: <error>"` message on failure —
    /// matching `install(hostFunction:into:)`'s sync-throw message shape. A
    /// rejection is appended to `failures` for the floating-rejection check
    /// of the finish step.
    ///
    /// Settling a promise (`resolve`/`reject.call(...)`) runs JS
    /// synchronously and drains JavaScriptCore's own microtask queue before
    /// returning — which can itself create *more* tracked promises (a
    /// `.then` continuation that awaits another async host-function call).
    /// The finish step after this job therefore reads the registry again.
    ///
    /// Floating-rejection detection (eventplan.md: "A floating rejection
    /// becomes the run's error") is decided *once*, when no bridge promise
    /// is pending — never at this settlement. A rejected promise a
    /// still-pending sibling gates (`const a = slow(); const b =
    /// fastReject(); try { await a; await b } catch {}`) can settle,
    /// unconsumed, before the snippet even reaches the `await` that will
    /// consume it; JSC's own per-microtask-checkpoint unhandled-rejection
    /// notification was tried first and rejects runs like that one even
    /// though the snippet does go on to catch it — measured directly against
    /// JSC, not theoretical. Checking every bridge-created promise's
    /// `ConsumedFlag` only when the whole registry has drained sidesteps
    /// that: by then, the snippet's async function body has either run to
    /// completion (so every promise on its actual executed path was reached,
    /// and `.then` was called on it, however late — see
    /// `install(asyncHostFunction:into:registry:)`) or is stuck on an
    /// unrelated always-pending promise (the "never settled" case of
    /// `outcome(of:timeLimit:)`), so a still-unconsumed failure at that point
    /// is genuinely floating.
    ///
    /// Both failure modes carry the `"<name>: <error>"` shape, including the
    /// one the sync bridge reaches through the very same
    /// `jsValue(from:in:)` call: a result the host function itself produced
    /// happily but that could not be converted back into the sandbox. The
    /// thrown error is interpolated rather than replaced with a fixed
    /// summary, so the two bridges report an identical conversion failure
    /// identically.
    ///
    /// - Parameters:
    ///   - pending: the promise to settle, taken out of the registry.
    ///   - outcome: what the call produced.
    ///   - context: the sandbox's context.
    ///   - failures: the rejections recorded so far.
    private static func settle(
        _ pending: PendingPromise,
        with outcome: PromiseRegistry.Outcome,
        in context: JSContext,
        recordingFailuresTo failures: inout [(name: String, message: String, consumed: ConsumedFlag?)]
    ) {
        switch outcome {
        case .success(let value):
            let jsResult: JSValue
            do {
                jsResult = try jsValue(from: value, in: context)
            } catch {
                rejectWithMessage(message: "\(pending.name): \(error)", reject: pending.reject, in: context)
                return
            }
            pending.resolve.call(withArguments: [jsResult])
        case .failure(let message):
            rejectWithMessage(message: "\(pending.name): \(message)", reject: pending.reject, in: context)
            failures.append((pending.name, message, pending.consumed))
        }
    }

    /// Rejects `reject` with a new JS `Error` built from `message` —
    /// matching `install(hostFunction:into:)`'s sync-throw message shape.
    /// Shared by `settle(_:with:in:recordingFailuresTo:)`'s two failure paths (a success value that
    /// could not be converted back into the sandbox, and a genuine async
    /// host-function failure) so their error construction can't drift apart.
    private static func rejectWithMessage(message: String, reject: JSValue, in context: JSContext) {
        let reason = JSValue(newErrorFromMessage: message, in: context)
        reject.call(withArguments: [reason as Any])
    }

    // MARK: - Value conversion

    /// Converts a `JSValue` to `InterpreterValue` by round-tripping it
    /// through the context's own sandboxed `JSON.stringify` — the same
    /// mechanism a snippet itself would use, so conversion never reaches
    /// outside the standard, injected surface.
    private static func jsonValue(of value: JSValue?, in context: JSContext) throws -> InterpreterValue {
        guard let value, !value.isUndefined else { return .null }
        guard
            let json = context.objectForKeyedSubscript("JSON"),
            let stringify = json.objectForKeyedSubscript("stringify")
        else {
            throw InterpreterError(kind: .exception, message: "JSON.stringify is unavailable.")
        }
        guard let stringified = stringify.call(withArguments: [value]), !stringified.isUndefined else {
            // `JSON.stringify` itself returns `undefined` for values it
            // can't represent (functions, symbols, `undefined`).
            return .null
        }
        // `toString()` is `String!`, so binding it to a non-optional `String`
        // would force-unwrap and trap. Nothing here can prove it non-nil: the
        // receiver is whatever the sandbox's own `JSON.stringify` returned.
        guard let jsonString = stringified.toString() else {
            throw InterpreterError(kind: .exception, message: "Could not read the stringified value as text.")
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw InterpreterError(kind: .exception, message: "Could not encode the value as UTF-8 JSON.")
        }
        do {
            return try JSONDecoder().decode(InterpreterValue.self, from: data)
        } catch {
            throw InterpreterError(
                kind: .exception,
                message: "Value is not JSON-encodable: \(error)."
            )
        }
    }

    /// The inverse of `jsonValue(of:in:)`: encodes `value` to JSON and
    /// parses it back with the context's own sandboxed `JSON.parse`.
    ///
    /// The parse result is rejected when it is `undefined`, not only when it
    /// is `nil` — mirroring `jsonValue(of:in:)`'s own `!stringified
    /// .isUndefined` check on the opposite direction. `JSON.parse` never
    /// returns `undefined` for what `JSONEncoder` produced, and the `nil`
    /// checks alone cannot catch a sandbox whose `JSON.parse` a snippet
    /// replaced: `JSValue`'s lookup and call methods hand back an
    /// `undefined` `JSValue`, never `nil`, when the receiver is missing or
    /// is not callable. Without the `undefined` check, a replaced
    /// `JSON.parse` would quietly convert every value to `undefined` here
    /// instead of failing.
    private static func jsValue(from value: InterpreterValue, in context: JSContext) throws -> JSValue {
        let data = try JSONEncoder().encode(value)
        let jsonString = String(decoding: data, as: UTF8.self)
        guard
            let json = context.objectForKeyedSubscript("JSON"),
            let parse = json.objectForKeyedSubscript("parse"),
            let parsed = parse.call(withArguments: [jsonString]),
            !parsed.isUndefined
        else {
            throw InterpreterError(kind: .exception, message: "JSON.parse is unavailable.")
        }
        return parsed
    }

    // MARK: - Error mapping

    /// The message reported for a JS exception whose own text cannot be read.
    ///
    /// `JSValue.toString()` is `String!`, so every read of it needs a fallback
    /// rather than an implicit unwrap that would trap while already handling a
    /// failure. Named once because both of `makeError(from:)`'s branches need
    /// the same wording — a reader of the rendered error should not be able to
    /// tell which branch produced it.
    private static let unreadableExceptionMessage = "Unknown JavaScript exception."

    /// Maps a captured JS exception to an `InterpreterError`, extracting a
    /// `message` and, when present, a `line`.
    private static func makeError(from exception: JSValue) -> InterpreterError {
        let message: String
        if exception.isObject, let messageValue = exception.objectForKeyedSubscript("message"), !messageValue.isUndefined {
            message = messageValue.toString() ?? Self.unreadableExceptionMessage
        } else {
            message = exception.toString() ?? Self.unreadableExceptionMessage
        }

        var line: Int?
        if exception.isObject, let lineValue = exception.objectForKeyedSubscript("line"), !lineValue.isUndefined {
            line = Int(lineValue.toInt32())
        }

        return InterpreterError(kind: .exception, message: message, line: line)
    }
}
