import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``CSVParserPlugin`` — the port of
/// `parser/plugins/csv_plugin.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The tests port the Rust tests of `csv_plugin.rs`, and add the rules that
/// the Rust tests do not name: the line numbers skip blank lines, and the
/// `.tsv` test is case-sensitive. The expected values of the added tests come
/// from the Rust plugin (`DataPluginEntityGoldenTests` holds the full output).
@Suite("CSVParserPluginTests")
struct CSVParserPluginTests {

    /// The entities that the CSV plugin reads from `content` at `filePath`.
    private static func entities(_ content: String, at filePath: String = "data.csv") -> [SemanticEntity] {
        CSVParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// Each data row is one `row` entity (`test_basic_csv_row_extraction`).
    @Test("each data row is one row entity")
    func eachDataRowIsOneRowEntity() {
        let entities = Self.entities("name,age,city\nAlice,30,NYC\nBob,25,LA\n")

        #expect(entities.map(\.entityType) == [CSVParserPlugin.rowEntityType, CSVParserPlugin.rowEntityType])
    }

    /// The metadata of a row maps each header to its cell
    /// (`test_header_values_in_metadata`).
    @Test("the metadata maps each header to its cell")
    func theMetadataMapsEachHeaderToItsCell() throws {
        let entity = try #require(Self.entities("name,age,city\nAlice,30,NYC\n").first)

        #expect(entity.metadata == ["name": "Alice", "age": "30", "city": "NYC"])
    }

    /// The first cell names the row (`test_row_name_uses_first_column`).
    @Test("the first cell names the row")
    func theFirstCellNamesTheRow() throws {
        let entity = try #require(Self.entities("id,value\nABC123,hello\n").first)

        #expect(entity.name == "row[ABC123]")
        #expect(entity.id == "data.csv::row::row[ABC123]")
    }

    /// A row with an empty first cell gets its index as its name
    /// (`test_row_name_fallback_when_first_cell_empty`).
    @Test("an empty first cell gives the row index as the name")
    func anEmptyFirstCellGivesTheRowIndex() {
        #expect(Self.entities("id,value\n,hello\n").map(\.name) == ["row[row_1]"])
    }

    /// A `.tsv` file uses a tab as the separator (`test_tsv_separator_detection`).
    @Test("a tsv file uses a tab as the separator")
    func aTSVFileUsesATab() throws {
        let entity = try #require(Self.entities("name\tage\tcolor\nAlice\t30\tblue\n", at: "data.tsv").first)

        #expect(entity.metadata == ["name": "Alice", "age": "30", "color": "blue"])
    }

    /// The test for a `.tsv` path is case-sensitive, the same as
    /// `file_path.ends_with(".tsv")` in Rust: the registry gives `DATA.TSV`
    /// to this plugin, which then splits its lines at a comma.
    @Test("the tsv test is case-sensitive")
    func theTSVTestIsCaseSensitive() throws {
        let entity = try #require(Self.entities("name\tage\nAlice\t30\n", at: "DATA.TSV").first)

        #expect(entity.metadata == ["name\tage": "Alice\t30"])
        #expect(entity.name == "row[Alice\t30]")
    }

    /// A quoted cell keeps its separator (`test_quoted_fields_with_comma_inside`).
    @Test("a quoted cell keeps its separator")
    func aQuotedCellKeepsItsSeparator() throws {
        let entity = try #require(Self.entities("name,address\nAlice,\"123 Main St, Apt 4\"\n").first)

        #expect(entity.metadata?["address"] == "123 Main St, Apt 4")
    }

    /// Two quote marks in a quoted cell are one quote mark
    /// (`test_quoted_field_with_escaped_quote`).
    @Test("two quote marks in a quoted cell are one quote mark")
    func twoQuoteMarksAreOne() throws {
        let entity = try #require(Self.entities("name,bio\nAlice,\"She said \"\"hello\"\"\"\n").first)

        #expect(entity.metadata?["bio"] == "She said \"hello\"")
    }

    /// An empty file and a header with no row give no entity
    /// (`test_empty_content_returns_no_entities`, `test_header_only_returns_no_entities`).
    @Test("no data row gives no entity", arguments: ["", "name,age,city\n", "\n  \n"])
    func noDataRowGivesNoEntity(content: String) {
        #expect(Self.entities(content).isEmpty)
    }

    /// Each row is one line, numbered from the header
    /// (`test_line_numbers_are_correct`).
    @Test("each row is one line")
    func eachRowIsOneLine() {
        let entities = Self.entities("id,name\n1,Alice\n2,Bob\n")

        #expect(entities.map(\.startLine) == [2, 3])
        #expect(entities.map(\.endLine) == [2, 3])
    }

    /// The line numbers count only the lines that are not blank, the same as
    /// the Rust plugin, which filters the blank lines out before it counts.
    @Test("the line numbers skip blank lines")
    func theLineNumbersSkipBlankLines() {
        let entities = Self.entities("id,name\n\n1,Alice\n\n2,Bob\n")

        #expect(entities.map(\.startLine) == [2, 3])
        #expect(entities.map(\.content) == ["1,Alice", "2,Bob"])
    }

    /// The path of the file is the path of each row (`test_file_path_in_entity`).
    @Test("the path of the file is the path of each row")
    func thePathOfTheFileIsThePathOfEachRow() {
        #expect(Self.entities("id\n1\n", at: "path/to/records.csv").map(\.filePath) == ["path/to/records.csv"])
    }

    /// The default registry gives a `.csv` and a `.tsv` file to this plugin.
    @Test("the default registry selects the CSV plugin", arguments: ["data.csv", "data.tsv", "DATA.TSV"])
    func theDefaultRegistrySelectsTheCSVPlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == CSVParserPlugin.pluginID)
    }
}
