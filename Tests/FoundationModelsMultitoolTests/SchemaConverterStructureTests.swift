import Foundation
import MCP
import Testing

@testable import FoundationModelsMultitool

/// Table-driven tests asserting the JSON-Schema-2020-12-to-`SchemaIR` structure
/// mapping over a corpus of real-world MCP tool `inputSchema` fixtures.
///
/// A port of the sibling `FoundationModelsMCP` suite of the same name. The
/// fixtures it reads stand in `MCPFixtures/`, and `loadMCPSchemaFixture(_:)`
/// is how each test reads one.
///
/// `DynamicGenerationSchema` / `GenerationSchema` are opaque (no public
/// introspection), so these tests assert against `SchemaIR` — the inspectable
/// stage-1 intermediate representation — rather than the emitted Apple types.
/// The one exception is `emissionSmokeTest`, which only checks that stage 2
/// (`SchemaIR` → `DynamicGenerationSchema` → `GenerationSchema`) completes
/// without throwing.
@Suite("SchemaConverterStructureTests")
struct SchemaConverterStructureTests {

    /// Every structure fixture in `MCPFixtures/`, covering each structural
    /// shape the converter maps — object/properties/required, primitives,
    /// arrays, enums, nested objects, and `$ref`/`$defs` — at least once.
    private static let allFixtureNames = [
        "read_file",
        "search_code",
        "list_directory",
        "set_log_level",
        "create_user",
        "create_ticket",
        "weather_query",
        "git_commit",
        "advanced_filter",
    ]

    // MARK: - type: object + properties, required → non-optional

    @Test("object properties are parsed with required fields marked non-optional")
    func objectPropertiesAndRequired() throws {
        let inputSchema = try loadMCPSchemaFixture("read_file")
        let conversion = SchemaConverter.parse(inputSchema, name: "read_file")

        guard case .object(let name, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }
        #expect(name == "read_file")
        #expect(properties.count == 1)

        let path = try #require(properties.first { $0.name == "path" })
        #expect(path.isOptional == false)
        #expect(path.description == "Absolute path to the file to read.")
        guard case .string = path.schema else {
            Issue.record("expected path to be .string")
            return
        }
    }

    // MARK: - primitives (string, number, integer, boolean)

    @Test("primitive property types map to their IR primitive cases")
    func primitiveTypes() throws {
        let inputSchema = try loadMCPSchemaFixture("search_code")
        let conversion = SchemaConverter.parse(inputSchema, name: "search_code")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }

        let query = try #require(properties.first { $0.name == "query" })
        let maxResults = try #require(properties.first { $0.name == "maxResults" })
        let matchThreshold = try #require(properties.first { $0.name == "matchThreshold" })
        let caseSensitive = try #require(properties.first { $0.name == "caseSensitive" })

        guard case .string = query.schema else {
            Issue.record("expected query to be .string")
            return
        }
        guard case .integer = maxResults.schema else {
            Issue.record("expected maxResults to be .integer")
            return
        }
        guard case .number = matchThreshold.schema else {
            Issue.record("expected matchThreshold to be .number")
            return
        }
        guard case .boolean = caseSensitive.schema else {
            Issue.record("expected caseSensitive to be .boolean")
            return
        }

        #expect(query.isOptional == false)
        #expect(maxResults.isOptional == true)
        #expect(matchThreshold.isOptional == true)
        #expect(caseSensitive.isOptional == true)
    }

    // MARK: - array + items

    @Test("array property carries its items schema")
    func arrayItems() throws {
        let inputSchema = try loadMCPSchemaFixture("list_directory")
        let conversion = SchemaConverter.parse(inputSchema, name: "list_directory")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }

        let paths = try #require(properties.first { $0.name == "paths" })
        guard case .array(let items) = paths.schema else {
            Issue.record("expected paths to be .array")
            return
        }
        guard case .string = items else {
            Issue.record("expected array items to be .string")
            return
        }
    }

    // MARK: - enum

    @Test("enum property is parsed with all choice values")
    func enumProperty() throws {
        let inputSchema = try loadMCPSchemaFixture("set_log_level")
        let conversion = SchemaConverter.parse(inputSchema, name: "set_log_level")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }

        let level = try #require(properties.first { $0.name == "level" })
        #expect(level.description == "The minimum severity to log.")
        guard case .enumeration(_, let description, let values) = level.schema else {
            Issue.record("expected level to be .enumeration")
            return
        }
        #expect(description == "The minimum severity to log.")
        #expect(values == ["debug", "info", "warning", "error", "critical"])
    }

    // MARK: - nested objects

    @Test("nested object property is parsed with its own properties")
    func nestedObject() throws {
        let inputSchema = try loadMCPSchemaFixture("create_user")
        let conversion = SchemaConverter.parse(inputSchema, name: "create_user")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }

        let address = try #require(properties.first { $0.name == "address" })
        #expect(address.description == "The user's mailing address.")
        guard case .object(_, let nestedDescription, let addressProperties) = address.schema else {
            Issue.record("expected address to be a nested .object")
            return
        }
        #expect(nestedDescription == "The user's mailing address.")

        #expect(Set(addressProperties.map(\.name)) == ["street", "city", "postalCode"])
        let postalCode = try #require(addressProperties.first { $0.name == "postalCode" })
        #expect(postalCode.isOptional == true)
        let street = try #require(addressProperties.first { $0.name == "street" })
        #expect(street.isOptional == false)
    }

    // MARK: - $ref / $defs → named schema + dependencies

    @Test("$ref resolves to a reference node with the definition parsed into definitions")
    func refAndDefs() throws {
        let inputSchema = try loadMCPSchemaFixture("create_ticket")
        let conversion = SchemaConverter.parse(inputSchema, name: "create_ticket")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }

        let priority = try #require(properties.first { $0.name == "priority" })
        guard case .reference(let definitionName) = priority.schema else {
            Issue.record("expected priority to be a .reference")
            return
        }
        #expect(definitionName == "Priority")

        let definition = try #require(conversion.definitions["Priority"])
        guard case .enumeration(_, let definitionDescription, let values) = definition else {
            Issue.record("expected the Priority definition to be an .enumeration")
            return
        }
        #expect(definitionDescription == "Ticket priority.")
        #expect(values == ["low", "medium", "high", "urgent"])
    }

    @Test("$ref also resolves the legacy #/definitions/ pointer form")
    func legacyDefinitionsRefPrefix() throws {
        let inputSchema: Value = [
            "type": "object",
            "properties": [
                "priority": ["$ref": "#/definitions/Priority"]
            ],
            "required": ["priority"],
            "definitions": [
                "Priority": [
                    "type": "string",
                    "enum": ["low", "medium", "high"],
                ]
            ],
        ]
        let conversion = SchemaConverter.parse(inputSchema, name: "legacy_ref")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }
        let priority = try #require(properties.first { $0.name == "priority" })
        guard case .reference(let definitionName) = priority.schema else {
            Issue.record("expected priority to be a .reference")
            return
        }
        #expect(definitionName == "Priority")

        let definition = try #require(conversion.definitions["Priority"])
        guard case .enumeration(_, _, let values) = definition else {
            Issue.record("expected the Priority definition to be an .enumeration")
            return
        }
        #expect(values == ["low", "medium", "high"])

        _ = try SchemaConverter.emit(conversion)
    }

    // MARK: - unknown keywords fall through gracefully

    @Test("unmapped JSON Schema keywords fall through to .unknown instead of throwing")
    func unknownKeywordFallback() throws {
        let inputSchema = try loadMCPSchemaFixture("advanced_filter")
        let conversion = SchemaConverter.parse(inputSchema, name: "advanced_filter")

        guard case .object(_, _, let properties) = conversion.root else {
            Issue.record("expected an object root")
            return
        }

        let predicate = try #require(properties.first { $0.name == "predicate" })
        guard case .unknown = predicate.schema else {
            Issue.record("expected predicate (anyOf) to fall through to .unknown")
            return
        }
    }

    // MARK: - full corpus coverage

    @Test("every corpus fixture parses to an object root")
    func corpusParsesToObjectRoots() throws {
        for fixtureName in Self.allFixtureNames {
            let inputSchema = try loadMCPSchemaFixture(fixtureName)
            let conversion = SchemaConverter.parse(inputSchema, name: fixtureName)
            guard case .object = conversion.root else {
                Issue.record("fixture \(fixtureName) did not parse to an object root")
                continue
            }
        }
    }

    // MARK: - emission smoke test (SchemaIR → DynamicGenerationSchema → GenerationSchema)

    @Test("every corpus fixture emits a GenerationSchema without throwing")
    func emissionSmokeTest() throws {
        for fixtureName in Self.allFixtureNames {
            let inputSchema = try loadMCPSchemaFixture(fixtureName)
            let conversion = SchemaConverter.parse(inputSchema, name: fixtureName)
            _ = try SchemaConverter.emit(conversion)
        }
    }
}
