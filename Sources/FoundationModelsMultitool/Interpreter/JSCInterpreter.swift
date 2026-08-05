import Foundation
import JavaScriptCore
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
/// Swift, whether the *real* configured `timeLimit` has elapsed or
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
    /// wins, since `evaluate` only ever throws once per run.
    fileprivate enum Cause: Sendable {
        /// The run exceeded its configured wall-clock time limit.
        case timedOut
        /// M10: `isCancelled` reported `true` before the real time limit
        /// elapsed.
        case cancelled
    }

    private let lock: OSAllocatedUnfairLock<Cause?>

    /// When this run's watchdog was armed — the reference point
    /// `shouldTerminate()` measures elapsed time from.
    private let runStart: ContinuousClock.Instant

    /// The *real* configured time limit this state enforces — independent
    /// of whatever short poll interval the group's own
    /// `JSContextGroupSetExecutionTimeLimit` was actually armed with (see
    /// this type's documentation).
    private let timeLimit: TimeInterval

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
    ///   - timeLimit: the real wall-clock ceiling this state enforces.
    ///   - isCancelled: polled once per callback invocation to detect
    ///     external (M10 `Task`) cancellation.
    fileprivate init(
        group: JSContextGroupRef,
        pollInterval: TimeInterval,
        timeLimit: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool
    ) {
        self.lock = OSAllocatedUnfairLock(initialState: nil)
        self.runStart = ContinuousClock.now
        self.group = group
        self.pollInterval = pollInterval
        self.timeLimit = timeLimit
        self.isCancelled = isCancelled
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
    ///   reports `true` or the real `timeLimit` has elapsed, recording which
    ///   caused it; `false` (having just re-armed one more poll-interval
    ///   window) otherwise.
    fileprivate func shouldTerminate() -> Bool {
        if isCancelled() {
            lock.withLock { if $0 == nil { $0 = .cancelled } }
            return true
        }
        if runStart.duration(to: .now) >= .seconds(timeLimit) {
            lock.withLock { if $0 == nil { $0 = .timedOut } }
            return true
        }
        rearm()
        return false
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

/// JavaScriptCore-backed `Interpreter`.
///
/// Each `run` gets a brand-new `JSContextGroup`/`JSContext` — deny-by-default,
/// reachable only from the standard ECMAScript globals JSC ships with
/// (`Math`, `JSON`, `Array`, …), the injected `console`, and whatever
/// `HostFunction`s/`AsyncHostFunction`s were installed for that run. Nothing
/// set by one run (a global, a host function) is visible to the next.
///
/// The whole run executes on a dedicated background queue — never the
/// caller's thread. `HostFunction` calls run synchronously, inline, on that
/// queue. `AsyncHostFunction` calls return a JS `Promise` backed by its own
/// Swift `Task`, running concurrently on the cooperative pool; the queue
/// blocks only while waiting for those `Task`s to report back (see
/// `pumpUntilSettled`), never for the caller's own thread — eventplan.md
/// "Async JavaScript": "We remove the v1 blocking bridge... We do not build
/// a semaphore-based park mechanism and its thread guards only to delete
/// them later."
public final class JSCInterpreter: Interpreter {
    /// Where this interpreter logs its M10 diagnostics — snippet start/end
    /// and duration, and how a run ended (clean, exception, timeout, or
    /// cancelled).
    private static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "JSCInterpreter")

    /// How often `WatchdogState.shouldTerminate()` is invoked while a
    /// snippet runs — see that type's documentation for why this, not the
    /// run's real configured `timeLimit`, is the value actually armed via
    /// `JSContextGroupSetExecutionTimeLimit`. 20ms bounds M10 cancellation
    /// latency well below any realistic `timeLimit`, at negligible overhead.
    private static let watchdogPollInterval: TimeInterval = 0.02

    /// Wall-clock ceiling for a single `run`, enforced by `WatchdogState`.
    private let timeLimit: TimeInterval

    /// Dedicated worker the actual JS evaluation runs on (see the type doc).
    private let queue: DispatchQueue

    /// Creates a JavaScriptCore-backed interpreter that enforces the given
    /// per-run time limit.
    ///
    /// - Parameter timeLimit: seconds a single `run` may execute before the
    ///   watchdog terminates it. Defaults to a generous ceiling suitable for
    ///   real tool-composing snippets.
    public init(timeLimit: TimeInterval = 5.0) {
        self.timeLimit = timeLimit
        self.queue = DispatchQueue(label: "FoundationModelsMultitool.JSCInterpreter")
    }

    /// Runs `code` on the dedicated worker queue in a fresh, isolated
    /// sandbox with `installing`/`installingAsync` made available as
    /// globals — the sole requirement of `Interpreter` this type
    /// implements; every other overload (`run(code:installing:)`,
    /// `run(code:installing:isCancelled:)`,
    /// `run(code:installing:installingAsync:)`) reaches this one through
    /// `Interpreter`'s own default conformances.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run. A top-level `return` is
    ///     supported — the snippet does not need to be an IIFE itself.
    ///   - installing: synchronous host functions to expose as globals for
    ///     this run only.
    ///   - installingAsync: asynchronous host functions to expose as
    ///     globals for this run only — see `JSCInterpreter`'s own
    ///     documentation for the promise-pump mechanism that backs them.
    ///   - isCancelled: polled on a short interval while the snippet runs.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `CancellationError` if `isCancelled` reported `true` before
    ///   the run otherwise completed; `InterpreterError` for a thrown/syntax
    ///   exception, a watchdog timeout, or a floating rejection.
    public func run(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> InterpreterResult {
        try queue.sync {
            try Self.evaluate(
                code: code,
                installing: installing,
                installingAsync: installingAsync,
                timeLimit: timeLimit,
                isCancelled: isCancelled
            )
        }
    }

    // MARK: - Run

    /// A single run's sandbox: the `JSContextGroup`/`JSContext` pair, the
    /// installed standard surface, the watchdog wired to that group, and the
    /// async host-function bridge's own state — bundled together so
    /// `evaluate` doesn't have to juggle their lifetimes (and matching
    /// teardown order) inline.
    private struct Sandbox {
        fileprivate let group: JSContextGroupRef
        fileprivate let globalContextRef: JSGlobalContextRef
        fileprivate let context: JSContext
        fileprivate let consoleLines: ConsoleLines
        fileprivate let watchdogState: WatchdogState
        fileprivate let promiseRegistry: PromiseRegistry

        fileprivate func tearDown() {
            JSContextGroupClearExecutionTimeLimit(group)
            JSGlobalContextRelease(globalContextRef)
            JSContextGroupRelease(group)
        }
    }

    /// Creates a fresh, isolated sandbox with `installing` bound in and the
    /// watchdog armed — at `Self.watchdogPollInterval`, not `timeLimit`
    /// itself; see `WatchdogState`'s documentation for why. Cleans up any
    /// partially-created pieces on the way out if a later step fails.
    private static func makeSandbox(
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        timeLimit: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool
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

        let promiseRegistry = PromiseRegistry()
        for asyncHostFunction in installingAsync {
            install(asyncHostFunction: asyncHostFunction, into: context, registry: promiseRegistry)
        }

        let watchdogState = WatchdogState(
            group: group,
            pollInterval: watchdogPollInterval,
            timeLimit: timeLimit,
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

    /// Builds a sandbox, evaluates `code` in it as an IIFE, and maps the
    /// outcome (return value, console lines, exception, watchdog timeout, or
    /// M10 external cancellation) to an `InterpreterResult` or thrown error.
    ///
    /// Logs the run's start and its end (outcome + duration) via `logger` —
    /// plan.md M10: "os.Logger... at the seams — snippet start/end +
    /// duration."
    private static func evaluate(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        timeLimit: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> InterpreterResult {
        let start = ContinuousClock.now
        logger.debug("runCode snippet started (\(code.count, privacy: .public) characters).")

        let sandbox = try makeSandbox(
            installing: installing,
            installingAsync: installingAsync,
            timeLimit: timeLimit,
            isCancelled: isCancelled
        )
        defer { sandbox.tearDown() }

        var capturedException: JSValue?
        sandbox.context.exceptionHandler = { _, exception in
            capturedException = exception
        }

        // Wrap in an *async* IIFE so both a top-level `return` and a
        // top-level `await` are legal — models with async-JS priors
        // routinely write `await tools.weather(...)`, and under a plain
        // IIFE that is a bare syntax error whose message never mentions
        // `await` ("Unexpected identifier 'tools'"), an unrecoverable
        // dead end for the model. An outer plain IIFE holds the outcome
        // object as a local (never a global — the sandbox's injected-global
        // surface is pinned by `HardeningTests`) and returns it; the async
        // IIFE's `.then` callbacks capture and mutate that same object. The
        // whole prefix is prepended to the snippet's own first line (rather
        // than on a line of its own) so every reported line number still
        // matches the caller's original source 1:1. The settled result is
        // readable by the time `evaluateScript` returns for any snippet
        // whose awaits resolve without external events — host functions are
        // synchronous, so their awaited results are already-settled values
        // and JavaScriptCore drains the resulting microtasks when the
        // evaluation's call stack empties.
        let wrapped = """
            (function(){ var outcome = {}; (async function(){\(code)
            })().then(function(v){ outcome.value = v; outcome.done = true; }, \
            function(e){ outcome.error = e; outcome.done = true; }); return outcome; })()
            """
        let outcome = sandbox.context.evaluateScript(wrapped)

        do {
            // Settle-before-return: block until every promise the async
            // host-function bridge created has settled (or the watchdog
            // forces the run to end) before deciding the run's outcome —
            // see `pumpUntilSettled`. A snippet with no `installingAsync`
            // calls leaves the registry empty from the start, so this is a
            // no-op and every existing synchronous-only run behaves exactly
            // as before. A non-`nil` result is a floating rejection — a
            // bridge-created promise that rejected and that the snippet
            // never consumed (`.then`/`.catch`/`.finally`/`await`), per
            // eventplan.md "Async JavaScript": "A floating rejection becomes
            // the run's error. It does not disappear."
            let floatingRejectionError = pumpUntilSettled(sandbox: sandbox)

            // Check the watchdog's recorded cause before the captured
            // exception: a watchdog-forced termination (timeout or
            // cancellation) is not guaranteed to also populate a normal,
            // catchable JS exception, so the recorded cause is the
            // authoritative signal.
            switch sandbox.watchdogState.cause {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw InterpreterError(
                    kind: .timeout,
                    message: "Execution exceeded the \(timeLimit)s time limit."
                )
            case nil:
                break
            }
            if let capturedException {
                throw makeError(from: capturedException)
            }
            if let floatingRejectionError {
                throw floatingRejectionError
            }

            // An async IIFE reports a thrown/rejected error through its
            // promise, not the context's exception handler — map it to the
            // same `InterpreterError` a synchronous throw produces.
            if let rejection = outcome?.objectForKeyedSubscript("error"), !rejection.isUndefined {
                throw makeError(from: rejection)
            }
            // Settled with neither value nor error: the snippet awaited a
            // promise no queued microtask could ever settle (the sandbox
            // has no timers or I/O), so its result will never arrive.
            guard let settled = outcome?.objectForKeyedSubscript("done"), settled.toBool() else {
                throw InterpreterError(
                    kind: .exception,
                    message: "The snippet's result never settled — it awaited a promise that "
                        + "nothing in the sandbox can resolve (there are no timers or I/O here). "
                        + "Await only tool calls and already-resolved values."
                )
            }

            let returnValue = try jsonValue(of: outcome?.objectForKeyedSubscript("value"), in: sandbox.context)
            let result = InterpreterResult(returnValue: returnValue, consoleLines: sandbox.consoleLines.lines)
            logger.debug("runCode snippet finished in \(start.duration(to: .now), privacy: .public).")
            return result
        } catch {
            logger.debug(
                "runCode snippet ended (\(String(describing: error), privacy: .public)) after \(start.duration(to: .now), privacy: .public)."
            )
            throw error
        }
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
                .map { $0.isUndefined ? "undefined" : $0.toString() }
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

    // MARK: - Async host functions (promise pump)

    /// Whether `.then` was ever called on one bridge-created promise —
    /// `install(asyncHostFunction:into:registry:)` returns a thenable whose
    /// `then` method flips this before delegating to the real promise, so
    /// `await`, `.then(...)`, `.catch(...)`, `.finally(...)`, and
    /// `Promise.all([...])` (which all route through `.then` per spec) all
    /// mark it, however late. Checked only once, after `pumpUntilSettled`
    /// has drained the whole registry — see that function's documentation
    /// for why checking per-settlement instead would be wrong.
    /// JS-thread-confined, like `ConsoleLines`: `.then` is only ever invoked
    /// while JS executes on the interpreter's dedicated worker queue.
    private final class ConsumedFlag {
        fileprivate var value = false
    }

    /// Every JS `Promise` the async host-function bridge has created for one
    /// run, tracked from creation until it settles — the settle-before-return
    /// registry: `evaluate` gives no result until this registry is empty
    /// (see `pumpUntilSettled`), so a floating call's work always completes
    /// (and a floating rejection is never silently dropped) before the run
    /// returns, even when the snippet's own top-level `return` never awaited
    /// it.
    ///
    /// Each entry's Swift `Task` reports its outcome back through
    /// `complete(id:outcome:)`, from whichever thread the cooperative pool
    /// happens to run it on — genuine concurrency, so `Promise.all` over
    /// several calls runs them at once. Only `pumpUntilSettled`, running on
    /// the interpreter's own dedicated worker queue (the "JS thread"), ever
    /// touches a stored `resolve`/`reject`, so those `JSValue`s are never
    /// touched off that queue — hopping back with `queue.async` from the
    /// `Task` instead would deadlock the same serial queue `run` already
    /// holds via `queue.sync`.
    ///
    /// `@unchecked`: split into two halves with different, non-overlapping
    /// access patterns. `entries` (and `nextID`) hold the non-`Sendable`
    /// `JSValue` resolvers and are touched *only* from the JS thread —
    /// `register`/`attachTask`/`attachConsumedFlag` run inside the promise
    /// executor, itself only ever invoked while JS executes on the
    /// interpreter's dedicated worker queue, and
    /// `takeReadyToSettle`/`cancelAllPending`/`isEmpty` run only from
    /// `pumpUntilSettled`, which is called from the very same queue — so,
    /// exactly like `ConsoleLines`, no lock is needed there. The completion
    /// mailbox genuinely crosses threads (every backing `Task` writes to it
    /// from wherever the cooperative pool runs it; the JS thread reads it),
    /// so it alone is `lock`-guarded, and holds only `Sendable` data
    /// (`Outcome`, not a raw `Result<InterpreterValue, Error>` — an
    /// existential `Error` isn't `Sendable`, so each `Task` renders its
    /// catch into a `String` immediately, matching
    /// `install(hostFunction:into:)`'s own `"\(error)"` interpolation), and
    /// a `semaphore` the JS thread waits on so a settlement wakes
    /// `pumpUntilSettled` immediately instead of only on its next poll tick.
    private final class PromiseRegistry: @unchecked Sendable {
        /// A settled async host function call: success carries its
        /// `InterpreterValue` result; failure carries the error already
        /// rendered to a message, since `Error` itself isn't `Sendable`.
        fileprivate enum Outcome: Sendable {
            case success(InterpreterValue)
            case failure(String)
        }

        /// One tracked promise: its JS resolvers, the host function's name
        /// (for a consistent `"<name>: <error>"` rejection message, matching
        /// `install(hostFunction:into:)`'s sync counterpart), the flag
        /// tracking whether the snippet ever consumed it, and the backing
        /// `Task` — cancelled, rather than settled, when the watchdog forces
        /// the run to end before this entry's result arrives (see
        /// `cancelAllPending`).
        private struct Entry {
            let resolve: JSValue
            let reject: JSValue
            let name: String
            var consumed: ConsumedFlag?
            var task: Task<Void, Never>?
        }

        /// JS-thread-confined; see this type's own documentation.
        private var entries: [Int: Entry] = [:]
        private var nextID = 0

        private let lock = OSAllocatedUnfairLock(initialState: [Int: Outcome]())
        private let semaphore = DispatchSemaphore(value: 0)

        /// Registers a newly created promise's `resolve`/`reject` pair,
        /// returning the id `complete(id:outcome:)`, `attachTask(id:task:)`,
        /// and `attachConsumedFlag(id:flag:)` report against.
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

        /// Records the async host function's outcome for `id` and wakes
        /// `waitAndTakeReadyToSettle`. Called from whichever thread the
        /// backing `Task` completes on.
        fileprivate func complete(id: Int, outcome: Outcome) {
            lock.withLock { $0[id] = outcome }
            semaphore.signal()
        }

        /// Whether any promise this registry created is still awaiting
        /// settlement.
        fileprivate var isEmpty: Bool {
            entries.isEmpty
        }

        /// Waits up to `timeout` for at least one new completion, then
        /// removes and returns every entry whose result has arrived (there
        /// may be more than the one waited for), pairing each with the
        /// `resolve`/`reject`/`consumed` `pumpUntilSettled` should use.
        /// Returns empty on a timeout with nothing new.
        fileprivate func waitAndTakeReadyToSettle(
            timeout: DispatchTime
        ) -> [(resolve: JSValue, reject: JSValue, name: String, outcome: Outcome, consumed: ConsumedFlag?)] {
            guard semaphore.wait(timeout: timeout) == .success else { return [] }
            let completed = lock.withLock { outcomes in
                let taken = outcomes
                outcomes.removeAll()
                return taken
            }
            // The blocking `wait()` above consumed exactly one signal; a
            // batch this size may correspond to several `complete(id:outcome:)`
            // calls, each of which signalled once — drain their matching
            // signals too (non-blocking, they are already known to be
            // available) so the semaphore's count never drifts from the
            // number of not-yet-drained completions.
            if completed.count > 1 {
                for _ in 1..<completed.count { _ = semaphore.wait(timeout: .now()) }
            }
            var ready: [(resolve: JSValue, reject: JSValue, name: String, outcome: Outcome, consumed: ConsumedFlag?)] = []
            for (id, outcome) in completed {
                guard let entry = entries.removeValue(forKey: id) else { continue }
                ready.append((entry.resolve, entry.reject, entry.name, outcome, entry.consumed))
            }
            return ready
        }

        /// Cancels every still-pending entry's backing `Task` and drops it
        /// — used when the watchdog forces the run to end before they
        /// settle. Never calls `resolve`/`reject`: doing so would resume JS
        /// execution outside the watchdog's own protection (see
        /// `pumpUntilSettled`), and tearing down the sandbox with these
        /// promises left permanently pending is the same supported path
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
    /// promise later through `registry` (`pumpUntilSettled`), never directly
    /// here.
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
    /// exactly the observation point `pumpUntilSettled` needs for "was this
    /// rejection floating." Inheriting from `Promise.prototype` rather than
    /// `Object.prototype` additionally gives the value working `.catch`/
    /// `.finally` for free: both are defined there as thin wrappers that
    /// call `this.then(...)`, which resolves to *our* own `then` (an own
    /// property shadows an inherited one), so they route through tracking
    /// too — confirmed directly against JSC (`instanceof Promise`,
    /// `.catch(...)`, and `.finally(...)` all behave correctly; the wrapper
    /// still `JSON.stringify`s to `{}` and has no enumerable keys, since
    /// `then` is defined non-enumerable).
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
            let values: [InterpreterValue]
            do {
                values = try convertArguments(in: currentContext)
            } catch {
                return setException(message: "\(asyncHostFunction.name): \(error)", in: currentContext)
            }

            var createdID: Int?
            let internalPromise = JSValue(newPromiseIn: currentContext) { resolve, reject in
                guard let resolve, let reject else { return }
                let id = registry.register(resolve: resolve, reject: reject, name: asyncHostFunction.name)
                createdID = id
                let task = Task {
                    do {
                        let result = try await asyncHostFunction.call(values)
                        registry.complete(id: id, outcome: .success(result))
                    } catch {
                        registry.complete(id: id, outcome: .failure("\(error)"))
                    }
                }
                registry.attachTask(id: id, task: task)
            }
            guard let internalPromise, let id = createdID else {
                return setException(message: "\(asyncHostFunction.name): failed to create a promise.", in: currentContext)
            }
            guard
                let objectConstructor = currentContext.objectForKeyedSubscript("Object"),
                let defineProperty = objectConstructor.objectForKeyedSubscript("defineProperty"),
                let create = objectConstructor.objectForKeyedSubscript("create"),
                let promiseConstructor = currentContext.objectForKeyedSubscript("Promise"),
                let promisePrototype = promiseConstructor.objectForKeyedSubscript("prototype")
            else {
                return setException(message: "\(asyncHostFunction.name): Object/Promise are unavailable.", in: currentContext)
            }
            guard let thenable = create.call(withArguments: [promisePrototype]), !thenable.isUndefined else {
                return setException(message: "\(asyncHostFunction.name): failed to create a thenable.", in: currentContext)
            }
            defineProperty.call(withArguments: [
                thenable, Self.internalPromisePropertyName,
                ["value": internalPromise, "enumerable": false, "writable": false, "configurable": false],
            ])
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
            defineProperty.call(withArguments: [
                thenable, "then",
                ["value": trackedThen, "enumerable": false, "writable": false, "configurable": false],
            ])
            registry.attachConsumedFlag(id: id, flag: consumed)
            return thenable
        }
        context.setObject(body, forKeyedSubscript: asyncHostFunction.name as NSString)
    }

    /// The non-enumerable own property name `install(asyncHostFunction:into:
    /// registry:)` stashes the internal promise under, read back via
    /// `JSContext.currentThis()` inside the tracked `then` — see that
    /// function's documentation for why this indirection (rather than
    /// simply capturing the internal promise) is required.
    private static let internalPromisePropertyName = "__internalPromise"

    /// Blocks the calling (JS) thread until every promise `sandbox`'s async
    /// host-function bridge has created has settled — the settle-before-
    /// return contract: `evaluate` gives no result until this returns, so
    /// the work of a floating call (`tools.files.write(...); return
    /// "done";`) always completes, and a floating rejection is never
    /// silently dropped.
    ///
    /// Settling a promise (`resolve`/`reject.call(...)`) runs JS
    /// synchronously and drains JavaScriptCore's own microtask queue before
    /// returning — which can itself create *more* tracked promises (a
    /// `.then` continuation that awaits another async host-function call),
    /// so this keeps looping until the registry is genuinely empty, not just
    /// empty at the moment it was first checked.
    ///
    /// While no promise has settled yet, no JS is executing, so JSC's own
    /// watchdog callback (`jscTerminateCallback`) cannot fire — this polls
    /// `sandbox.watchdogState.shouldTerminate()` itself instead, waking
    /// immediately on a settlement (via `PromiseRegistry`'s semaphore) or, at
    /// worst, every `watchdogPollInterval`. On a decision to terminate
    /// (timeout or M10 cancellation), every still-pending entry's `Task` is
    /// cancelled — never settled via `resolve`/`reject`, since resuming JS
    /// execution here would run outside the watchdog's own re-armed
    /// protection window (see `PromiseRegistry.cancelAllPending`'s
    /// documentation) — and this returns `nil`; the caller's own
    /// `sandbox.watchdogState.cause` check then throws the same
    /// `CancellationError`/timeout it always has. This is a deliberate,
    /// safety-motivated narrowing of eventplan.md "Async JavaScript"'s
    /// literal "reject each pending promise" wording for the
    /// watchdog-forced-termination path specifically — recorded on task
    /// `01KZ6MYJSSSF41HXMC2YAHBKG5`.
    ///
    /// Floating-rejection detection (eventplan.md: "A floating rejection
    /// becomes the run's error") is decided *once*, after the registry is
    /// fully empty — never per-settlement. A rejected promise a still-pending
    /// sibling gates (`const a = slow(); const b = fastReject(); try { await
    /// a; await b } catch {}`) can settle, unconsumed, before the snippet
    /// even reaches the `await` that will consume it; JSC's own
    /// per-microtask-checkpoint unhandled-rejection notification was tried
    /// here first and rejects runs like that one even though the snippet
    /// does go on to catch it — measured directly against JSC, not
    /// theoretical. Checking every bridge-created promise's `ConsumedFlag`
    /// only after the whole registry drains sidesteps that: by then, the
    /// snippet's async function body has either run to completion (so every
    /// promise on its actual executed path was reached, and `.then` was
    /// called on it, however late — see `install(asyncHostFunction:into:
    /// registry:)`) or is stuck on an unrelated always-pending promise (the
    /// pre-existing "never settled" case below), so a still-unconsumed
    /// failure at that point is genuinely floating.
    private static func pumpUntilSettled(sandbox: Sandbox) -> InterpreterError? {
        var failures: [(name: String, message: String, consumed: ConsumedFlag?)] = []
        while !sandbox.promiseRegistry.isEmpty {
            let ready = sandbox.promiseRegistry.waitAndTakeReadyToSettle(timeout: .now() + watchdogPollInterval)
            if !ready.isEmpty {
                settle(ready, in: sandbox.context, recordingFailuresTo: &failures)
                continue
            }
            guard !sandbox.watchdogState.shouldTerminate() else {
                sandbox.promiseRegistry.cancelAllPending()
                return nil
            }
        }
        guard let floating = failures.first(where: { $0.consumed?.value != true }) else { return nil }
        return InterpreterError(kind: .exception, message: "\(floating.name): \(floating.message)")
    }

    /// Settles every promise in `ready` (see `settle(_:in:)`), appending
    /// each rejection's `name`/message/`ConsumedFlag` to `failures` for
    /// `pumpUntilSettled`'s end-of-drain floating-rejection check.
    private static func settle(
        _ ready: [(resolve: JSValue, reject: JSValue, name: String, outcome: PromiseRegistry.Outcome, consumed: ConsumedFlag?)],
        in context: JSContext,
        recordingFailuresTo failures: inout [(name: String, message: String, consumed: ConsumedFlag?)]
    ) {
        for settlement in ready {
            settle(settlement, in: context)
            guard case .failure(let message) = settlement.outcome else { continue }
            failures.append((settlement.name, message, settlement.consumed))
        }
    }

    /// Settles one promise with its async host function's outcome: resolves
    /// with the JSON-converted value on success, or rejects with an
    /// `"<name>: <error>"` message on failure — matching
    /// `install(hostFunction:into:)`'s sync-throw message shape.
    private static func settle(
        _ settlement: (resolve: JSValue, reject: JSValue, name: String, outcome: PromiseRegistry.Outcome, consumed: ConsumedFlag?),
        in context: JSContext
    ) {
        switch settlement.outcome {
        case .success(let value):
            guard let jsResult = try? jsValue(from: value, in: context) else {
                let reason = JSValue(
                    newErrorFromMessage: "\(settlement.name): could not convert the result to JSON.",
                    in: context
                )
                settlement.reject.call(withArguments: [reason as Any])
                return
            }
            settlement.resolve.call(withArguments: [jsResult])
        case .failure(let message):
            let reason = JSValue(newErrorFromMessage: "\(settlement.name): \(message)", in: context)
            settlement.reject.call(withArguments: [reason as Any])
        }
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
        let jsonString: String = stringified.toString()
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
    private static func jsValue(from value: InterpreterValue, in context: JSContext) throws -> JSValue {
        let data = try JSONEncoder().encode(value)
        let jsonString = String(decoding: data, as: UTF8.self)
        guard
            let json = context.objectForKeyedSubscript("JSON"),
            let parse = json.objectForKeyedSubscript("parse"),
            let parsed = parse.call(withArguments: [jsonString])
        else {
            throw InterpreterError(kind: .exception, message: "JSON.parse is unavailable.")
        }
        return parsed
    }

    // MARK: - Error mapping

    /// Maps a captured JS exception to an `InterpreterError`, extracting a
    /// `message` and, when present, a `line`.
    private static func makeError(from exception: JSValue) -> InterpreterError {
        let message: String
        if exception.isObject, let messageValue = exception.objectForKeyedSubscript("message"), !messageValue.isUndefined {
            message = messageValue.toString()
        } else {
            message = exception.toString() ?? "Unknown JavaScript exception."
        }

        var line: Int?
        if exception.isObject, let lineValue = exception.objectForKeyedSubscript("line"), !lineValue.isUndefined {
            line = Int(lineValue.toInt32())
        }

        return InterpreterError(kind: .exception, message: message, line: line)
    }
}
