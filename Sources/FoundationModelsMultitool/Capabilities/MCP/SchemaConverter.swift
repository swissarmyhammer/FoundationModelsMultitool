// `SchemaConverter` — a JSON Schema from `tools/list` becomes a
// `GenerationSchema`.
//
// A behavioral port of `../FoundationModelsMCP/Sources/FoundationModelsMCP/
// SchemaConverter.swift`. eventplan.md § "Consolidation of the siblings" moves
// "the `SchemaConverter` / `GeneratedContentCodec` pair" into this folder.
// This file is the inbound half of the pair: the `inputSchema` of one MCP tool
// becomes the `GenerationSchema` of the verb's arguments, which is what the
// model generates against. `GeneratedContentCodec` is the outbound half.
//
// **The conversion has two stages, and the first one is the one the tests
// read.** `DynamicGenerationSchema` and `GenerationSchema` are opaque:
// FoundationModels shows nothing of a schema it has constructed. So
// `parse(_:name:onDrop:)` first walks the raw `Value` into `SchemaIR`, a plain
// value the tests inspect, and `emit(_:)` then translates that value into the
// Apple types with no decision of its own. Every structural choice stands in
// the first stage, where a test can see it.
//
// **What the converter cannot express, it drops and reports.** A JSON Schema
// keyword with no `DynamicGenerationSchema` equivalent — `anyOf`, `oneOf`,
// `not`, `patternProperties`, an open `additionalProperties`, a positional
// `items` — degrades the node to a permissive string schema. Each drop reaches
// the caller through the `onDrop` closure as one `SchemaConversionLogRecord`,
// naming the keyword and the JSON path. The sibling package reported the same
// records through that closure; this file keeps the closure and adds no logger
// of its own, thus the caller decides where a record goes.
//
// **The types are internal.** The Shell capability keeps its types internal,
// and this folder does the same: `MCPTool`, which comes in a later task, is
// the one production caller, and the tests reach the converter with
// `@testable import`. The three value types below hold the synthesized
// memberwise initializer, which is internal too.

import Foundation
import FoundationModels
import MCP

/// An inspectable intermediate representation of a JSON Schema (2020-12) node, parsed from an MCP tool's `inputSchema`.
///
/// `DynamicGenerationSchema` / `GenerationSchema` are opaque — FoundationModels
/// exposes no public introspection on a constructed schema — so `SchemaIR` is
/// the assertion surface for tests: property names, primitive types,
/// optionality, nesting, resolved `$ref`s, and runtime constraint guides are
/// all plain, inspectable data.
///
/// Structure (object/properties/required, primitives, arrays, enums, nested
/// objects, and `$ref`/`$defs`) and constraint guides (``guided(base:guide:)``,
/// covering `minimum`/`maximum`, `pattern`, and `minItems`/`maxItems`) are both
/// represented here. Any JSON Schema keyword or shape this converter does not
/// map to a `DynamicGenerationSchema` structure degrades to ``unknown``,
/// logging what was dropped rather than silently misrepresenting the schema.
indirect enum SchemaIR: Sendable, Equatable {
    /// `type: "object"` with `properties`/`required`.
    case object(name: String, description: String?, properties: [Property])
    /// `type: "string"`.
    case string
    /// `type: "integer"`.
    case integer
    /// `type: "number"`.
    case number
    /// `type: "boolean"`.
    case boolean
    /// `type: "array"` with `items`.
    case array(items: SchemaIR)
    /// `enum: [...]` — the discrete set of values the model may choose from.
    ///
    /// This is JSON Schema's `enum`-to-`anyOf` guide mapping already fully
    /// realized: unlike ``guided(base:guide:)``, which layers a constraint on
    /// top of a structural base, an enum gets its own named choice schema at
    /// emission (`DynamicGenerationSchema(name:description:anyOf:)`), so no
    /// separate guide wrapper is needed.
    case enumeration(name: String, description: String?, values: [String])
    /// `$ref` to a `$defs` entry, resolved by name against `SchemaConversion.definitions`.
    case reference(name: String)
    /// A JSON Schema keyword or shape this converter does not map to a `DynamicGenerationSchema` structure (e.g. `anyOf`/`oneOf` unions, `patternProperties`, a schema with no recognized `type`).
    ///
    /// Degrades to a permissive string schema at emission time. Every time a
    /// node degrades to `.unknown` because of a specific unsupported keyword
    /// (as opposed to simply lacking a recognized `type`), `SchemaConverter`
    /// reports exactly one ``SchemaConversionLogRecord`` naming that keyword
    /// and the node's JSON path via the caller-supplied ``SchemaConversionLogHandler``.
    case unknown
    /// A structural schema (``string``, ``integer``, ``number``, or ``array(items:)``) further restricted by a runtime constraint, emitted as an Apple `GenerationGuide` — or, for array element counts, `DynamicGenerationSchema`'s dedicated count parameters.
    case guided(base: SchemaIR, guide: GuideSpec)

    /// One property of an ``object(name:description:properties:)`` node.
    struct Property: Sendable, Equatable {
        /// The property's key in the enclosing object's JSON Schema `properties` map.
        var name: String
        /// The property's JSON Schema `description`, if present.
        var description: String?
        /// The parsed schema for this property's value.
        var schema: SchemaIR
        /// `false` when the property's name is present in the enclosing object's JSON Schema `required` array.
        var isOptional: Bool
    }

    /// A runtime constraint mapped from a JSON Schema keyword, carried by a ``guided(base:guide:)`` node.
    ///
    /// Each case is emitted as a real Apple `GenerationGuide` (or, for
    /// ``count(minimum:maximum:)``, `DynamicGenerationSchema`'s dedicated
    /// element-count parameters), so the constraint tightens constrained
    /// decoding instead of merely hinting at it via `description`.
    enum GuideSpec: Sendable, Equatable {
        /// `minimum`/`maximum` (and, folded in, `exclusiveMinimum`/`exclusiveMaximum`) on an `integer` or `number` schema.
        ///
        /// Apple's `GenerationGuide` numeric factories are typed to `Decimal`,
        /// so both JSON Schema `integer` and `number` bounds are represented
        /// as `Decimal` here (and emitted via `DynamicGenerationSchema(type:
        /// Decimal.self, guides:)` regardless of the base's own primitive
        /// type). A `nil` bound means that side is unconstrained.
        ///
        /// JSON Schema 2020-12's `exclusiveMinimum`/`exclusiveMaximum` are
        /// strict (`>`/`<`) bounds, but `GenerationGuide`'s numeric factories
        /// only express inclusive (`>=`/`<=`) bounds. `SchemaConverter` folds
        /// an exclusive bound into an inclusive one by nudging it inward:
        /// by exactly `1` for an `integer` base (the next representable
        /// integer), or by a small fixed `Decimal` epsilon (`1e-9`) for a
        /// `number` base, since `Decimal` has no portable "next representable
        /// value" operation. When both the inclusive and exclusive form of
        /// the same bound are present, the stricter (nudged) one wins.
        case numericRange(minimum: Decimal?, maximum: Decimal?)
        /// `pattern` on a `string` schema — the raw ECMA-262 regex source text.
        ///
        /// `SchemaConverter` only ever constructs this case for a source that
        /// has already been confirmed to compile as a Swift `Regex` during
        /// parsing; a pattern that fails to compile is dropped (logged, and
        /// the property falls back to a plain, unconstrained `string`)
        /// instead of throwing.
        case pattern(String)
        /// `minItems`/`maxItems` on an `array` schema.
        ///
        /// Emitted via `DynamicGenerationSchema(arrayOf:minimumElements:maximumElements:)`
        /// rather than a `GenerationGuide<[Element]>`, since that initializer
        /// is `DynamicGenerationSchema`'s own dedicated element-count API. A
        /// `nil` bound means that side is unconstrained.
        case count(minimum: Int?, maximum: Int?)
    }
}

/// A single JSON Schema keyword `SchemaConverter` could not map onto a `DynamicGenerationSchema` structure or guide, dropped during parsing.
///
/// `SchemaConverter.parse(_:name:onDrop:)` reports exactly one record per
/// dropped construct via the caller-supplied ``SchemaConversionLogHandler``,
/// so callers (and tests) can see precisely what was silently permissivized
/// rather than accurately represented.
struct SchemaConversionLogRecord: Sendable, Equatable {
    /// The JSON Schema keyword that triggered the drop (e.g. `"anyOf"`, `"patternProperties"`, `"$ref"`, `"pattern"`).
    var keyword: String
    /// A slash-delimited JSON path to the node the keyword was found on, rooted at `""` for the top-level `inputSchema`.
    var path: String
}

/// A caller-injected sink for ``SchemaConversionLogRecord``s reported during `SchemaConverter.parse(_:name:onDrop:)`.
///
/// Defaults to a no-op in `parse(_:name:onDrop:)`, so callers that don't care
/// about dropped constructs don't need to supply one; tests inject a
/// recording handler to assert on exactly what was dropped.
typealias SchemaConversionLogHandler = @Sendable (SchemaConversionLogRecord) -> Void

/// The result of parsing an MCP `inputSchema`: the root ``SchemaIR`` plus any named `$defs` schemas reachable from it via `$ref`.
struct SchemaConversion: Sendable, Equatable {
    /// The name given to the root schema (typically the MCP tool name); also the `DynamicGenerationSchema` / `GenerationSchema` type name at emission.
    ///
    /// `emit(_:)` reads the name off ``root`` rather than off this property,
    /// because `parse(_:name:onDrop:)` gave the root node the same name.
    /// This property is read by the synthesized `Equatable` conformance;
    /// periphery sees no caller.
    // periphery:ignore
    var name: String
    /// The parsed root schema — the top-level `inputSchema` node.
    var root: SchemaIR
    /// Parsed `$defs` entries, keyed by definition name, resolved via ``SchemaIR/reference(name:)``.
    var definitions: [String: SchemaIR]
}

/// Converts an MCP tool's `inputSchema` (`MCP.Value`, JSON Schema 2020-12) into Apple's `GenerationSchema`.
///
/// Conversion happens in two stages, because `DynamicGenerationSchema`/
/// `GenerationSchema` are opaque with no public introspection:
///
/// 1. ``parse(_:name:onDrop:)`` walks the raw `Value` into `SchemaIR` — the
///    inspectable representation tests assert against.
/// 2. ``emit(_:)`` is a thin translation of the already-parsed `SchemaIR`
///    into `DynamicGenerationSchema` → `GenerationSchema`.
enum SchemaConverter {
    /// Parses an MCP `inputSchema` into an inspectable `SchemaIR`.
    ///
    /// - Parameters:
    ///   - inputSchema: The tool's raw JSON Schema `inputSchema`, as decoded
    ///     by the MCP swift-sdk (targets the 2020-12 dialect).
    ///   - name: The name given to the root schema — typically the MCP tool
    ///     name — used as the emitted `DynamicGenerationSchema`'s type name.
    ///   - onDrop: Invoked once for every JSON Schema construct dropped during
    ///     parsing (see ``SchemaIR/unknown`` and the unsupported-keyword
    ///     table), naming the keyword and JSON path. Defaults to a no-op for
    ///     callers that don't need to observe dropped constructs.
    /// - Returns: The parsed root schema plus any resolved `$defs`.
    static func parse(
        _ inputSchema: Value, name: String, onDrop: SchemaConversionLogHandler = { _ in }
    ) -> SchemaConversion {
        guard case .object(let fields) = inputSchema else {
            return SchemaConversion(name: name, root: .unknown, definitions: [:])
        }
        let definitions = parseDefinitions(fields, onDrop: onDrop)
        let root = parseNode(inputSchema, name: name, path: "", onDrop: onDrop)
        return SchemaConversion(name: name, root: root, definitions: definitions)
    }

    /// Emits a `GenerationSchema` from an already-parsed `SchemaConversion`.
    ///
    /// Thin by design: every structural decision was already made during
    /// ``parse(_:name:onDrop:)``. This step only walks `SchemaIR` into
    /// `DynamicGenerationSchema` values and hands them to
    /// `GenerationSchema.init(root:dependencies:)`.
    ///
    /// - Parameter conversion: The schema conversion to emit.
    /// - Returns: A `GenerationSchema` representing the converted schema.
    /// - Throws: `GenerationSchema.SchemaError` if the parsed schemas
    ///   describe an invalid type graph (e.g. a `$ref` with no matching
    ///   `$defs` entry, or a duplicate type name).
    static func emit(_ conversion: SchemaConversion) throws -> GenerationSchema {
        let dependencies = conversion.definitions.map { _, node in
            dynamicSchema(for: node)
        }
        let root = dynamicSchema(for: conversion.root)
        return try GenerationSchema(root: root, dependencies: dependencies)
    }

    // MARK: - Parsing (Value → SchemaIR)

    /// JSON Schema 2020-12 (MCP's targeted dialect) uses `$defs`, but many real-world schemas — ported from draft-07-era generators (Pydantic v1, `zod-to-json-schema`, OpenAPI-derived tooling) — still emit the legacy `definitions` container.
    ///
    /// Both are recognized so a `$ref` into either resolves instead of silently degrading to `.unknown`.
    private static let definitionsContainerKeys = ["$defs", "definitions"]

    /// The JSON Schema `description` keyword, used as a dictionary key when pulling a node's description out of its raw `Value` fields.
    private static let descriptionKey = "description"

    /// Parses the `$defs`/`definitions` container (if present) into named `SchemaIR` entries.
    ///
    /// - Parameters:
    ///   - fields: The raw JSON Schema object's fields, as decoded from the `inputSchema` `Value`.
    ///   - onDrop: Invoked once for every JSON Schema construct dropped while parsing a definition.
    /// - Returns: Parsed `$defs`/`definitions` entries, keyed by definition name.
    private static func parseDefinitions(
        _ fields: [String: Value], onDrop: SchemaConversionLogHandler
    ) -> [String: SchemaIR] {
        var result: [String: SchemaIR] = [:]
        for containerKey in definitionsContainerKeys {
            guard case .object(let definitionFields)? = fields[containerKey] else { continue }
            for (definitionName, definitionValue) in definitionFields {
                result[definitionName] = parseNode(
                    definitionValue, name: definitionName, path: "/\(containerKey)/\(definitionName)",
                    onDrop: onDrop)
            }
        }
        return result
    }

    /// The JSON Schema keywords `SchemaConverter` cannot map onto any `DynamicGenerationSchema` structure or guide, in the fixed order they are checked.
    ///
    /// A node carrying any of these degrades wholesale to ``SchemaIR/unknown``
    /// (see `parseNode(_:name:path:onDrop:)`) rather than being partially
    /// represented, since a partial structural mapping would silently drop the
    /// permissiveness (or negation, or union) the keyword expresses.
    /// `additionalProperties: false` is the one exception — it is the JSON
    /// Schema *default* and is already exactly what a closed
    /// `DynamicGenerationSchema(properties:)` expresses, so it is not treated
    /// as a drop.
    private static let unsupportedKeywords = [
        "anyOf", "oneOf", "additionalProperties", "patternProperties", "not", "prefixItems",
    ]

    /// Reports every keyword in ``unsupportedKeywords`` present on `fields`.
    ///
    /// - Parameter fields: The raw JSON Schema node's fields to scan.
    /// - Returns: The unsupported keywords found, in ``unsupportedKeywords`` order.
    private static func unsupportedKeywordsPresent(in fields: [String: Value]) -> [String] {
        unsupportedKeywords.filter { keyword in
            guard let value = fields[keyword] else { return false }
            if keyword == "additionalProperties", case .bool(false) = value { return false }
            return true
        }
    }

    /// Parses a single JSON Schema node (object, primitive, array, enum, `$ref`, or unrecognized shape) into `SchemaIR`.
    ///
    /// - Parameters:
    ///   - value: The raw JSON Schema node to parse.
    ///   - name: The name to assign the parsed node (used for nested object/array/enum naming).
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked once for every JSON Schema construct dropped while parsing this node or its descendants.
    /// - Returns: The parsed `SchemaIR` node, or `.unknown` if the shape is not recognized.
    private static func parseNode(
        _ value: Value, name: String, path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        guard case .object(let fields) = value else { return .unknown }

        // Checked before `$ref`: under JSON Schema 2020-12 (MCP's targeted
        // dialect), `$ref` is a normal applicator, not a replacement for its
        // siblings — a sibling `anyOf`/`oneOf`/etc. is meaningful and must
        // not be silently discarded just because `$ref` itself happens to
        // resolve.
        let droppedKeywords = unsupportedKeywordsPresent(in: fields)
        if !droppedKeywords.isEmpty {
            for keyword in droppedKeywords {
                onDrop(SchemaConversionLogRecord(keyword: keyword, path: path))
            }
            return .unknown
        }

        if case .string(let reference)? = fields["$ref"] {
            if let definitionName = definitionName(fromRef: reference) {
                return .reference(name: definitionName)
            }
            onDrop(SchemaConversionLogRecord(keyword: "$ref", path: path))
            return .unknown
        }

        if case .array(let enumValues)? = fields["enum"] {
            return .enumeration(
                name: name,
                description: fields[descriptionKey]?.stringValue,
                values: enumValues.compactMap(scalarString)
            )
        }

        let typeString = fields["type"]?.stringValue
        switch typeString {
        case "object":
            return parseObject(fields, name: name, path: path, onDrop: onDrop)
        case "array":
            return parseArray(fields, name: name, path: path, onDrop: onDrop)
        default:
            return parseUntypedNode(
                fields, name: name, path: path, onDrop: onDrop, typeString: typeString)
        }
    }

    /// Parses a node whose `type` is anything other than `object`/`array` — a recognized primitive `type` string, or an absent/unrecognized `type` that may still be shaped like an object.
    ///
    /// - Parameters:
    ///   - fields: The node's raw JSON Schema fields.
    ///   - name: The name to assign the parsed node.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked once for every JSON Schema construct dropped while parsing this node or its descendants.
    ///   - typeString: The node's raw JSON Schema `type` value, already confirmed not to name a recognized `object`/`array` shape.
    /// - Returns: The applicable scalar guide's `SchemaIR` if `typeString` names a recognized primitive; the parsed object if the node has a `properties` field despite lacking a recognized `type` (e.g. a root `inputSchema` that omits `"type": "object"`, which the MCP spec still treats as an object schema); or `.unknown` otherwise.
    private static func parseUntypedNode(
        _ fields: [String: Value], name: String, path: String, onDrop: SchemaConversionLogHandler,
        typeString: String?
    ) -> SchemaIR {
        if let primitive = typeString.flatMap({ primitiveTypeMap[$0] }) {
            return applyScalarGuide(to: primitive, fields: fields, path: path, onDrop: onDrop)
        }
        if fields["properties"] != nil {
            return parseObject(fields, name: name, path: path, onDrop: onDrop)
        }
        return .unknown
    }

    /// The JSON Schema primitive `type` strings, keyed to their `SchemaIR` case.
    private static let primitiveTypeMap: [String: SchemaIR] = [
        "string": .string,
        "integer": .integer,
        "number": .number,
        "boolean": .boolean,
    ]

    /// Applies a primitive scalar's constraint keywords — `pattern` on `.string`, `minimum`/`maximum`/`exclusiveMinimum`/`exclusiveMaximum` on `.integer`/`.number` — wrapping `primitive` in ``SchemaIR/guided(base:guide:)`` when one applies.
    ///
    /// - Parameters:
    ///   - primitive: The already-resolved primitive base schema.
    ///   - fields: The node's raw JSON Schema fields, to read constraint keywords from.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked if `primitive` is `.string` and `pattern` fails to compile as a Swift `Regex`.
    /// - Returns: `primitive` unchanged if no applicable constraint keyword is present, or `.guided(base: primitive, guide:)` if one is.
    private static func applyScalarGuide(
        to primitive: SchemaIR, fields: [String: Value], path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        switch primitive {
        case .integer, .number:
            return applyNumericRangeGuide(to: primitive, fields: fields, path: path, onDrop: onDrop)
        case .string:
            return applyPatternGuide(fields: fields, path: path, onDrop: onDrop)
        default:
            return primitive
        }
    }

    /// The power of ten of ``numberExclusiveBoundEpsilon``: `1e-9`.
    private static let numberExclusiveBoundExponent = -9

    /// A fixed epsilon nudged inward from a `number` schema's `exclusiveMinimum`/`exclusiveMaximum` to approximate its strict bound as an inclusive one, since `Decimal` has no portable "next representable value" operation (see ``SchemaIR/GuideSpec/numericRange(minimum:maximum:)``).
    private static let numberExclusiveBoundEpsilon = Decimal(
        sign: .plus, exponent: numberExclusiveBoundExponent, significand: 1)

    /// Applies `minimum`/`maximum`/`exclusiveMinimum`/`exclusiveMaximum` to an `.integer` or `.number` base, wrapping it in ``SchemaIR/guided(base:guide:)`` if any bound is present.
    ///
    /// - Parameters:
    ///   - base: The already-resolved `.integer` or `.number` base schema.
    ///   - fields: The node's raw JSON Schema fields, to read `minimum`/`maximum`/`exclusiveMinimum`/`exclusiveMaximum` from.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked if the effective minimum and maximum cross (`minimum > maximum`), which describes no value at all and can't be expressed as a `ClosedRange`.
    /// - Returns: `base` unchanged if no bound keyword is present or the effective bounds cross, or `.guided(base:, guide: .numericRange(...))` if a valid (non-crossing) bound is present.
    private static func applyNumericRangeGuide(
        to base: SchemaIR, fields: [String: Value], path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        let isInteger = base == .integer
        let minimum = combinedBound(
            inclusive: decimalValue(fields["minimum"]),
            exclusive: decimalValue(fields["exclusiveMinimum"]),
            isInteger: isInteger, selectMaximum: false)
        let maximum = combinedBound(
            inclusive: decimalValue(fields["maximum"]),
            exclusive: decimalValue(fields["exclusiveMaximum"]),
            isInteger: isInteger, selectMaximum: true)
        return applyBoundsGuide(
            to: base, minimum: minimum, maximum: maximum, keyword: "minimum", path: path, onDrop: onDrop
        ) { .numericRange(minimum: $0, maximum: $1) }
    }

    /// Guards a computed minimum/maximum bound pair against crossing and, if valid, wraps `base` in ``SchemaIR/guided(base:guide:)``.
    ///
    /// Shared by ``applyNumericRangeGuide(to:fields:path:onDrop:)`` and
    /// ``applyCountGuide(to:fields:path:onDrop:)``, which differ only in the
    /// bound type (`Decimal` for JSON Schema numbers, `Int` for array
    /// counts), the keyword named in the log record when the bounds cross,
    /// and how the valid bounds become a ``SchemaIR/GuideSpec``. Both share
    /// the same three-step shape: skip if neither bound is present, drop
    /// (logged) if both are present but cross — since a crossed pair
    /// describes no value/array at all and a naive `ClosedRange` would trap
    /// on it — and otherwise construct the guide.
    ///
    /// - Parameters:
    ///   - base: The already-resolved base schema to wrap or return unchanged.
    ///   - minimum: The effective minimum bound, or `nil` if none.
    ///   - maximum: The effective maximum bound, or `nil` if none.
    ///   - keyword: The JSON Schema keyword to name in the log record if the bounds cross.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked if both bounds are present and cross (`minimum > maximum`).
    ///   - makeGuide: Constructs the ``SchemaIR/GuideSpec`` from the valid (non-crossing) bounds.
    /// - Returns: `base` unchanged if neither bound is present or they cross, or `.guided(base:, guide: makeGuide(minimum, maximum))` if a valid bound is present.
    private static func applyBoundsGuide<Bound: Comparable>(
        to base: SchemaIR,
        minimum: Bound?,
        maximum: Bound?,
        keyword: String,
        path: String,
        onDrop: SchemaConversionLogHandler,
        makeGuide: (Bound?, Bound?) -> SchemaIR.GuideSpec
    ) -> SchemaIR {
        guard minimum != nil || maximum != nil else { return base }
        if let minimum, let maximum, minimum > maximum {
            onDrop(SchemaConversionLogRecord(keyword: keyword, path: path))
            return base
        }
        return .guided(base: base, guide: makeGuide(minimum, maximum))
    }

    /// Combines an inclusive bound (`minimum`/`maximum`) with its nudged-inward exclusive counterpart (`exclusiveMinimum`/`exclusiveMaximum`), taking the stricter of the two when both are present.
    ///
    /// Minimum and maximum combination are mirror images of each other: a
    /// minimum nudges its exclusive form *up* and prefers the *greater*
    /// (stricter) value, while a maximum nudges *down* and prefers the
    /// *lesser* (stricter) value. `selectMaximum` picks which mirror to
    /// apply so both call sites (``applyNumericRangeGuide(to:fields:path:onDrop:)``)
    /// share one implementation instead of two near-identical copies.
    ///
    /// - Parameters:
    ///   - inclusive: The JSON Schema `minimum`/`maximum` value, if present.
    ///   - exclusive: The JSON Schema `exclusiveMinimum`/`exclusiveMaximum` value, if present.
    ///   - isInteger: Whether the constrained base is `.integer` (nudged by `1`) rather than `.number` (nudged by ``numberExclusiveBoundEpsilon``).
    ///   - selectMaximum: `false` to combine a minimum (nudge up, prefer greater); `true` to combine a maximum (nudge down, prefer lesser).
    /// - Returns: The effective inclusive bound, or `nil` if neither `inclusive` nor `exclusive` was present.
    private static func combinedBound(
        inclusive: Decimal?, exclusive: Decimal?, isInteger: Bool, selectMaximum: Bool
    ) -> Decimal? {
        let nudgeMagnitude = isInteger ? 1 : numberExclusiveBoundEpsilon
        let nudged = exclusive.map { selectMaximum ? $0 - nudgeMagnitude : $0 + nudgeMagnitude }
        func stricter(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
            selectMaximum ? min(lhs, rhs) : max(lhs, rhs)
        }
        switch (inclusive, nudged) {
        case (let inclusive?, let nudged?): return stricter(inclusive, nudged)
        case (let inclusive?, nil): return inclusive
        case (nil, let nudged?): return nudged
        case (nil, nil): return nil
        }
    }

    /// Reads a JSON Schema numeric keyword's raw `Value` as a `Decimal`.
    ///
    /// - Parameter value: The raw `Value` to convert, typically a dictionary lookup like `fields["minimum"]`.
    /// - Returns: The value as a `Decimal`, or `nil` if `value` is absent or not a JSON number.
    private static func decimalValue(_ value: Value?) -> Decimal? {
        switch value {
        case .int(let int): return Decimal(int)
        case .double(let double): return Decimal(double)
        default: return nil
        }
    }

    /// Applies `pattern` to a `.string` base, wrapping it in ``SchemaIR/guided(base:guide:)`` if `pattern` compiles as a Swift `Regex`; logs and falls back to a plain `.string` otherwise.
    ///
    /// - Parameters:
    ///   - fields: The node's raw JSON Schema fields, to read `pattern` from.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked if `pattern` is present but fails to compile as a Swift `Regex`.
    /// - Returns: `.string` if no `pattern` is present or it fails to compile, or `.guided(base: .string, guide: .pattern(...))` if it compiles.
    private static func applyPatternGuide(
        fields: [String: Value], path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        guard case .string(let source)? = fields["pattern"] else { return .string }
        guard (try? Regex(source)) != nil else {
            onDrop(SchemaConversionLogRecord(keyword: "pattern", path: path))
            return .string
        }
        return .guided(base: .string, guide: .pattern(source))
    }

    /// Parses an object node's `properties` and `required` into an ``SchemaIR/object(name:description:properties:)`` case.
    ///
    /// - Parameters:
    ///   - fields: The object node's raw JSON Schema fields.
    ///   - name: The name to assign the parsed object.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked once for every JSON Schema construct dropped while parsing a property's schema.
    /// - Returns: The parsed ``SchemaIR/object(name:description:properties:)`` node.
    private static func parseObject(
        _ fields: [String: Value], name: String, path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        let requiredNames: Set<String>
        if case .array(let requiredValues)? = fields["required"] {
            requiredNames = Set(requiredValues.compactMap(\.stringValue))
        } else {
            requiredNames = []
        }

        var properties: [SchemaIR.Property] = []
        if case .object(let propertyFields)? = fields["properties"] {
            for (propertyName, propertySchema) in propertyFields.sorted(by: { $0.key < $1.key }) {
                properties.append(
                    SchemaIR.Property(
                        name: propertyName,
                        description: parsePropertyDescription(propertySchema),
                        schema: parseNode(
                            propertySchema, name: "\(name)_\(propertyName)", path: "\(path)/\(propertyName)",
                            onDrop: onDrop),
                        isOptional: !requiredNames.contains(propertyName)
                    )
                )
            }
        }

        return .object(
            name: name,
            description: fields[descriptionKey]?.stringValue,
            properties: properties
        )
    }

    /// Reads a property's JSON Schema `description`, given its raw (as-yet-unparsed) value from the enclosing object's `properties` map.
    ///
    /// Has exactly one call site (`parseObject`'s properties loop) and the
    /// guard-case-plus-dictionary-lookup it wraps is not, on its own,
    /// complex enough to need extracting for that reason alone. It stays a
    /// separate function anyway: inlining it back into the `for` loop would
    /// reintroduce the `function → if → for → if` nesting that this
    /// extraction flattened to `function → if → for → call`. This is a
    /// deliberate call-site-readability trade-off, not a case of
    /// "single-use rule" cargo culting.
    ///
    /// - Parameter propertySchema: The property's raw JSON Schema value.
    /// - Returns: The property's `description` string, or `nil` if `propertySchema` is not an object node (every valid JSON Schema property schema is) or has no `description`.
    private static func parsePropertyDescription(_ propertySchema: Value) -> String? {
        guard case .object(let propertySchemaFields) = propertySchema else { return nil }
        return propertySchemaFields[descriptionKey]?.stringValue
    }

    /// Parses an array node's `items` and `minItems`/`maxItems` into an ``SchemaIR/array(items:)`` case, optionally wrapped in ``SchemaIR/guided(base:guide:)``.
    ///
    /// - Parameters:
    ///   - fields: The array node's raw JSON Schema fields.
    ///   - name: The name to assign the parsed array's item schema.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked if `items` is the legacy draft-07 tuple form (an array of schemas), or while parsing the item schema's descendants.
    /// - Returns: The parsed ``SchemaIR/array(items:)`` node (with `.unknown` items if `items` is absent), wrapped in `.guided(_, .count(...))` if `minItems`/`maxItems` is present.
    private static func parseArray(
        _ fields: [String: Value], name: String, path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        guard let items = fields["items"] else {
            return applyCountGuide(to: .array(items: .unknown), fields: fields, path: path, onDrop: onDrop)
        }
        if case .array = items {
            // Legacy draft-07 positional tuple validation (`items` as an array
            // of per-position schemas) has no `DynamicGenerationSchema`
            // equivalent — a single `arrayOf:` schema can't vary by position.
            onDrop(SchemaConversionLogRecord(keyword: "items", path: path))
            return .unknown
        }
        let itemsSchema = parseNode(items, name: "\(name)_item", path: "\(path)/items", onDrop: onDrop)
        return applyCountGuide(to: .array(items: itemsSchema), fields: fields, path: path, onDrop: onDrop)
    }

    /// Applies `minItems`/`maxItems` to an `.array` base, wrapping it in ``SchemaIR/guided(base:guide:)`` if either is present.
    ///
    /// - Parameters:
    ///   - base: The already-resolved `.array(items:)` base schema.
    ///   - fields: The array node's raw JSON Schema fields, to read `minItems`/`maxItems` from.
    ///   - path: A slash-delimited JSON path to this node, for ``SchemaConversionLogRecord``.
    ///   - onDrop: Invoked if `minItems` and `maxItems` cross (`minItems > maxItems`), which describes no array at all.
    /// - Returns: `base` unchanged if neither `minItems` nor `maxItems` is present or they cross, or `.guided(base:, guide: .count(...))` if a valid (non-crossing) bound is present.
    private static func applyCountGuide(
        to base: SchemaIR, fields: [String: Value], path: String, onDrop: SchemaConversionLogHandler
    ) -> SchemaIR {
        let minimum = intValue(fields["minItems"])
        let maximum = intValue(fields["maxItems"])
        // `minItems > maxItems` is self-contradictory (no array satisfies
        // it); `applyBoundsGuide` drops the constraint (logged) and keeps
        // the plain structural array rather than silently emitting an
        // unsatisfiable schema verbatim, mirroring
        // `applyNumericRangeGuide`'s crossed-bound handling.
        return applyBoundsGuide(
            to: base, minimum: minimum, maximum: maximum, keyword: "minItems", path: path, onDrop: onDrop
        ) { .count(minimum: $0, maximum: $1) }
    }

    /// Reads a JSON Schema integer keyword's raw `Value` as an `Int`.
    ///
    /// - Parameter value: The raw `Value` to convert, typically a dictionary lookup like `fields["minItems"]`.
    /// - Returns: The value as an `Int`, or `nil` if `value` is absent or not a JSON integer.
    private static func intValue(_ value: Value?) -> Int? {
        guard case .int(let int)? = value else { return nil }
        return int
    }

    /// MCP 2025-11-25 targets JSON Schema 2020-12, whose default `$ref` anchor for a top-level `$defs` entry is `#/$defs/<name>`; the legacy `#/definitions/<name>` form (see `definitionsContainerKeys`) is recognized alongside it.
    ///
    /// - Parameter reference: The raw `$ref` string value from a schema node.
    /// - Returns: The resolved definition name, or `nil` if `reference` does not match a recognized `$defs`/`definitions` container prefix.
    private static func definitionName(fromRef reference: String) -> String? {
        for containerKey in definitionsContainerKeys {
            let prefix = "#/\(containerKey)/"
            if reference.hasPrefix(prefix) {
                return String(reference.dropFirst(prefix.count))
            }
        }
        return nil
    }

    // MARK: - Emission (SchemaIR → DynamicGenerationSchema)

    /// The primitive `SchemaIR` cases (plus the ``SchemaIR/unknown`` fallback, which also degrades to a permissive string schema), each paired with its precomputed `DynamicGenerationSchema`.
    ///
    /// Looked up by equality in ``dynamicSchema(for:)`` instead of switching on each case, since every entry differs only in the `Generable` type passed to ``primitiveSchema(_:)``.
    private static let primitiveDynamicSchemas: [(SchemaIR, DynamicGenerationSchema)] = [
        (.string, primitiveSchema(String.self)),
        (.integer, primitiveSchema(Int.self)),
        (.number, primitiveSchema(Double.self)),
        (.boolean, primitiveSchema(Bool.self)),
        (.unknown, primitiveSchema(String.self)),
    ]

    /// Translates a parsed `SchemaIR` node into its `DynamicGenerationSchema` equivalent.
    ///
    /// - Parameter node: The parsed schema node to translate.
    /// - Returns: The equivalent `DynamicGenerationSchema`.
    private static func dynamicSchema(for node: SchemaIR) -> DynamicGenerationSchema {
        switch node {
        case .object(let name, let description, let properties):
            return DynamicGenerationSchema(
                name: name,
                description: description,
                properties: properties.map { property in
                    DynamicGenerationSchema.Property(
                        name: property.name,
                        description: property.description,
                        schema: dynamicSchema(for: property.schema),
                        isOptional: property.isOptional
                    )
                }
            )
        case .array(let items):
            return DynamicGenerationSchema(arrayOf: dynamicSchema(for: items))
        case .enumeration(let name, let description, let values):
            return DynamicGenerationSchema(name: name, description: description, anyOf: values)
        case .reference(let name):
            return DynamicGenerationSchema(referenceTo: name)
        case .guided(let base, let guide):
            return dynamicSchema(forGuidedBase: base, guide: guide)
        case .string, .integer, .number, .boolean, .unknown:
            // Every primitive case (plus `.unknown`'s permissive fallback) is
            // precomputed in `primitiveDynamicSchemas`; look it up by equality
            // rather than repeating `primitiveSchema(_:)` per case.
            return primitiveDynamicSchemas.first(where: { $0.0 == node })?.1 ?? primitiveSchema(String.self)
        }
    }

    /// Builds a `DynamicGenerationSchema` for a `Generable` primitive Swift type.
    ///
    /// - Parameter type: The primitive Swift type (`String`, `Int`, `Double`, or `Bool`) to build a schema for.
    /// - Returns: The equivalent `DynamicGenerationSchema`.
    private static func primitiveSchema<Primitive: Generable>(_ type: Primitive.Type) -> DynamicGenerationSchema {
        DynamicGenerationSchema(type: type)
    }

    /// Translates a ``SchemaIR/guided(base:guide:)`` node into its `DynamicGenerationSchema` equivalent, applying `guide` as a real Apple `GenerationGuide` (or, for ``SchemaIR/GuideSpec/count(minimum:maximum:)``, `DynamicGenerationSchema`'s dedicated element-count parameters).
    ///
    /// - Parameters:
    ///   - base: The structural schema `guide` constrains.
    ///   - guide: The runtime constraint to apply.
    /// - Returns: The equivalent `DynamicGenerationSchema`, with the guide applied. Falls back to the unguided ``dynamicSchema(for:)`` translation of `base` for a `(base, guide)` combination `SchemaConverter` never actually constructs during parsing (each `GuideSpec` case is only ever paired with the base it was parsed from).
    private static func dynamicSchema(forGuidedBase base: SchemaIR, guide: SchemaIR.GuideSpec) -> DynamicGenerationSchema {
        switch (base, guide) {
        case (.integer, .numericRange(let minimum, let maximum)),
            (.number, .numericRange(let minimum, let maximum)):
            return DynamicGenerationSchema(type: Decimal.self, guides: [decimalRangeGuide(minimum: minimum, maximum: maximum)])
        case (.string, .pattern(let source)):
            return dynamicSchema(forStringPattern: source, fallbackBase: base)
        case (.array(let items), .count(let minimum, let maximum)):
            return DynamicGenerationSchema(
                arrayOf: dynamicSchema(for: items), minimumElements: minimum, maximumElements: maximum)
        default:
            return dynamicSchema(for: base)
        }
    }

    /// Builds the `DynamicGenerationSchema` for a `.string` base guided by ``SchemaIR/GuideSpec/pattern(_:)``, compiling `source` as a Swift `Regex`.
    ///
    /// - Parameters:
    ///   - source: The pattern's raw ECMA-262 regex source. `SchemaConverter` only ever constructs a `.pattern` guide for a source already confirmed to compile as a `Regex` during parsing (see ``applyPatternGuide(fields:path:onDrop:)``), so this recompile is expected to succeed; the fallback below exists only as a defensive guard, never actually exercised on a `SchemaIR` `SchemaConverter` itself produced.
    ///   - fallbackBase: The `.string` base to fall back to (unguided) if `source` fails to compile here.
    /// - Returns: `DynamicGenerationSchema(type: String.self, guides: [.pattern(regex)])` if `source` compiles as a `Regex`, or the unguided ``dynamicSchema(for:)`` translation of `fallbackBase` otherwise.
    private static func dynamicSchema(forStringPattern source: String, fallbackBase: SchemaIR) -> DynamicGenerationSchema {
        guard let regex = try? Regex(source) else { return dynamicSchema(for: fallbackBase) }
        return DynamicGenerationSchema(type: String.self, guides: [.pattern(regex)])
    }

    /// Builds the `GenerationGuide<Decimal>` for a ``SchemaIR/GuideSpec/numericRange(minimum:maximum:)``.
    ///
    /// - Parameters:
    ///   - minimum: The effective inclusive minimum, if any.
    ///   - maximum: The effective inclusive maximum, if any.
    /// - Returns: `.range(_:)` if both bounds are present, `.minimum(_:)`/`.maximum(_:)` if only one is.
    private static func decimalRangeGuide(minimum: Decimal?, maximum: Decimal?) -> GenerationGuide<Decimal> {
        switch (minimum, maximum) {
        case (let minimum?, let maximum?):
            return .range(minimum...maximum)
        case (let minimum?, nil):
            return .minimum(minimum)
        case (nil, let maximum?):
            return .maximum(maximum)
        case (nil, nil):
            preconditionFailure(
                "SchemaConverter never constructs .numericRange(nil, nil); applyNumericRangeGuide(to:fields:) only wraps a base in .guided when at least one bound is present.")
        }
    }
}
