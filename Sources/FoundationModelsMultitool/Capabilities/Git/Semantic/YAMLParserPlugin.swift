// `YAMLParserPlugin` — the plugin of the semantic diff for a YAML file.
//
// A port of `parser/plugins/yaml.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `YamlParserPlugin` and the functions `find_top_level_keys`,
// `trim_trailing_blanks_yaml`, and `yaml_value_to_string`. The Rust plugin
// uses no tree-sitter grammar (git.md decision 12): it finds the keys with a
// line scan and hashes the value of each key after serde_yaml_ng parsed the
// file. This port reads and writes YAML with ``YAMLLoader`` and
// ``YAMLEmitter``, the port of serde_yaml_ng over the same libyaml.
//
// Each line that starts at column 0 with a character that is not a space, a
// tab, or `#`, is not a document marker, and has a `:` is one key: the key is
// the text before the first `:`, trimmed. A key runs to the line before the
// next key (the last key: to the last line), with no blank line at its end.
// The entity is a `section` when the parsed value of the key is a mapping or
// a sequence, else a `property`. The content hash is the hash of the value
// text: the YAML that serde_yaml_ng writes for a section (trimmed), the text
// of a scalar, or the hash of the lines of the key when the parsed mapping
// holds no key with the text of the line scan (a quoted key, for example).
// A text that serde_yaml_ng refuses, or whose root is not a mapping, gives no
// entity.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The YAML plugin: `YamlParserPlugin` in `parser/plugins/yaml.rs`.
struct YAMLParserPlugin: SemanticParserPlugin {

    /// The id of the YAML plugin.
    static let pluginID = "yaml"

    /// The entity type of a key whose value is a mapping or a sequence.
    static let sectionEntityType = "section"

    /// The entity type of a key whose value is a scalar.
    static let propertyEntityType = "property"

    /// The prefixes of a line that is not a key: a comment, a document start,
    /// and a document end. Each match is case-free (no letter).
    private static let skippedLinePrefixes = ["#", "---", "..."]

    var id: String { Self.pluginID }

    /// The extensions of a YAML file.
    var extensions: [String] { [".yml", ".yaml"] }

    /// The entities of one file: `extract_entities` in `yaml.rs`.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        let lines = RustText.lines(of: content)
        let keys = Self.topLevelKeys(in: lines)
        guard !keys.isEmpty, let parsed = try? YAMLLoader.value(of: content),
            case .mapping(let mapping) = parsed.untagged
        else { return [] }
        let valueTexts = Self.valueTexts(of: mapping)
        return keys.indices.map { index in
            let key = keys[index]
            let boundary = index + 1 < keys.count ? keys[index + 1].line : lines.count + 1
            let endLine = Self.endLine(of: lines, start: key.line, boundary: boundary)
            let text = lines[(key.line - 1)..<endLine].joined(separator: "\n")
            let value = valueTexts[Array(key.name.utf8)] ?? (text: text, isSection: false)
            return SemanticEntity(
                filePath: filePath, entityType: value.isSection ? Self.sectionEntityType : Self.propertyEntityType,
                name: key.name, content: text, contentHash: SemanticHash.contentHash(value.text), startLine: key.line,
                endLine: endLine)
        }
    }

    /// The top-level keys of a file: `find_top_level_keys` in `yaml.rs`.
    private static func topLevelKeys(in lines: [String]) -> [(name: String, line: Int)] {
        lines.indices.compactMap { index in
            let line = lines[index]
            guard let first = line.unicodeScalars.first, first != " ", first != "\t",
                !skippedLinePrefixes.contains(where: { line.utf8.starts(with: $0.utf8) }),
                let colon = line.unicodeScalars.firstIndex(of: ":")
            else { return nil }
            let name = RustText.trimmed(String(String.UnicodeScalarView(line.unicodeScalars[..<colon])))
            return name.isEmpty ? nil : (name, index + 1)
        }
    }

    /// The 1-based last line of a key that starts at `start` and stops before
    /// `boundary`, with no blank line at its end: `trim_trailing_blanks_yaml`
    /// in `yaml.rs`.
    private static func endLine(of lines: [String], start: Int, boundary: Int) -> Int {
        var end = boundary - 1
        while end > start && RustText.isBlank(lines[end - 1]) {
            end -= 1
        }
        return end
    }

    /// The value text and the section flag of each key of the parsed
    /// mapping, by the bytes of the key text: the `value_map` of `yaml.rs`. A
    /// key that is not a text has the `Debug` text of its value; a later key
    /// with the same text wins, as in the Rust `HashMap`.
    private static func valueTexts(of mapping: YAMLMapping) -> [[UInt8]: (text: String, isSection: Bool)] {
        var texts: [[UInt8]: (text: String, isSection: Bool)] = [:]
        for entry in mapping.entries {
            let keyText: String
            if case .string(let text) = entry.key.untagged {
                keyText = text
            } else {
                keyText = entry.key.debugText
            }
            texts[Array(keyText.utf8)] = valueText(of: entry.value)
        }
        return texts
    }

    /// The value text of one value and whether it is a section.
    private static func valueText(of value: YAMLValue) -> (text: String, isSection: Bool) {
        switch value.untagged {
        case .mapping, .sequence:
            return (RustText.trimmed(YAMLEmitter.text(of: value) ?? ""), true)
        default:
            return (scalarText(of: value), false)
        }
    }

    /// The text of a value that is not a section: `yaml_value_to_string` in
    /// `yaml.rs`. A tagged value writes its `Debug` text.
    private static func scalarText(of value: YAMLValue) -> String {
        switch value {
        case .string(let text):
            return text
        case .number(let number):
            return number.text
        case .bool(let flag):
            return String(flag)
        case .null:
            return "null"
        default:
            return value.debugText
        }
    }
}

extension YAMLValue {

    /// The value with each tag removed: `untag_ref` in serde_yaml_ng, which
    /// `as_mapping`, `as_sequence`, and `as_str` read through.
    var untagged: YAMLValue {
        guard case .tagged(_, let content) = self else { return self }
        return content.untagged
    }
}
