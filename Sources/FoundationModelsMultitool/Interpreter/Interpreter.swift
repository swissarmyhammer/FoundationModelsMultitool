import Foundation

/// A JSON-shaped value used at the interpreter boundary.
///
/// `Interpreter` conformers speak JSON in both directions — a snippet's
/// `return` value comes back as one of these cases, and host-function
/// arguments/results cross the same seam — so callers never depend on any
/// specific JS engine's native value representation (`JSValue` and friends
/// stay private to `JSCInterpreter`).
public indirect enum InterpreterValue: Sendable, Equatable {
    /// The JSON `null` value.
    case null
    /// A JSON boolean.
    case bool(Bool)
    /// A JSON number.
    case number(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array of values.
    case array([InterpreterValue])
    /// A JSON object mapping string keys to values.
    case object([String: InterpreterValue])
}

extension InterpreterValue: Codable {
    /// Creates an `InterpreterValue` by decoding the given decoder's JSON
    /// value, trying null, bool, number, string, array, and object in turn.
    ///
    /// - Parameter decoder: the decoder to read the JSON value from.
    /// - Throws: `DecodingError` if the decoded value is not valid JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([InterpreterValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: InterpreterValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value at \(decoder.codingPath)."
            )
        }
    }

    /// Encodes this value to the given encoder as the corresponding JSON
    /// value, degrading non-finite `.number` values to `null`.
    ///
    /// - Parameter encoder: the encoder to write the JSON value to.
    /// - Throws: `EncodingError` if the underlying container fails to encode
    ///   the value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            // JSON has no literal for NaN/±Infinity. `JSONEncoder` throws on
            // a non-finite `Double` by default; instead, degrade the same
            // way a snippet's own `JSON.stringify` would (it silently turns
            // NaN/±Infinity into `null`), so both conversion directions
            // agree and a stray non-finite value never surfaces as an
            // encoding error.
            if value.isFinite {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

/// A native Swift function installed into the interpreter's global scope for
/// the duration of one `run`, callable from the snippet by `name`.
///
/// This is the seam through which later milestones (`ToolInvoker`, M3) bind
/// wrapped `Tool`s in as `tools.<name>` functions; M1 only needs the shape —
/// arguments and results cross in/out as `InterpreterValue`, same as the
/// snippet's own `return` value.
///
/// `AsyncHostFunction`, below, mirrors this struct's shape exactly except for
/// `call`'s `async`; that is deliberate, not overlooked duplication — Swift
/// has no way to parameterize a stored closure's `async`-ness generically
/// (there is no shared protocol/effect-polymorphism over `throws` vs.
/// `async throws` closure types), so the two structs stay separate,
/// hand-written types rather than one generic over the effect.
public struct HostFunction: Sendable {
    /// The identifier the snippet calls this function by.
    public let name: String

    /// The native implementation. Receives the call's arguments already
    /// converted to `InterpreterValue`; its return value becomes what the
    /// snippet's call expression evaluates to.
    public let call: @Sendable ([InterpreterValue]) throws -> InterpreterValue

    /// Creates a host function with the given name and implementation.
    ///
    /// Explicit (rather than relying on the compiler-synthesized memberwise
    /// initializer) because a `public` struct's synthesized initializer is
    /// only `internal`-accessible — without this, no module outside
    /// `FoundationModelsMultitool` could construct a `HostFunction`, even
    /// though this type is a required parameter of the public
    /// `Interpreter.run(code:installing:)` API.
    ///
    /// - Parameters:
    ///   - name: the global identifier the snippet calls this function by.
    ///   - call: the native implementation.
    public init(name: String, call: @escaping @Sendable ([InterpreterValue]) throws -> InterpreterValue) {
        self.name = name
        self.call = call
    }
}

/// A native Swift function installed into the interpreter's global scope for
/// the duration of one `run`, callable from the snippet by `name` — the
/// asynchronous counterpart to `HostFunction`.
///
/// The interpreter installs every `AsyncHostFunction` as a JS function that
/// returns a `Promise`: `call` runs in its own Swift `Task`, and the
/// interpreter settles the promise with that `Task`'s outcome once it
/// completes (see the event-loop documentation of `JSCInterpreter`). Two calls
/// installed together run concurrently — a snippet's own
/// `Promise.all([tools.a(), tools.b()])` starts both `Task`s at once.
///
/// Per the plan's one-rule contract (eventplan.md "Async JavaScript": "each
/// call that goes into Swift effects returns a promise... these calls are
/// synchronous: `help()`/`docs()`... and `notify()`/`progress()`"), reserve
/// this for anything that does a real Swift effect — a tool invocation, an
/// elicitation, a wait — and keep the synchronous `HostFunction` for pure
/// surface reads and void enqueue-and-continue calls.
public struct AsyncHostFunction: Sendable {
    /// The identifier the snippet calls this function by.
    public let name: String

    /// The native implementation. Receives the call's arguments already
    /// converted to `InterpreterValue`; its return value becomes the value
    /// the returned JS `Promise` resolves to, and a thrown error becomes the
    /// promise's rejection reason.
    public let call: @Sendable ([InterpreterValue]) async throws -> InterpreterValue

    /// Creates an async host function with the given name and
    /// implementation.
    ///
    /// Explicit (rather than relying on the compiler-synthesized memberwise
    /// initializer) for the same reason as `HostFunction.init`: a `public`
    /// struct's synthesized initializer is only `internal`-accessible.
    ///
    /// - Parameters:
    ///   - name: the global identifier the snippet calls this function by.
    ///   - call: the native implementation.
    public init(name: String, call: @escaping @Sendable ([InterpreterValue]) async throws -> InterpreterValue) {
        self.name = name
        self.call = call
    }
}

/// The outcome of a successful `Interpreter.run`.
public struct InterpreterResult: Sendable, Equatable {
    /// The snippet's `return` value, JSON-shaped. A snippet with no explicit
    /// `return` (or one that returns `undefined`) produces `.null`.
    public let returnValue: InterpreterValue

    /// Every `console.log` line, in call order.
    public let consoleLines: [String]

    /// Creates an interpreter result with the given return value and console
    /// lines.
    ///
    /// Explicit for the same reason as `HostFunction.init`: a `public`
    /// struct's synthesized memberwise initializer is only
    /// `internal`-accessible, and any external `Interpreter` conformer needs
    /// to construct an `InterpreterResult` to return from `run`.
    ///
    /// - Parameters:
    ///   - returnValue: the snippet's `return` value, JSON-shaped.
    ///   - consoleLines: every `console.log` line, in call order.
    public init(returnValue: InterpreterValue, consoleLines: [String]) {
        self.returnValue = returnValue
        self.consoleLines = consoleLines
    }
}

/// A typed failure from `Interpreter.run`.
public struct InterpreterError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What kind of failure produced this error.
    public enum Kind: Sendable, Equatable {
        /// The snippet threw, or a syntax/runtime error occurred while
        /// parsing or evaluating it.
        case exception
        /// The watchdog terminated a run that exceeded its configured time
        /// limit.
        case timeout
    }

    /// What kind of failure this was.
    public let kind: Kind

    /// A human-readable description of the failure.
    public let message: String

    /// The 1-based source line the failure is attributed to, when the
    /// engine can report one.
    public let line: Int?

    /// Creates an error describing a failure from `Interpreter.run`.
    ///
    /// - Parameters:
    ///   - kind: whether this is a thrown/syntax exception or a watchdog
    ///     timeout.
    ///   - message: a human-readable description of the failure.
    ///   - line: the 1-based source line the failure is attributed to.
    ///     Populated when the engine can attribute the failure to a specific
    ///     line — e.g. a thrown exception or a syntax error — and `nil` when
    ///     it can't, as with a `.timeout` (the watchdog terminates execution
    ///     without a specific line to blame).
    public init(kind: Kind, message: String, line: Int? = nil) {
        self.kind = kind
        self.message = message
        self.line = line
    }

    /// A human-readable description of the error, including the source line
    /// when one is available.
    public var description: String {
        guard let line else { return message }
        return "\(message) (line \(line))"
    }
}

/// Runs a JavaScript snippet against a set of installed host functions and
/// reports back its `return` value and captured console output.
///
/// Conformers own the whole sandbox lifecycle for a single `run` — engine
/// selection is an implementation detail behind this protocol. `JSCInterpreter`
/// (JavaScriptCore) is the only conformer today, but the seam exists so the
/// engine is swappable without touching callers.
///
/// A conformer has no clock. It stops a run only when the calling `Task` is
/// cancelled. The host that owns the time budget cancels that `Task`: for
/// `runCode`, this is the one tool-level timeout (`MultiTool.timeout(from:)`).
public protocol Interpreter: Sendable {
    /// Runs `code` with `installing` and `installingAsync` made available as
    /// globals, in a fresh, isolated execution environment reachable from
    /// nowhere else — no state from a previous `run` is visible, and nothing
    /// beyond the standard language surface and the installed functions is
    /// reachable from the snippet. This is the one requirement every other
    /// `run` overload in this protocol forwards to (see the default
    /// conformances below).
    ///
    /// Each call the snippet makes to one of `installingAsync` returns a JS
    /// `Promise` backed by its own Swift `Task`, so `Promise.all` over several
    /// calls runs them concurrently.
    ///
    /// The run gives no result until every promise the bridge created for
    /// `installingAsync` has settled — a floating call
    /// (`tools.files.write(...); return "done";`) always completes its
    /// work, and a floating rejection always becomes the run's error, even
    /// when the snippet's own `return` never awaited it (eventplan.md
    /// "Async JavaScript": settle-before-return).
    ///
    /// The call is `async`, and a run that waits for an async host function
    /// holds no thread: a conformer suspends the caller until the run
    /// settles, and it executes the snippet only in short jobs.
    ///
    /// Cancelling the `Task` that awaits this call terminates the run: the
    /// conformer stops the snippet, cancels the `Task` of each pending async
    /// host function call, and throws `CancellationError`.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run. A top-level `return` is
    ///     supported — the snippet does not need to be an IIFE itself.
    ///   - installing: synchronous host functions to expose as globals for
    ///     this run only.
    ///   - installingAsync: asynchronous host functions to expose as
    ///     globals for this run only.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `CancellationError` if the calling `Task` was cancelled
    ///   before the run otherwise completed; `InterpreterError` for a
    ///   thrown/syntax exception or a floating rejection.
    func run(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction]
    ) async throws -> InterpreterResult

    /// Parses `code` and reports whether it is syntactically valid, without
    /// installing a single host function and without executing any of it.
    ///
    /// The parse covers exactly what `run` would evaluate, wrapping included,
    /// so a top-level `return` and a top-level `await` are as legal here as
    /// they are there, and a reported line number refers to the caller's own
    /// source.
    ///
    /// This is the deterministic first gate a caller applies to a snippet it
    /// did not write — `SearchToolsTool`'s generated sample — before it is worth
    /// looking at anything else about it. An unresolved identifier is not a
    /// syntax error, so a snippet naming a global this check never installed
    /// still parses.
    ///
    /// This requirement deliberately has no default conformance below. Either
    /// default would answer for a conformer that has no parser to ask: one
    /// that never throws turns the gate into a rubber stamp, and one that
    /// always throws turns off sample generation entirely. A conformer answers
    /// for itself instead.
    ///
    /// - Parameter code: the JavaScript source to parse.
    /// - Throws: `InterpreterError` of kind `.exception`, carrying the
    ///   engine's own parse-failure message and the line it blames, when
    ///   `code` does not parse.
    func checkSyntax(of code: String) throws
}

extension Interpreter {
    /// Default conformance: forwards to
    /// `run(code:installing:installingAsync:)` with no asynchronous host
    /// functions.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: host functions to expose as globals for this run only.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: whatever `run(code:installing:installingAsync:)` itself
    ///   throws.
    public func run(code: String, installing: [HostFunction]) async throws -> InterpreterResult {
        try await run(code: code, installing: installing, installingAsync: [])
    }
}
