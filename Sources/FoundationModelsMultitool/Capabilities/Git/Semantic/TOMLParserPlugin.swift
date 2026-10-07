// `TOMLParserPlugin` — the plugin of the semantic diff for a TOML file.
//
// A port of `parser/plugins/toml_plugin.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `TomlParserPlugin` and the functions `find_toml_sections`,
// `has_section_before`, `trim_trailing_blanks_toml`, and
// `toml_value_to_string`. The Rust plugin uses no tree-sitter grammar: it
// finds the entries with a line scan and hashes the value of each entry after
// the `toml` crate parsed the file. This port parses with TOMLDecoder through
// ``TOMLValue``.
//
// Each line whose trimmed text starts with `[` is a section header: its key
// is the text with each leading `[` and each trailing `]` removed, trimmed
// (`[[bin]]` is `bin`; `[b] # note` is `b] # note`, as in Rust). Before the
// first line that starts with `[`, each line with a `=` is a root key: the
// text before the first `=`, trimmed. An entry runs to the line before the
// next entry (the last entry: to the last line), with no blank line and no
// comment line at its end. When the parsed root table holds the key text, a
// table value makes a `section` with the hash of its pretty JSON text, and
// each other value makes a `property` with the hash of its text. Else (a
// dotted header such as `[a.b]`, a quoted key) the entry is a `property`
// with the hash of its own lines. A text that the parser refuses gives no
// entity.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The TOML plugin: `TomlParserPlugin` in `parser/plugins/toml_plugin.rs`.
struct TOMLParserPlugin: SemanticParserPlugin {

    /// The id of the TOML plugin.
    static let pluginID = "toml"

    /// The entity type of an entry whose value is a table.
    static let sectionEntityType = "section"

    /// The entity type of each other entry.
    static let propertyEntityType = "property"

    var id: String { Self.pluginID }

    /// The extension of a TOML file.
    var extensions: [String] { [".toml"] }

    /// The entities of one file: `extract_entities` in `toml_plugin.rs`.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        let lines = RustText.lines(of: content)
        let entries = Self.entries(in: lines)
        guard !entries.isEmpty, case .table(let root) = TOMLValue.root(of: content) else { return [] }
        let values = Dictionary(root.map { (Array($0.key.utf8), $0.value) }, uniquingKeysWith: { first, _ in first })
        return entries.indices.map { index in
            let entry = entries[index]
            let boundary = index + 1 < entries.count ? entries[index + 1].line : lines.count + 1
            let endLine = Self.endLine(of: lines, start: entry.line, boundary: boundary)
            let text = lines[(entry.line - 1)..<endLine].joined(separator: "\n")
            let (hashedText, entityType) = Self.hashedText(of: values[Array(entry.key.utf8)], lines: text)
            return SemanticEntity(
                filePath: filePath, entityType: entityType, name: entry.key, content: text,
                contentHash: SemanticHash.contentHash(hashedText), startLine: entry.line, endLine: endLine)
        }
    }

    /// The text to hash and the entity type of an entry with the parsed
    /// value `value` (or none) and the text `lines`.
    private static func hashedText(of value: TOMLValue?, lines: String) -> (String, String) {
        switch value {
        case .table?:
            return (value?.prettyJSON ?? "", sectionEntityType)
        case let value?:
            return (value.scalarText, propertyEntityType)
        case nil:
            return (lines, propertyEntityType)
        }
    }

    /// The entries of a file: `find_toml_sections` in `toml_plugin.rs`.
    private static func entries(in lines: [String]) -> [(key: String, line: Int)] {
        var entries: [(key: String, line: Int)] = []
        var hasHeaderLine = false
        for (index, line) in lines.enumerated() {
            let trimmed = RustText.trimmed(line)
            guard !trimmed.isEmpty, !trimmed.hasPrefixByte(UInt8(ascii: "#")) else { continue }
            if trimmed.hasPrefixByte(UInt8(ascii: "[")) {
                hasHeaderLine = true
                let key = RustText.trimmed(
                    trimmed.trimmingLeading(UInt8(ascii: "[")).trimmingTrailing(UInt8(ascii: "]")))
                if !key.isEmpty {
                    entries.append((key, index + 1))
                }
                continue
            }
            guard entries.isEmpty || !hasHeaderLine, let equals = trimmed.unicodeScalars.firstIndex(of: "=") else {
                continue
            }
            let key = RustText.trimmed(String(String.UnicodeScalarView(trimmed.unicodeScalars[..<equals])))
            if !key.isEmpty {
                entries.append((key, index + 1))
            }
        }
        return entries
    }

    /// The 1-based last line of an entry that starts at `start` and stops
    /// before `boundary`, with no blank line and no comment line at its end:
    /// `trim_trailing_blanks_toml` in `toml_plugin.rs`.
    private static func endLine(of lines: [String], start: Int, boundary: Int) -> Int {
        var end = boundary - 1
        while end > start {
            let trimmed = RustText.trimmed(lines[end - 1])
            guard trimmed.isEmpty || trimmed.hasPrefixByte(UInt8(ascii: "#")) else { break }
            end -= 1
        }
        return end
    }
}

extension String {

    /// Whether the first byte of the text is `byte`.
    fileprivate func hasPrefixByte(_ byte: UInt8) -> Bool {
        utf8.first == byte
    }

    /// The text with each `byte` at its start removed: the Rust
    /// `trim_start_matches` with one ASCII byte.
    fileprivate func trimmingLeading(_ byte: UInt8) -> String {
        String(decoding: utf8.drop { $0 == byte }, as: UTF8.self)
    }

    /// The text with each `byte` at its end removed: the Rust
    /// `trim_end_matches` with one ASCII byte.
    fileprivate func trimmingTrailing(_ byte: UInt8) -> String {
        var bytes = Array(utf8)
        while bytes.last == byte {
            bytes.removeLast()
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
