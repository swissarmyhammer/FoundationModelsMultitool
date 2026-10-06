// `CodeEntityExtractor` — reads the entities of one parse tree of a code
// file: each function, type, module, and other declaration.
//
// A port of `parser/plugins/code/entity_extractor.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the function
// `extract_entities` and the struct `EntityWalk`. The name readers of that
// file are in ``EntityNameReader`` and ``DeclaringCallReader``.
//
// The Rust code reads a tree-sitter `Node`. This port reads a
// ``CodeSyntaxNode``, as ``SemanticHash`` reads a ``StructuralHashNode``.
// The code plugin gives it the tree-sitter parse (``TreeSitterSyntaxNode``),
// and a test can give it a tree that the test writes by hand.
//
// The Rust `extract_entity_nodes` also gives the node of each entity, for the
// `public_surface` reader. The diff does not read the nodes, thus this port
// does not have that function.

/// One node of a parse tree, as ``CodeEntityExtractor`` reads it: the part
/// of a tree-sitter `Node` that `entity_extractor.rs` reads.
protocol CodeSyntaxNode: StructuralHashNode {

    /// The named child nodes, in source order (tree-sitter
    /// `Node::named_children`).
    var namedChildren: [Self] { get }

    /// The 0-based row where the node starts (tree-sitter
    /// `Node::start_position().row`).
    var startRow: Int { get }

    /// The 0-based row where the node ends (tree-sitter
    /// `Node::end_position().row`).
    var endRow: Int { get }

    /// The first child with the field name `name`, or `nil` (tree-sitter
    /// `Node::child_by_field_name`).
    func child(byFieldName name: String) -> Self?
}

/// The node kinds that carry meaning in one language: the vocabulary fields
/// of `LanguageConfig` in `languages.rs`.
struct EntityVocabulary: Sendable {

    /// The node kinds that are entities themselves: functions, types,
    /// modules (`entity_node_types`).
    let entityNodeTypes: Set<String>

    /// The node kinds that hold entities and are not entities, such as a
    /// class body. The walk reads the entities in them as children of the
    /// entity that holds them (`container_node_types`).
    let containerNodeTypes: Set<String>

    /// The call targets that declare an entity, in a language that spells a
    /// declaration as a call, such as Elixir `def`. Empty for each other
    /// language (`call_entity_identifiers`).
    let callEntityIdentifiers: Set<String>
}

/// The entity reader of `entity_extractor.rs`.
enum CodeEntityExtractor {

    /// The entities of one parse: `extract_entities` in
    /// `entity_extractor.rs`.
    ///
    /// The result has one entity for each declaration, in the order of the
    /// walk. A nested declaration comes after the entity that holds it, and
    /// its ``SemanticEntity/parentID`` is the id of that entity.
    ///
    /// - Parameters:
    ///   - root: The root of the parse tree.
    ///   - source: The UTF-8 bytes that the tree was parsed from.
    ///   - filePath: The path of the file, for the id of each entity.
    ///   - vocabulary: The node kinds of the language.
    /// - Returns: The entities, or an empty list when the file declares
    ///   nothing.
    static func extractEntities<Node: CodeSyntaxNode>(
        root: Node, source: [UInt8], filePath: String, vocabulary: EntityVocabulary
    ) -> [SemanticEntity] {
        var walk = EntityWalk<Node>(filePath: filePath, vocabulary: vocabulary, source: source)
        walk.visit(root, parentID: nil)
        return walk.entities
    }

    /// The semantic name of each node kind that a language spells in its
    /// own way: `map_node_type` in `entity_extractor.rs`. A kind that is not
    /// in the table is its own name.
    static let entityTypeByKind: [String: String] = [
        "function_declaration": "function", "function_definition": "function", "function_item": "function",
        "method_declaration": "method", "method_definition": "method", "method": "method",
        "singleton_method": "method",
        "class_declaration": "class", "class_definition": "class", "class_specifier": "class",
        "interface_declaration": "interface",
        "type_alias_declaration": "type", "type_declaration": "type", "type_item": "type", "type_definition": "type",
        "enum_declaration": "enum", "enum_item": "enum", "enum_specifier": "enum",
        "struct_item": "struct", "struct_specifier": "struct", "struct_declaration": "struct",
        "union_specifier": "union",
        "impl_item": "impl",
        "trait_item": "trait", "trait_declaration": "trait",
        "mod_item": "module", "module": "module", "namespace_definition": "module", "namespace_declaration": "module",
        "export_statement": "export",
        "lexical_declaration": "variable", "variable_declaration": "variable", "var_declaration": "variable",
        "declaration": "variable",
        "const_declaration": "constant", "const_item": "constant",
        "static_item": "static",
        "decorated_definition": "decorated_definition",
        "constructor_declaration": "constructor",
        "field_declaration": "field", "public_field_definition": "field", "field_definition": "field",
        "property_declaration": "property",
        "annotation_type_declaration": "annotation",
        "template_declaration": "template",
    ]
}

/// The state of one walk of a tree: `EntityWalk` in `entity_extractor.rs`,
/// with the list of entities that the Rust code passes to each step.
private struct EntityWalk<Node: CodeSyntaxNode> {

    /// The node kind of an export statement, which the walk follows to the
    /// declaration it exports.
    private static var exportStatementKind: String { "export_statement" }

    /// The field of an export statement that holds the declaration.
    private static var declarationField: String { "declaration" }

    /// The node kind of a call, which declares an entity in some languages.
    private static var callKind: String { "call" }

    /// The file of the parse, for the id of each entity.
    let filePath: String

    /// The node kinds of the language.
    let vocabulary: EntityVocabulary

    /// The UTF-8 bytes of the parse, for the text of each node.
    let source: [UInt8]

    /// The entities so far, in the order of the walk.
    private(set) var entities: [SemanticEntity] = []

    /// Reads each entity at or below `node`: `visit` in Rust.
    ///
    /// One reading takes `node`: a declaring call, a declaration, or an
    /// export statement. A node that is none of these passes its children on
    /// with the same parent.
    mutating func visit(_ node: Node, parentID: String?) {
        if readDeclaringCall(node, parentID: parentID) { return }
        if readDeclaration(node, parentID: parentID) { return }
        if followExport(node, parentID: parentID) { return }
        for child in node.namedChildren {
            visit(child, parentID: parentID)
        }
    }

    /// Records `node` when it is a call that declares an entity, such as
    /// Elixir `def`: `read_declaring_call` in Rust.
    ///
    /// - Returns: Whether `node` was such a call.
    private mutating func readDeclaringCall(_ node: Node, parentID: String?) -> Bool {
        guard node.kind == Self.callKind, !vocabulary.callEntityIdentifiers.isEmpty,
            let declared = DeclaringCallReader.entity(of: node, vocabulary: vocabulary, source: source)
        else { return false }
        record(node, name: declared.name, entityType: declared.entityType, parentID: parentID)
        return true
    }

    /// Records `node` when the vocabulary names its kind and the
    /// declaration names itself: `read_declaration` in Rust.
    ///
    /// - Returns: Whether `node` was such a declaration.
    private mutating func readDeclaration(_ node: Node, parentID: String?) -> Bool {
        guard vocabulary.entityNodeTypes.contains(node.kind),
            let name = EntityNameReader.name(of: node, source: source)
        else { return false }
        let entityType =
            node.kind == EntityNameReader.decoratedDefinitionKind
            ? EntityNameReader.decoratedType(of: node)
            : CodeEntityExtractor.entityTypeByKind[node.kind] ?? node.kind
        record(node, name: name, entityType: entityType, parentID: parentID)
        return true
    }

    /// Visits the declaration that an export statement exports, thus the
    /// declaration is the entity and not the statement: `follow_export` in
    /// Rust.
    ///
    /// - Returns: Whether `node` was an export statement with a declaration.
    private mutating func followExport(_ node: Node, parentID: String?) -> Bool {
        guard node.kind == Self.exportStatementKind,
            let declaration = node.child(byFieldName: Self.declarationField)
        else { return false }
        visit(declaration, parentID: parentID)
        return true
    }

    /// Records `node` as one entity, then visits the entities in its
    /// container children: `record` in Rust.
    private mutating func record(_ node: Node, name: String, entityType: String, parentID: String?) {
        let content = EntityNameReader.text(of: node, source: source)
        let id = SemanticEntity.makeID(filePath: filePath, entityType: entityType, name: name, parentID: parentID)
        entities.append(
            SemanticEntity(
                id: id, filePath: filePath, entityType: entityType, name: name, parentID: parentID,
                content: content, contentHash: SemanticHash.contentHash(content),
                structuralHash: SemanticHash.structuralHash(of: node, source: source),
                startLine: node.startRow + 1, endLine: node.endRow + 1, metadata: nil))
        visitContained(node, parentID: id)
    }

    /// Visits each child of each container child of `node`, with the parent
    /// `parentID`: `visit_contained` in Rust. The other children of an
    /// entity are not read.
    private mutating func visitContained(_ node: Node, parentID: String) {
        for container in node.namedChildren where vocabulary.containerNodeTypes.contains(container.kind) {
            for nested in container.namedChildren {
                visit(nested, parentID: parentID)
            }
        }
    }
}
