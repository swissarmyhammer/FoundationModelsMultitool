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
public protocol Interpreter: Sendable {
    /// Runs `code` with `installing` made available as globals, in a fresh,
    /// isolated execution environment reachable from nowhere else — no state
    /// from a previous `run` is visible, and nothing beyond the standard
    /// language surface and `installing` is reachable from the snippet.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run. A top-level `return` is
    ///     supported — the snippet does not need to be an IIFE itself.
    ///   - installing: host functions to expose as globals for this run only.
    /// - Returns: the snippet's return value and captured console output.
    /// - Throws: `InterpreterError` for a thrown/syntax exception or a
    ///   watchdog timeout.
    func run(code: String, installing: [HostFunction]) throws -> InterpreterResult
}
