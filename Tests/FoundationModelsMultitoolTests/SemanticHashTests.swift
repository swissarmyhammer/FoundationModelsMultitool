import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Golden-vector tests for ``SemanticHash`` — the port of `utils/hash.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The fixture `GitGoldens/semantic-hash-golden.json` comes from the Rust
/// crate. A throwaway Rust program called `content_hash`, `short_hash`, and
/// `structural_hash` (xxhash-rust 0.8.15, tree-sitter 0.26.9,
/// tree-sitter-rust 0.24.2) and wrote each input and each result. For
/// `structural_hash`, the program also wrote the tree that tree-sitter
/// parsed, thus this suite hashes the same tree without tree-sitter.
///
/// The entity id and the "structural change" result of the semantic diff
/// depend on these values. Thus the Swift hash must give the same value as
/// the Rust hash for each input.
@Suite("SemanticHashTests")
struct SemanticHashTests {

    // MARK: Golden fixture model

    /// The fixture file: one list for each hash function.
    private struct Golden: Decodable {

        /// One `content_hash` input and its result.
        struct ContentCase: Decodable {
            let input: String
            let hash: String
        }

        /// One `short_hash` input, its length, and its result.
        struct ShortCase: Decodable {
            let input: String
            let length: Int
            let hash: String
        }

        /// One source text, the tree that tree-sitter parsed from it, and
        /// the `structural_hash` of the root of that tree.
        struct StructuralCase: Decodable {
            let source: String
            let tree: FixtureNode
            let hash: String
        }

        let contentHash: [ContentCase]
        let shortHash: [ShortCase]
        let structuralHash: [StructuralCase]
    }

    /// One node of a tree-sitter tree, as the fixture writes it.
    private struct FixtureNode: Decodable, StructuralHashNode {
        let kind: String
        let startByte: Int
        let endByte: Int
        let children: [FixtureNode]
    }

    /// The golden fixture, read from the test bundle.
    private static func loadGolden() throws -> Golden {
        try TestResource.bundledJSON(Golden.self, named: "semantic-hash-golden", in: "GitGoldens")
    }

    // MARK: Golden-vector parity

    /// Each length path of XXH3-64 (0, 1-3, 4-8, 9-16, 17-128, 129-240, and
    /// the long path) gives the Rust value.
    @Test("content hash matches the Rust golden vectors")
    func contentHashMatchesTheRustGoldenVectors() throws {
        let cases = try Self.loadGolden().contentHash
        #expect(!cases.isEmpty)
        for golden in cases {
            #expect(
                SemanticHash.contentHash(golden.input) == golden.hash,
                "contentHash of \(golden.input.utf8.count) bytes should be \(golden.hash)"
            )
        }
    }

    /// The short hash is the prefix of the content hash, and a length above
    /// 16 gives the full hash.
    @Test("short hash matches the Rust golden vectors")
    func shortHashMatchesTheRustGoldenVectors() throws {
        let cases = try Self.loadGolden().shortHash
        #expect(!cases.isEmpty)
        for golden in cases {
            #expect(
                SemanticHash.shortHash(golden.input, length: golden.length) == golden.hash,
                "shortHash(\(golden.input.debugDescription), \(golden.length)) should be \(golden.hash)"
            )
        }
    }

    /// The structural hash of each parsed tree gives the Rust value. The
    /// fixture holds sources that differ only in comments and format, thus
    /// this test also shows that those differences give the same hash.
    @Test("structural hash matches the Rust golden vectors")
    func structuralHashMatchesTheRustGoldenVectors() throws {
        let cases = try Self.loadGolden().structuralHash
        #expect(!cases.isEmpty)
        for golden in cases {
            #expect(
                SemanticHash.structuralHash(of: golden.tree, source: Array(golden.source.utf8)) == golden.hash,
                "structuralHash of \(golden.source.debugDescription) should be \(golden.hash)"
            )
        }
    }

    // MARK: Behavior

    /// A content hash is 16 lowercase hexadecimal characters.
    @Test("content hash is 16 lowercase hexadecimal characters")
    func contentHashIsSixteenLowercaseHexCharacters() {
        let hash = SemanticHash.contentHash("test")
        #expect(hash.count == 16)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    /// A comment node adds nothing to the structural hash, at each depth.
    @Test("a comment node adds nothing to the structural hash")
    func aCommentNodeAddsNothingToTheStructuralHash() {
        let source = Array("a /* x */".utf8)
        let leaf = FixtureNode(kind: "identifier", startByte: 0, endByte: 1, children: [])
        let comment = FixtureNode(kind: "block_comment", startByte: 2, endByte: 9, children: [])
        let withComment = FixtureNode(kind: "root", startByte: 0, endByte: 9, children: [leaf, comment])
        let withoutComment = FixtureNode(kind: "root", startByte: 0, endByte: 9, children: [leaf])

        #expect(
            SemanticHash.structuralHash(of: withComment, source: source)
                == SemanticHash.structuralHash(of: withoutComment, source: source))
    }

    /// A leaf whose range is out of the source adds nothing, as in Rust.
    @Test("a leaf outside the source adds nothing to the structural hash")
    func aLeafOutsideTheSourceAddsNothing() {
        let source = Array("ab".utf8)
        let outside = FixtureNode(kind: "identifier", startByte: 1, endByte: 9, children: [])
        let empty = FixtureNode(kind: "identifier", startByte: 0, endByte: 0, children: [])

        #expect(
            SemanticHash.structuralHash(of: outside, source: source)
                == SemanticHash.structuralHash(of: empty, source: source))
        #expect(SemanticHash.structuralHash(of: empty, source: source) == SemanticHash.contentHash(""))
    }
}
