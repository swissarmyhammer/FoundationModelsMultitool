import Foundation
import FoundationModelsCodeContext
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``MarkdownParserPlugin`` — the port of
/// `parser/plugins/markdown.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The tests port the Rust tests of `markdown.rs`, and add the rules of the
/// heading pattern `^(#{1,6})\s+(.+)` that the Rust tests do not name. The
/// expected values of the added tests come from the Rust plugin
/// (`DataPluginEntityGoldenTests` holds the full output).
@Suite("MarkdownParserPluginTests")
struct MarkdownParserPluginTests {

    /// The entities that the Markdown plugin reads from `content` at
    /// `filePath`.
    private static func entities(_ content: String, at filePath: String = "doc.md") -> [SemanticEntity] {
        MarkdownParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// One heading gives one `heading` entity with no parent (`test_single_heading`).
    @Test("one heading gives one heading entity")
    func oneHeadingGivesOneHeadingEntity() throws {
        let entity = try #require(Self.entities("# Hello\n\nSome content here.\n").first)

        #expect(entity.entityType == MarkdownParserPlugin.headingEntityType)
        #expect(entity.name == "Hello")
        #expect(entity.startLine == 1)
        #expect(entity.parentID == nil)
    }

    /// A lower heading has the higher heading above it as its parent
    /// (`test_heading_hierarchy_parent_assignment`).
    @Test("a lower heading has the higher heading as its parent")
    func aLowerHeadingHasTheHigherHeadingAsItsParent() {
        let entities = Self.entities("# Parent\n\nIntro.\n\n## Child\n\nDetails.\n")

        #expect(entities.map(\.name) == ["Parent", "Child"])
        #expect(entities.map(\.parentID) == [nil, "doc.md::heading::Parent"])
    }

    /// Three levels give a chain of parents (`test_nested_sections_three_levels`).
    @Test("three levels give a chain of parents")
    func threeLevelsGiveAChainOfParents() {
        let entities = Self.entities("# Top\n## Mid\n### Deep\n", at: "readme.md")

        #expect(entities.map(\.parentID) == [nil, "readme.md::heading::Top", "readme.md::heading::Mid"])
    }

    /// The text before the first heading is the `(preamble)` entity
    /// (`test_preamble_detected_before_first_heading`).
    @Test("the text before the first heading is the preamble")
    func theTextBeforeTheFirstHeadingIsThePreamble() throws {
        let entities = Self.entities("This is preamble text.\nMore preamble.\n\n# Section\n\nContent.\n", at: "guide.md")
        let preamble = try #require(entities.first)

        #expect(preamble.entityType == MarkdownParserPlugin.preambleEntityType)
        #expect(preamble.name == "(preamble)")
        #expect(preamble.parentID == nil)
        #expect(preamble.content == "This is preamble text.\nMore preamble.")
        #expect(preamble.endLine == 3)
    }

    /// A file that starts with a heading has no preamble
    /// (`test_no_preamble_when_heading_first`).
    @Test("a file that starts with a heading has no preamble")
    func aFileThatStartsWithAHeadingHasNoPreamble() {
        #expect(!Self.entities("# Title\n\nContent.\n").contains { $0.entityType == MarkdownParserPlugin.preambleEntityType })
    }

    /// Two headings of the same level have the same parent
    /// (`test_sibling_headings_reset_parent`).
    @Test("two sibling headings have the same parent")
    func twoSiblingHeadingsHaveTheSameParent() {
        let entities = Self.entities("# Top\n## First\n## Second\n")

        #expect(entities.map(\.parentID) == [nil, "doc.md::heading::Top", "doc.md::heading::Top"])
    }

    /// An empty file has no entity (`test_empty_content_returns_no_entities`).
    @Test("an empty file has no entity")
    func anEmptyFileHasNoEntity() {
        #expect(Self.entities("", at: "empty.md").isEmpty)
    }

    /// The id of a heading starts with the file path
    /// (`test_entity_ids_include_file_path`).
    @Test("the id of a heading starts with the file path")
    func theIDOfAHeadingStartsWithTheFilePath() {
        #expect(Self.entities("# My Section\n", at: "path/to/file.md").map(\.id) == ["path/to/file.md::heading::My Section"])
    }

    /// The content of a section is its heading and its body lines, trimmed
    /// (`test_section_content_includes_body_lines`, `test_start_and_end_line_numbers`).
    @Test("the content of a section is its lines trimmed")
    func theContentOfASectionIsItsLinesTrimmed() throws {
        let entity = try #require(Self.entities("# Section\nLine one.\nLine two.\n\n").first)

        #expect(entity.content == "# Section\nLine one.\nLine two.")
        #expect(entity.contentHash == CodeEntities.contentHash("# Section\nLine one.\nLine two."))
        #expect(entity.startLine == 1)
        #expect(entity.endLine == 4)
    }

    /// A heading line needs whitespace after the marks, at most six marks,
    /// and one more character: `#Title`, `####### Seven`, and a bare `#` are
    /// body lines.
    @Test("a line is a heading only with whitespace after one to six marks")
    func aLineIsAHeadingOnlyWithWhitespaceAfterOneToSixMarks() {
        let entities = Self.entities("# Top\n#Title\n####### Seven\n#\n###### Six\n")

        #expect(entities.map(\.name) == ["Top", "Six"])
        #expect(entities.first?.content == "# Top\n#Title\n####### Seven\n#")
    }

    /// The name is the text after the marks, trimmed; a heading line of marks
    /// and two spaces has an empty name.
    @Test("the name is the trimmed text after the marks")
    func theNameIsTheTrimmedTextAfterTheMarks() {
        let entities = Self.entities("##   Spaced  name  \n#  \n")

        #expect(entities.map(\.name) == ["Spaced  name", ""])
        #expect(entities.map(\.id) == ["doc.md::heading::Spaced  name", "doc.md::heading::"])
    }

    /// The default registry gives a `.md` and a `.mdx` file to this plugin.
    @Test("the default registry selects the Markdown plugin", arguments: ["README.md", "page.mdx", "NOTES.MD"])
    func theDefaultRegistrySelectsTheMarkdownPlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == MarkdownParserPlugin.pluginID)
    }
}
