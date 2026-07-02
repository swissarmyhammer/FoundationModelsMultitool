import Foundation
import FoundationModels

/// A failure to marshal a JS argument object into `GeneratedContent`, or to
/// render a tool `Output` back out to a JS-ready value.
public struct ArgumentMarshalerError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What kind of marshaling failure this was.
    public enum Kind: Sendable, Equatable {
        /// `marshalArguments` was given something other than a JS object
        /// (`InterpreterValue.object`) — every tool call is `tools.name({…})`,
        /// a single object argument (plan.md: "every generated function
        /// takes a single object argument"), so anything else can't be
        /// turned into a `GeneratedContent` of named properties.
        case argumentsNotAnObject

        /// `renderOutput` was given an `Output` that is `PromptRepresentable`
        /// (the `Tool` protocol's actual bound) but not also
        /// `ConvertibleToGeneratedContent` — see `ArgumentMarshaler`'s "Pin"
        /// documentation for why this case has no supported rendering.
        case outputNotGenerable

        /// A `Generable` `Output`'s own `generatedContent.jsonString` did not
        /// decode as JSON. Not reachable through any real `Generable`
        /// conformance (its `jsonString` is documented to always be valid
        /// JSON) — kept as a defensive, reportable failure rather than a
        /// trap, mirroring `ToolAPIRenderer`'s "throw rather than crash" posture.
        case malformedOutputJSON
    }

    /// What kind of failure this was.
    public let kind: Kind

    /// A human-readable description of the failure.
    public let message: String

    /// Creates a marshaling error of the given kind with the given message.
    ///
    /// - Parameters:
    ///   - kind: what kind of failure this was.
    ///   - message: a human-readable description of the failure.
    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`. Identical to `message`.
    public var description: String { message }
}

/// Marshals values across the JS ⇄ `GeneratedContent` boundary a wrapped
/// tool call crosses twice: **in**, a snippet's argument object becomes the
/// `GeneratedContent` `ToolInvoker` (M3b) validates against `T.Arguments`;
/// **out**, a tool's `Output` becomes the JS-ready value a `runCode` snippet
/// sees (plan.md § "`ArgumentMarshaler`: JS value ⇄ `GeneratedContent`").
///
/// Both directions cross through `InterpreterValue`, not a raw `JSValue` —
/// `JSCInterpreter` (M1) already converts every `tools.X(...)` call's
/// arguments from `JSValue` to `InterpreterValue` before a `HostFunction`
/// ever runs (`JSCInterpreter.jsonValue(of:in:)`), and converts an
/// `InterpreterValue` result back to `JSValue` the same way on the way out.
/// `InterpreterValue` is exactly the engine-agnostic seam `Interpreter`'s own
/// documentation calls out ("`JSValue` and friends stay private to
/// `JSCInterpreter`") — routing through it here keeps `ArgumentMarshaler`
/// (and everything built on it, including `ToolInvoker`) independent of
/// which `Interpreter` conformer is in use, and matches `ToolInvoker`'s own
/// committed signature (`invoke<T: Tool>(_:content: GeneratedContent)`,
/// which likewise never mentions `JSValue`).
///
/// ## Pin (plan.md Finding #4): the `ToolOutput` accessor
///
/// The plan's Finding #4 flagged one open pin: "the exact accessor for
/// `ToolOutput`'s underlying `GeneratedContent` (its DocC page 404'd)".
/// Checked directly against the compiled OS-27 SDK
/// (`FoundationModels.swiftinterface`): **no such type exists.** The only
/// `ToolOutput` in the module is `Transcript.ToolOutput` — a transcript
/// *record* of a completed call, unrelated to what a `Tool` author returns.
/// A `Tool`'s `Output` associated type is bound only to `PromptRepresentable`
/// (`associatedtype Output: PromptRepresentable`) — there is no wrapper type
/// to find an accessor on at all; the plan's premise (a `ToolOutput` struct a
/// tool returns) doesn't hold. The real, resolved pipeline:
///
/// - Every practical `Output` — a `@Generable` struct, a bare `String`
///   (itself `Generable`), `Bool`/`Int`/`Double`, or an array of any of
///   those — is `ConvertibleToGeneratedContent` (via `Generable`, which
///   refines it), so its `.generatedContent` is read directly off the value,
///   no accessor pin needed. `renderOutput` checks for this capability with
///   `output as? any ConvertibleToGeneratedContent` — that protocol (not
///   `Generable`) is used for the check because it declares exactly the one
///   member this function needs (`generatedContent`) and, having no
///   associated types, is unconditionally safe to use as an existential.
/// - The residual case — an `Output` that conforms to `PromptRepresentable`
///   directly, without also being `Generable`/`ConvertibleToGeneratedContent`
///   — has **no supported rendering**, and this is now a *confirmed* SDK
///   gap, not a "worst case, fall back to text" as the plan hoped: the
///   `PromptRepresentable.promptRepresentation` a non-`Generable` type
///   exposes is a `Prompt`, and `Prompt` (the top-level type, not
///   `Transcript.Prompt`) has no public string accessor at all — only
///   `Sendable` conformance and its two initializers, confirmed by reading
///   every extension of it in `FoundationModels.swiftinterface`. `renderOutput`
///   throws `.outputNotGenerable` for this case with a clear message rather
///   than fabricate placeholder text. In practice this only affects an
///   `Output` type that deliberately implements `PromptRepresentable` by
///   hand instead of using `@Generable` — every tool this package's
///   milestones actually wrap (M4 onward) uses `@Generable` outputs.
public enum ArgumentMarshaler {
    // MARK: - In: JS argument object -> GeneratedContent

    /// Marshals a snippet's call argument — always a single JS object,
    /// `tools.name({ … })` — into a `GeneratedContent` built directly from
    /// its key/value pairs via `GeneratedContent`'s `properties:id:`
    /// initializer. No schema is consulted here (validation against a
    /// tool's `Arguments` happens downstream, in `ToolInvoker`/M3b) and no
    /// JSON string is round-tripped — every value is read off `arguments`
    /// and converted natively.
    ///
    /// A key present with an explicit JS `null` marshals as a property whose
    /// `GeneratedContent.kind` is `.null` — present, distinct from a key the
    /// snippet never set at all, which is simply absent from the result
    /// (matching JS's own `JSON.stringify` semantics for an omitted object
    /// property, which is exactly how `JSCInterpreter` produces `arguments`
    /// in the first place).
    ///
    /// - Parameter arguments: the call's single argument, as converted from
    ///   `JSValue` by the interpreter. Must be `.object` — every wrapped
    ///   tool's generated declaration takes one named-argument object
    ///   (plan.md: "object (named) parameters, always — never positional").
    /// - Returns: a `GeneratedContent` whose `.kind` is `.structure`, one
    ///   property per key in `arguments`.
    /// - Throws: `ArgumentMarshalerError` with kind `.argumentsNotAnObject`
    ///   if `arguments` is not `.object`.
    public static func marshalArguments(_ arguments: InterpreterValue) throws -> GeneratedContent {
        guard case .object(let fields) = arguments else {
            let kindDescription: String =
                switch arguments {
                case .null: "null"
                case .bool: "a boolean"
                case .number: "a number"
                case .string: "a string"
                case .array: "an array"
                case .object: "an object"
                }
            throw ArgumentMarshalerError(
                kind: .argumentsNotAnObject,
                message: "Tool call arguments must be a JS object (`tools.name({ … })`); "
                    + "got \(kindDescription) instead."
            )
        }
        // `fields` is a Swift `Dictionary`, so keys are already unique —
        // `uniquingKeysWith` can never actually run; it exists only because
        // `GeneratedContent`'s only *runtime-constructible* `properties:`
        // overload (a compile-time `KeyValuePairs` literal can't be built
        // from a dynamic key set) requires one. Sorted for a deterministic
        // property order — `InterpreterValue.object` is itself a
        // `Dictionary`, so the JS object's original insertion order was
        // already lost by the time it reached here; alphabetical is at
        // least stable run to run, the same tradeoff `ToolAPIRenderer` makes
        // for a schema that lacks its own `x-order`.
        let properties: [(String, any ConvertibleToGeneratedContent)] = fields.sorted { $0.key < $1.key }.map { key, value in
            (key, content(from: value))
        }
        return GeneratedContent(
            properties: properties,
            id: nil,
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Recursively converts one JSON-shaped `InterpreterValue` into the
    /// equivalent `GeneratedContent`, built directly off `GeneratedContent`'s
    /// own `Kind` cases — the native representation, not a JSON string.
    /// Shared by every nesting level (`marshalArguments`'s top-level
    /// properties, array elements, and nested-object properties), so array
    /// and object nesting recurse through the exact same conversion.
    ///
    /// - Parameter value: the JSON-shaped value to convert.
    /// - Returns: the equivalent `GeneratedContent`.
    private static func content(from value: InterpreterValue) -> GeneratedContent {
        switch value {
        case .null:
            return GeneratedContent(kind: .null)
        case .bool(let boolValue):
            return GeneratedContent(kind: .bool(boolValue))
        case .number(let numberValue):
            // `GeneratedContent.jsonString` does not throw for a non-finite
            // `Double` (`.nan`/`.infinity`) — it traps the process (an
            // internal `try!` around `JSONEncoder`, confirmed by direct
            // execution against the compiled OS-27 SDK) — so a non-finite
            // value must never reach a `.number` kind at all. Degrading to
            // `.null` mirrors `InterpreterValue.encode`'s own precedent for
            // the identical problem one layer up (and matches what a
            // snippet's own `JSON.stringify` already does to a non-finite
            // number), so both directions of this boundary agree.
            return GeneratedContent(kind: numberValue.isFinite ? .number(numberValue) : .null)
        case .string(let stringValue):
            return GeneratedContent(kind: .string(stringValue))
        case .array(let items):
            return GeneratedContent(kind: .array(items.map(content(from:))))
        case .object(let fields):
            return GeneratedContent(
                kind: .structure(
                    properties: fields.mapValues(content(from:)),
                    orderedKeys: fields.keys.sorted()
                )
            )
        }
    }

    // MARK: - Out: tool Output -> JS-ready value

    /// Renders a tool's `Output` back out to the JS-ready `InterpreterValue`
    /// a `runCode` snippet's call expression evaluates to (plan.md:
    /// "structured `Output`'s `GeneratedContent` has a `jsonString`, parsed
    /// into a JS object; a text `Output` becomes a string").
    ///
    /// One pipeline covers both halves of that split: whenever `output` is
    /// also `ConvertibleToGeneratedContent` (true for every `@Generable`
    /// type, and for `String` itself, which is `Generable`), its
    /// `generatedContent.jsonString` is decoded straight into an
    /// `InterpreterValue` — a `.structure`-kind content decodes to
    /// `.object`, a bare `.string`-kind content (a `String` `Output`)
    /// decodes to `.string`, and so on for every `GeneratedContent.Kind` —
    /// so "structured renders as an object, text renders as a string"
    /// follows for free from what `Output`'s own content actually is,
    /// with no separate text-only code path to keep in sync. See this
    /// type's documentation for the resolved `ToolOutput` accessor pin and
    /// why the non-`Generable` fallback below is a hard, documented gap
    /// rather than a text rendering.
    ///
    /// - Parameter output: the tool's `Output` value to render.
    /// - Returns: the JS-ready `InterpreterValue` a snippet's call
    ///   expression should evaluate to.
    /// - Throws: `ArgumentMarshalerError` with kind `.outputNotGenerable` if
    ///   `output` is `PromptRepresentable` but not also
    ///   `ConvertibleToGeneratedContent`; kind `.malformedOutputJSON` in the
    ///   unreachable-in-practice case that a `Generable` value's own
    ///   `jsonString` fails to decode.
    public static func renderOutput<Output: PromptRepresentable>(_ output: Output) throws -> InterpreterValue {
        guard let generatedContentOutput = output as? any ConvertibleToGeneratedContent else {
            throw ArgumentMarshalerError(
                kind: .outputNotGenerable,
                message: "Output type \(type(of: output)) is `PromptRepresentable` but not "
                    + "`ConvertibleToGeneratedContent` (e.g. not `@Generable`), so its result can't "
                    + "be rendered: `FoundationModels.Prompt` (the type its `promptRepresentation` "
                    + "would produce) has no public accessor to recover text from. Return a "
                    + "`@Generable` type (or `String`) from this tool's `call(arguments:)` instead."
            )
        }
        let jsonString = sanitizingNonFiniteNumbers(in: generatedContentOutput.generatedContent).jsonString
        do {
            return try JSONDecoder().decode(InterpreterValue.self, from: Data(jsonString.utf8))
        } catch {
            throw ArgumentMarshalerError(
                kind: .malformedOutputJSON,
                message: "Output type \(type(of: output))'s GeneratedContent.jsonString was not "
                    + "valid JSON: \(error)."
            )
        }
    }

    /// Recursively rebuilds `content` with every non-finite `Double`
    /// (`.nan`/`.infinity`/`-.infinity`) found anywhere in its `.number`
    /// positions replaced with `.null`, so `renderOutput` can safely read
    /// `.jsonString` on the result afterward.
    ///
    /// This guard exists for the same reason as the identical one in
    /// `content(from:)`: `GeneratedContent.jsonString` traps the process
    /// (rather than throwing) for a non-finite number anywhere in the
    /// content tree — confirmed by direct execution against the compiled
    /// OS-27 SDK. Unlike `marshalArguments`'s input, a real tool's
    /// `Generable` `Output` is author-controlled Swift, not JS-derived —
    /// its `Double` fields can plausibly evaluate to a non-finite value
    /// (a division, an average of an empty collection, an overflow), so
    /// this is a real, reachable case here too, not defensive dead code.
    /// `.id` is intentionally dropped when a node is rebuilt (via
    /// `GeneratedContent(kind:)`'s default `id: nil`) — harmless, since the
    /// sanitized copy only ever feeds `.jsonString`, which carries no
    /// identity information anyway.
    ///
    /// - Parameter content: the content to sanitize.
    /// - Returns: an equivalent `GeneratedContent` with every non-finite
    ///   number degraded to `.null`.
    private static func sanitizingNonFiniteNumbers(in content: GeneratedContent) -> GeneratedContent {
        switch content.kind {
        case .null, .bool, .string:
            return content
        case .number(let numberValue):
            return numberValue.isFinite ? content : GeneratedContent(kind: .null)
        case .array(let items):
            return GeneratedContent(kind: .array(items.map(sanitizingNonFiniteNumbers(in:))))
        case .structure(let properties, let orderedKeys):
            return GeneratedContent(
                kind: .structure(
                    properties: properties.mapValues(sanitizingNonFiniteNumbers(in:)),
                    orderedKeys: orderedKeys
                )
            )
        @unknown default:
            // `GeneratedContent.Kind` is a resilient (non-frozen) SDK enum,
            // so the compiler requires this case even though every case
            // documented in the compiled `FoundationModels.swiftinterface`
            // is already handled above. Returning `content` unchanged is the
            // conservative choice — a hypothetical future case can't be
            // sanitized without knowing its shape, and it's no worse than
            // today (this function only ever *removes* a crash risk it
            // knows how to find).
            return content
        }
    }
}
