import Foundation
import FoundationModels
import os

/// A failure to render a complete, valid `ToolDescriptor` for a tool.
///
/// Thrown only when the schema genuinely cannot be turned into a
/// declaration at all — a missing `"type"` on a node we must render, or a
/// top-level `parameters` schema that isn't an `object` (every `Tool`'s
/// `Arguments` must be a struct, so this only happens when the core
/// `render(name:description:parameters:returns:onWiden:)` entry point is fed
/// a schema directly, bypassing a real `Tool`). This is the "completeness is
/// a contract... throw a descriptive error rather than emit a lossy stub"
/// half of plan.md's contract; the other half — a schema element we
/// recognize but can't express in TypeScript — widens to `any` and reports
/// through `onWiden` instead of throwing.
public struct ToolAPIRendererError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A human-readable description of why rendering failed.
    public let message: String

    /// Creates a renderer error with the given message.
    ///
    /// - Parameter message: a human-readable description of the failure.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Renders a `FoundationModels.Tool`'s public surface — `name`,
/// `description`, and `parameters: GenerationSchema` — into a
/// TypeScript-style declaration with a JSDoc doc comment (plan.md §
/// "`ToolAPIRenderer`: `Tool` → a typed, documented declaration").
///
/// The pipeline is **encode → transliterate → capture comments**:
/// `GenerationSchema` is `Encodable` (Apple's JSON-Schema analog, and the
/// only read path — there is no field-enumeration API), so `render` encodes
/// it with `JSONEncoder`, decodes the result into a small structural mirror
/// (`SchemaNode`), and transliterates that tree into a TS type plus a JSDoc
/// comment per plan.md's type-mapping and doc-mapping tables. Nothing here
/// executes — this is purely descriptive, build-time surface generation; the
/// runtime call path (`ToolInvoker`, M3) carries no schema.
public enum ToolAPIRenderer {
    /// `@usableFromInline` (rather than `private`) because the two `render`
    /// overloads' default `onWiden` argument references it, and a default
    /// argument expression on a `public` function must be at least as
    /// visible as the function itself.
    @usableFromInline
    static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "ToolAPIRenderer")

    /// How a tool's `Output` should be rendered as its `@returns` type.
    public enum Returns: Sendable {
        /// `Output` (or its `PartiallyGenerated`/element type) is itself
        /// `Generable` — render its own `GenerationSchema` as the TS return
        /// type, the same way `parameters` is rendered. This covers both
        /// structured outputs (a `@Generable` struct → a TS object type) and
        /// plain-text outputs, since `String` is itself `Generable` (its
        /// schema is simply `{"type":"string"}`) — one pipeline for both
        /// halves of plan.md's "Return-type handling".
        case schema(GenerationSchema)

        /// `Output` is only known to be `PromptRepresentable` (the `Tool`
        /// protocol's actual bound) — no schema is available, so there is no
        /// author-supplied text to echo. Renders as `string`, documented
        /// with fixed prose per plan.md's "otherwise... type it `string` and
        /// document it in `@returns` prose" — the fallback for Findings #4's
        /// worst case.
        case text
    }

    /// Renders `tool` into a `ToolDescriptor`, deriving `returns` from
    /// `T.Output` automatically: when `Output` is `Generable` (true for
    /// every structured `@Generable` type, and for `String` itself), its own
    /// `generationSchema` becomes the `@returns` type; otherwise the
    /// `.text` fallback applies.
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool to render. Only its public surface
    ///     (`name`, `description`, `parameters`) is read — no source access,
    ///     per Findings #1.
    ///   - onWiden: called with a human-readable message whenever a schema
    ///     element this renderer doesn't have a specific TS mapping for is
    ///     widened to `any`. Defaults to logging via `os.Logger`.
    /// - Returns: `tool`'s rendered name/declaration/doc/example/source.
    /// - Throws: `ToolAPIRendererError` if `tool.parameters` can't be turned
    ///   into a complete declaration (see the type's documentation).
    public static func render<T: Tool>(
        _ tool: T,
        onWiden: @escaping (String) -> Void = { logger.warning("\($0, privacy: .public)") }
    ) throws -> ToolDescriptor {
        let returns: Returns
        if let generableOutput = T.Output.self as? any Generable.Type {
            returns = .schema(generableOutput.generationSchema)
        } else {
            returns = .text
        }
        return try render(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
            returns: returns,
            onWiden: onWiden
        )
    }

    /// Renders a tool's raw surface pieces into a `ToolDescriptor`. This is
    /// the primary, directly testable entry point — `render(_:onWiden:)`
    /// above is a thin convenience wrapper over it for a real `Tool`.
    ///
    /// - Parameters:
    ///   - name: the function name the snippet calls this tool by.
    ///   - description: the tool's leading doc-comment summary.
    ///   - parameters: the tool's `Arguments` schema. Must encode to an
    ///     `object` schema (true for every real `Tool`, since `Arguments`
    ///     must be a `@Generable` struct); anything else throws.
    ///   - returns: how to render the `@returns` type; defaults to `.text`.
    ///   - onWiden: called whenever a schema element widens to `any`.
    ///     Defaults to logging via `os.Logger`.
    /// - Returns: the rendered name/declaration/doc/example/source.
    /// - Throws: `ToolAPIRendererError` if `parameters` (or a schema
    ///   referenced from it) is missing a `"type"` it needs to be rendered,
    ///   references an unresolvable `$ref`, or isn't an `object` at the top
    ///   level.
    public static func render(
        name: String,
        description: String,
        parameters: GenerationSchema,
        returns: Returns = .text,
        onWiden: @escaping (String) -> Void = { logger.warning("\($0, privacy: .public)") }
    ) throws -> ToolDescriptor {
        let parametersNode = try decode(parameters, subject: "\"\(name)\"'s parameters")
        guard parametersNode.type == "object" else {
            throw ToolAPIRendererError(
                "Tool \"\(name)\"'s parameters schema is not an object (found \(parametersNode.type ?? "<none>")); "
                    + "named arguments require an object schema."
            )
        }

        var argsContext = RenderContext(root: parametersNode, defs: parametersNode.defs ?? [:])
        let argsType = try tsType(for: parametersNode, context: &argsContext, path: "args", onWiden: onWiden)

        let order = propertyOrder(of: parametersNode)
        let required = Set(parametersNode.required ?? [])
        var paramLines: [String] = []
        var exampleFields: [String] = []
        for key in order {
            guard let propertyNode = parametersNode.properties?[key] else { continue }
            let isRequired = required.contains(key)
            let clause = paramClause(for: propertyNode, required: isRequired)
            paramLines.append(clause.isEmpty ? "@param args.\(key)" : "@param args.\(key) — \(clause)")
            if isRequired {
                var exampleContext = argsContext
                let literal = try exampleLiteral(for: propertyNode, name: key, context: &exampleContext)
                exampleFields.append("\(key): \(literal)")
            }
        }

        let returnsType: String
        let returnsDescription: String?
        switch returns {
        case .schema(let schema):
            let node = try decode(schema, subject: "\"\(name)\"'s return")
            var returnsContext = RenderContext(root: node, defs: node.defs ?? [:])
            returnsType = try tsType(for: node, context: &returnsContext, path: "returns", onWiden: onWiden)
            returnsDescription = node.description
        case .text:
            returnsType = "string"
            returnsDescription = "plain text result."
        }
        let returnsLine = returnsDescription.map { "@returns \(returnsType) — \($0)" } ?? "@returns \(returnsType)"

        let exampleArgsLiteral = exampleFields.isEmpty ? "{}" : "{ \(exampleFields.joined(separator: ", ")) }"
        let exampleCall = "tools.\(name)(\(exampleArgsLiteral))"
        let exampleLine = "@example const r = \(exampleCall);"

        var docLines = ["/**"]
        docLines.append(contentsOf: commentLines(for: description))
        docLines.append(contentsOf: paramLines.map { " * \($0)" })
        docLines.append(" * \(returnsLine)")
        docLines.append(" * \(exampleLine)")
        docLines.append(" */")
        let doc = docLines.joined(separator: "\n")

        let declaration = "declare function \(name)(args: \(argsType)): \(returnsType);"

        return ToolDescriptor(
            name: name,
            declaration: declaration,
            doc: doc,
            example: "\(exampleCall);",
            source: "\(doc)\n\(declaration)"
        )
    }

    // MARK: - Schema decoding

    /// A minimal, structural mirror of the JSON Schema `GenerationSchema`'s
    /// `Encodable` conformance produces — just the keys `ToolAPIRenderer`
    /// reads. Decoded straight off `JSONEncoder().encode(schema)`, since
    /// `GenerationSchema` has no field-enumeration API of its own (plan.md
    /// Finding #3: encode is the read path).
    ///
    /// A `final class` rather than a `struct`: `items`/`properties` values
    /// are themselves `SchemaNode`s, and a genuinely recursive schema (a
    /// `Tool.Arguments` containing `[Self]`, plan.md's `x-order`/`$ref`
    /// shape confirmed against the compiled SDK) makes this type
    /// self-referential — a value type cannot recursively contain itself,
    /// but a reference type can.
    private final class SchemaNode: Decodable {
        let type: String?
        let title: String?
        let description: String?
        let properties: [String: SchemaNode]?
        let required: [String]?
        let items: SchemaNode?
        let enumValues: [InterpreterValue]?
        let minimum: Double?
        let maximum: Double?
        let minItems: Int?
        let maxItems: Int?
        let pattern: String?
        let ref: String?
        let defs: [String: SchemaNode]?
        let anyOf: [SchemaNode]?
        let propertyOrder: [String]?

        enum CodingKeys: String, CodingKey {
            case type, title, description, properties, required, items
            case enumValues = "enum"
            case minimum, maximum, minItems, maxItems, pattern
            case ref = "$ref"
            case defs = "$defs"
            case anyOf
            case propertyOrder = "x-order"
        }
    }

    /// Encodes `schema` with `JSONEncoder` and decodes the result into a
    /// `SchemaNode` tree.
    private static func decode(_ schema: GenerationSchema, subject: String) throws -> SchemaNode {
        let data: Data
        do {
            data = try JSONEncoder().encode(schema)
        } catch {
            throw ToolAPIRendererError("Failed to encode \(subject) GenerationSchema to JSON: \(error).")
        }
        do {
            return try JSONDecoder().decode(SchemaNode.self, from: data)
        } catch {
            throw ToolAPIRendererError("Failed to decode \(subject) schema's encoded JSON: \(error).")
        }
    }

    // MARK: - Rendering context

    /// Threaded through recursive rendering so `$ref`s can be resolved
    /// (against either the enclosing schema's `$defs`, or `"#"` — a
    /// self-reference to `root`) and cycles detected.
    private struct RenderContext {
        let root: SchemaNode
        let defs: [String: SchemaNode]
        var inProgressRefs: Set<String> = []

        /// Resolves `ref` (`"#"` for the schema's own root, or
        /// `"#/$defs/Name"` for a named nested type) against this context.
        func resolve(_ ref: String) -> SchemaNode? {
            if ref == "#" { return root }
            guard let name = ref.split(separator: "/").last else { return nil }
            return defs[String(name)]
        }
    }

    /// The declared property order for an object node — `x-order` when
    /// present (always, for a real encoded `GenerationSchema`), falling back
    /// to alphabetical for any schema that omits it.
    private static func propertyOrder(of node: SchemaNode) -> [String] {
        node.propertyOrder ?? (node.properties ?? [:]).keys.sorted()
    }

    // MARK: - Type rendering (the type-mapping table)

    /// Renders `node`'s TypeScript type, resolving `$ref`s and recursing
    /// into `object`/`array` structure. Widens anything this function
    /// doesn't have a specific mapping for to `any`, reporting through
    /// `onWiden` — except a missing `"type"` (and no `anyOf` either), which
    /// means the node can't be identified at all, so it throws instead (the
    /// completeness contract: throw rather than emit a lossy stub).
    ///
    /// This throw is defensive: `GenerationSchema`'s own `Decodable`
    /// conformance already rejects a property lacking every one of
    /// `"type"`/`"const"`/`"$ref"`/`"anyOf"` at decode time (confirmed
    /// against the compiled SDK — see
    /// `AppleEncoderParityTests`/`ToolAPIRendererTests
    /// .unidentifiableSchemaNodeCannotEvenBeConstructed`), so no real
    /// `GenerationSchema` value can reach this branch. It stays as a second,
    /// independent line of defense rather than dead weight to remove.
    private static func tsType(
        for node: SchemaNode,
        context: inout RenderContext,
        path: String,
        onWiden: (String) -> Void
    ) throws -> String {
        if let ref = node.ref {
            guard !context.inProgressRefs.contains(ref) else {
                onWiden("Cyclic $ref \"\(ref)\" at \(path); widening to `any`.")
                return "any"
            }
            guard let resolved = context.resolve(ref) else {
                throw ToolAPIRendererError("Unresolvable $ref \"\(ref)\" at \(path).")
            }
            context.inProgressRefs.insert(ref)
            defer { context.inProgressRefs.remove(ref) }
            return try tsType(for: resolved, context: &context, path: path, onWiden: onWiden)
        }

        guard let type = node.type else {
            if node.anyOf != nil {
                onWiden("Unrenderable schema element (anyOf) at \(path); widening to `any`.")
                return "any"
            }
            throw ToolAPIRendererError("Schema node at \(path) has no \"type\" and cannot be rendered.")
        }

        switch type {
        case "object":
            return try renderObjectType(node, context: &context, path: path, onWiden: onWiden)
        case "string":
            if let enumValues = node.enumValues, !enumValues.isEmpty {
                return enumUnion(enumValues)
            }
            return "string"
        case "integer", "number":
            return "number"
        case "boolean":
            return "boolean"
        case "array":
            guard let items = node.items else {
                throw ToolAPIRendererError("Array schema at \(path) is missing \"items\".")
            }
            let elementType = try tsType(for: items, context: &context, path: "\(path)[]", onWiden: onWiden)
            return "\(elementType)[]"
        default:
            onWiden("Unrecognized schema type \"\(type)\" at \(path); widening to `any`.")
            return "any"
        }
    }

    /// Renders an `object` node's properties as an inline TS object type,
    /// `{ a: T; b?: U }`, in declared order.
    private static func renderObjectType(
        _ node: SchemaNode,
        context: inout RenderContext,
        path: String,
        onWiden: (String) -> Void
    ) throws -> String {
        let properties = node.properties ?? [:]
        guard !properties.isEmpty else { return "{}" }
        let required = Set(node.required ?? [])
        var parts: [String] = []
        for key in propertyOrder(of: node) {
            guard let propertyNode = properties[key] else { continue }
            let propertyType = try tsType(for: propertyNode, context: &context, path: "\(path).\(key)", onWiden: onWiden)
            let optionalMark = required.contains(key) ? "" : "?"
            parts.append("\(key)\(optionalMark): \(propertyType)")
        }
        return "{ \(parts.joined(separator: "; ")) }"
    }

    // MARK: - Doc-comment rendering (the doc-mapping table)

    /// Splits `text` into JSDoc comment lines, each prefixed `" * "`. Text is
    /// author-supplied (`tool.description`) and rendered verbatim — the
    /// renderer never fabricates or appends punctuation to it.
    private static func commentLines(for text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { " * \($0)" }
    }

    /// Composes one property's `@param` clause — the text after
    /// `@param args.<name> — `, or `""` if the property has neither a
    /// description nor any guide-derived constraint to report.
    ///
    /// Order (matching the worked `WeatherTool` example's `units` param —
    /// `"temperature unit; one of \"c\" | \"f\". (optional)"`): the
    /// author's `description`, joined to an `enum` clause with `"; "` when
    /// both are present; then any type-specific constraint parenthetical
    /// (`(integer)`, numeric range, pattern, or item count); then
    /// `"(optional)"` for a non-required property. `GenerationSchema` has no
    /// default-value concept (see `AppleEncoderParityTests`), so no `default
    /// …` clause is ever rendered.
    private static func paramClause(for node: SchemaNode, required: Bool) -> String {
        var lead = node.description ?? ""
        if let enumValues = node.enumValues, !enumValues.isEmpty {
            let clause = "one of \(enumUnion(enumValues))."
            lead = lead.isEmpty ? clause : "\(lead); \(clause)"
        }

        var clauses: [String] = []
        if node.type == "integer" { clauses.append("(integer)") }
        if let rangeClause = numericRangeClause(node) { clauses.append(rangeClause) }
        if let patternClause = patternClause(node) { clauses.append(patternClause) }
        if let countClause = countClause(node) { clauses.append(countClause) }
        if !required { clauses.append("(optional)") }

        var fragments: [String] = []
        if !lead.isEmpty { fragments.append(lead) }
        fragments.append(contentsOf: clauses)
        return fragments.joined(separator: " ")
    }

    /// Renders a numeric guide's `minimum`/`maximum`/`range` as a
    /// parenthetical, e.g. `"(range 1…10)"`, `"(minimum 1)"`, or
    /// `"(maximum 10)"`. `nil` if neither bound is present.
    private static func numericRangeClause(_ node: SchemaNode) -> String? {
        guard node.type == "integer" || node.type == "number" else { return nil }
        switch (node.minimum, node.maximum) {
        case let (minimum?, maximum?):
            return "(range \(formatNumber(minimum))…\(formatNumber(maximum)))"
        case let (minimum?, nil):
            return "(minimum \(formatNumber(minimum)))"
        case let (nil, maximum?):
            return "(maximum \(formatNumber(maximum)))"
        default:
            return nil
        }
    }

    /// Renders a string guide's `pattern` as a parenthetical, e.g.
    /// `"(pattern: /[A-Z]{3}/)"`. `nil` if no pattern is present.
    private static func patternClause(_ node: SchemaNode) -> String? {
        guard let pattern = node.pattern else { return nil }
        return "(pattern: /\(pattern)/)"
    }

    /// Renders an array guide's `minItems`/`maxItems`/`count` as a
    /// parenthetical, e.g. `"(1…3 items)"`, `"(1+ items)"`, or `"(up to 3
    /// items)"`. `nil` if neither bound is present.
    private static func countClause(_ node: SchemaNode) -> String? {
        guard node.type == "array" else { return nil }
        switch (node.minItems, node.maxItems) {
        case let (minItems?, maxItems?):
            return "(\(minItems)…\(maxItems) items)"
        case let (minItems?, nil):
            return "(\(minItems)+ items)"
        case let (nil, maxItems?):
            return "(up to \(maxItems) items)"
        default:
            return nil
        }
    }

    // MARK: - Example synthesis

    /// Synthesizes a plausible, syntactically valid JS literal for one
    /// required property, used to build the auto-generated `@example` call.
    /// Optional properties are never included in the example (plan.md:
    /// "optionals are simply omitted... the call site is self-documenting").
    ///
    /// The placeholder scheme is intentionally generic — there is no schema
    /// signal (no example/default value `GenerationSchema` can carry, per
    /// `AppleEncoderParityTests`) to derive a more specific literal from:
    /// the first `enum` choice when constrained, the property's own `name`
    /// for an unconstrained `string` (self-documenting without implying a
    /// real value), a range's `minimum` (else `0`) for numbers, `true` for
    /// booleans, and a single recursively-synthesized element for a
    /// non-empty-required array.
    private static func exampleLiteral(
        for node: SchemaNode,
        name: String,
        context: inout RenderContext
    ) throws -> String {
        if let ref = node.ref {
            guard let resolved = context.resolve(ref) else {
                throw ToolAPIRendererError("Unresolvable $ref \"\(ref)\" while synthesizing an example for \"\(name)\".")
            }
            return try exampleLiteral(for: resolved, name: name, context: &context)
        }
        if let enumValues = node.enumValues, let first = enumValues.first {
            return tsLiteral(first)
        }
        switch node.type {
        case "string":
            return "\"\(name)\""
        case "integer", "number":
            return formatNumber(node.minimum ?? 0)
        case "boolean":
            return "true"
        case "array":
            guard let items = node.items else { return "[]" }
            guard (node.minItems ?? 0) >= 1 else { return "[]" }
            let element = try exampleLiteral(for: items, name: "item", context: &context)
            return "[\(element)]"
        case "object":
            return try exampleObjectLiteral(node, context: &context)
        default:
            // Unrenderable (e.g. `anyOf`) — already reported via `onWiden`
            // when the type was rendered; a null placeholder keeps the
            // example syntactically valid.
            return "null"
        }
    }

    /// Builds `{ field: value, … }` for an object node's required
    /// properties, recursively synthesizing each field's example literal.
    private static func exampleObjectLiteral(_ node: SchemaNode, context: inout RenderContext) throws -> String {
        let properties = node.properties ?? [:]
        guard !properties.isEmpty else { return "{}" }
        let required = Set(node.required ?? [])
        var fields: [String] = []
        for key in propertyOrder(of: node) where required.contains(key) {
            guard let propertyNode = properties[key] else { continue }
            fields.append("\(key): \(try exampleLiteral(for: propertyNode, name: key, context: &context))")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    // MARK: - Literal formatting

    /// Renders an enum's choices as a TS literal union, e.g. `"c" | "f"`.
    ///
    /// The type-mapping table's row covers both string and number literal
    /// unions, but in this SDK `GenerationGuide.anyOf(_:)` — the only way a
    /// real `@Generable` type produces an `"enum"` array at all — is
    /// exclusively `where Value == String` (confirmed against the compiled
    /// `FoundationModels.swiftinterface`: no `Int`/`Double`/`Bool` overload
    /// exists). So `tsLiteral`'s `.number`/`.bool` cases are unreachable
    /// through any real `GenerationSchema`, the same category as the
    /// default-value and nullable-union findings in
    /// `AppleEncoderParityTests` — kept for forward-compatibility (a future
    /// SDK, or a hand-built `DynamicGenerationSchema`, could add one) rather
    /// than assumed dead.
    private static func enumUnion(_ values: [InterpreterValue]) -> String {
        values.map(tsLiteral).joined(separator: " | ")
    }

    /// Renders one JSON scalar as a TS literal.
    private static func tsLiteral(_ value: InterpreterValue) -> String {
        switch value {
        case .string(let string):
            return "\"\(string)\""
        case .number(let number):
            return formatNumber(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null, .array, .object:
            // Enum/default values are always JSON scalars in practice; this
            // is an unreachable-in-practice fallback that keeps the
            // function total rather than partial.
            return "null"
        }
    }

    /// Formats a `Double` without a trailing `.0` for whole numbers (JSON
    /// Schema `minimum`/`maximum` decode as `Double` even for an `integer`
    /// schema), and via its normal description otherwise.
    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}
