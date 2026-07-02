import Foundation
import FoundationModels

/// A pre-call validation failure raised by `ToolInvoker.invoke` before
/// `tool.call(arguments:)` ever runs.
///
/// Deliberately distinct from whatever a tool's own `call(arguments:)`
/// throws (plan.md: "Validation/call errors become JS exceptions carrying
/// the message") — `ToolInvoker.invoke` never wraps a tool's own thrown
/// error in this type, so a caller can always tell "the call never
/// happened" (`ToolInvokerError`) from "the tool ran and failed" (the
/// tool's own error type, propagated unchanged).
public struct ToolInvokerError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What kind of pre-call failure this was.
    public enum Kind: Sendable, Equatable {
        /// A required argument (per `tool.parameters`'s `"required"` list)
        /// was entirely absent from the marshaled `GeneratedContent` — not
        /// merely present with a `null` value, but missing as a key.
        case missingRequiredField

        /// A present, non-null argument's `GeneratedContent.Kind` doesn't
        /// match its schema's declared JSON Schema `"type"` (e.g. a number
        /// where the schema declares `"string"`). Caught independently of
        /// `T.Arguments(content)`'s own throw so the offending field is
        /// always named precisely and deterministically, rather than
        /// depending on the wording of whatever error the `@Generable`
        /// macro's synthesized initializer happens to produce.
        case typeMismatch

        /// A present argument's value violates a `@Guide` constraint its
        /// schema carries — an `enum`/`anyOf` choice, a numeric
        /// `minimum`/`maximum`, or an array `minItems`/`maxItems` — none of
        /// which `T.Arguments(content)`'s own decoding enforces (plan.md:
        /// "`ToolInvoker` adds guide checks... for a precise pre-call
        /// error").
        case guideViolation

        /// `T.Arguments(content)` itself threw, for a reason this
        /// invoker's own checks above didn't already catch — most notably
        /// a nested property's own shape, since those checks only inspect
        /// the *Arguments* struct's immediate top-level properties. The
        /// underlying error's description is folded into `message`.
        case invalidArguments
    }

    /// What kind of failure this was.
    public let kind: Kind

    /// The offending argument's field name, when this failure can be
    /// attributed to one specific property. `nil` for a failure that isn't
    /// about a single named field (e.g. `.invalidArguments`, where
    /// `T.Arguments`'s own decoder didn't identify one either).
    public let field: String?

    /// A human-readable, model-repairable description of the failure —
    /// names the offending field and quotes the violated constraint, per
    /// plan.md's "Validation/call errors carry a precise, model-repairable
    /// message."
    public let message: String

    /// Creates a `ToolInvoker` pre-call validation error.
    ///
    /// - Parameters:
    ///   - kind: what kind of failure this was.
    ///   - field: the offending field name, when known.
    ///   - message: a human-readable, model-repairable description.
    public init(kind: Kind, field: String? = nil, message: String) {
        self.kind = kind
        self.field = field
        self.message = message
    }

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`. Identical to `message`.
    public var description: String { message }
}

/// Invokes a black-box `any Tool` through Swift's implicit existential
/// opening (SE-0352) — the native-call half of the invocation pipeline
/// plan.md specifies for M3b: marshal (via `ArgumentMarshaler`, M3a) →
/// **validate → call** here → render `Output` back out
/// (`ArgumentMarshaler.renderOutput`, also M3a).
///
/// ## Why existential opening, concretely
///
/// A registered tool is held as `any Tool` — its concrete `Arguments`/
/// `Output` types are erased by the time a snippet calls `tools.<name>(…)`.
/// `invoke<T: Tool>(_:content:)` is generic over `T`; passing an `any Tool`
/// value as its first argument makes the compiler *open* the existential —
/// bind `T` to the value's real underlying type for the duration of the
/// call (plan.md Findings #2) — so `T.Arguments(content)` and
/// `tool.call(arguments:)` below are ordinary, statically-typed Swift
/// calls, never reflection or a runtime dispatch table.
///
/// ## Two independent validation layers, both before `call` ever runs
///
/// 1. **This invoker's own top-level check** (`validate`, below) walks
///    `tool.parameters`'s encoded schema — the same encode-then-decode read
///    path `ToolAPIRenderer` uses, since `GenerationSchema` has no
///    field-enumeration API of its own — and checks, for each of the
///    *Arguments* struct's own top-level properties: that a required
///    property is present, that a present property's
///    `GeneratedContent.Kind` matches its declared JSON Schema `"type"`,
///    and that a present property doesn't violate an `enum`/`anyOf`,
///    numeric `minimum`/`maximum`, or array `minItems`/`maxItems` guide.
///    This layer exists specifically for the guide checks —
///    `T.Arguments(content)`'s own decoding does not enforce them at all —
///    and, as a side effect, also gives a **deterministic, precisely
///    field-named** error for a shape/type mismatch, independent of
///    whatever wording the `@Generable` macro's synthesized initializer
///    happens to throw.
/// 2. **`T.Arguments(content)`'s own throwing initializer** (plan.md's
///    "free validation") is still called afterward, as a second,
///    independent line of defense for anything layer 1 doesn't check —
///    most notably a nested property's own shape, since layer 1 only
///    inspects the *Arguments* struct's immediate top-level properties, not
///    recursively into a nested `@Generable` field. `ToolInvoker`
///    deliberately does not reimplement `ToolAPIRenderer`'s full recursive
///    `$ref`-resolving type mapper here — that machinery renders a
///    *declaration*; this invoker only ever needs to check a handful of
///    scalar constraints against already-marshaled values, a much narrower
///    job scoped to the arguments' own top level.
///
/// A tool's own `call(arguments:)` throw is never wrapped in
/// `ToolInvokerError` — it propagates unchanged, so a caller can always
/// distinguish "never called" (`ToolInvokerError`) from "called and
/// failed" (the tool's own error, message intact).
public enum ToolInvoker {
    /// Validates `content` against `tool`'s declared argument schema, then
    /// invokes `tool` natively via existential opening.
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool to invoke. May be passed as a concrete
    ///     `T` or as an `any Tool` existential — SE-0352 implicit opening
    ///     binds `T` to the existential's underlying type either way, so
    ///     this works identically for a tool whose concrete type is
    ///     unnamed at the call site.
    ///   - content: the call's arguments, already marshaled into
    ///     `GeneratedContent` (typically via
    ///     `ArgumentMarshaler.marshalArguments`).
    /// - Returns: `tool`'s `Output`, exactly as `tool.call(arguments:)`
    ///   produced it — rendering it to a JS-ready value is
    ///   `ArgumentMarshaler.renderOutput`'s job, not this function's.
    /// - Throws: `ToolInvokerError` if `content` fails validation before
    ///   `tool.call` runs; otherwise, whatever `tool.call(arguments:)`
    ///   itself throws, unchanged.
    public static func invoke<T: Tool>(_ tool: T, content: GeneratedContent) async throws -> T.Output {
        try validate(content, against: tool.parameters, toolName: tool.name)
        let arguments: T.Arguments
        do {
            arguments = try T.Arguments(content)
        } catch {
            throw ToolInvokerError(
                kind: .invalidArguments,
                message: "Tool \"\(tool.name)\" rejected its arguments: \(error)"
            )
        }
        return try await tool.call(arguments: arguments)
    }

    // MARK: - Pre-call validation

    /// One property's guide-relevant schema attributes — just the subset of
    /// JSON Schema keywords `validate`/`validateType`/`validateGuides`
    /// check, decoded straight off `tool.parameters`'s encoded JSON
    /// (`GenerationSchema` has no field-enumeration API; encode-then-decode
    /// is the read path, the same technique `ToolAPIRenderer.SchemaNode`
    /// uses for a different purpose). Deliberately much narrower than that
    /// type: no `$ref`/`$defs`/`items`/`anyOf` — this invoker only ever
    /// validates the *Arguments* struct's immediate top-level scalar
    /// properties (see this file's top-level documentation), never
    /// recurses into nested structure.
    private struct ArgumentPropertySchema: Decodable {
        let type: String?
        let enumValues: [String]?
        let minimum: Double?
        let maximum: Double?
        let minItems: Int?
        let maxItems: Int?

        enum CodingKeys: String, CodingKey {
            case type
            case enumValues = "enum"
            case minimum, maximum, minItems, maxItems
        }
    }

    /// The top-level shape of an encoded `Tool.Arguments` `GenerationSchema`
    /// this invoker reads: its properties (by name) and which of them are
    /// required.
    private struct ArgumentsSchema: Decodable {
        let properties: [String: ArgumentPropertySchema]?
        let required: [String]?
    }

    /// Encodes `parameters` with `JSONEncoder` (the same call
    /// `ToolAPIRenderer` makes on a tool's schema) and decodes the result
    /// into an `ArgumentsSchema`.
    ///
    /// - Parameters:
    ///   - parameters: the tool's `Arguments` schema.
    ///   - toolName: the owning tool's name, for the error message.
    /// - Returns: the decoded top-level schema shape.
    /// - Throws: `ToolInvokerError` with kind `.invalidArguments` if
    ///   `parameters` fails to encode or its encoded JSON fails to decode
    ///   into an `ArgumentsSchema` — unreachable for any real `Tool`
    ///   (`Arguments` must be a `@Generable` struct, whose `generationSchema`
    ///   always encodes to this shape), kept as a defensive, reportable
    ///   failure rather than a trap.
    private static func decodeArgumentsSchema(
        _ parameters: GenerationSchema,
        toolName: String
    ) throws -> ArgumentsSchema {
        let data: Data
        do {
            data = try JSONEncoder().encode(parameters)
        } catch {
            throw ToolInvokerError(
                kind: .invalidArguments,
                message: "Tool \"\(toolName)\"'s parameters schema failed to encode: \(error)"
            )
        }
        do {
            return try JSONDecoder().decode(ArgumentsSchema.self, from: data)
        } catch {
            throw ToolInvokerError(
                kind: .invalidArguments,
                message: "Tool \"\(toolName)\"'s parameters schema failed to decode: \(error)"
            )
        }
    }

    /// Validates `content` — a marshaled call's arguments — against
    /// `parameters`, `tool`'s declared argument schema, before `call` ever
    /// runs. See this file's top-level documentation for what this checks
    /// versus what's left to `T.Arguments(content)`'s own decoding.
    ///
    /// An **optional** property present in `content` with an explicit
    /// `null` value skips type/guide checking entirely and defers to
    /// `T.Arguments(content)`'s own optional-decoding (which treats a
    /// `null`-kind `GeneratedContent` as `nil`) — `ArgumentMarshaler
    /// .marshalArguments` distinguishes an explicit JS `null` from an
    /// omitted key, and for an optional property both are legitimate ways
    /// to supply "no value." A **required** property's explicit `null`,
    /// though, still runs through `validateType` below like any other
    /// present value: no schema in this SDK ever declares a nullable type
    /// (confirmed by `AppleEncoderParityTests` — there is no `["T",
    /// "null"]` union shape), so `null` can never match a required
    /// property's declared `"type"`, and `validateType` reports that
    /// mismatch with the same precisely-field-named error as any other
    /// wrong-kind value, rather than silently falling through to whatever
    /// wording `T.Arguments(content)`'s synthesized initializer happens to
    /// produce.
    ///
    /// - Parameters:
    ///   - content: the marshaled call arguments to validate.
    ///   - parameters: `tool`'s declared argument schema.
    ///   - toolName: the owning tool's name, for error messages.
    /// - Throws: `ToolInvokerError` with kind `.missingRequiredField`,
    ///   `.typeMismatch`, or `.guideViolation` for the first violation
    ///   found; `.invalidArguments` if `parameters` itself can't be
    ///   decoded.
    private static func validate(
        _ content: GeneratedContent,
        against parameters: GenerationSchema,
        toolName: String
    ) throws {
        let schema = try decodeArgumentsSchema(parameters, toolName: toolName)
        guard let properties = schema.properties, !properties.isEmpty else { return }

        guard case .structure(let contentProperties, _) = content.kind else {
            // `ArgumentMarshaler.marshalArguments` always produces a
            // `.structure`-kind content for a call's arguments (every
            // wrapped tool takes one named-argument object) — unreachable
            // through that path, kept as a defensive failure for any other
            // caller of this function.
            throw ToolInvokerError(
                kind: .typeMismatch,
                message: "Tool \"\(toolName)\" arguments must be an object."
            )
        }

        let required = Set(schema.required ?? [])
        for field in required.sorted() where contentProperties[field] == nil {
            throw ToolInvokerError(
                kind: .missingRequiredField,
                field: field,
                message: "Tool \"\(toolName)\" is missing its required argument \"\(field)\"."
            )
        }

        for field in properties.keys.sorted() {
            guard let value = contentProperties[field] else { continue }
            if value.kind == .null, !required.contains(field) { continue }
            guard let propertySchema = properties[field] else { continue }
            try validateType(value, against: propertySchema, field: field, toolName: toolName)
            try validateGuides(value, against: propertySchema, field: field, toolName: toolName)
        }
    }

    /// Checks that `value`'s `GeneratedContent.Kind` matches
    /// `schema.type`'s JSON Schema category. `nil` if `schema.type` is
    /// absent (e.g. an unresolvable `$ref`) — this invoker doesn't attempt
    /// `ToolAPIRenderer`'s full `$ref` resolution, so an untyped property
    /// silently skips this check and defers to `T.Arguments(content)`.
    ///
    /// - Parameters:
    ///   - value: the marshaled property value to check.
    ///   - schema: the property's schema.
    ///   - field: the property's name, for the error message.
    ///   - toolName: the owning tool's name, for the error message.
    /// - Throws: `ToolInvokerError` with kind `.typeMismatch` if `value`'s
    ///   kind doesn't match `schema.type`.
    private static func validateType(
        _ value: GeneratedContent,
        against schema: ArgumentPropertySchema,
        field: String,
        toolName: String
    ) throws {
        guard let type = schema.type else { return }
        let matches: Bool
        switch (type, value.kind) {
        case ("string", .string): matches = true
        case ("integer", .number), ("number", .number): matches = true
        case ("boolean", .bool): matches = true
        case ("array", .array): matches = true
        case ("object", .structure): matches = true
        default: matches = false
        }
        guard matches else {
            throw ToolInvokerError(
                kind: .typeMismatch,
                field: field,
                message: "Tool \"\(toolName)\" argument \"\(field)\" must be \(type), got \(kindDescription(value.kind)) instead."
            )
        }
    }

    /// Checks `value` against every `@Guide` constraint `schema` carries
    /// for its own JSON Schema category: an `enum` choice for a string, a
    /// `minimum`/`maximum` bound for a number, or a `minItems`/`maxItems`
    /// bound for an array.
    ///
    /// - Parameters:
    ///   - value: the marshaled property value to check.
    ///   - schema: the property's schema.
    ///   - field: the property's name, for the error message.
    ///   - toolName: the owning tool's name, for the error message.
    /// - Throws: `ToolInvokerError` with kind `.guideViolation`, quoting
    ///   the violated constraint, for the first guide `value` violates.
    private static func validateGuides(
        _ value: GeneratedContent,
        against schema: ArgumentPropertySchema,
        field: String,
        toolName: String
    ) throws {
        switch value.kind {
        case .string(let string):
            if let enumValues = schema.enumValues, !enumValues.isEmpty, !enumValues.contains(string) {
                throw ToolInvokerError(
                    kind: .guideViolation,
                    field: field,
                    message: "Tool \"\(toolName)\" argument \"\(field)\" must be one of "
                        + "\(quotedList(enumValues)); got \"\(string)\"."
                )
            }
        case .number(let number):
            if let minimum = schema.minimum, number < minimum {
                throw ToolInvokerError(
                    kind: .guideViolation,
                    field: field,
                    message: "Tool \"\(toolName)\" argument \"\(field)\" must be >= \(minimum); got \(number)."
                )
            }
            if let maximum = schema.maximum, number > maximum {
                throw ToolInvokerError(
                    kind: .guideViolation,
                    field: field,
                    message: "Tool \"\(toolName)\" argument \"\(field)\" must be <= \(maximum); got \(number)."
                )
            }
        case .array(let items):
            if let minItems = schema.minItems, items.count < minItems {
                throw ToolInvokerError(
                    kind: .guideViolation,
                    field: field,
                    message: "Tool \"\(toolName)\" argument \"\(field)\" must have at least "
                        + "\(minItems) item(s); got \(items.count)."
                )
            }
            if let maxItems = schema.maxItems, items.count > maxItems {
                throw ToolInvokerError(
                    kind: .guideViolation,
                    field: field,
                    message: "Tool \"\(toolName)\" argument \"\(field)\" must have at most "
                        + "\(maxItems) item(s); got \(items.count)."
                )
            }
        case .null, .bool, .structure:
            break
        @unknown default:
            // `GeneratedContent.Kind` is a resilient (non-frozen) SDK enum
            // (see `ArgumentMarshaler.sanitizingNonFiniteNumbers`'s
            // identical `@unknown default`); no guide this invoker knows
            // how to check applies to a case it doesn't recognize.
            break
        }
    }

    /// A human-readable category name for `kind`, used in a `.typeMismatch`
    /// error's message.
    private static func kindDescription(_ kind: GeneratedContent.Kind) -> String {
        switch kind {
        case .null: "null"
        case .bool: "a boolean"
        case .number: "a number"
        case .string: "a string"
        case .array: "an array"
        case .structure: "an object"
        @unknown default: "an unrecognized value"
        }
    }

    /// Renders `values` as a comma-separated list of double-quoted
    /// literals, e.g. `"\"c\", \"f\""`, for a `.guideViolation` message
    /// quoting an `enum`/`anyOf` constraint.
    private static func quotedList(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ", ")
    }
}
