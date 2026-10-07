import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``JSONParserPlugin`` — the port of `parser/plugins/json.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The tests port the Rust tests of `json.rs`. The Rust plugin reads the
/// text by hand (it does not use `serde_json`), and so does the port: each
/// top-level key of the root object is one entity, and the id holds the JSON
/// Pointer of the key. `DataPluginEntityGoldenTests` holds the output of the
/// Rust plugin for more inputs.
@Suite("JSONParserPluginTests")
struct JSONParserPluginTests {

    /// The entities that the JSON plugin reads from `content` at `filePath`.
    private static func entities(_ content: String, at filePath: String = "config.json") -> [SemanticEntity] {
        JSONParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// Each top-level key has its own lines; an object value spans its lines
    /// (`test_json_line_positions`).
    @Test("each top-level key has its own lines")
    func eachTopLevelKeyHasItsOwnLines() {
        let content = """
            {
              "name": "my-app",
              "version": "1.0.0",
              "scripts": {
                "build": "tsc",
                "test": "jest"
              },
              "description": "a test app"
            }

            """
        let entities = Self.entities(content, at: "package.json")

        #expect(entities.map(\.name) == ["name", "version", "scripts", "description"])
        #expect(entities.map(\.startLine) == [2, 3, 4, 8])
        #expect(entities.map(\.endLine) == [2, 3, 7, 8])
        #expect(entities.map(\.entityType) == ["property", "property", "object", "property"])
    }

    /// A renamed key with the same value is a rename
    /// (`test_rename_detected_end_to_end`).
    @Test("a renamed key with the same value is a rename")
    func aRenamedKeyIsARename() throws {
        let before = Self.entities("{\n  \"timeout\": 30\n}\n")
        let after = Self.entities("{\n  \"request_timeout\": 30\n}\n")

        let result = EntityMatcher.matchEntities(before: before, after: after, similarity: nil)
        let change = try #require(result.changes.first)

        #expect(result.changes.count == 1)
        #expect(change.changeType == .renamed)
        #expect(change.entityName == "request_timeout")
    }

    /// The structural hash reads the value only, so a renamed key keeps it
    /// (`test_renamed_scalar_property_shares_structural_hash`,
    /// `test_renamed_object_property_shares_structural_hash`).
    @Test(
        "a renamed key keeps its structural hash",
        arguments: [
            ("{\n  \"timeout\": 30\n}\n", "{\n  \"request_timeout\": 30\n}\n"),
            ("{\n  \"config\": {\n    \"port\": 8080\n  }\n}\n", "{\n  \"settings\": {\n    \"port\": 8080\n  }\n}\n"),
        ])
    func aRenamedKeyKeepsItsStructuralHash(before: String, after: String) throws {
        let old = try #require(Self.entities(before).first)
        let new = try #require(Self.entities(after).first)

        #expect(old.contentHash != new.contentHash)
        #expect(old.structuralHash == new.structuralHash)
    }

    /// A root that is not an object, an empty file, and a blank file have no
    /// entity (`test_non_object_json_returns_empty`, `test_empty_json_returns_empty`,
    /// `test_whitespace_only_returns_empty`).
    @Test("no root object gives no entity", arguments: ["[1, 2, 3]", "", "   \n  \n  "])
    func noRootObjectGivesNoEntity(content: String) {
        #expect(Self.entities(content).isEmpty)
    }

    /// A scalar value is a `property` (`test_single_property`,
    /// `test_boolean_and_null_values`, `test_numeric_value`).
    @Test("a scalar value is a property")
    func aScalarValueIsAProperty() {
        let entities = Self.entities("{\n  \"enabled\": true,\n  \"debug\": false,\n  \"extra\": null,\n  \"port\": 8080\n}\n")

        #expect(entities.map(\.entityType) == ["property", "property", "property", "property"])
    }

    /// An array value is an `object`, and so is a nested object; a nested key
    /// is not an entity (`test_nested_array_value`,
    /// `test_deeply_nested_object_is_single_entity`).
    @Test("a container value is one object entity")
    func aContainerValueIsOneObjectEntity() {
        #expect(Self.entities("{\n  \"items\": [\n    1,\n    2\n  ]\n}\n").map(\.entityType) == ["object"])
        #expect(
            Self.entities("{\n  \"config\": {\n    \"db\": {\n      \"host\": \"localhost\"\n    }\n  }\n}\n").map(\.name)
                == ["config"])
    }

    /// The JSON Pointer in the id writes `~` as `~0` and `/` as `~1`
    /// (`test_json_pointer_with_special_chars`).
    @Test("the pointer escapes a tilde and a slash")
    func thePointerEscapesATildeAndASlash() {
        let entities = Self.entities("{\n  \"a/b\": 1,\n  \"c~d\": 2\n}\n", at: "special.json")

        #expect(entities.map(\.id) == ["special.json::property::/a~1b", "special.json::property::/c~0d"])
    }

    /// A colon in a value and an escaped quote in a key do not end the key
    /// (`test_string_value_with_colon`, `test_escaped_quote_in_key`).
    @Test("a colon in a value and an escaped quote in a key do not end the key")
    func aColonAndAnEscapedQuoteDoNotEndTheKey() {
        #expect(Self.entities("{\n  \"url\": \"http://example.com:8080\"\n}\n").map(\.name) == ["url"])
        #expect(Self.entities("{\n  \"say\\\"hi\\\"\": \"value\"\n}\n").map(\.name) == ["say\\\"hi\\\""])
    }

    /// The keys keep the order of the text (`test_many_properties`).
    @Test("the keys keep the order of the text")
    func theKeysKeepTheOrderOfTheText() {
        let entities = Self.entities("{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3,\n  \"d\": 4,\n  \"e\": 5\n}\n")

        #expect(entities.map(\.name) == ["a", "b", "c", "d", "e"])
    }

    /// The value text is the text after the first colon outside a string,
    /// with no trailing comma (`test_extract_value_content_*`).
    @Test(
        "the value text is the text after the first bare colon",
        arguments: [
            ("\"key\": 42", "42"), ("\"key\": \"hello\"", "\"hello\""), ("\"key\": 42,", "42"),
            ("\"url:port\": 8080", "8080"), ("just some text", "just some text"),
        ])
    func theValueTextIsTheTextAfterTheFirstBareColon(entry: String, value: String) {
        #expect(JSONParserPlugin.valueText(ofEntry: entry) == value)
    }

    /// The path of the file is the path of each entity (`test_entity_file_path`).
    @Test("the path of the file is the path of each entity")
    func thePathOfTheFileIsThePathOfEachEntity() {
        #expect(Self.entities("{\n  \"key\": \"value\"\n}\n", at: "path/to/config.json").map(\.filePath) == ["path/to/config.json"])
    }

    /// The default registry gives a `.json` file to this plugin
    /// (`test_json_plugin_id_and_extensions`).
    @Test("the default registry selects the JSON plugin", arguments: ["package.json", "DATA.JSON"])
    func theDefaultRegistrySelectsTheJSONPlugin(filePath: String) {
        #expect(JSONParserPlugin().extensions == [".json"])
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == JSONParserPlugin.pluginID)
    }
}
