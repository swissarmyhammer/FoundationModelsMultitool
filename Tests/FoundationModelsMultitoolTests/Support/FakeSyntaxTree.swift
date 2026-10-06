@testable import FoundationModelsMultitool

/// The shape of one node of a ``FakeSyntaxNode`` tree, before
/// ``FakeSyntaxTree/build(_:)`` gives it its bytes.
///
/// A suite writes the tree that a grammar would give, with no grammar: the
/// extractor suites use it for each language whose grammar is not in the
/// package yet.
indirect enum FakeSyntaxShape {

    /// A node with no children and the text `text`.
    case leaf(kind: String, text: String, field: String? = nil, isNamed: Bool = true)

    /// A named node with the children `children`.
    case node(kind: String, children: [FakeSyntaxShape], field: String? = nil)
}

/// One node of a tree that a test writes by hand: a ``CodeSyntaxNode`` with
/// no tree-sitter parse behind it.
struct FakeSyntaxNode: CodeSyntaxNode {

    let kind: String

    /// Whether the grammar names this node, as tree-sitter `Node::is_named`.
    let isNamed: Bool

    /// The field name that the parent gives this node, or `nil`.
    let fieldName: String?

    let startByte: Int

    let endByte: Int

    let startRow: Int

    let endRow: Int

    let children: [FakeSyntaxNode]

    var namedChildren: [FakeSyntaxNode] { children.filter(\.isNamed) }

    func child(byFieldName name: String) -> FakeSyntaxNode? {
        children.first { $0.fieldName == name }
    }
}

/// Builds a ``FakeSyntaxNode`` tree and its source from a
/// ``FakeSyntaxShape``.
///
/// The source is the text of each leaf in order, with one space after each
/// leaf. Each node is on row 0, thus each entity of the tree has the line
/// range 1 to 1.
enum FakeSyntaxTree {

    /// The tree of `shape` and its UTF-8 source.
    static func build(_ shape: FakeSyntaxShape) -> (root: FakeSyntaxNode, source: [UInt8]) {
        var source: [UInt8] = []
        let root = node(of: shape, source: &source)
        return (root, source)
    }

    /// The node of `shape`, with its leaves appended to `source`.
    private static func node(of shape: FakeSyntaxShape, source: inout [UInt8]) -> FakeSyntaxNode {
        switch shape {
        case .leaf(let kind, let text, let field, let isNamed):
            let start = source.count
            source.append(contentsOf: text.utf8)
            let end = source.count
            source.append(UInt8(ascii: " "))
            return FakeSyntaxNode(
                kind: kind, isNamed: isNamed, fieldName: field, startByte: start, endByte: end, startRow: 0,
                endRow: 0, children: [])
        case .node(let kind, let children, let field):
            let start = source.count
            let built = children.map { node(of: $0, source: &source) }
            let end = built.last?.endByte ?? start
            return FakeSyntaxNode(
                kind: kind, isNamed: true, fieldName: field, startByte: start, endByte: end, startRow: 0,
                endRow: 0, children: built)
        }
    }
}
