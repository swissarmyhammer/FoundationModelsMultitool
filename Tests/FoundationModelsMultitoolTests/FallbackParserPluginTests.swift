import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``FallbackParserPlugin`` — the port of
/// `parser/plugins/fallback.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The tests port the Rust tests of `fallback.rs`. The plugin cuts a file
/// into chunks of 20 lines, and the default registry gives it each file that
/// no other plugin reads.
@Suite("FallbackParserPluginTests")
struct FallbackParserPluginTests {

    /// The entities that the fallback plugin reads from `content` at
    /// `filePath`.
    private static func entities(_ content: String, at filePath: String = "file.txt") -> [SemanticEntity] {
        FallbackParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// The text of `count` lines `line 1` to `line <count>`, with no newline
    /// after the last line.
    private static func numberedLines(_ count: Int) -> String {
        (1...count).map { "line \($0)" }.joined(separator: "\n")
    }

    /// An empty file has no chunk (`test_empty_content_returns_no_entities`).
    @Test("an empty file has no chunk")
    func anEmptyFileHasNoChunk() {
        #expect(Self.entities("").isEmpty)
    }

    /// A file of fewer than 20 lines is one chunk (`test_single_chunk_under_20_lines`).
    @Test("a file under 20 lines is one chunk")
    func aFileUnderTwentyLinesIsOneChunk() {
        let entities = Self.entities(Self.numberedLines(10))

        #expect(entities.count == 1)
        #expect(entities.first?.entityType == FallbackParserPlugin.chunkEntityType)
        #expect(entities.first?.startLine == 1)
        #expect(entities.first?.endLine == 10)
        #expect(entities.first?.name == "lines 1-10")
    }

    /// A file of exactly 20 lines is one chunk (`test_exactly_20_lines_is_one_chunk`).
    @Test("a file of 20 lines is one chunk")
    func aFileOfTwentyLinesIsOneChunk() {
        let entities = Self.entities(Self.numberedLines(20))

        #expect(entities.map(\.name) == ["lines 1-20"])
    }

    /// A file of 21 lines is two chunks (`test_21_lines_creates_two_chunks`).
    @Test("a file of 21 lines is two chunks")
    func aFileOfTwentyOneLinesIsTwoChunks() {
        let entities = Self.entities(Self.numberedLines(21))

        #expect(entities.map(\.name) == ["lines 1-20", "lines 21-21"])
        #expect(entities.last?.startLine == 21)
        #expect(entities.last?.endLine == 21)
    }

    /// A file of 40 lines is two full chunks (`test_40_lines_creates_two_equal_chunks`).
    @Test("a file of 40 lines is two full chunks")
    func aFileOfFortyLinesIsTwoFullChunks() {
        let entities = Self.entities(Self.numberedLines(40))

        #expect(entities.map(\.startLine) == [1, 21])
        #expect(entities.map(\.endLine) == [20, 40])
    }

    /// The content of a chunk is its lines joined by a newline, with no
    /// newline at the end (`test_chunk_content_contains_lines`).
    @Test("the content of a chunk is its lines")
    func theContentOfAChunkIsItsLines() throws {
        let entity = try #require(Self.entities("alpha\nbeta\ngamma\n").first)

        #expect(entity.content == "alpha\nbeta\ngamma")
        #expect(entity.contentHash == SemanticHash.contentHash("alpha\nbeta\ngamma"))
        #expect(entity.structuralHash == nil)
    }

    /// The path of the file is the path of each chunk and the start of its
    /// id (`test_file_path_in_entity`, `test_chunk_ids_include_file_path`).
    @Test("the id of a chunk starts with the file path")
    func theIDOfAChunkStartsWithTheFilePath() throws {
        let entity = try #require(Self.entities("hello\n", at: "src/notes.txt").first)

        #expect(entity.filePath == "src/notes.txt")
        #expect(entity.id == "src/notes.txt::chunk::lines 1-1")
    }

    /// The default registry gives the fallback plugin each extension that no
    /// other plugin claims, and each file with no extension (git.md decision
    /// 13).
    @Test(
        "the default registry selects the fallback plugin for an unclaimed extension",
        arguments: ["notes.txt", "data.xyz", "Makefile", "src/.gitignore", "archive.json.gz"])
    func theDefaultRegistrySelectsTheFallback(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == ParserRegistry.fallbackPluginID)
    }
}
