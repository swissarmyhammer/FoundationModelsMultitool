import FoundationModelsCodeContext

// `CSVParserPlugin` — the plugin of the semantic diff for a CSV or TSV file.
//
// A port of `parser/plugins/csv_plugin.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `CsvParserPlugin` and the function `parse_csv_line`. The Rust plugin reads
// the text by hand, with no CSV library and no grammar (git.md, note 3 of
// the spike grammar table), and so does this port.
//
// The first line that is not blank is the header. Each later line that is not
// blank is one `row` entity. The line numbers count only the lines that are
// not blank, the same as Rust, which filters the blank lines out before it
// counts them.
//
// The test for a TSV path is case-sensitive, the same as
// `file_path.ends_with(".tsv")` in Rust: the registry gives `DATA.TSV` to this
// plugin (its extension match ignores case), and the plugin then splits the
// lines at a comma.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The CSV plugin: `CsvParserPlugin` in `parser/plugins/csv_plugin.rs`.
struct CSVParserPlugin: SemanticParserPlugin {

    /// The id of the CSV plugin.
    static let pluginID = "csv"

    /// The entity type of each data row (`"row"` in Rust).
    static let rowEntityType = "row"

    /// The suffix of a path whose cells are split at a tab. The match is
    /// case-sensitive, the same as `ends_with(".tsv")` in Rust.
    static let tabSeparatedSuffix = ".tsv"

    var id: String { Self.pluginID }

    /// The extensions of a comma-separated and of a tab-separated file.
    var extensions: [String] { [".csv", Self.tabSeparatedSuffix] }

    /// The entities of one file: `extract_entities` in `csv_plugin.rs`.
    ///
    /// Each row is named `row[<first cell>]`, or `row[row_<n>]` when its first
    /// cell is empty, where `<n>` is its index among the lines that are not
    /// blank. The metadata maps each header to the cell under it (an empty
    /// text for a missing cell; a later header with the same name wins). The
    /// content is the line itself.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        let lines = RustText.lines(of: content).filter { !RustText.isBlank($0) }
        guard let headerLine = lines.first else { return [] }
        let separator: Character = filePath.hasSuffix(Self.tabSeparatedSuffix) ? "\t" : ","
        let headers = Self.cells(of: headerLine, separator: separator)
        return lines.indices.dropFirst().map { index in
            Self.row(lines[index], index: index, headers: headers, separator: separator, filePath: filePath)
        }
    }

    /// The entity of the data line at `index` among the lines that are not
    /// blank.
    private static func row(
        _ line: String, index: Int, headers: [String], separator: Character, filePath: String
    ) -> SemanticEntity {
        let cells = cells(of: line, separator: separator)
        let firstCell = cells.first ?? ""
        let name = "row[\(firstCell.isEmpty ? "row_\(index)" : firstCell)]"
        let metadata = Dictionary(
            headers.indices.map { (headers[$0], $0 < cells.count ? cells[$0] : "") }, uniquingKeysWith: { $1 })
        return SemanticEntity(
            filePath: filePath, entityType: rowEntityType, name: name, content: line,
            contentHash: CodeEntities.contentHash(line), startLine: index + 1, endLine: index + 1,
            metadata: metadata)
    }

    /// The cells of one line: `parse_csv_line` in `csv_plugin.rs`.
    ///
    /// A quote mark opens and closes a quoted run, in which a separator is
    /// text and two quote marks are one quote mark. Each cell is trimmed with
    /// the Rust `str::trim`. A line always has one cell or more.
    ///
    /// - Parameters:
    ///   - line: The line to split.
    ///   - separator: The separator of the cells.
    /// - Returns: The cells.
    static func cells(of line: String, separator: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var isQuoted = false
        var scalars = line.unicodeScalars.makeIterator()
        var pending = scalars.next()
        while let scalar = pending {
            pending = scalars.next()
            switch (isQuoted, Character(scalar)) {
            case (true, "\"") where pending == "\"":
                current.unicodeScalars.append(scalar)
                pending = scalars.next()
            case (true, "\""):
                isQuoted = false
            case (false, "\""):
                isQuoted = true
            case (false, separator):
                cells.append(RustText.trimmed(current))
                current = ""
            default:
                current.unicodeScalars.append(scalar)
            }
        }
        cells.append(RustText.trimmed(current))
        return cells
    }
}
