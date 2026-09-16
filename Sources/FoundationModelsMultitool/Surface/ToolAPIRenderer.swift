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

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`.
    ///
    /// Identical to `message`.
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
///
/// Two entry points share one text format. The schema path,
/// `render(name:description:parameters:returns:onWiden:)`, decodes a
/// `GenerationSchema` into `RenderedParameter` values in the schema's own
/// `x-order`. The typed path, `render(name:description:arguments:returns:onWiden:)`,
/// takes those values from the caller, in list order. Only the typed path
/// writes the declaration, the doc comment and the example, so a surface a
/// caller builds from typed parameters and a surface a schema produces
/// cannot drift apart.
///
/// One thing the rendered surface states that no schema can: a `tools.*`
/// binding is asynchronous. The declared return type is therefore
/// `Promise<T>` around the schema's own `T`, and the `@example` call site
/// awaits it — see
/// `render(name:description:arguments:returns:onWiden:)`.
public enum ToolAPIRenderer {
    /// `@usableFromInline` (rather than `private`) because the three `render`
    /// overloads' default `onWiden` argument references it, and a default
    /// argument expression on a `public` function must be at least as
    /// visible as the function itself.
    @usableFromInline
    static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "ToolAPIRenderer")

    /// The JSDoc continuation-line prefix (`" * "`) shared by every line of
    /// the doc comment this renderer emits — the summary/description lines,
    /// `@param`, `@returns`, and `@example`.
    private static let docLinePrefix = " * "

    /// How a tool's `Output` should be rendered as its `@returns` type.
    ///
    /// Every case names the type a call *resolves to*; the renderer wraps it
    /// in `Promise<…>` before declaring it, since a `tools.*` call returns a
    /// promise (see `render(name:description:parameters:returns:onWiden:)`).
    public enum Returns: Sendable {
        /// `Output` (or its `PartiallyGenerated`/element type) is itself
        /// `Generable` — render its own `GenerationSchema` as the TS return
        /// type, the same way `parameters` is rendered.
        ///
        /// This covers both structured outputs (a `@Generable` struct → a TS
        /// object type) and plain-text outputs, since `String` is itself
        /// `Generable` (its schema is simply `{"type":"string"}`) — one
        /// pipeline for both halves of plan.md's "Return-type handling".
        case schema(GenerationSchema)

        /// `Output` is only known to be `PromptRepresentable` (the `Tool`
        /// protocol's actual bound) — no schema is available, so there is no
        /// author-supplied text to echo.
        ///
        /// Resolves to `string`, documented with fixed prose per plan.md's
        /// "otherwise... type it `string` and document it in `@returns`
        /// prose" — the fallback for Findings #4's worst case.
        case text

        /// `Output` is JSON text the binding parses before it hands the value
        /// to the snippet, and the JSON carries no declared structure.
        ///
        /// Resolves to `object`, documented with the fixed prose
        /// `JSON result, parsed.`, so a declaration ends in `Promise<object>`.
        case json
    }

    /// One parameter of a tool's surface, as a typed caller states it.
    ///
    /// The schema path reads one of these from each property of a decoded
    /// `GenerationSchema`; a typed caller builds them by hand. Either way the
    /// list, in order, is what `render(name:description:arguments:returns:onWiden:)`
    /// renders the `args` object type, the `@param` lines and the `@example`
    /// call from.
    public struct RenderedParameter: Sendable, Equatable {
        /// The parameter's name, exactly as the snippet spells the key.
        public let name: String

        /// The parameter's declared shape.
        public let shape: ToolValueShape

        /// Whether a call must supply the parameter.
        public let isRequired: Bool

        /// The author's prose for the `@param` line, or `""` for none.
        public let description: String

        /// Parenthetical constraint clauses the `@param` line shows after the
        /// description and the choice clause, before the required mark —
        /// `(integer)`, `(range 1…10)`, `(pattern: /[A-Z]{3}/)`, `(1…3 items)`.
        /// A schema derives them from its guides; a typed caller usually has
        /// none.
        public let constraints: [String]

        /// The JavaScript literal the `@example` call passes for this
        /// parameter when it is required, or `nil` to synthesize one from
        /// `shape`. A schema supplies the literal its guides shape — a range's
        /// minimum, one element for an array that needs at least one — which
        /// the shape alone cannot know.
        ///
        /// The value must be exactly one JavaScript literal expression — a
        /// string, a number, `true`, `false` or `null`, or an array or object
        /// literal built from those — as `JavaScriptLiteralSyntax` recognizes
        /// it. The text is spliced into generated code, so
        /// `render(name:description:arguments:returns:onWiden:)` checks it
        /// and throws `ToolAPIRendererError` for any other text, rather than
        /// let a caller's value close the example's object literal or open a
        /// statement of its own.
        public let exampleValue: String?

        /// Creates a rendered parameter.
        ///
        /// Explicit for the same reason as `ToolDescriptor.init`: a `public`
        /// struct's synthesized initializer is only `internal`-accessible.
        ///
        /// - Parameters:
        ///   - name: the parameter's name.
        ///   - shape: the parameter's declared shape.
        ///   - isRequired: whether a call must supply the parameter.
        ///   - description: the author's prose for the `@param` line.
        ///   - constraints: the parenthetical constraint clauses; none by
        ///     default.
        ///   - exampleValue: the example literal to show for a required
        ///     parameter, or `nil` to synthesize one from `shape`. Must be
        ///     one JavaScript literal expression; `render` refuses any other
        ///     text.
        public init(
            name: String,
            shape: ToolValueShape,
            isRequired: Bool,
            description: String,
            constraints: [String] = [],
            exampleValue: String? = nil
        ) {
            self.name = name
            self.shape = shape
            self.isRequired = isRequired
            self.description = description
            self.constraints = constraints
            self.exampleValue = exampleValue
        }
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

    /// Renders a tool's raw surface pieces into a `ToolDescriptor`.
    ///
    /// This is the schema path: it decodes `parameters`, reads each property
    /// into a `RenderedParameter` in the schema's own `x-order`, and hands
    /// the list to `render(name:description:arguments:returns:onWiden:)`,
    /// which writes the text. `render(_:onWiden:)` above is a thin
    /// convenience wrapper over this for a real `Tool`.
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
    /// - Throws: `ToolAPIRendererError` if `name` isn't a legal TypeScript
    ///   identifier (schema-derived text is never trusted to be safe to
    ///   splice straight into a `declare function` signature), or if
    ///   `parameters` (or a schema referenced from it) is missing a `"type"`
    ///   it needs to be rendered, references an unresolvable `$ref`, or
    ///   isn't an `object` at the top level.
    public static func render(
        name: String,
        description: String,
        parameters: GenerationSchema,
        returns: Returns = .text,
        onWiden: @escaping (String) -> Void = { logger.warning("\($0, privacy: .public)") }
    ) throws -> ToolDescriptor {
        let parametersNode = try decode(parameters, subject: "\"\(name)\"'s parameters")
        guard parametersNode.type == typeObject else {
            throw ToolAPIRendererError(
                "Tool \"\(name)\"'s parameters schema is not an object (found \(parametersNode.type ?? "<none>")); "
                    + "named arguments require an object schema."
            )
        }
        var context = RenderContext(root: parametersNode, defs: parametersNode.defs ?? [:])
        let arguments = try renderedParameters(of: parametersNode, context: &context, onWiden: onWiden)
        return try render(name: name, description: description, arguments: arguments, returns: returns, onWiden: onWiden)
    }

    /// Renders a tool's surface from typed parameters.
    ///
    /// This is the typed path, and the one place that writes the text
    /// format: every other `render` overload ends here. The parameters
    /// render in list order — the `args` object type, the `@param` lines and
    /// the `@example` call (which names the required parameters only) all
    /// follow it — so a caller that builds its parameters by hand gets the
    /// same surface a schema would.
    ///
    /// - Parameters:
    ///   - name: the function name the snippet calls this tool by.
    ///   - description: the tool's leading doc-comment summary.
    ///   - arguments: the tool's parameters, in the order to render them.
    ///   - returns: how to render the `@returns` type; defaults to `.text`.
    ///   - onWiden: called whenever a `.schema` return widens to `any`.
    ///     Defaults to logging via `os.Logger`.
    /// - Returns: the rendered name/declaration/doc/example/source.
    /// - Throws: `ToolAPIRendererError` if `name` isn't a legal TypeScript
    ///   identifier (schema-derived text is never trusted to be safe to
    ///   splice straight into a `declare function` signature), if a required
    ///   parameter's `exampleValue` is not one JavaScript literal expression
    ///   (caller-supplied text is never trusted to be safe to splice into
    ///   the `@example` call either), or if a `.schema` return cannot be
    ///   rendered.
    public static func render(
        name: String,
        description: String,
        arguments: [RenderedParameter],
        returns: Returns = .text,
        onWiden: @escaping (String) -> Void = { logger.warning("\($0, privacy: .public)") }
    ) throws -> ToolDescriptor {
        guard isLegalTSIdentifier(name) else {
            throw ToolAPIRendererError(
                "Tool name \"\(name)\" is not a legal TypeScript identifier "
                    + "(must match ^[A-Za-z_$][A-Za-z0-9_$]*$); refusing to emit a "
                    + "`declare function` declaration for it rather than risk breaking "
                    + "out of the generated code."
            )
        }
        let argumentsShape = ToolObjectShape(
            properties: arguments.map {
                ToolObjectShape.Property(name: $0.name, shape: $0.shape, isRequired: $0.isRequired)
            }
        )
        let paramLines = arguments.map { paramLine(for: $0) }
        // Optional parameters are never included in the example (plan.md:
        // "optionals are simply omitted... the call site is self-documenting").
        let exampleFields = try arguments.filter(\.isRequired).map { parameter in
            let literal = try exampleLiteral(for: parameter)
            return "\(objectKeyLiteral(parameter.name)): \(literal)"
        }

        let result = try resolvedResult(of: returns, name: name, onWiden: onWiden)
        // Every `tools.<name>` binding is installed as an `AsyncHostFunction`
        // on the interpreter's promise pump (eventplan.md "Async JavaScript"),
        // so the call evaluates to a JS `Promise` and the declared result
        // shape is only what awaiting it yields. Wrapping once here — rather
        // than at each of the two splice sites — is what keeps the
        // `declare function` signature and the `@returns` line (which derives
        // from this same string, via `docReturnsType` below) from ever
        // disagreeing about what a call actually returns.
        let returnsType = "Promise<\(result.shape.declaredType)>"
        // `returnsType` also backs the real `declare function` return type
        // in `declaration` below, so it's escaped here into a doc-only
        // copy rather than in place — a schema-derived enum choice
        // embedded in it (via `declaredType(of:)`'s `.string` branch) must
        // not be altered in the type this renderer actually declares. Only
        // this copy, used in `returnsLine`, needs `*/`-safety, since only
        // this copy lands inside the JSDoc block.
        let docReturnsType = escapeForJSDocComment(returnsType)
        let returnsLine = result.description.map {
            "@returns \(docReturnsType) — \(escapeForJSDocComment($0))"
        } ?? "@returns \(docReturnsType)"

        let exampleArgsLiteral = exampleFields.isEmpty ? "{}" : "{ \(exampleFields.joined(separator: ", ")) }"
        // The `await` is part of the call this renderer teaches, not
        // decoration: the call itself only yields the promise `returnsType`
        // now declares, and reaching into that promise for a field
        // (`r.tempC`) raises the interpreter's "did you forget `await`?"
        // repair error instead of reading the resolved value. Every snippet
        // body runs inside an async function, so this is directly runnable
        // as written.
        let exampleCall = "await tools.\(name)(\(exampleArgsLiteral))"
        // Same reasoning as `docReturnsType`: `exampleCall` also backs
        // `ToolDescriptor.example` below (left raw and runnable, for
        // direct copy-paste execution), so only this doc-line copy is
        // escaped for `*/`-safety — `exampleCall` can embed a schema-derived
        // enum choice or property name via `exampleLiteral`/`objectKeyLiteral`.
        let exampleLine = "@example const r = \(escapeForJSDocComment(exampleCall));"

        let docLines = ["/**"] + commentLines(for: description) + paramLines.map { "\(docLinePrefix)\($0)" }
            + ["\(docLinePrefix)\(returnsLine)", "\(docLinePrefix)\(exampleLine)", " */"]
        let doc = docLines.joined(separator: "\n")

        let declaration = "declare function \(name)(args: \(argumentsShape.declaredType)): \(returnsType);"

        return ToolDescriptor(
            name: name,
            description: description,
            declaration: declaration,
            doc: doc,
            example: "\(exampleCall);",
            source: "\(doc)\n\(declaration)",
            signature: ToolSignature(arguments: argumentsShape, result: result.shape)
        )
    }

    /// Reads a top-level `parameters` object node's properties as typed
    /// parameters, in declared order, each carrying the guide clauses and the
    /// example literal only its schema node knows.
    ///
    /// - Parameters:
    ///   - node: the top-level `parameters` object node.
    ///   - context: the rendering context for `$ref` resolution and cycle
    ///     detection.
    ///   - onWiden: called when a property's shape widens to `.any`.
    /// - Returns: one parameter per declared property, in `x-order`.
    /// - Throws: whatever `objectShape(_:context:path:onWiden:)` or
    ///   `exampleLiteral(for:name:context:)` throws for one of the node's
    ///   properties.
    private static func renderedParameters(
        of node: SchemaNode,
        context: inout RenderContext,
        onWiden: (String) -> Void
    ) throws -> [RenderedParameter] {
        let properties = node.properties ?? [:]
        let argumentsShape = try objectShape(node, context: &context, path: "args", onWiden: onWiden)
        return try argumentsShape.properties.compactMap { property -> RenderedParameter? in
            guard let propertyNode = properties[property.name] else { return nil }
            var exampleContext = context
            let exampleValue = try property.isRequired
                ? exampleLiteral(for: propertyNode, name: property.name, context: &exampleContext)
                : nil
            return RenderedParameter(
                name: property.name,
                shape: property.shape,
                isRequired: property.isRequired,
                description: propertyNode.description ?? "",
                constraints: constraintClauses(for: propertyNode),
                exampleValue: exampleValue
            )
        }
    }

    /// Resolves what awaiting a call yields: the result shape, and the prose
    /// for the `@returns` line when there is any.
    ///
    /// - Parameters:
    ///   - returns: how the tool's `Output` renders.
    ///   - name: the tool's name, for error messages.
    ///   - onWiden: called when a `.schema` element widens to `.any`.
    /// - Returns: the result shape and its `@returns` prose.
    /// - Throws: `ToolAPIRendererError` when a `.schema` return cannot be
    ///   rendered.
    private static func resolvedResult(
        of returns: Returns,
        name: String,
        onWiden: (String) -> Void
    ) throws -> (shape: ToolValueShape, description: String?) {
        switch returns {
        case .schema(let schema):
            let node = try decode(schema, subject: "\"\(name)\"'s return")
            var context = RenderContext(root: node, defs: node.defs ?? [:])
            return (try shape(for: node, context: &context, path: "returns", onWiden: onWiden), node.description)
        case .text:
            return (.string(choices: []), "plain text result.")
        case .json:
            return (.json, "JSON result, parsed.")
        }
    }

    // MARK: - Raw JSON Schema text

    /// Encodes `schema` to its raw JSON Schema source text — the same
    /// `JSONEncoder` call `decode(_:subject:)` below makes on a tool's
    /// schema (plan.md Finding #3: "encode is the read path"), exposed here
    /// for a caller that needs the JSON Schema *string* itself — e.g. to
    /// constrain a guided-generation grammar (`Grammar.jsonSchema(_:)`) —
    /// rather than a rendered TypeScript declaration.
    ///
    /// - Parameter schema: the schema to encode.
    /// - Returns: the encoded JSON Schema source text.
    /// - Throws: `ToolAPIRendererError` if `schema` fails to encode — not
    ///   expected for a real tool's `parameters` (a `GenerationSchema`
    ///   derived from a `@Generable` `Arguments` struct always encodes
    ///   successfully), kept as a defensive, reportable failure rather than
    ///   a trap, matching this type's "throw rather than crash" posture.
    public static func jsonSchemaString(for schema: GenerationSchema) throws -> String {
        let data: Data
        do {
            data = try JSONEncoder().encode(schema)
        } catch {
            throw ToolAPIRendererError("Failed to encode GenerationSchema to JSON: \(error).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Schema decoding

    /// A minimal, structural mirror of the JSON Schema `GenerationSchema`'s
    /// `Encodable` conformance produces — just the keys `ToolAPIRenderer`
    /// reads.
    ///
    /// Decoded straight off `JSONEncoder().encode(schema)`, since
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
    ///
    /// - Parameters:
    ///   - schema: the schema to encode and decode.
    ///   - subject: a label for error messages.
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

    // MARK: - String safety (escaping schema-derived text)
    //
    // `GenerationSchema` carries author-supplied, otherwise-unvalidated text
    // — tool/property names and descriptions, regex patterns — that this
    // renderer splices directly into generated TypeScript source and JSDoc
    // comments. None of it can be trusted to be "safe" TS/JS/comment syntax
    // on its own; every splice site below routes through one of these
    // shared helpers so an unusual (or malicious) schema value can widen,
    // get escaped, or throw, but can never corrupt or break out of the
    // generated declaration.

    /// The identifier grammar this renderer accepts for a name it emits
    /// bare — a tool name (as a `declare function <name>(...)` signature)
    /// or a property name (as an unquoted object-literal key): an ASCII
    /// letter, `_`, or `$`, followed by any number of ASCII letters,
    /// digits, `_`, or `$`.
    ///
    /// Deliberately narrower than the full TypeScript identifier grammar
    /// (which also permits non-ASCII Unicode identifier characters) — a
    /// schema-derived name outside this unambiguous subset is safer
    /// treated as "not a bare identifier" (rejected outright for a tool
    /// name, or re-rendered as a quoted string key for a property name via
    /// `objectKeyLiteral`) than risk misclassifying an edge case as safe
    /// to emit unquoted.
    ///
    /// Built with `Regex(_:)` + matched via `wholeMatch(of:)` rather than
    /// `NSRegularExpression` with `^`/`$` anchors: `NSRegularExpression`'s
    /// `$` matches before a trailing line terminator (not only at the true
    /// end of the string), so `^...$` alone would accept a name like
    /// `"toolName\n"` as "legal" — `wholeMatch(of:)` requires the pattern to
    /// consume the entire string, with no such carve-out.
    ///
    /// `nonisolated(unsafe)`: `Regex` doesn't conform to `Sendable` (a
    /// compiler-level gap, not a real thread-safety issue — a compiled
    /// `Regex` is an immutable value type, safe to read concurrently), so
    /// Swift 6 strict concurrency would otherwise reject this `static let`.
    nonisolated(unsafe) private static let identifierPattern = try! Regex("[A-Za-z_$][A-Za-z0-9_$]*")

    /// Whether `name` can be emitted bare — as a `declare function` name or
    /// an unquoted object-literal key — without risking a syntax break (or
    /// code injection) from schema-derived text.
    ///
    /// Internal (not `private`), rather than duplicated, so
    /// `MultiTool.Builder.build()` (M2.5, `MultiToolBuilder.swift`) can
    /// reuse this exact check on a group name before splicing it into a
    /// generated `tools.<group>.<name>` namespace — the same posture this
    /// file takes toward a tool's own `name`.
    static func isLegalTSIdentifier(_ name: String) -> Bool {
        name.wholeMatch(of: identifierPattern) != nil
    }

    /// Escapes `text` for safe interpolation into a JS/TS double-quoted
    /// string literal: backslashes first (so a backslash already present
    /// in `text` isn't re-escaped by the quote-escaping step that
    /// follows), then double quotes.
    ///
    /// Internal (not `private`), rather than duplicated, so `TypedMockDryRun`
    /// can build on it when it splices a rendered declared type or a property
    /// name into the JavaScript harness it generates — the same posture this
    /// file takes toward sharing `isLegalTSIdentifier`.
    static func escapeForJSStringLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Renders `text` as a complete JavaScript double-quoted string literal.
    ///
    /// Builds on ``escapeForJSStringLiteral(_:)`` — which neutralizes the
    /// backslashes and the quotes — and additionally neutralizes the line
    /// terminators JavaScript forbids inside a string literal, then puts the
    /// result between double quotes. No text can close the literal or open
    /// code of its own.
    ///
    /// Internal (not `private`), rather than duplicated, so `TypedMockDryRun`
    /// splices a rendered declared type into its harness through it, and the
    /// test fixtures splice a path or a file content into a snippet through
    /// it — the same posture this file takes toward sharing
    /// `escapeForJSStringLiteral`.
    ///
    /// - Parameter text: the text to render.
    /// - Returns: the quoted, escaped JavaScript string literal.
    static func jsStringLiteral(_ text: String) -> String {
        let escaped = escapeForJSStringLiteral(text)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\"\(escaped)\""
    }

    /// Renders `key` as an object-literal key for the auto-generated
    /// `@example` call: bare (`field`) when it's a legal TS identifier, or
    /// a quoted, escaped string-literal key (`"field\"x\""`) otherwise.
    ///
    /// Shared by every example-literal builder that writes a property name
    /// as an object key (the top-level `exampleFields` in
    /// `render(name:description:parameters:returns:onWiden:)` and
    /// `exampleObjectLiteral`'s nested fields), so a schema-derived
    /// property name can never break out of the generated object-literal
    /// syntax.
    private static func objectKeyLiteral(_ key: String) -> String {
        isLegalTSIdentifier(key) ? key : "\"\(escapeForJSStringLiteral(key))\""
    }

    /// Escapes `text` for safe interpolation into a `/** … */` JSDoc
    /// block: replaces every embedded `*/` with `* /` (space-separated),
    /// so schema-derived text (a tool or property `description`) can
    /// never terminate the comment block early and "escape" into the
    /// generated declaration that follows it.
    private static func escapeForJSDocComment(_ text: String) -> String {
        text.replacingOccurrences(of: "*/", with: "* /")
    }

    /// Escapes `pattern` for safe rendering inside the doc-text `/pattern/`
    /// regex-literal form `patternClause` renders: replaces every embedded
    /// `/` with `\/`, so an embedded delimiter can't prematurely terminate
    /// the literal (and corrupt the surrounding `@param` clause).
    private static func escapeForRegexLiteralDoc(_ pattern: String) -> String {
        pattern.replacingOccurrences(of: "/", with: "\\/")
    }

    // MARK: - Type rendering (the type-mapping table)

    /// The TypeScript `any` type name, returned whenever a schema element
    /// widens rather than mapping to a precise TS type — `shape(for:context:
    /// path:onWiden:)` widens from three distinct branches.
    private static let anyTypeName = "any"

    /// The JSON Schema `"type"` keyword's scalar values this renderer
    /// recognizes, compared or switched on against `SchemaNode.type`
    /// throughout `shape(for:context:path:onWiden:)` and its sibling
    /// doc/example-synthesis helpers below.
    ///
    /// Named rather than inlined because each is referenced at three or
    /// more call sites.
    private static let typeObject = "object"
    private static let typeString = "string"
    private static let typeInteger = "integer"
    private static let typeNumber = "number"
    private static let typeBoolean = "boolean"
    private static let typeArray = "array"

    /// Renders `shape`'s TypeScript type — the one place a `ToolValueShape`
    /// becomes the text a `declare function` line carries.
    ///
    /// Backs `ToolValueShape.declaredType`. Rendering from the shape rather
    /// than from the schema a second time is what makes the advertised
    /// signature and the structural signature one description of a tool
    /// instead of two: there is no second traversal to fall out of step.
    ///
    /// - Parameter shape: the declared shape to render.
    /// - Returns: the rendered TypeScript type.
    static func declaredType(of shape: ToolValueShape) -> String {
        switch shape {
        case .string(let choices):
            return choices.isEmpty ? typeString : enumUnion(choices)
        case .number:
            return typeNumber
        case .boolean:
            return typeBoolean
        case .array(let element):
            return "\(declaredType(of: element))[]"
        case .object(let object):
            return declaredType(ofObject: object)
        case .json:
            return typeObject
        case .any:
            return anyTypeName
        }
    }

    /// Renders an object shape as an inline TS object type, `{ a: T; b?: U }`,
    /// in declared order.
    ///
    /// Keys go through `objectKeyLiteral`, same as the example-literal
    /// builders — this is the *real* declared type (embedded in `declare
    /// function`'s signature, not just a doc/example), so a schema-derived
    /// property name containing a quote or other special character must
    /// not be allowed to break out of the object-type syntax here either.
    ///
    /// Backs `ToolObjectShape.declaredType`.
    ///
    /// - Parameter object: the declared object shape to render.
    /// - Returns: the rendered inline TS object type.
    static func declaredType(ofObject object: ToolObjectShape) -> String {
        guard !object.properties.isEmpty else { return "{}" }
        let parts = object.properties.map { property in
            let optionalMark = property.isRequired ? "" : "?"
            return "\(objectKeyLiteral(property.name))\(optionalMark): \(declaredType(of: property.shape))"
        }
        return "{ \(parts.joined(separator: "; ")) }"
    }

    /// Reads `node`'s declared shape, resolving `$ref`s and recursing into
    /// `object`/`array` structure.
    ///
    /// Widens anything this function doesn't have a specific mapping for to
    /// `.any`, reporting through `onWiden` — except a missing `"type"` (and
    /// no `anyOf` either), which means the node can't be identified at all,
    /// so it throws instead (the completeness contract: throw rather than
    /// emit a lossy stub).
    ///
    /// This throw is defensive: `GenerationSchema`'s own `Decodable`
    /// conformance already rejects a property lacking every one of
    /// `"type"`/`"const"`/`"$ref"`/`"anyOf"` at decode time (confirmed
    /// against the compiled SDK — see
    /// `AppleEncoderParityTests`/`ToolAPIRendererTests
    /// .unidentifiableSchemaNodeCannotEvenBeConstructed`), so no real
    /// `GenerationSchema` value can reach this branch. It stays as a second,
    /// independent line of defense rather than dead weight to remove.
    ///
    /// - Parameters:
    ///   - node: the schema node whose declared shape to read.
    ///   - context: the rendering context for `$ref` resolution and cycle
    ///     detection.
    ///   - path: the node's location within the schema, for error and
    ///     `onWiden` messages.
    ///   - onWiden: called when this node's shape widens to `.any`.
    /// - Returns: the node's declared shape.
    /// - Throws: `ToolAPIRendererError` when the node cannot be identified,
    ///   references an unresolvable `$ref`, or is an array missing `"items"`.
    private static func shape(
        for node: SchemaNode,
        context: inout RenderContext,
        path: String,
        onWiden: (String) -> Void
    ) throws -> ToolValueShape {
        if let ref = node.ref {
            guard !context.inProgressRefs.contains(ref) else {
                onWiden("Cyclic $ref \"\(ref)\" at \(path); widening to `any`.")
                return .any
            }
            guard let resolved = context.resolve(ref) else {
                throw ToolAPIRendererError("Unresolvable $ref \"\(ref)\" at \(path).")
            }
            context.inProgressRefs.insert(ref)
            defer { context.inProgressRefs.remove(ref) }
            return try shape(for: resolved, context: &context, path: path, onWiden: onWiden)
        }

        guard let type = node.type else {
            if node.anyOf != nil {
                onWiden("Unrenderable schema element (anyOf) at \(path); widening to `any`.")
                return .any
            }
            throw ToolAPIRendererError("Schema node at \(path) has no \"type\" and cannot be rendered.")
        }

        switch type {
        case typeObject:
            return .object(try objectShape(node, context: &context, path: path, onWiden: onWiden))
        case typeString:
            return .string(choices: node.enumValues ?? [])
        case typeInteger, typeNumber:
            return .number
        case typeBoolean:
            return .boolean
        case typeArray:
            guard let items = node.items else {
                throw ToolAPIRendererError("Array schema at \(path) is missing \"items\".")
            }
            return .array(element: try shape(for: items, context: &context, path: "\(path)[]", onWiden: onWiden))
        default:
            onWiden("Unrecognized schema type \"\(type)\" at \(path); widening to `any`.")
            return .any
        }
    }

    /// Reads an `object` node's declared properties, in declared order.
    ///
    /// - Parameters:
    ///   - node: the object schema node to read.
    ///   - context: the rendering context for `$ref` resolution.
    ///   - path: the node's location within the schema, for error and
    ///     `onWiden` messages.
    ///   - onWiden: called when a property's shape widens to `.any`.
    /// - Returns: the node's declared object shape.
    /// - Throws: whatever `shape(for:context:path:onWiden:)` throws for one of
    ///   the node's properties.
    private static func objectShape(
        _ node: SchemaNode,
        context: inout RenderContext,
        path: String,
        onWiden: (String) -> Void
    ) throws -> ToolObjectShape {
        let properties = node.properties ?? [:]
        let required = Set(node.required ?? [])
        var declared: [ToolObjectShape.Property] = []
        for key in propertyOrder(of: node) {
            guard let propertyNode = properties[key] else { continue }
            let propertyShape = try shape(for: propertyNode, context: &context, path: "\(path).\(key)", onWiden: onWiden)
            declared.append(
                ToolObjectShape.Property(name: key, shape: propertyShape, isRequired: required.contains(key))
            )
        }
        return ToolObjectShape(properties: declared)
    }

    // MARK: - Doc-comment rendering (the doc-mapping table)

    /// Splits `text` into JSDoc comment lines, each prefixed with
    /// `docLinePrefix`.
    ///
    /// Text is author-supplied (`tool.description`) and rendered verbatim —
    /// the renderer never fabricates or appends punctuation to it — except
    /// for `escapeForJSDocComment`, which neutralizes an embedded `*/` so
    /// it can't terminate the enclosing `/** … */` block early.
    private static func commentLines(for text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return escapeForJSDocComment(text).split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(docLinePrefix)\($0)" }
    }

    /// The parenthetical an `integer` schema adds to its `@param` line, so a
    /// reader knows the `number` the declaration shows takes whole values.
    private static let integerClause = "(integer)"

    /// The guide-derived parenthetical clauses of one property, in the order
    /// the `@param` line shows them: `(integer)`, a numeric range, a pattern,
    /// an item count. `GenerationSchema` has no default-value concept (see
    /// `AppleEncoderParityTests`), so no `default …` clause is ever rendered.
    ///
    /// - Parameter node: the property schema node.
    /// - Returns: the clauses present on `node`, or none.
    private static func constraintClauses(for node: SchemaNode) -> [String] {
        [
            node.type == typeInteger ? integerClause : nil,
            numericRangeClause(node),
            patternClause(node),
            countClause(node),
        ].compactMap { $0 }
    }

    /// Composes one parameter's `@param` line.
    ///
    /// Order (matching the worked `WeatherTool` example's `units` param —
    /// `"temperature unit; one of \"c\" | \"f\". (optional)"`): the
    /// author's `description`, joined to the choice clause with `"; "` when
    /// both are present; then the constraint parentheticals; then
    /// `"(optional)"` for a non-required parameter, or `"(required)"` for a
    /// required one — explicit and symmetric, so a reader (including the
    /// small local model that discovers tools via `searchTools`/`help()`/
    /// `docs(name)`) never has to infer required-ness from the *absence* of
    /// `"(optional)"`.
    ///
    /// The name, the description and the choice clause each land inside the
    /// `/** … */` block, so each passes through `escapeForJSDocComment` — an
    /// embedded `*/` could otherwise terminate the block early. The choice
    /// clause needs that pass on top of `enumUnion`'s own, which (via
    /// `tsLiteral`) only escapes each choice for JS string-literal syntax.
    ///
    /// - Parameter parameter: the parameter to document.
    /// - Returns: the `@param` line, without the doc-line prefix.
    private static func paramLine(for parameter: RenderedParameter) -> String {
        let description = escapeForJSDocComment(parameter.description)
        let choiceClause = choiceClause(of: parameter.shape).map(escapeForJSDocComment)
        let lead = [description, choiceClause].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
        let requiredMark = parameter.isRequired ? "(required)" : "(optional)"
        let clause = ([lead] + parameter.constraints + [requiredMark]).filter { !$0.isEmpty }.joined(separator: " ")
        return "@param args.\(escapeForJSDocComment(parameter.name)) — \(clause)"
    }

    /// The `one of "a" | "b".` clause for a string constrained to choices, or
    /// `nil` for every other shape.
    ///
    /// - Parameter shape: the parameter's declared shape.
    /// - Returns: the choice clause, unescaped for the JSDoc block.
    private static func choiceClause(of shape: ToolValueShape) -> String? {
        guard case .string(let choices) = shape, !choices.isEmpty else { return nil }
        return "one of \(enumUnion(choices))."
    }

    /// Renders a `(minimum, maximum)` bound pair as a parenthetical clause,
    /// or `nil` if neither bound is present.
    ///
    /// Shared by `numericRangeClause` and `countClause`, which were
    /// near-verbatim copies of the same guard/switch/format/return-nil
    /// structure over `minimum`/`maximum` vs. `minItems`/`maxItems` — the
    /// type guard and the three format strings (both bounds, minimum-only,
    /// maximum-only) are the only real per-call-site differences, so
    /// they're supplied as closures.
    ///
    /// - Parameters:
    ///   - minimum: the lower bound, if present.
    ///   - maximum: the upper bound, if present.
    ///   - both: formats the clause when both bounds are present.
    ///   - minOnly: formats the clause when only `minimum` is present.
    ///   - maxOnly: formats the clause when only `maximum` is present.
    private static func boundsClause<Bound>(
        minimum: Bound?,
        maximum: Bound?,
        both: (Bound, Bound) -> String,
        minOnly: (Bound) -> String,
        maxOnly: (Bound) -> String
    ) -> String? {
        switch (minimum, maximum) {
        case let (minimum?, maximum?):
            return both(minimum, maximum)
        case let (minimum?, nil):
            return minOnly(minimum)
        case let (nil, maximum?):
            return maxOnly(maximum)
        default:
            return nil
        }
    }

    /// Renders a numeric guide's `minimum`/`maximum`/`range` as a
    /// parenthetical, e.g. `"(range 1…10)"`, `"(minimum 1)"`, or
    /// `"(maximum 10)"`.
    ///
    /// `nil` if neither bound is present.
    private static func numericRangeClause(_ node: SchemaNode) -> String? {
        guard node.type == typeInteger || node.type == typeNumber else { return nil }
        return boundsClause(
            minimum: node.minimum,
            maximum: node.maximum,
            both: { "(range \(formatNumber($0))…\(formatNumber($1)))" },
            minOnly: { "(minimum \(formatNumber($0)))" },
            maxOnly: { "(maximum \(formatNumber($0)))" }
        )
    }

    /// Renders a string guide's `pattern` as a parenthetical, e.g.
    /// `"(pattern: /[A-Z]{3}/)"`.
    ///
    /// `nil` if no pattern is present. The pattern is passed through
    /// `escapeForRegexLiteralDoc` — an
    /// unescaped `/` embedded in the pattern would otherwise prematurely
    /// close the doc text's `/…/` regex-literal form — and the whole
    /// clause through `escapeForJSDocComment`: a pattern ending in `*`
    /// (an ordinary regex, e.g. `.*`) forms a literal `*/` right at the
    /// join with this clause's own appended closing `/`, which
    /// `escapeForRegexLiteralDoc` alone (it only escapes `/`) doesn't
    /// catch, and which would otherwise terminate the enclosing JSDoc
    /// block early exactly like every other unescaped splice site here.
    private static func patternClause(_ node: SchemaNode) -> String? {
        guard let pattern = node.pattern else { return nil }
        return escapeForJSDocComment("(pattern: /\(escapeForRegexLiteralDoc(pattern))/)")
    }

    /// Renders an array guide's `minItems`/`maxItems`/`count` as a
    /// parenthetical, e.g. `"(1…3 items)"`, `"(1+ items)"`, or `"(up to 3
    /// items)"`.
    ///
    /// `nil` if neither bound is present.
    private static func countClause(_ node: SchemaNode) -> String? {
        guard node.type == typeArray else { return nil }
        return boundsClause(
            minimum: node.minItems,
            maximum: node.maxItems,
            both: { "(\($0)…\($1) items)" },
            minOnly: { "(\($0)+ items)" },
            maxOnly: { "(up to \($0) items)" }
        )
    }

    // MARK: - Example synthesis

    /// Synthesizes a plausible, syntactically valid JS literal for one
    /// required property, used to build the auto-generated `@example` call.
    ///
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
    ///
    /// - Parameters:
    ///   - node: the schema node whose example literal to synthesize.
    ///   - name: the property's name, used for a self-documenting `string`
    ///     placeholder and in error messages.
    ///   - context: the rendering context for `$ref` resolution.
    /// - Returns: the synthesized JS literal source text.
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
        case typeString:
            return "\"\(escapeForJSStringLiteral(name))\""
        case typeInteger, typeNumber:
            return formatNumber(node.minimum ?? 0)
        case typeBoolean:
            return "true"
        case typeArray:
            guard let items = node.items else { return "[]" }
            guard (node.minItems ?? 0) >= 1 else { return "[]" }
            let element = try exampleLiteral(for: items, name: "item", context: &context)
            return "[\(element)]"
        case typeObject:
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
    ///
    /// Keys go through `objectKeyLiteral`, same as the top-level
    /// `exampleFields` in `render(name:description:parameters:returns:onWiden:)`.
    ///
    /// - Parameters:
    ///   - node: the object schema to render.
    ///   - context: the rendering context for `$ref` resolution.
    private static func exampleObjectLiteral(_ node: SchemaNode, context: inout RenderContext) throws -> String {
        let properties = node.properties ?? [:]
        guard !properties.isEmpty else { return "{}" }
        let required = Set(node.required ?? [])
        var fields: [String] = []
        for key in propertyOrder(of: node) where required.contains(key) {
            guard let propertyNode = properties[key] else { continue }
            let literal = try exampleLiteral(for: propertyNode, name: key, context: &context)
            fields.append("\(objectKeyLiteral(key)): \(literal)")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    /// The example literal for one required typed parameter: the caller's
    /// `exampleValue` once `JavaScriptLiteralSyntax` accepts it, or a literal
    /// synthesized from the shape when the caller supplied none.
    ///
    /// This is the one place a `RenderedParameter.exampleValue` reaches the
    /// generated text, so it is the one place the check stands. The schema
    /// path's own literals come through here too, which holds
    /// `exampleLiteral(for:name:context:)` to the same grammar.
    ///
    /// - Parameter parameter: the required parameter to render.
    /// - Returns: the JS literal source text for the `@example` call.
    /// - Throws: `ToolAPIRendererError` when `exampleValue` is present and is
    ///   not one JavaScript literal expression.
    private static func exampleLiteral(for parameter: RenderedParameter) throws -> String {
        guard let exampleValue = parameter.exampleValue else {
            return exampleLiteral(for: parameter.shape, name: parameter.name)
        }
        guard JavaScriptLiteralSyntax.isLiteral(exampleValue) else {
            throw ToolAPIRendererError(
                "Parameter \"\(parameter.name)\"'s exampleValue \(exampleValue.debugDescription) is not one "
                    + "JavaScript literal expression (a string, number, true, false, null, array or object "
                    + "literal); refusing to splice it into the generated `@example` call rather than risk "
                    + "breaking out of the generated code."
            )
        }
        return exampleValue
    }

    /// Synthesizes the example literal for a typed parameter from its shape
    /// alone: the first choice for a constrained string, the property's own
    /// name for an unconstrained one, `0` for a number, `true` for a boolean,
    /// `[]` for an array, the required fields for an object, `{}` for a
    /// parsed JSON value, and `null` for `any`.
    ///
    /// A schema knows more than a shape does — a range's `minimum`, an
    /// array's `minItems` — so the schema path supplies
    /// `RenderedParameter.exampleValue` from `exampleLiteral(for:name:context:)`
    /// instead, and this synthesizer serves the typed path.
    ///
    /// - Parameters:
    ///   - shape: the declared shape to synthesize a literal for.
    ///   - name: the property's name, the placeholder for an unconstrained
    ///     string.
    /// - Returns: the synthesized JS literal source text.
    private static func exampleLiteral(for shape: ToolValueShape, name: String) -> String {
        switch shape {
        case .string(let choices):
            return choices.first.map(tsLiteral) ?? "\"\(escapeForJSStringLiteral(name))\""
        case .number:
            return formatNumber(0)
        case .boolean:
            return "true"
        case .array:
            return "[]"
        case .object(let object):
            return exampleObjectLiteral(of: object)
        case .json:
            return "{}"
        case .any:
            return "null"
        }
    }

    /// Builds `{ field: value, … }` for an object shape's required
    /// properties, or `{}` when it requires none.
    ///
    /// - Parameter object: the object shape to render.
    /// - Returns: the synthesized JS object literal.
    private static func exampleObjectLiteral(of object: ToolObjectShape) -> String {
        let fields = object.properties.filter(\.isRequired).map { property in
            "\(objectKeyLiteral(property.name)): \(exampleLiteral(for: property.shape, name: property.name))"
        }
        return fields.isEmpty ? "{}" : "{ \(fields.joined(separator: ", ")) }"
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
    ///
    /// `.string` is escaped via `escapeForJSStringLiteral`, same as every
    /// other schema-derived string this renderer wraps in double quotes —
    /// an enum/default choice containing an embedded quote would
    /// otherwise break the TS string-literal syntax it's spliced into.
    private static func tsLiteral(_ value: InterpreterValue) -> String {
        switch value {
        case .string(let string):
            return "\"\(escapeForJSStringLiteral(string))\""
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

    /// The magnitude a whole-valued `Double` must stay under to be rendered
    /// through `Int64`.
    ///
    /// Well inside both limits that matter: `Int64`'s range, which the
    /// conversion would otherwise trap outside of, and 2^53, above which a
    /// `Double` no longer holds consecutive integers — so a value this far out
    /// is rendered by `Double`'s own description, which says what the value
    /// actually is rather than what an integer cast made of it.
    private static let integerRenderingMagnitudeLimit: Double = 1e15

    /// Formats a `Double` without a trailing `.0` for whole numbers (JSON
    /// Schema `minimum`/`maximum` decode as `Double` even for an `integer`
    /// schema), and via its normal description otherwise.
    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < integerRenderingMagnitudeLimit {
            return String(Int64(value))
        }
        return String(value)
    }
}
