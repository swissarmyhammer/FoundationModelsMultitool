import Foundation
import Testing

import FoundationModels

/// Pins `GenerationSchema`'s real, compiled-SDK encoded JSON shape against
/// plan.md Finding #3, for fixture `@Generable` types (plan.md's
/// "Apple-encoder parity" pin). Run directly against Apple's own encoder —
/// no `ToolAPIRenderer` involved — so a divergence here is a fact about the
/// SDK, not about our renderer.
///
/// Two divergences from Finding #3's claimed shape were found and are
/// asserted below rather than assumed:
///
/// 1. **Optional is never a `["T", "null"]` union.** Finding #3 claimed
///    optional properties encode as `{"type": ["boolean", "null"]}`. The real
///    encoder (confirmed here, and independently with
///    `representNilExplicitlyInGeneratedContent: true`) always encodes the
///    plain scalar `"type"` and simply omits the property from `"required"`.
///    `ToolAPIRenderer` keys optionality off `required` alone, matching
///    reality.
/// 2. **`GenerationSchema` has no default-value concept at all.** A Swift
///    default property value never appears in the encoded schema, and even
///    round-tripping a hand-authored JSON Schema containing an explicit
///    `"default"` key through `GenerationSchema`'s own `Decodable`
///    conformance silently drops it — `GenerationSchema`'s internal model
///    has no slot for it. `ToolAPIRenderer` therefore renders no `default`
///    clause; the doc-mapping table's "default value" row is not
///    reachable through any real `GenerationSchema`.
@Suite("GenerationSchema Apple-encoder parity (plan.md Finding #3)")
struct AppleEncoderParityTests {
    /// Encodes `schema` with `JSONEncoder` (the same call `ToolAPIRenderer`
    /// makes) and parses it back as a loosely-typed JSON object for
    /// convenient shape assertions.
    private func encodedSchemaObject(_ schema: GenerationSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("object + properties + required encode as plain JSON Schema, matching Finding #3")
    func objectShapeMatchesFinding3() throws {
        let object = try encodedSchemaObject(WeatherArguments.generationSchema)
        #expect(object["type"] as? String == "object")
        let properties = try #require(object["properties"] as? [String: Any])
        #expect(properties.keys.sorted() == ["city", "units"])
        let cityProperty = try #require(properties["city"] as? [String: Any])
        #expect(cityProperty["type"] as? String == "string")
        #expect(cityProperty["description"] as? String == "IATA city code or city name.")
        let required = try #require(object["required"] as? [String])
        #expect(required == ["city"])
    }

    @Test("enum choices encode as {type: string, enum: […]}, matching Finding #3")
    func enumShapeMatchesFinding3() throws {
        let object = try encodedSchemaObject(EnumArgument.generationSchema)
        let properties = try #require(object["properties"] as? [String: Any])
        let sizeProperty = try #require(properties["size"] as? [String: Any])
        #expect(sizeProperty["type"] as? String == "string")
        #expect(sizeProperty["enum"] as? [String] == ["small", "medium", "large"])
    }

    @Test("optional properties are omitted from `required`, not encoded as a [\"T\", \"null\"] union — a divergence from Finding #3")
    func optionalDivergesFromNullableUnionClaim() throws {
        let object = try encodedSchemaObject(WeatherArguments.generationSchema)
        let properties = try #require(object["properties"] as? [String: Any])
        let unitsProperty = try #require(properties["units"] as? [String: Any])

        // Finding #3 claimed this would be `["string", "null"]`; the real
        // encoder emits the plain scalar type.
        #expect(unitsProperty["type"] as? String == "string")

        let required = try #require(object["required"] as? [String])
        #expect(!required.contains("units"))
    }

    @Test("optional is still a plain scalar type even with representNilExplicitlyInGeneratedContent: true")
    func explicitNilRepresentationStillOmitsFromRequiredOnly() throws {
        let object = try encodedSchemaObject(ExplicitNilArgument.generationSchema)
        let properties = try #require(object["properties"] as? [String: Any])
        let maybeProperty = try #require(properties["maybe"] as? [String: Any])
        #expect(maybeProperty["type"] as? String == "string")
        let required = try #require(object["required"] as? [String])
        #expect(!required.contains("maybe"))
    }

    @Test("a Swift default property value never appears in the encoded schema")
    func defaultValuesAreNeverEncoded() throws {
        let object = try encodedSchemaObject(DefaultedArgument.generationSchema)
        let properties = try #require(object["properties"] as? [String: Any])
        let unitsProperty = try #require(properties["units"] as? [String: Any])
        #expect(unitsProperty["default"] == nil)
    }

    @Test("a hand-authored \"default\" key does not survive GenerationSchema's own Decodable round-trip")
    func handAuthoredDefaultKeyIsDroppedOnDecode() throws {
        let handAuthored = """
        {
          "type": "object",
          "title": "Hand",
          "additionalProperties": false,
          "x-order": ["a"],
          "properties": {
            "a": { "type": "string", "description": "a field", "default": "hi" }
          },
          "required": ["a"]
        }
        """
        let decoded = try JSONDecoder().decode(GenerationSchema.self, from: Data(handAuthored.utf8))
        let object = try encodedSchemaObject(decoded)
        let properties = try #require(object["properties"] as? [String: Any])
        let aProperty = try #require(properties["a"] as? [String: Any])
        #expect(aProperty["default"] == nil)
        #expect(aProperty["description"] as? String == "a field")
    }
}

/// A property with `representNilExplicitlyInGeneratedContent: true` — the
/// one other mechanism that might plausibly change optional's encoded shape.
/// It doesn't (see `explicitNilRepresentationStillOmitsFromRequiredOnly`).
@Generable(representNilExplicitlyInGeneratedContent: true)
struct ExplicitNilArgument {
    var maybe: String?
    var required: String
}
