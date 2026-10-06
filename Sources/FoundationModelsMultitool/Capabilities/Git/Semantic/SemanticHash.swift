// `SemanticHash` — the content hash and the structural hash of a semantic
// entity.
//
// A port of `utils/hash.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`. Each value is the
// 64-bit XXH3 hash (``XXH3``) as 16 lowercase hexadecimal characters, the
// same text as the Rust `format!("{:016x}", ...)`. The entity matcher
// compares these values, thus each value must be equal to the Rust value.
// Golden vectors from the Rust crate pin them
// (`GitGoldens/semantic-hash-golden.json`, read by `SemanticHashTests`).
//
// The Rust `structural_hash` reads a tree-sitter `Node`. This port reads a
// ``StructuralHashNode`` instead, thus it needs no tree-sitter package. A
// language plugin makes its parse tree conform to that protocol.

/// One node of a parse tree, as ``SemanticHash/structuralHash(of:source:)``
/// reads it: the part of a tree-sitter `Node` that `hash_structural_tokens`
/// in `utils/hash.rs` reads.
protocol StructuralHashNode {

    /// The grammar kind of the node, for example `function_item` or
    /// `line_comment` (tree-sitter `Node::kind`).
    var kind: String { get }

    /// The byte offset in the source where the node starts
    /// (tree-sitter `Node::start_byte`).
    var startByte: Int { get }

    /// The byte offset in the source where the node ends, excluded
    /// (tree-sitter `Node::end_byte`).
    var endByte: Int { get }

    /// The child nodes, named and anonymous, in source order
    /// (tree-sitter `Node::children`).
    var children: [Self] { get }
}

/// The content hash and the structural hash of `utils/hash.rs` in
/// `swissarmyhammer-sem`.
enum SemanticHash {

    /// The number of hexadecimal characters in one hash: 16, for 64 bits.
    private static let hexDigits = 16

    /// The radix of the hash text: hexadecimal.
    private static let hexRadix = 16

    /// The node kinds that the structural hash skips: `is_comment_node` in
    /// `utils/hash.rs`.
    private static let commentKinds: Set<String> = ["comment", "line_comment", "block_comment", "doc_comment"]

    /// The byte that follows each leaf text in the structural token stream.
    private static let leafSeparator = UInt8(ascii: " ")

    /// The byte that follows each node kind in the structural token stream.
    private static let kindSeparator = UInt8(ascii: ":")

    /// The hash of `content`: `content_hash` in `utils/hash.rs`.
    ///
    /// - Parameter content: The text to hash, as UTF-8 bytes.
    /// - Returns: The 64-bit XXH3 hash as 16 lowercase hexadecimal
    ///   characters.
    static func contentHash(_ content: String) -> String {
        hexText(XXH3.hash64(Array(content.utf8)))
    }

    /// The first `length` characters of ``contentHash(_:)``: `short_hash` in
    /// `utils/hash.rs`. A length above 16 gives the full hash.
    ///
    /// - Parameters:
    ///   - content: The text to hash.
    ///   - length: The number of characters to keep.
    /// - Returns: The prefix of the content hash.
    static func shortHash(_ content: String, length: Int) -> String {
        String(contentHash(content).prefix(length))
    }

    /// The structural hash of a parse tree: `structural_hash` in
    /// `utils/hash.rs`.
    ///
    /// The hash skips each comment node and the whitespace around each leaf
    /// text. Thus two trees that differ only in comments or in format give
    /// the same hash. The hash reads the kind of each inner node too, thus
    /// two trees with the same leaves in a different structure give
    /// different hashes.
    ///
    /// - Parameters:
    ///   - node: The root of the tree to hash.
    ///   - source: The UTF-8 bytes of the source that the tree was parsed
    ///     from.
    /// - Returns: The 64-bit XXH3 hash of the token stream as 16 lowercase
    ///   hexadecimal characters.
    static func structuralHash<Node: StructuralHashNode>(of node: Node, source: [UInt8]) -> String {
        var tokens: [UInt8] = []
        appendStructuralTokens(of: node, source: source, to: &tokens)
        return hexText(XXH3.hash64(tokens))
    }

    /// Appends the token stream of `node` to `tokens`:
    /// `hash_structural_tokens` in `utils/hash.rs`.
    ///
    /// A leaf adds its trimmed text and one space. An inner node adds its
    /// kind and one colon, and then the tokens of each child. A comment
    /// node adds nothing.
    private static func appendStructuralTokens<Node: StructuralHashNode>(
        of node: Node, source: [UInt8], to tokens: inout [UInt8]
    ) {
        guard !commentKinds.contains(node.kind) else { return }
        guard node.children.isEmpty else {
            tokens.append(contentsOf: node.kind.utf8)
            tokens.append(kindSeparator)
            for child in node.children {
                appendStructuralTokens(of: child, source: source, to: &tokens)
            }
            return
        }
        guard node.startByte < node.endByte, node.endByte <= source.count else { return }
        let trimmed = trimmingASCIIWhitespace(source[node.startByte..<node.endByte])
        guard !trimmed.isEmpty else { return }
        tokens.append(contentsOf: trimmed)
        tokens.append(leafSeparator)
    }

    /// The bytes of `u8::is_ascii_whitespace`: space, tab, line feed, form
    /// feed, and carriage return.
    private static let asciiWhitespace: Set<UInt8> = [
        UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), asciiFormFeed, UInt8(ascii: "\r"),
    ]

    /// The ASCII form feed, one of the bytes of `u8::is_ascii_whitespace`.
    private static let asciiFormFeed: UInt8 = 0x0C

    /// The bytes with the leading and trailing ASCII whitespace removed:
    /// `trim_bytes` in `utils/hash.rs`.
    private static func trimmingASCIIWhitespace(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        guard let first = bytes.firstIndex(where: { !asciiWhitespace.contains($0) }),
            let last = bytes.lastIndex(where: { !asciiWhitespace.contains($0) })
        else { return [] }
        return bytes[first...last]
    }

    /// `value` as `format!("{:016x}", value)` writes it: lowercase
    /// hexadecimal, padded with zeros to 16 characters.
    private static func hexText(_ value: UInt64) -> String {
        let digits = String(value, radix: hexRadix)
        return String(repeating: "0", count: hexDigits - digits.count) + digits
    }
}
