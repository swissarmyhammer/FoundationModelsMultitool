import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``TOMLParserPlugin`` — the port of
/// `parser/plugins/toml_plugin.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The first test ports `test_toml_line_positions`. The other tests check
/// the content hash, which the Rust plugin computes from the value of each
/// entry: the pretty JSON text of a table, and the Rust `Display` text of a
/// scalar. `DataPluginEntityGoldenTests` holds the output of the Rust plugin
/// for more inputs.
@Suite("TOMLParserPluginTests")
struct TOMLParserPluginTests {

    /// The entities that the TOML plugin reads from `content` at `filePath`.
    private static func entities(_ content: String, at filePath: String = "Cargo.toml") -> [SemanticEntity] {
        TOMLParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// Each section header starts an entity that runs to the next one
    /// (`test_toml_line_positions`).
    @Test("each section runs to the next section")
    func eachSectionRunsToTheNextSection() {
        let content = """
            [package]
            name = "my-app"
            version = "1.0.0"

            [dependencies]
            serde = "1.0"
            tokio = { version = "1", features = ["full"] }

            """
        let entities = Self.entities(content)

        #expect(entities.map(\.name) == ["package", "dependencies"])
        #expect(entities.map(\.startLine) == [1, 5])
        #expect(entities.map(\.endLine) == [3, 7])
        #expect(entities.map(\.entityType) == ["section", "section"])
    }

    /// The hash of a table is the hash of its pretty JSON text, with the keys
    /// in byte order.
    @Test("the hash of a table is the hash of its JSON text")
    func theHashOfATableIsTheHashOfItsJSONText() {
        let entities = Self.entities("[package]\nversion = \"1.0.0\"\nname = \"my-app\"\n")

        #expect(entities.map(\.contentHash) == [
            SemanticHash.contentHash("{\n  \"name\": \"my-app\",\n  \"version\": \"1.0.0\"\n}")
        ])
    }

    /// A root key before the first header is a `property`; the hash of a
    /// scalar is the hash of its text.
    @Test("a root key is a property")
    func aRootKeyIsAProperty() {
        let entities = Self.entities("title = \"demo\"\nport = 8080\n\n[server]\nhost = \"x\"\n")

        #expect(entities.map(\.name) == ["title", "port", "server"])
        #expect(entities.map(\.entityType) == ["property", "property", "section"])
        #expect(entities.prefix(2).map(\.contentHash) == [SemanticHash.contentHash("demo"), SemanticHash.contentHash("8080")])
    }

    /// A header that the parsed table does not hold under its text (a dotted
    /// header) is a `property` with the hash of its own lines.
    @Test("a dotted header hashes its lines")
    func aDottedHeaderHashesItsLines() {
        let entities = Self.entities("[a.b]\nc = 1\n")

        #expect(entities.map(\.name) == ["a.b"])
        #expect(entities.map(\.entityType) == ["property"])
        #expect(entities.map(\.contentHash) == [SemanticHash.contentHash("[a.b]\nc = 1")])
    }

    /// A text that the TOML parser refuses gives no entity.
    @Test("an invalid document gives no entity", arguments: ["a = \n", "a = 1\na = 2\n", "[t]\n[t]\n", "", "# only\n"])
    func anInvalidDocumentGivesNoEntity(content: String) {
        #expect(Self.entities(content).isEmpty)
    }

    /// An integer out of the `Int64` range makes the `toml` crate refuse the
    /// file. TOMLDecoder reads it as a float, thus the plugin finds it in the
    /// text.
    @Test(
        "an integer out of range gives no entity",
        arguments: [
            "a = 99999999999999999999\n", "a = 0xFFFFFFFFFFFFFFFF\n", "a = -9_223_372_036_854_775_809\n",
            "[t]\na = [\n  1,\n  99999999999999999999,\n]\n", "a = { b = 99999999999999999999 }\n",
        ])
    func anIntegerOutOfRangeGivesNoEntity(content: String) {
        #expect(Self.entities(content).isEmpty)
    }

    /// A long digit run that is a key, a string, or a comment is not an
    /// integer value.
    @Test("a long digit run that is not a value is not an integer")
    func aLongDigitRunThatIsNotAValueIsNotAnInteger() {
        let entities = Self.entities(
            "99999999999999999999 = 1\nx = \"99999999999999999999\" # 99999999999999999999\ny = { 99999999999999999999 = 2 }\n"
        )

        #expect(entities.map(\.name) == ["99999999999999999999", "x", "y"])
    }

    /// The radix prefixes are case-sensitive, as in the `toml` crate: `0X` is
    /// not a hexadecimal prefix, thus `0XFFFFFFFFFFFFFFFF` is not an integer
    /// that the range check reads, and the file is refused for its syntax.
    @Test("the radix prefix is case-sensitive")
    func theRadixPrefixIsCaseSensitive() {
        #expect(Self.entities("a = 0XFFFFFFFFFFFFFFFF\n").isEmpty)
        #expect(Self.entities("a = 0xFFFFFFFFFFFFFFF\n").map(\.contentHash) == [
            SemanticHash.contentHash(String(Int64(0xFFF_FFFF_FFFF_FFFF)))
        ])
    }

    /// A time keeps the spelling of the source: no seconds, and a zero
    /// fraction.
    @Test("a time keeps its spelling")
    func aTimeKeepsItsSpelling() {
        let entities = Self.entities("l = 07:32\nn = 09:45:00.000\n")

        #expect(entities.map(\.contentHash) == [SemanticHash.contentHash("07:32"), SemanticHash.contentHash("09:45:00.0")])
    }

    /// The default registry gives a `.toml` file to this plugin.
    @Test("the default registry selects the TOML plugin", arguments: ["Cargo.toml", "PYPROJECT.TOML"])
    func theDefaultRegistrySelectsTheTOMLPlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == TOMLParserPlugin.pluginID)
    }
}
