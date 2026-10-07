// `MarkdownParserPlugin` — the plugin of the semantic diff for a Markdown
// file.
//
// A port of `parser/plugins/markdown.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `MarkdownParserPlugin`. The Rust plugin finds each heading line with the
// regular expression `^(#{1,6})\s+(.+)` and uses no tree-sitter grammar
// (git.md note 3 of "Tree-sitter packages"). This port reads the same lines
// with no regular expression: the rules of ``HeadingLine`` are the rules of
// that pattern.
//
// Each heading starts a section that runs to the next heading. The text
// before the first heading, from its first line that is not blank, is the
// `(preamble)` section. A heading has the nearest earlier heading of a lower
// level as its parent. The plugin does not know code fences, the same as
// Rust: a `#` line in a fence is a heading.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The Markdown plugin: `MarkdownParserPlugin` in `parser/plugins/markdown.rs`.
struct MarkdownParserPlugin: SemanticParserPlugin {

    /// The id of the Markdown plugin.
    static let pluginID = "markdown"

    /// The entity type of a heading section (`"heading"` in Rust).
    static let headingEntityType = "heading"

    /// The entity type of the text before the first heading (`"preamble"` in
    /// Rust).
    static let preambleEntityType = "preamble"

    /// The name of the preamble entity.
    static let preambleName = "(preamble)"

    var id: String { Self.pluginID }

    /// The extensions of a Markdown and an MDX file.
    var extensions: [String] { [".md", ".mdx"] }

    /// The entities of one file: `extract_entities` in `markdown.rs`.
    ///
    /// The content of a section is its lines joined by a newline and then
    /// trimmed with the Rust `str::trim`; a section whose content is empty
    /// gives no entity. The last line of a section is its last line in the
    /// file, blank lines included.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        MarkdownSection.sections(in: RustText.lines(of: content), filePath: filePath).compactMap { section in
            let text = RustText.trimmed(section.lines.joined(separator: "\n"))
            guard !text.isEmpty else { return nil }
            return SemanticEntity(
                filePath: filePath, entityType: section.entityType, name: section.name, parentID: section.parentID,
                content: text, contentHash: SemanticHash.contentHash(text), startLine: section.startLine,
                endLine: section.startLine + section.lines.count - 1)
        }
    }
}

/// One section of a Markdown file: `Section` in `markdown.rs`.
private struct MarkdownSection {

    /// The name of the heading, or ``MarkdownParserPlugin/preambleName``.
    let name: String

    /// ``MarkdownParserPlugin/headingEntityType`` or
    /// ``MarkdownParserPlugin/preambleEntityType``.
    let entityType: String

    /// The id of the parent heading, or `nil`.
    let parentID: String?

    /// The 1-based line of the heading, or of the first preamble line.
    let startLine: Int

    /// The lines of the section, the heading line included.
    var lines: [String]

    /// The sections of a file, in source order.
    ///
    /// - Parameters:
    ///   - lines: The lines of the file.
    ///   - filePath: The path of the file, for the id of a parent heading.
    /// - Returns: The sections.
    static func sections(in lines: [String], filePath: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        var current: MarkdownSection?
        var openHeadings: [HeadingLine] = []
        for (index, line) in lines.enumerated() {
            if let heading = HeadingLine(line) {
                current.map { sections.append($0) }
                openHeadings.removeAll { $0.level >= heading.level }
                current = MarkdownSection(
                    heading: heading, parentName: openHeadings.last?.name, line: line, index: index, filePath: filePath)
                openHeadings.append(heading)
            } else if current != nil {
                current?.lines.append(line)
            } else if !RustText.isBlank(line) {
                current = MarkdownSection(preambleLine: line, index: index)
            }
        }
        current.map { sections.append($0) }
        return sections
    }

    /// The section that a heading line opens.
    private init(heading: HeadingLine, parentName: String?, line: String, index: Int, filePath: String) {
        name = heading.name
        entityType = MarkdownParserPlugin.headingEntityType
        parentID = parentName.map {
            SemanticEntity.makeID(
                filePath: filePath, entityType: MarkdownParserPlugin.headingEntityType, name: $0, parentID: nil)
        }
        startLine = index + 1
        lines = [line]
    }

    /// The preamble section that its first line opens.
    private init(preambleLine line: String, index: Int) {
        name = MarkdownParserPlugin.preambleName
        entityType = MarkdownParserPlugin.preambleEntityType
        parentID = nil
        startLine = index + 1
        lines = [line]
    }
}

/// A heading line: a match of `^(#{1,6})\s+(.+)` in `markdown.rs`.
///
/// The line starts with one to six `#` marks and then whitespace (the Unicode
/// `White_Space` property, as `\s` of the Rust `regex` crate). The pattern
/// then needs one more character of any kind; thus a line of marks and one
/// whitespace character is not a heading, and a line of marks and two
/// whitespace characters is a heading with an empty name.
private struct HeadingLine {

    /// The mark that opens a heading.
    private static let mark: Unicode.Scalar = "#"

    /// The largest count of marks: `{1,6}` in the pattern.
    private static let maximumLevel = 6

    /// The count of marks.
    let level: Int

    /// The text after the marks, trimmed with the Rust `str::trim`.
    let name: String

    /// The heading on `line`, or `nil` when the line is not a heading.
    init?(_ line: String) {
        let scalars = line.unicodeScalars
        let level = scalars.prefix { $0 == Self.mark }.count
        let rest = scalars.dropFirst(level)
        let whitespaceCount = rest.prefix(while: RustText.isWhitespace).count
        guard (1...Self.maximumLevel).contains(level), whitespaceCount > 0,
            rest.count > whitespaceCount || whitespaceCount > 1
        else { return nil }
        self.level = level
        name = RustText.trimmed(String(String.UnicodeScalarView(rest)))
    }
}
