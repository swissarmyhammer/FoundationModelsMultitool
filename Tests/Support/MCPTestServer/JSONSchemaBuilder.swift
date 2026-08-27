// `JSONSchemaBuilder` — the small object schemas the scripted tools declare.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/JSONSchemaBuilder.swift`.
// Test support — see the header of `ScriptedServer.swift`.

import MCP

/// Minimal JSON Schema 2020-12 object-schema construction, shared by every
/// ``ScriptedServer`` tool factory so that no factory hand-rolls a
/// `Value.object([...])` literal for a trivial `inputSchema`.
public enum JSONSchemaBuilder {
    /// Builds an object-typed `inputSchema` / `outputSchema` `Value`.
    ///
    /// - Parameters:
    ///   - properties: Each property name mapped to its own schema fragment
    ///     (for example the result of ``string(description:)``).
    ///   - required: The subset of the keys of `properties` that are
    ///     required. Defaults to none.
    /// - Returns: A `Value.object` describing `{ "type": "object", ... }`.
    public static func object(properties: [String: Value], required: [String] = []) -> Value {
        var fields: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            fields["required"] = .array(required.map(Value.string))
        }
        return .object(fields)
    }

    /// Builds one string-property schema fragment, for use as one value in
    /// the `properties` of ``object(properties:required:)``.
    ///
    /// - Parameter description: An optional description of the property.
    /// - Returns: A `Value.object` describing `{ "type": "string", ... }`.
    public static func string(description: String? = nil) -> Value {
        var fields: [String: Value] = ["type": .string("string")]
        if let description {
            fields["description"] = .string(description)
        }
        return .object(fields)
    }

    /// The empty object schema (`{ "type": "object", "properties": {} }`),
    /// shared by every tool that takes no arguments.
    public static let emptySchema: Value = object(properties: [:])
}
