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
/// after a context group's execution time limit has been exceeded. Returning
/// `true` terminates the running script; `false` grants it one more
/// time-limit window.
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
/// state directly, so this is how the callback reports back "I fired" to the
/// Swift code waiting on `evaluateScript` to return.
///
/// JSC's documentation does not commit to which thread invokes
/// `JSShouldTerminateCallback` (in practice it is checked from the
/// interpreter loop itself, but that is not a guarantee this code should
/// lean on) — so the flag is lock-protected rather than a plain `Bool`,
/// keeping correctness independent of that unstated thread-affinity detail.
private final class WatchdogState: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    fileprivate var timedOut: Bool {
        lock.withLock { $0 }
    }

    fileprivate func markTimedOut() {
        lock.withLock { $0 = true }
    }
}

/// The watchdog callback itself: always terminates (returns `true`) once
/// invoked, and records that the termination was a timeout rather than an
/// ordinary JS exception, since JSC's own exception-handling path is not
/// guaranteed to surface a normal catchable exception for a watchdog-forced
/// termination.
private func jscTerminateCallback(_: JSContextRef?, _ info: UnsafeMutableRawPointer?) -> Bool {
    guard let info else { return true }
    Unmanaged<WatchdogState>.fromOpaque(info).takeUnretainedValue().markTimedOut()
    return true
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
    /// Wall-clock ceiling for a single `run`, enforced by the
    /// `JSContextGroupSetExecutionTimeLimit` watchdog.
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
        try queue.sync {
            try Self.evaluate(code: code, installing: installing, timeLimit: timeLimit)
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
    /// time-limit watchdog armed. Cleans up any partially-created pieces on
    /// the way out if a later step fails.
    private static func makeSandbox(installing: [HostFunction], timeLimit: TimeInterval) throws -> Sandbox {
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

        let watchdogState = WatchdogState()
        let statePointer = Unmanaged.passUnretained(watchdogState).toOpaque()
        JSContextGroupSetExecutionTimeLimit(group, timeLimit, jscTerminateCallback, statePointer)

        return Sandbox(
            group: group,
            globalContextRef: globalContextRef,
            context: context,
            consoleLines: consoleLines,
            watchdogState: watchdogState
        )
    }

    /// Builds a sandbox, evaluates `code` in it as an IIFE, and maps the
    /// outcome (return value, console lines, exception, or watchdog timeout)
    /// to an `InterpreterResult` or thrown `InterpreterError`.
    private static func evaluate(
        code: String,
        installing: [HostFunction],
        timeLimit: TimeInterval
    ) throws -> InterpreterResult {
        let sandbox = try makeSandbox(installing: installing, timeLimit: timeLimit)
        defer { sandbox.tearDown() }

        var capturedException: JSValue?
        sandbox.context.exceptionHandler = { _, exception in
            capturedException = exception
        }

        // Wrap in an IIFE so a top-level `return` is legal. The opening
        // `(function(){` is prepended to the snippet's own first line
        // (rather than on a line of its own) so every reported line number
        // still matches the caller's original source 1:1.
        let wrapped = "(function(){\(code)\n})()"
        let returnedValue = sandbox.context.evaluateScript(wrapped)

        // Check the watchdog flag before the captured exception: a
        // watchdog-forced termination is not guaranteed to also populate a
        // normal, catchable JS exception, so the flag is the authoritative
        // signal.
        if sandbox.watchdogState.timedOut {
            throw InterpreterError(
                kind: .timeout,
                message: "Execution exceeded the \(timeLimit)s time limit."
            )
        }
        if let capturedException {
            throw makeError(from: capturedException)
        }

        let returnValue = try jsonValue(of: returnedValue, in: sandbox.context)
        return InterpreterResult(returnValue: returnValue, consoleLines: sandbox.consoleLines.lines)
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
