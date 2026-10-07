// `JSONParserPlugin` — the plugin of the semantic diff for a JSON file.
//
// A port of `parser/plugins/json.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `JsonParserPlugin`, the scanner `ScanState` with `find_top_level_entries`,
// and the functions `extract_value_content`, `find_closing_brace_line`, and
// `trim_trailing_blanks`. The Rust plugin does not parse JSON with
// `serde_json`: it reads the text one character at a time to find each
// top-level key and its line. This port reads the text in the same way, and
// does not use `JSONSerialization` (that would lose the key order and the
// lines).
//
// Each top-level key of the root object is one entity. Its type is `object`
// when the value is an object or an array, else `property`. Its id holds the
// JSON Pointer of the key (`~` is written `~0`, `/` is written `~1`). Its
// structural hash is the content hash of the value text, so a renamed key
// with the same value keeps it. The scanner does not check the JSON: a text
// that is not valid JSON still gives the entities that the scan finds, the
// same as Rust.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The JSON plugin: `JsonParserPlugin` in `parser/plugins/json.rs`.
struct JSONParserPlugin: SemanticParserPlugin {

    /// The id of the JSON plugin.
    static let pluginID = "json"

    /// The entity type of a key whose value is not a container.
    static let propertyEntityType = "property"

    /// The entity type of a key whose value is an object or an array.
    static let objectEntityType = "object"

    var id: String { Self.pluginID }

    /// The extension of a JSON file.
    var extensions: [String] { [".json"] }

    /// The entities of one file: `extract_entities` in `json.rs`.
    ///
    /// A text whose first character that is not whitespace is not `{` gives
    /// no entity. An entry runs to the line before the next entry (the last
    /// entry: to the line before the last line that is only `}`), with no
    /// blank line and no lone `,` line at its end. A layout for which the
    /// Rust plugin slices outside its lines (and panics) gives no entity, as
    /// the Rust differ catches the panic.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        guard RustText.trimmed(content).unicodeScalars.first == "{" else { return [] }
        let lines = RustText.lines(of: content)
        let entries = JSONEntryScanner.entries(in: content)
        var entities: [SemanticEntity] = []
        for (index, entry) in entries.enumerated() {
            let boundary = index + 1 < entries.count ? entries[index + 1].startLine : Self.closingBraceLine(of: lines)
            guard let endLine = Self.endLine(of: lines, start: entry.startLine, boundary: boundary),
                entry.startLine - 1 <= endLine, endLine <= lines.count
            else { return [] }
            entities.append(Self.entity(of: entry, lines: lines[(entry.startLine - 1)..<endLine], filePath: filePath))
        }
        return entities
    }

    /// The entity of one entry.
    private static func entity(of entry: JSONEntry, lines: ArraySlice<String>, filePath: String) -> SemanticEntity {
        let content = lines.joined(separator: "\n")
        return SemanticEntity(
            id: SemanticEntity.makeID(
                filePath: filePath, entityType: entry.entityType, name: entry.pointer, parentID: nil),
            filePath: filePath, entityType: entry.entityType, name: entry.key, parentID: nil, content: content,
            contentHash: SemanticHash.contentHash(content),
            structuralHash: SemanticHash.contentHash(valueText(ofEntry: content)),
            startLine: entry.startLine, endLine: lines.endIndex, metadata: nil)
    }

    /// The value text of the text of one entry: `extract_value_content` in
    /// `json.rs`.
    ///
    /// The value is the text after the first `:` outside a string, trimmed,
    /// with each trailing `,` removed and then trimmed again. A text with no
    /// such `:` is its own value.
    ///
    /// - Parameter entry: The text of the entry.
    /// - Returns: The value text.
    static func valueText(ofEntry entry: String) -> String {
        var isInString = false
        var isEscaped = false
        let scalars = entry.unicodeScalars
        for index in scalars.indices {
            let scalar = scalars[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if scalar == "\\" && isInString {
                isEscaped = true
                continue
            }
            if scalar == "\"" {
                isInString.toggle()
            }
            if scalar == ":" && !isInString {
                var value = RustText.trimmed(String(String.UnicodeScalarView(scalars[scalars.index(after: index)...])))
                while value.unicodeScalars.last == "," {
                    value.unicodeScalars.removeLast()
                }
                return RustText.trimmed(value)
            }
        }
        return entry
    }

    /// The 1-based line of the closing brace of the root object: the last line
    /// that is `}` after a trim (`find_closing_brace_line` in `json.rs`), else
    /// the count of lines.
    private static func closingBraceLine(of lines: [String]) -> Int {
        (lines.lastIndex { RustText.trimmed($0) == "}" } ?? lines.count - 1) + 1
    }

    /// The 1-based last line of an entry that starts at `start` and stops
    /// before `boundary`: `trim_trailing_blanks` in `json.rs`, which steps back
    /// over each blank line and each lone `,` line, but not to `start`.
    ///
    /// - Returns: The line, or `nil` where the Rust function reads outside
    ///   the lines (a panic in Rust).
    private static func endLine(of lines: [String], start: Int, boundary: Int) -> Int? {
        var end = boundary - 1
        while end > start {
            guard end <= lines.count else { return nil }
            let trimmed = RustText.trimmed(lines[end - 1])
            guard trimmed.isEmpty || trimmed == "," else { break }
            end -= 1
        }
        return end
    }
}

/// One top-level entry of the root object: `JsonEntry` in `json.rs`.
private struct JSONEntry {

    /// The key, as the text has it between its quote marks (an escape stays
    /// as it is).
    let key: String

    /// The JSON Pointer of the key: `/` and the key, with `~` as `~0` and `/`
    /// as `~1`.
    var pointer: String {
        "/" + key.replacing("~", with: "~0").replacing("/", with: "~1")
    }

    /// The entity type: empty while the entry is open, then
    /// ``JSONParserPlugin/objectEntityType`` or
    /// ``JSONParserPlugin/propertyEntityType``. An entry that the scan leaves
    /// open keeps the empty type, the same as Rust.
    var entityType = ""

    /// The 1-based line of the `:` after the key.
    let startLine: Int
}

/// The scanner of the top-level entries: `ScanState` and
/// `find_top_level_entries` in `json.rs`.
///
/// The scanner reads one Unicode scalar at a time (a Rust `char`). It counts
/// the lines at each `\n`, follows the strings and their escapes, and counts
/// the depth of `{`/`[` against `}`/`]`. At depth 1, a string before a `:` is
/// a key, and the `:` opens an entry.
private struct JSONEntryScanner {

    /// The entries found so far.
    private var entries: [JSONEntry] = []

    /// The depth of containers: 1 in the root object.
    private var depth = 0

    /// Whether the scan is in a string.
    private var isInString = false

    /// Whether the scalar before was a `\` in a string.
    private var isEscaped = false

    /// The 1-based line of the scan.
    private var lineNumber = 1

    /// The key that the last depth-1 string read, until a depth-1 `,`.
    private var currentKey: String?

    /// Whether a depth-1 `:` opened an entry that no depth-1 `,` closed yet.
    private var isEntryOpen = false

    /// The text of the key that the scan reads now.
    private var keyText = ""

    /// Whether the scan reads a key now.
    private var isReadingKey = false

    /// The entries of `content`: `find_top_level_entries` in `json.rs`.
    static func entries(in content: String) -> [JSONEntry] {
        var scanner = JSONEntryScanner()
        content.unicodeScalars.forEach { scanner.read($0) }
        scanner.closeLastEntry()
        return scanner.entries
    }

    /// One step of the scan: `process` in `json.rs`.
    private mutating func read(_ scalar: Unicode.Scalar) {
        if scalar == "\n" {
            lineNumber += 1
        } else if isEscaped {
            appendToKey(scalar)
            isEscaped = false
        } else if scalar == "\\" && isInString {
            appendToKey(scalar)
            isEscaped = true
        } else if isInString {
            readInString(scalar)
        } else {
            readStructural(scalar)
        }
    }

    /// Adds `scalar` to the key text when the scan reads a key.
    private mutating func appendToKey(_ scalar: Unicode.Scalar) {
        if isReadingKey {
            keyText.unicodeScalars.append(scalar)
        }
    }

    /// One scalar in a string: `on_in_string_char` in `json.rs`.
    private mutating func readInString(_ scalar: Unicode.Scalar) {
        guard scalar == "\"" else {
            appendToKey(scalar)
            return
        }
        isInString = false
        if isReadingKey {
            isReadingKey = false
            currentKey = keyText
            keyText = ""
        }
    }

    /// One scalar out of a string: `on_structural_char` in `json.rs`.
    private mutating func readStructural(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\"":
            isInString = true
            if depth == 1 && currentKey == nil && !isEntryOpen {
                isReadingKey = true
                keyText = ""
            }
        case ":" where depth == 1:
            if let currentKey {
                entries.append(JSONEntry(key: currentKey, startLine: lineNumber))
                isEntryOpen = true
            }
        case "{", "[":
            depth += 1
            if depth == 2 && isEntryOpen && !entries.isEmpty {
                entries[entries.count - 1].entityType = JSONParserPlugin.objectEntityType
            }
        case "}", "]":
            depth -= 1
        case "," where depth == 1:
            closeLastEntry()
            currentKey = nil
            isEntryOpen = false
        default:
            break
        }
    }

    /// Gives the last entry the `property` type when it has no type yet:
    /// `finalize_scalar_entity_type` in `json.rs`.
    private mutating func closeLastEntry() {
        if let last = entries.indices.last, entries[last].entityType.isEmpty {
            entries[last].entityType = JSONParserPlugin.propertyEntityType
        }
    }
}
