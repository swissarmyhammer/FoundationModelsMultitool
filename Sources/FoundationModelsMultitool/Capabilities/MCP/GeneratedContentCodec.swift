// `GeneratedContentCodec` — the bridge between `GeneratedContent` and
// `MCP.Value`.
//
// A behavioral port of `../FoundationModelsMCP/Sources/FoundationModelsMCP/
// GeneratedContentCodec.swift`. eventplan.md § "Consolidation of the siblings"
// moves "the `SchemaConverter` / `GeneratedContentCodec` pair" into this
// folder. The converter is the inbound half: a JSON Schema from `tools/list`
// becomes the `GenerationSchema` of a verb's arguments. This file is the
// outbound half: the `GeneratedContent` the model produced against that
// schema becomes the `[String: MCP.Value]` of `tools/call`.
//
// **The types are internal.** The Shell capability keeps its types internal,
// and this folder does the same: `MCPTool`, which comes in a later task, is
// the one production caller, and the tests reach the codec with
// `@testable import`.
//
// **Integers are the one place the two representations disagree.**
// `GeneratedContent.Kind.number` holds a `Double` and nothing else, and
// `MCP.Value` holds `.int` beside `.double`. The codec keeps that distinction
// exactly as far as the SDK can show it: a whole-number `Double` becomes
// `.int`, and an `.int` that a `Double` cannot hold exactly is refused rather
// than rounded. The doc comments of `GeneratedContentCodecError` state each
// refusal.

import FoundationModels
import MCP

/// Errors thrown by ``GeneratedContentCodec`` when a value on one side of the
/// `GeneratedContent` ⇄ `MCP.Value` bridge has no equivalent representation
/// on the other side.
enum GeneratedContentCodecError: Error, Equatable, Sendable {
    /// ``GeneratedContentCodec/arguments(from:)`` requires a `GeneratedContent`
    /// whose `kind` is `.structure`, since MCP tool-call arguments are always
    /// a named argument map (a JSON object), never a bare scalar or array.
    case argumentsRequireObject
    /// `MCP.Value.data` (binary resource content) has no `GeneratedContent.Kind`
    /// equivalent — `GeneratedContent` only represents null/bool/number/string/
    /// array/object shapes.
    case unsupportedDataValue
    /// `GeneratedContent.Kind.number` wraps a `Double`, whose 53-bit mantissa
    /// cannot exactly represent every `Int` beyond `±2^53`. Converting such an
    /// `Int` would silently change its value on the way back out, so this is
    /// thrown instead of corrupting the integer.
    case integerPrecisionLoss(Int)
}

/// Converts between Apple FoundationModels' `GeneratedContent` — the
/// constrained-generation output of a `LanguageModelSession` — and the MCP
/// swift-sdk's `Value` — the JSON representation MCP uses for tool-call
/// arguments and results.
///
/// `GeneratedContent.Kind` is the only introspectable view of a
/// `GeneratedContent`'s shape, and its `.number` case wraps a plain `Double`:
/// there is no separate integer case. This means the SDK itself cannot
/// distinguish "the model generated the integer 5" from "the model generated
/// the double 5.0" once either is stored in a `GeneratedContent` — that
/// distinction genuinely does not exist to recover. This codec preserves
/// integer-ness exactly for whatever the SDK *can* distinguish: a `Double`
/// with no fractional part converts to `Value.int`, matching how a model
/// asked for an `integer`-typed property always produces a whole number.
enum GeneratedContentCodec {

    // MARK: - GeneratedContent -> MCP.Value

    /// Converts a `GeneratedContent`'s top-level structure into the
    /// `[String: Value]` argument map MCP tool calls require.
    ///
    /// - Parameter content: A `GeneratedContent` produced by constrained
    ///   generation against an object-shaped `GenerationSchema` (e.g. a
    ///   tool's `inputSchema`).
    /// - Returns: The content's properties, converted to `Value`.
    /// - Throws: ``GeneratedContentCodecError/argumentsRequireObject`` if
    ///   `content.kind` is not `.structure`.
    static func arguments(from content: GeneratedContent) throws -> [String: Value] {
        guard case .structure(let properties, _) = content.kind else {
            throw GeneratedContentCodecError.argumentsRequireObject
        }
        return properties.mapValues(value(from:))
    }

    /// Converts a `GeneratedContent` of any shape into its `Value` equivalent.
    ///
    /// - Parameter content: The `GeneratedContent` to convert.
    /// - Returns: The equivalent `Value`, recursively converting nested
    ///   arrays/objects.
    static func value(from content: GeneratedContent) -> Value {
        switch content.kind {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .number(let double):
            if let int = Int(exactly: double) {
                return .int(int)
            }
            return .double(double)
        case .string(let string):
            return .string(string)
        case .array(let elements):
            return .array(elements.map(value(from:)))
        case .structure(let properties, _):
            return .object(properties.mapValues(value(from:)))
        @unknown default:
            return .null
        }
    }

    // MARK: - MCP.Value -> GeneratedContent

    /// Converts a `Value` into its `GeneratedContent` equivalent, for
    /// round-tripping a tool result (or test fixture) back into
    /// FoundationModels' constrained-generation representation.
    ///
    /// - Parameter value: The `Value` to convert.
    /// - Returns: The equivalent `GeneratedContent`.
    /// - Throws: ``GeneratedContentCodecError/unsupportedDataValue`` if
    ///   `value` is `.data`, which has no `GeneratedContent.Kind` equivalent,
    ///   or ``GeneratedContentCodecError/integerPrecisionLoss(_:)`` if `value`
    ///   contains an `.int` beyond `Double`'s exact-representation range.
    static func generatedContent(from value: Value) throws -> GeneratedContent {
        GeneratedContent(kind: try kind(from: value))
    }

    /// Converts a `Value` into its `GeneratedContent.Kind` equivalent.
    ///
    /// - Parameter value: The `Value` to convert.
    /// - Returns: The equivalent `GeneratedContent.Kind`.
    /// - Throws: ``GeneratedContentCodecError/unsupportedDataValue`` if
    ///   `value` is `.data`, or ``GeneratedContentCodecError/integerPrecisionLoss(_:)``
    ///   if `value` is an `.int` whose magnitude exceeds what `Double` can
    ///   represent exactly (`±2^53`).
    private static func kind(from value: Value) throws -> GeneratedContent.Kind {
        switch value {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            let double = Double(int)
            guard Int(exactly: double) == int else {
                throw GeneratedContentCodecError.integerPrecisionLoss(int)
            }
            return .number(double)
        case .double(let double):
            return .number(double)
        case .string(let string):
            return .string(string)
        case .data:
            throw GeneratedContentCodecError.unsupportedDataValue
        case .array(let elements):
            return .array(try elements.map(generatedContent(from:)))
        case .object(let fields):
            let orderedKeys = fields.keys.sorted()
            let properties = try fields.mapValues(generatedContent(from:))
            return .structure(properties: properties, orderedKeys: orderedKeys)
        }
    }
}
