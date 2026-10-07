import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``YAMLParserPlugin`` — the port of `parser/plugins/yaml.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The first test ports `test_yaml_line_positions`. The other tests check
/// the content hash, which the Rust plugin computes from the text that
/// serde_yaml_ng writes for the value of each key. `DataPluginEntityGoldenTests`
/// holds the output of the Rust plugin for more inputs.
@Suite("YAMLParserPluginTests")
struct YAMLParserPluginTests {

    /// The entities that the YAML plugin reads from `content` at `filePath`.
    private static func entities(_ content: String, at filePath: String = "config.yaml") -> [SemanticEntity] {
        YAMLParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// Each top-level key has its own lines; a mapping value is a `section`
    /// (`test_yaml_line_positions`).
    @Test("each top-level key has its own lines")
    func eachTopLevelKeyHasItsOwnLines() {
        let entities = Self.entities("name: my-app\nversion: 1.0.0\nscripts:\n  build: tsc\n  test: jest\ndescription: a test app\n")

        #expect(entities.map(\.name) == ["name", "version", "scripts", "description"])
        #expect(entities.map(\.startLine) == [1, 2, 3, 6])
        #expect(entities.map(\.endLine) == [1, 2, 5, 6])
        #expect(entities.map(\.entityType) == ["property", "property", "section", "property"])
        #expect(entities.map(\.id).first == "config.yaml::property::name")
    }

    /// The hash of a scalar is the hash of its text; the hash of a section is
    /// the hash of the text that serde_yaml_ng writes for its value.
    @Test("the hash reads the value text")
    func theHashReadsTheValueText() {
        let entities = Self.entities("name: my-app\nscripts:\n  build:   tsc\n  test: jest\n")

        #expect(entities.map(\.contentHash) == [
            SemanticHash.contentHash("my-app"), SemanticHash.contentHash("build: tsc\ntest: jest"),
        ])
        #expect(entities.map(\.content) == ["name: my-app", "scripts:\n  build:   tsc\n  test: jest"])
    }

    /// A comment line, a document marker, and an indented line are not keys,
    /// and the blank lines at the end of a key are not in its content.
    @Test("comments markers and blank lines are not keys")
    func commentsMarkersAndBlankLinesAreNotKeys() {
        let entities = Self.entities("---\n# a comment\na: 1\n\n\nb: 2\n...\n")

        #expect(entities.map(\.name) == ["a", "b"])
        #expect(entities.map(\.endLine) == [3, 7])
    }

    /// A text that serde_yaml_ng cannot read, a root that is not a mapping,
    /// two documents, and a duplicate key give no entity.
    @Test(
        "an unreadable document gives no entity",
        arguments: ["a: [1, 2\n", "- a: 1\n", "a: 1\n---\nb: 2\n", "a: 1\na: 2\n", ""])
    func anUnreadableDocumentGivesNoEntity(content: String) {
        #expect(Self.entities(content).isEmpty)
    }

    /// A key that the line scan reads and the parsed mapping does not hold
    /// gets the hash of its own lines: here the quoted key `"q"` is `q` in the
    /// mapping.
    @Test("a key that the mapping does not hold hashes its lines")
    func aKeyThatTheMappingDoesNotHoldHashesItsLines() {
        let entities = Self.entities("\"q\": 1\n")

        #expect(entities.map(\.name) == ["\"q\""])
        #expect(entities.map(\.contentHash) == [SemanticHash.contentHash("\"q\": 1")])
    }

    /// A scalar above U+FFFF is written as it is, as unsafe-libyaml writes it,
    /// and not with a `\U` escape, as the C libyaml writes it. A private use
    /// scalar in the same text stays as it is.
    @Test("a scalar above U+FFFF is written as it is")
    func aScalarAboveTheBasicPlaneIsWrittenAsItIs() {
        let entities = Self.entities("s:\n  e: \"\\U0001F600 x\"\n  q: \"a\\x07\\U0001F600\"\n  p: \"\\uE000\\U0001F600\"\n")

        #expect(entities.map(\.contentHash) == [
            SemanticHash.contentHash("e: \u{1F600} x\nq: \"a\\a\u{1F600}\"\np: \u{E000}\u{1F600}")
        ])
    }

    /// The default registry gives a `.yml` and a `.yaml` file to this plugin.
    @Test("the default registry selects the YAML plugin", arguments: ["a.yml", "b.yaml", "C.YAML"])
    func theDefaultRegistrySelectsTheYAMLPlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == YAMLParserPlugin.pluginID)
    }
}
