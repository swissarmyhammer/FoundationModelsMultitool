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
/// `HostFunction`s were installed for that run. Nothing set by one run (a
/// global, a host function) is visible to the next.
///
/// The whole run executes on a dedicated background queue — never the
/// caller's thread — which is groundwork for the M4 blocking async bridge:
/// once `tools.X()` calls block that worker thread on a semaphore while the
/// async `Tool.call` runs on the cooperative pool, that blocking must not
/// happen on the caller's (potentially main) thread.
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
    /// sandbox with `installing` made available as globals.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run. A top-level `return` is
    ///     supported — the snippet does not need to be an IIFE itself.
    ///   - installing: host functions to expose as globals for this run only.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `InterpreterError` for a thrown/syntax exception or a
    ///   watchdog timeout.
    public func run(code: String, installing: [HostFunction]) throws -> InterpreterResult {
        try runWithCancellation(code: code, installing: installing, isCancelled: { false })
    }

    /// Runs `code` exactly as `run(code:installing:)` does, but also
    /// force-terminates the run as soon as `isCancelled` reports `true` — see
    /// `Interpreter.run(code:installing:isCancelled:)`.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: host functions to expose as globals for this run only.
    ///   - isCancelled: polled on a short interval while the snippet runs.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `CancellationError` if `isCancelled` reported `true` before
    ///   the run otherwise completed; `InterpreterError` for a thrown/syntax
    ///   exception or a watchdog timeout.
    public func run(
        code: String,
        installing: [HostFunction],
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> InterpreterResult {
        try runWithCancellation(code: code, installing: installing, isCancelled: isCancelled)
    }

    /// Shared body for both `run` overloads above — dispatches onto the
    /// dedicated worker queue and evaluates, differing only in the
    /// `isCancelled` polled while the snippet runs (`run(code:installing:)`
    /// passes a closure that never reports cancellation).
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: host functions to expose as globals for this run only.
    ///   - isCancelled: polled on a short interval while the snippet runs.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `CancellationError` if `isCancelled` reported `true` before
    ///   the run otherwise completed; `InterpreterError` for a thrown/syntax
    ///   exception or a watchdog timeout.
    private func runWithCancellation(
        code: String,
        installing: [HostFunction],
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> InterpreterResult {
        try queue.sync {
            try Self.evaluate(code: code, installing: installing, timeLimit: timeLimit, isCancelled: isCancelled)
        }
    }

    // MARK: - Run

    /// A single run's sandbox: the `JSContextGroup`/`JSContext` pair, the
    /// installed standard surface, and the watchdog wired to that group —
    /// bundled together so `evaluate` doesn't have to juggle their lifetimes
    /// (and matching teardown order) inline.
    private struct Sandbox {
        fileprivate let group: JSContextGroupRef
        fileprivate let globalContextRef: JSGlobalContextRef
        fileprivate let context: JSContext
        fileprivate let consoleLines: ConsoleLines
        fileprivate let watchdogState: WatchdogState

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
            watchdogState: watchdogState
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
        timeLimit: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> InterpreterResult {
        let start = ContinuousClock.now
        logger.debug("runCode snippet started (\(code.count, privacy: .public) characters).")

        let sandbox = try makeSandbox(installing: installing, timeLimit: timeLimit, isCancelled: isCancelled)
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
            let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
            do {
                let values = try arguments.map { try jsonValue(of: $0, in: currentContext) }
                let resultValue = try hostFunction.call(values)
                return try jsValue(from: resultValue, in: currentContext)
            } catch {
                currentContext.exception = JSValue(
                    newErrorFromMessage: "\(hostFunction.name): \(error)",
                    in: currentContext
                )
                return JSValue(undefinedIn: currentContext)
            }
        }
        context.setObject(body, forKeyedSubscript: hostFunction.name as NSString)
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
